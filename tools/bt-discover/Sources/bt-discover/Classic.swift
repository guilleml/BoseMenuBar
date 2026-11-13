// Descubrimiento en Bluetooth clásico (BR/EDR) mediante IOBluetooth + SDP.
import Foundation
import IOBluetooth

/// Nombres de números asignados por el Bluetooth SIG (públicos, solo para
/// facilitar la lectura). Cualquier UUID que no esté aquí se imprime en bruto.
let sigUUID16: [UInt16: String] = [
    0x0001: "SDP", 0x0003: "RFCOMM", 0x0017: "AVCTP", 0x0019: "AVDTP", 0x0100: "L2CAP",
    0x1000: "ServiceDiscoveryServer", 0x1002: "PublicBrowseRoot",
    0x1101: "SerialPort", 0x1108: "Headset", 0x110A: "AudioSource", 0x110B: "AudioSink",
    0x110C: "A/V_RemoteControlTarget", 0x110D: "AdvancedAudioDistribution",
    0x110E: "A/V_RemoteControl", 0x110F: "A/V_RemoteControlController",
    0x1112: "Headset_AG", 0x111E: "Handsfree", 0x111F: "HandsfreeAudioGateway",
    0x1131: "Headset_HS", 0x1200: "PnPInformation", 0x1203: "GenericAudio",
]

let sdpAttributeNames: [UInt16: String] = [
    0x0000: "ServiceRecordHandle", 0x0001: "ServiceClassIDList", 0x0002: "ServiceRecordState",
    0x0003: "ServiceID", 0x0004: "ProtocolDescriptorList", 0x0005: "BrowseGroupList",
    0x0006: "LanguageBaseAttributeIDList", 0x0009: "BluetoothProfileDescriptorList",
    0x000D: "AdditionalProtocolDescriptorLists",
    0x0100: "ServiceName", 0x0101: "ServiceDescription", 0x0102: "ProviderName",
]

/// Recibe el aviso de fin de la consulta SDP.
/// IOBluetooth usa un "protocolo informal" de Objective-C: no hay interfaz que
/// implementar (a diferencia de Java), basta con que el objeto responda al
/// selector `sdpQueryComplete:status:`. `@objc` expone el método con ese nombre.
final class SDPWaiter: NSObject {
    var finished = false
    var status: IOReturn = kIOReturnSuccess
    @objc func sdpQueryComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        self.status = status
        finished = true
    }
}

struct ClassicDiscovery {
    let nameFilter: String

