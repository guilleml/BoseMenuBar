// Conexión RFCOMM con los auriculares mediante IOBluetooth.
import Foundation
import IOBluetooth

public enum BoseError: Error, CustomStringConvertible {
    case deviceNotFound(String)
    case notConnected
    case openFailed(IOReturn)
    case writeFailed(IOReturn)
    case timeout(String)

    public var description: String {
        switch self {
        case .deviceNotFound(let n): return "No hay ningún dispositivo emparejado cuyo nombre contenga \"\(n)\"."
        case .notConnected: return "Los auriculares no están conectados al Mac."
        case .openFailed(let r): return String(format: "No se pudo abrir el canal RFCOMM (IOReturn 0x%08X).", r)
        case .writeFailed(let r): return String(format: "Fallo al escribir (IOReturn 0x%08X).", r)
        case .timeout(let what): return "Sin respuesta a tiempo: \(what)."
        }
    }
}

/// Canal RFCOMM observado en la captura (§1). Se intenta confirmar por SDP.
public let observedControlChannel: BluetoothRFCOMMChannelID = 2

public final class BoseConnection: NSObject, IOBluetoothRFCOMMChannelDelegate {
    public let device: IOBluetoothDevice
    private var channel: IOBluetoothRFCOMMChannel?
    private var parser = MessageParser()
    private var inbox: [BoseMessage] = []
    /// Solo se acumulan mensajes en `inbox` mientras hay un `request` en curso.
    private var collecting = false

    /// Callback opcional para todo el tráfico (modo detallado / registro).
    /// Los closures de Swift equivalen a las lambdas de Java.
    public var trace: ((String) -> Void)?
    /// Se llama con cada mensaje recibido (útil para la app: notificaciones).
    public var onMessage: ((BoseMessage) -> Void)?
    public var onClosed: (() -> Void)?
    /// Resultado de `openAsync()` (kIOReturnSuccess si el canal quedó abierto).
    public var onOpen: ((IOReturn) -> Void)?

    public init(device: IOBluetoothDevice) {
        self.device = device
    }

    /// Busca entre los emparejados el primero cuyo nombre contenga `name`.
    /// `syncState`: en un CLI deja girar el run loop 1 s para que IOBluetooth
    /// sincronice el estado (observado en la fase 1). En una app el run loop ya
    /// gira por sí solo y no conviene bombearlo de forma anidada: pasar `false`.
    public static func findPairedDevice(nameContaining name: String,
                                        syncState: Bool = true) throws -> IOBluetoothDevice {
        if syncState { BoseConnection.pump(seconds: 1.0) }
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        guard let d = paired.first(where: { ($0.name ?? "").localizedCaseInsensitiveContains(name) }) else {
            throw BoseError.deviceNotFound(name)
        }
        return d
    }

    public var isOpen: Bool { channel?.isOpen() ?? false }

    /// Canal RFCOMM del servicio SerialPort (0x1101) según la caché SDP; si no
    /// aparece, se usa el observado en la captura.
    public func controlChannelID() -> BluetoothRFCOMMChannelID {
        if let rec = device.getServiceRecord(for: IOBluetoothSDPUUID(uuid16: 0x1101)) {
            var id: BluetoothRFCOMMChannelID = 0
            if rec.getRFCOMMChannelID(&id) == kIOReturnSuccess { return id }
        }
        return observedControlChannel
    }

    public func open() throws {
        // Observado: el estado de conexión de un IOBluetoothDevice se sincroniza de
        // forma asíncrona después de crear el objeto; esperamos a que llegue.
        let deadline = Date().addingTimeInterval(3)
        while !device.isConnected() && Date() < deadline { BoseConnection.pump(seconds: 0.1) }
        if !device.isConnected() {
            trace?("Abriendo conexión de banda base…")
            let r = device.openConnection()
            trace?(String(format: "openConnection → 0x%08X, isConnected=%@", r, device.isConnected() ? "sí" : "no"))
            // Observado en macOS 26: isConnected() puede seguir en false aunque el
            // sistema tenga la conexión. Solo abortamos si openConnection falla; el
            // resultado de abrir el canal RFCOMM es la comprobación definitiva.
            guard r == kIOReturnSuccess else { throw BoseError.notConnected }
        }
        let id = controlChannelID()
        trace?("Abriendo RFCOMM canal \(id)…")
        var ch: IOBluetoothRFCOMMChannel?
        let r = device.openRFCOMMChannelSync(&ch, withChannelID: id, delegate: self)
        guard r == kIOReturnSuccess, let ch else { throw BoseError.openFailed(r) }
        channel = ch
        trace?("Canal abierto (MTU \(ch.getMTU())).")
    }

