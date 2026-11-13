import Foundation
import IOBluetooth
import os
import BoseKit

/// Estado de los auriculares y conexión con ellos.
///
/// Todo ocurre en el hilo principal: IOBluetooth entrega sus callbacks en el
/// run loop principal (abrimos el canal desde él) y los Timer también van ahí.
/// Por eso no hace falta sincronización (en Java sería como hacerlo todo en el EDT de Swing).
final class HeadphonesController: NSObject, ObservableObject {
    enum Status: Equatable {
        case connecting
        case connected
        case retrying(seconds: Int)
        case waitingForDevice
        case notPaired
    }

    @Published private(set) var status: Status = .connecting
    @Published private(set) var deviceName: String?
    @Published private(set) var modes: [ModeSlot] = []
    @Published private(set) var currentModeIndex: UInt8?
    /// Modo pedido cuya confirmación (`1f 03 06`) aún no ha llegado.
    @Published private(set) var pendingModeIndex: UInt8?
    @Published private(set) var battery: [BatteryEntry] = []
    @Published private(set) var equalizer: [EQBand] = []

    /// Modos que muestra el menú, en este orden (nombres tal como los devuelven los auriculares).
    static let menuModeNames = ["Quiet", "Aware", "Immersion"]
    private let nameFilter = "Bose"
    /// Reintentos tras perder la conexión; después se espera al aviso del sistema.
    private let retryDelays: [TimeInterval] = [2, 5, 10, 30]
    private let pollInterval: TimeInterval = 60
    /// Máximo que esperamos a que se abra el canal en cada intento. Sin este
    /// límite, un intento con los auriculares en el estuche quedaba pendiente
    /// indefinidamente (observado: 29 min en "Conectando…").
    private let connectTimeout: TimeInterval = 10

    private let log = Logger(subsystem: "local.boseqcultra2.menubar", category: "bluetooth")
    private var device: IOBluetoothDevice?
    private var connection: BoseConnection?
    private var retryIndex = 0
    private var retryTimer: Timer?
    private var pollTimer: Timer?
    private var connectTimeoutTimer: Timer?
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotification: IOBluetoothUserNotification?
    private var collectingModes: [ModeSlot]?

    override init() {
        super.init()
        // Aviso del sistema cada vez que se conecta cualquier dispositivo clásico.
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self, selector: #selector(systemDeviceConnected(_:device:)))
        connect()
    }

    // MARK: - Datos derivados para la interfaz

    var isConnected: Bool { status == .connected }

    /// Acordado: la barra muestra el menor de los componentes 01 y 02 (auriculares).
    var earbudsPercent: Int? {
        battery.filter { $0.componentID == 0x01 || $0.componentID == 0x02 }.map(\.percent).min()
    }

    /// Componente 03 = estuche (hipótesis de docs/protocol.md §4, confirmada por el usuario).
    /// docs/protocol.md §4 (13-11-2026 18:04): con el derecho fuera y el izquierdo en el
    /// estuche desapareció el ID 02 → hipótesis 02 = izquierdo, 01 = derecho.
    /// `nil` si los auriculares no envían el dato (p. ej. ese auricular está en el estuche).
    var leftPercent: Int? { battery.first { $0.componentID == 0x02 }?.percent }
    var rightPercent: Int? { battery.first { $0.componentID == 0x01 }?.percent }

    /// Nombres de las bandas, en el orden de la app de Bose (izquierda a derecha).
    /// Banda 0 = Graves confirmado; 1 = Medio y 2 = Agudos por orden (§5).
    static let eqBandNames: [UInt8: String] = [0: "Graves", 1: "Medio", 2: "Agudos"]

    var casePercent: Int? {
        battery.first { $0.componentID == 0x03 }?.percent
    }

    var selectableModes: [ModeSlot] {
        Self.menuModeNames.compactMap { name in modes.first { $0.name == name } }
    }

    /// Si el modo activo es otro (p. ej. uno personalizado), su nombre.
    var currentOtherModeName: String? {
        guard let i = currentModeIndex, !selectableModes.contains(where: { $0.index == i }) else { return nil }
        return modes.first { $0.index == i }?.name ?? String(format: "índice %02X", i)
    }

    var statusText: String {
        switch status {
        case .connecting: return "Conectando…"
        case .connected: return "Conectado"
        case .retrying(let s): return "Sin conexión — reintento en \(s) s"
        case .waitingForDevice: return "Sin conexión — esperando a los auriculares"
        case .notPaired: return "No hay auriculares Bose emparejados"
        }
    }

    // MARK: - Acciones