    func run() {
        print("==================== BLUETOOTH CLÁSICO (IOBluetooth / SDP) ====================")
        // pairedDevices() puede repetir un mismo dispositivo; deduplicamos por dirección.
        var seen = Set<String>()
        let paired = ((IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? [])
            .filter { seen.insert($0.addressString ?? UUID().uuidString).inserted }
        // Observado: justo al arrancar, IOBluetooth devuelve isConnected()=false para todo.
        // El estado real llega del demonio de Bluetooth de forma asíncrona, por el
        // run loop; lo dejamos girar un momento antes de consultarlo.
        pumpRunLoop(timeout: 1.5, until: { false })
        print("Dispositivos emparejados: \(paired.count)")
        for d in paired {
            print(String(format: "  - %@  [%@]  conectado=%@  CoD=0x%06X",
                         d.name ?? "(sin nombre)", d.addressString ?? "?",
                         d.isConnected() ? "sí" : "no", d.classOfDevice))
        }
        print("")

        let targets = paired.filter { ($0.name ?? "").localizedCaseInsensitiveContains(nameFilter) }
        if targets.isEmpty {
            print("No hay ningún dispositivo emparejado cuyo nombre contenga \"\(nameFilter)\".\n")
            return
        }
        for d in targets { inspect(d) }
    }

    private func inspect(_ device: IOBluetoothDevice) {
        print("---- \(device.name ?? "?") [\(device.addressString ?? "?")] ----")
        print("Conectado: \(device.isConnected() ? "sí" : "no")")
        print(String(format: "Clase de dispositivo: 0x%06X (major=0x%02X minor=0x%02X)",
                     device.classOfDevice, device.deviceClassMajor, device.deviceClassMinor))

        let waiter = SDPWaiter()
        let rc = device.performSDPQuery(waiter)
        if rc != kIOReturnSuccess {
            print(String(format: "performSDPQuery devolvió 0x%08X; se usa la caché de servicios.", rc))
        } else if !pumpRunLoop(timeout: 20, until: { waiter.finished }) {
            print("La consulta SDP no terminó en 20 s; se usa la caché de servicios.")
        } else {
            print(String(format: "Consulta SDP completada (status=0x%08X).", waiter.status))
        }
        if let last = device.getLastServicesUpdate() {
            print("Última actualización de servicios: \(last)")
        }

        let records = (device.services as? [IOBluetoothSDPServiceRecord]) ?? []
        print("Registros SDP: \(records.count)\n")
        for (i, r) in records.enumerated() {
            printRecord(r, index: i)
        }
    }

    private func printRecord(_ r: IOBluetoothSDPServiceRecord, index: Int) {
        print("  [Registro \(index)] \(r.getServiceName() ?? "(sin nombre)")")
        var channel: BluetoothRFCOMMChannelID = 0
        if r.getRFCOMMChannelID(&channel) == kIOReturnSuccess {
            print("    Canal RFCOMM: \(channel)")
        }
        var psm: BluetoothL2CAPPSM = 0
        if r.getL2CAPPSM(&psm) == kIOReturnSuccess {
            print(String(format: "    L2CAP PSM: 0x%04X", psm))
        }
        guard let attrs = r.attributes as? [NSNumber: IOBluetoothSDPDataElement] else { return }
        for key in attrs.keys.sorted(by: { $0.uint16Value < $1.uint16Value }) {
            let id = key.uint16Value
            let label = sdpAttributeNames[id].map { " \($0)" } ?? ""
            print(String(format: "    Atributo 0x%04X%@:", id, label))
            for line in describe(attrs[key]!, indent: 6) { print(line) }
        }
        print("")
    }

    /// Recorre recursivamente un elemento de datos SDP.
    private func describe(_ e: IOBluetoothSDPDataElement, indent: Int) -> [String] {
        let pad = String(repeating: " ", count: indent)
        // Tipos según la especificación SDP: 0 nil, 1 uint, 2 int, 3 UUID,
        // 4 texto, 5 bool, 6 secuencia, 7 alternativa, 8 URL.
        switch e.getTypeDescriptor() {
        case 0: return ["\(pad)nil"]
        case 1, 2:
            let kind = e.getTypeDescriptor() == 1 ? "uint" : "int"
            // Descriptor de tamaño SDP: 0→1, 1→2, 2→4, 3→8, 4→16 bytes.
            let sizeTable: [UInt32] = [1, 2, 4, 8, 16]
            let sd = Int(e.getSizeDescriptor())
            let bytes = sd < sizeTable.count ? sizeTable[sd] : e.getSize()
            if bytes > 4 {
                // Enteros de 64/128 bits: getNumberValue no los cubre; mostrar bytes.
                let raw = (e.getDataValue()).map { hex($0) } ?? "?"
                return ["\(pad)\(kind)\(bytes * 8) \(raw)"]
            }
            let v = e.getNumberValue()?.uint32Value ?? 0
            // IOBluetooth no conserva el ancho original del entero (lo normaliza), así que no lo mostramos.
            return ["\(pad)\(kind) 0x\(String(v, radix: 16, uppercase: true)) (\(v))"]
        case 3:
            guard let u = e.getUUIDValue() else { return ["\(pad)UUID ?"] }
            let data = Data(referencing: u)
            var name = ""
            // Los UUID de 16 y 32 bits son abreviaturas de la base del SIG
            // 0000xxxx-0000-1000-8000-00805F9B34FB; si los 16 bits altos son 0, buscamos el nombre.
            var short: UInt16? = nil
            if data.count == 2 { short = UInt16(data[0]) << 8 | UInt16(data[1]) }
            if data.count == 4, data[0] == 0, data[1] == 0 { short = UInt16(data[2]) << 8 | UInt16(data[3]) }
            if let v = short, let n = sigUUID16[v] { name = "  (\(n))" }
            if data.count == 16 {
                let h = data.map { String(format: "%02X", $0) }.joined()
                let parts = [h.prefix(8), h.dropFirst(8).prefix(4), h.dropFirst(12).prefix(4),
                             h.dropFirst(16).prefix(4), h.dropFirst(20)]
                name = "  = " + parts.joined(separator: "-")
            }
            return ["\(pad)UUID\(data.count * 8) \(hex(data))\(name)"]
        case 4: return ["\(pad)texto \"\(e.getStringValue() ?? "")\""]
        case 5: return ["\(pad)bool \(e.getNumberValue()?.boolValue ?? false)"]
        case 6, 7:
            let kind = e.getTypeDescriptor() == 6 ? "secuencia" : "alternativa"
            let items = (e.getArrayValue() as? [IOBluetoothSDPDataElement]) ?? []
            return ["\(pad)\(kind) (\(items.count))"] + items.flatMap { describe($0, indent: indent + 2) }
        case 8: return ["\(pad)URL \"\(e.getStringValue() ?? "")\""]
        default: return ["\(pad)tipo desconocido \(e.getTypeDescriptor())"]
        }
    }
}
