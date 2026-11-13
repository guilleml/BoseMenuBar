// Descubrimiento en Bluetooth Low Energy mediante CoreBluetooth (GATT).
// Solo descubre servicios, características y descriptores; no lee ni escribe valores.
import Foundation
import CoreBluetooth

/// En Java implementarías varias interfaces de listener; aquí la clase adopta
/// dos protocolos delegados. Tiene que heredar de NSObject porque CoreBluetooth
/// es un framework de Objective-C y llama a los métodos por selector.
final class BLEDiscovery: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private let nameFilter: String
    private let scanSeconds: TimeInterval
    private var central: CBCentralManager!
    private var stateKnown = false

    private var matches: [UUID: CBPeripheral] = [:]
    private var advertisements: [UUID: [String: Any]] = [:]
    private var queue: [CBPeripheral] = []
    private var current: CBPeripheral?
    private var pendingServices = 0
    private var pendingCharacteristics = 0
    private var currentDone = false

    init(nameFilter: String, scanSeconds: TimeInterval) {
        self.nameFilter = nameFilter
        self.scanSeconds = scanSeconds
    }

    func run() {
        print("==================== BLUETOOTH LOW ENERGY (CoreBluetooth / GATT) ====================")
        // queue: nil => los callbacks llegan por la cola principal, que atiende
        // el run loop que bombeamos con pumpRunLoop.
        central = CBCentralManager(delegate: self, queue: nil)
        guard pumpRunLoop(timeout: 10, until: { self.stateKnown }) else {
            print("CoreBluetooth no informó de su estado en 10 s.\n"); return
        }
        guard central.state == .poweredOn else {
            print("CoreBluetooth no está disponible (estado=\(describe(central.state))).\n"); return
        }

        // 1) Periféricos ya conectados al sistema que expongan algún servicio
        //    estándar del SIG (Generic Access, Device Information, Battery).
        let standard = ["1800", "180A", "180F"].map { CBUUID(string: $0) }
        let connected = central.retrieveConnectedPeripherals(withServices: standard)
        print("Periféricos BLE conectados al sistema (con 1800/180A/180F): \(connected.count)")
        for p in connected {
            print("  - \(p.name ?? "(sin nombre)")  id=\(p.identifier)")
            if (p.name ?? "").localizedCaseInsensitiveContains(nameFilter) { matches[p.identifier] = p }
        }
        print("")

        // 2) Escaneo de anuncios.
        print("Escaneando anuncios BLE durante \(Int(scanSeconds)) s…")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        pumpRunLoop(timeout: scanSeconds, until: { false })
        central.stopScan()
        print("Coincidencias con \"\(nameFilter)\": \(matches.count)\n")

        // 3) Conectar a cada coincidencia y recorrer su GATT.
        queue = Array(matches.values)
        while !queue.isEmpty {
            let p = queue.removeFirst()
            inspect(p)
        }
    }

    private func inspect(_ p: CBPeripheral) {
        print("---- \(p.name ?? "(sin nombre)")  id=\(p.identifier) ----")
        if let adv = advertisements[p.identifier] { printAdvertisement(adv) }
        current = p
        currentDone = false
        pendingServices = 0
        pendingCharacteristics = 0
        p.delegate = self
        central.connect(p, options: nil)
        if !pumpRunLoop(timeout: 20, until: { self.currentDone }) {
            print("  Tiempo agotado (20 s) recorriendo el GATT; resultado parcial.")
            if let services = p.services { printServices(services) }
        }
        central.cancelPeripheralConnection(p)
        print("")
    }

    private func printAdvertisement(_ adv: [String: Any]) {
        if let n = adv[CBAdvertisementDataLocalNameKey] { print("  Anuncio · nombre local: \(n)") }
        if let s = adv[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            print("  Anuncio · UUIDs de servicio: \(s.map(\.uuidString).joined(separator: ", "))")
        }
        if let m = adv[CBAdvertisementDataManufacturerDataKey] as? Data {
            print("  Anuncio · datos de fabricante: \(hex(m))")
        }
        if let sd = adv[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
            for (k, v) in sd { print("  Anuncio · service data \(k.uuidString): \(hex(v))") }
        }
        if let c = adv[CBAdvertisementDataIsConnectable] { print("  Anuncio · conectable: \(c)") }
    }

    private func printServices(_ services: [CBService]) {
        for s in services {
            print("  Servicio \(s.uuid.uuidString)  (\(s.uuid))  primario=\(s.isPrimary)")
            for c in s.characteristics ?? [] {
                print("    Característica \(c.uuid.uuidString)  (\(c.uuid))  propiedades=[\(props(c.properties))]")
                for d in c.descriptors ?? [] {
                    print("      Descriptor \(d.uuid.uuidString)  (\(d.uuid))")
                }
            }
        }
    }

    private func props(_ p: CBCharacteristicProperties) -> String {
        var out: [String] = []
        if p.contains(.broadcast) { out.append("broadcast") }
        if p.contains(.read) { out.append("read") }
        if p.contains(.writeWithoutResponse) { out.append("writeWithoutResponse") }
        if p.contains(.write) { out.append("write") }
        if p.contains(.notify) { out.append("notify") }
        if p.contains(.indicate) { out.append("indicate") }
        if p.contains(.authenticatedSignedWrites) { out.append("signedWrite") }
        if p.contains(.extendedProperties) { out.append("extended") }
        if p.contains(.notifyEncryptionRequired) { out.append("notifyEncrypted") }
        if p.contains(.indicateEncryptionRequired) { out.append("indicateEncrypted") }
        return out.joined(separator: ", ")
    }

    private func describe(_ s: CBManagerState) -> String {
        switch s {
        case .unknown: return "unknown"
        case .resetting: return "resetting"
        case .unsupported: return "unsupported"
        case .unauthorized: return "unauthorized (revisa Ajustes > Privacidad > Bluetooth)"
        case .poweredOff: return "poweredOff"
        case .poweredOn: return "poweredOn"
        @unknown default: return "\(s.rawValue)"
        }
    }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .unknown && central.state != .resetting { stateKnown = true }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let local = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        let name = peripheral.name ?? ""
        guard name.localizedCaseInsensitiveContains(nameFilter)
                || local.localizedCaseInsensitiveContains(nameFilter) else { return }
        if matches[peripheral.identifier] == nil {
            print("  Anuncio de \(name.isEmpty ? local : name)  id=\(peripheral.identifier)  RSSI=\(RSSI)")
        }
        matches[peripheral.identifier] = peripheral
        advertisements[peripheral.identifier] = advertisementData
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("  Conectado por BLE. Descubriendo servicios…")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("  No se pudo conectar por BLE: \(error?.localizedDescription ?? "error desconocido")")
        currentDone = true
    }

    // MARK: CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { print("  Error descubriendo servicios: \(error.localizedDescription)") }
        let services = peripheral.services ?? []
        if services.isEmpty { currentDone = true; return }
        pendingServices = services.count
        for s in services { peripheral.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error { print("  Error en características de \(service.uuid): \(error.localizedDescription)") }
        for c in service.characteristics ?? [] {
            pendingCharacteristics += 1
            peripheral.discoverDescriptors(for: c)
        }
        pendingServices -= 1
        checkDone(peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        pendingCharacteristics -= 1
        checkDone(peripheral)
    }

    private func checkDone(_ p: CBPeripheral) {
        guard pendingServices == 0, pendingCharacteristics == 0, !currentDone else { return }
        printServices(p.services ?? [])
        currentDone = true
    }
}