    func setMode(index: UInt8) {
        guard let connection, index != currentModeIndex else { return }
        log.info("Cambio de modo pedido: índice \(index)")
        pendingModeIndex = index
        do {
            try connection.send(BoseCommand.setMode(index: index))
        } catch {
            log.error("Error enviando cambio de modo: \(String(describing: error))")
            pendingModeIndex = nil
            return
        }
        // Si en 3 s no llega la confirmación, volvemos a leer el modo real.
        Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            guard let self, self.pendingModeIndex == index else { return }
            self.log.error("Sin confirmación del cambio a \(index); se relee el modo")
            self.pendingModeIndex = nil
            self.sendQuietly(BoseCommand.getCurrentMode)
        }
    }

    func setEqualizer(band: UInt8, value: Int) {
        guard let current = equalizer.first(where: { $0.index == band }),
              current.value != value, (current.min...current.max).contains(value) else { return }
        log.info("Cambio de EQ pedido: banda \(band) = \(value)")
        // El nuevo estado llega en la respuesta `01 07 03` y se aplica en handle(_:).
        sendQuietly(BoseCommand.setEQ(band: band, value: value))
    }

    func refresh() {
        sendQuietly(BoseCommand.dumpBlock01)
        sendQuietly(BoseCommand.listModes)
        sendQuietly(BoseCommand.getCurrentMode)
        sendQuietly(BoseCommand.dumpBlock02)
    }

    func reconnectNow() {
        retryIndex = 0
        connect()
    }

    // MARK: - Conexión

    private func connect() {
        retryTimer?.invalidate()
        retryTimer = nil
        log.info("connect(): conexión previa=\(self.connection != nil), dispositivo en caché=\(self.device != nil)")
        guard connection == nil else { return }

        let d: IOBluetoothDevice
        do {
            d = try device ?? BoseConnection.findPairedDevice(nameContaining: nameFilter, syncState: false)
        } catch {
            log.error("Búsqueda de dispositivo: \(String(describing: error), privacy: .public)")
            status = .notPaired
            return
        }
        device = d
        deviceName = d.name

        let c = BoseConnection(device: d)
        c.trace = { [weak self] in self?.log.debug("\($0, privacy: .public)") }
        // `[weak self]` evita un ciclo de referencias entre el controlador y los
        // closures que guarda la conexión (Swift usa conteo de referencias, no un GC).
        c.onOpen = { [weak self] r in self?.channelOpenCompleted(r) }
        c.onMessage = { [weak self] m in self?.handle(m) }
        c.onClosed = { [weak self] in self?.connectionLost(reason: "canal cerrado") }
        connection = c
        status = .connecting
        do {
            try c.openAsync()
        } catch {
            connectionLost(reason: "\(error)")
            return
        }
        connectTimeoutTimer?.invalidate()
        connectTimeoutTimer = Timer.scheduledTimer(withTimeInterval: connectTimeout, repeats: false) { [weak self] _ in
            guard let self, self.status == .connecting else { return }
            self.connectionLost(reason: "sin respuesta en \(Int(self.connectTimeout)) s")
        }
    }

    private func channelOpenCompleted(_ result: IOReturn) {
        connectTimeoutTimer?.invalidate()
        connectTimeoutTimer = nil
        guard result == kIOReturnSuccess else {
            connectionLost(reason: String(format: "apertura fallida (0x%08X)", result))
            return
        }
        log.info("Canal de control abierto")
        status = .connected
        retryIndex = 0
        disconnectNotification?.unregister()
        disconnectNotification = device?.register(
            forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))
        refresh()

        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.sendQuietly(BoseCommand.getCurrentMode)
            self?.sendQuietly(BoseCommand.dumpBlock02)
        }
    }

    private func connectionLost(reason: String) {
        log.info("Conexión perdida: \(reason, privacy: .public)")
        pollTimer?.invalidate()
        pollTimer = nil
        connectTimeoutTimer?.invalidate()
        connectTimeoutTimer = nil
        // Desenganchamos los callbacks antes de cerrar: si un intento abandonado
        // por el timeout se completa más tarde, no debe alterar el estado.
        connection?.onOpen = nil
        connection?.onMessage = nil
        connection?.onClosed = nil
        connection?.close()
        connection = nil
        pendingModeIndex = nil

        guard retryIndex < retryDelays.count else {
            status = .waitingForDevice
            return
        }
        let delay = retryDelays[retryIndex]
        retryIndex += 1
        status = .retrying(seconds: Int(delay))
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.connect()
        }
    }

    private func sendQuietly(_ m: BoseMessage) {
        do { try connection?.send(m) } catch { log.error("Error enviando \(m.description): \(String(describing: error))") }
    }

    // MARK: - Mensajes recibidos (docs/protocol.md)

    private func handle(_ m: BoseMessage) {
        if m.matches(0x1f, 0x06, 0x07) {            // inicio de la lista de modos (§3.1)
            collectingModes = []
        } else if let slot = BoseDecode.modeSlot(m) {
            if collectingModes != nil {
                collectingModes!.append(slot)
            } else {
                modes.removeAll { $0.index == slot.index }
                modes.append(slot)
            }
        } else if m.matches(0x1f, 0x06, 0x06) {     // fin de la lista de modos
            if let list = collectingModes { modes = list }
            collectingModes = nil
        } else if let idx = BoseDecode.modeChangeAck(m) {   // 1f 03 03 o 1f 03 06
            currentModeIndex = idx
            if pendingModeIndex == idx { pendingModeIndex = nil }
        } else if let bands = BoseDecode.equalizer(m) {
            equalizer = bands
        } else if let entries = BoseDecode.battery(m) {
            battery = entries
        }
    }

    // MARK: - Avisos del sistema (selectores de Objective-C)

    @objc private func systemDeviceConnected(_ note: IOBluetoothUserNotification, device d: IOBluetoothDevice) {
        guard connection == nil, (d.name ?? "").localizedCaseInsensitiveContains(nameFilter) else { return }
        log.info("El sistema avisa de que los auriculares se han conectado")
        device = d
        retryIndex = 0
        // Damos un momento al sistema para terminar de montar los perfiles de audio.
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in self?.connect() }
    }

    @objc private func deviceDisconnected(_ note: IOBluetoothUserNotification, device d: IOBluetoothDevice) {
        note.unregister()
        disconnectNotification = nil
        if connection != nil { connectionLost(reason: "el sistema avisa de desconexión") }
    }
}