    /// Apertura sin bloquear (para la app). El resultado llega por `onOpen`.
    /// No llama a openConnection(): si el sistema no tiene enlace con los
    /// auriculares, IOBluetooth intentará establecerlo al abrir el canal.
    public func openAsync() throws {
        let id = controlChannelID()
        trace?("Abriendo RFCOMM canal \(id) (asíncrono)…")
        var ch: IOBluetoothRFCOMMChannel?
        let r = device.openRFCOMMChannelAsync(&ch, withChannelID: id, delegate: self)
        guard r == kIOReturnSuccess, let ch else { throw BoseError.openFailed(r) }
        channel = ch
    }

    public func close() {
        channel?.close()
        channel = nil
    }

    public func send(_ m: BoseMessage) throws {
        guard let channel else { throw BoseError.notConnected }
        trace?("→ \(m)")
        var bytes = m.bytes
        let r = bytes.withUnsafeMutableBytes { buf in
            channel.writeSync(buf.baseAddress, length: UInt16(buf.count))
        }
        guard r == kIOReturnSuccess else { throw BoseError.writeFailed(r) }
    }

    /// Envía `m` y recoge mensajes hasta que `done` devuelva true o venza el plazo.
    /// Devuelve todos los mensajes recibidos en ese intervalo.
    @discardableResult
    public func request(_ m: BoseMessage, timeout: TimeInterval = 3,
                        what: String, until done: ([BoseMessage]) -> Bool) throws -> [BoseMessage] {
        inbox.removeAll()
        collecting = true
        defer { collecting = false; inbox.removeAll() }
        try send(m)
        let deadline = Date().addingTimeInterval(timeout)
        while !done(inbox) {
            if Date() >= deadline { throw BoseError.timeout(what) }
            BoseConnection.pump(seconds: 0.05)
        }
        return inbox
    }

    /// Deja girar el run loop actual. IOBluetooth entrega datos por él.
    public static func pump(seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    // MARK: - IOBluetoothRFCOMMChannelDelegate
    // IOBluetooth llama a estos métodos en el hilo del run loop que abrió el canal.

    public func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!,
                                  data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let chunk = Array(UnsafeRawBufferPointer(start: dataPointer, count: dataLength))
        for m in parser.feed(chunk) {
            trace?("← \(m)")
            if collecting { inbox.append(m) }
            onMessage?(m)
        }
    }

    public func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        trace?(String(format: "Apertura del canal completada (IOReturn 0x%08X).", error))
        if error != kIOReturnSuccess { channel = nil }
        onOpen?(error)
    }

    public func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        trace?("Canal RFCOMM cerrado.")
        channel = nil
        onClosed?()
    }
}

// MARK: - Operaciones de alto nivel

extension BoseConnection {
    public func readCurrentMode() throws -> UInt8 {
        let msgs = try request(BoseCommand.getCurrentMode, what: "modo actual") {
            $0.contains { BoseDecode.currentMode($0) != nil }
        }
        return msgs.compactMap(BoseDecode.currentMode).last!
    }

    /// Lista de modos; termina al recibir `1f 06 06 00` (§3.1).
    public func readModes() throws -> [ModeSlot] {
        let msgs = try request(BoseCommand.listModes, what: "lista de modos") {
            $0.contains { $0.matches(0x1f, 0x06, 0x06) }
        }
        return msgs.compactMap(BoseDecode.modeSlot)
    }

    public func readBattery() throws -> [BatteryEntry] {
        let msgs = try request(BoseCommand.dumpBlock02, what: "batería") {
            $0.contains { BoseDecode.battery($0) != nil }
        }
        return msgs.compactMap(BoseDecode.battery).last!
    }

    public func readEqualizer() throws -> [EQBand] {
        let msgs = try request(BoseCommand.dumpBlock01, what: "ecualizador") {
            $0.contains { BoseDecode.equalizer($0) != nil }
        }
        return msgs.compactMap(BoseDecode.equalizer).last!
    }

    /// Cambia una banda y espera el estado `01 07 03` con ese valor (§5).
    @discardableResult
    public func setEqualizer(band: UInt8, value: Int) throws -> [EQBand] {
        let msgs = try request(BoseCommand.setEQ(band: band, value: value), what: "confirmación del ecualizador") {
            $0.contains { BoseDecode.equalizer($0)?.contains(where: { $0.index == band && $0.value == value }) == true }
        }
        return msgs.compactMap(BoseDecode.equalizer).last!
    }

    /// Cambia de modo y espera la confirmación `1f 03 06 01 <idx>` o `1f 03 03 01 <idx>` (§3.3).
    public func setMode(index: UInt8) throws {
        try request(BoseCommand.setMode(index: index), what: "confirmación del cambio de modo") {
            $0.contains { BoseDecode.modeChangeAck($0) == index }
        }
    }
}
