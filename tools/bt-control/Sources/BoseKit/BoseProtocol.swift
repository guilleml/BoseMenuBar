// Comandos y decodificadores. Solo contiene lo OBSERVADO en la captura
// (docs/protocol.md). Cada elemento cita la sección del documento.

/// Peticiones. Un `enum` sin casos se usa en Swift como espacio de nombres
/// (parecido a una clase Java `final` con constructor privado y miembros `static`).
public enum BoseCommand {
    /// §3.2: `1f 03 01 00` → `1f 03 03 01 <idx>`.
    public static let getCurrentMode = BoseMessage(0x1f, 0x03, 0x01)

    /// §3.1: `1f 06 05 00` → N × `1f 06 03 30 …` y `1f 06 06 00` al final.
    public static let listModes = BoseMessage(0x1f, 0x06, 0x05)

    /// §3.3: `1f 03 05 02 <idx> 01` → `1f 03 03 01 <idx>`, `1f 03 06 01 <idx>`.
    /// CAMBIA EL ESTADO de los auriculares.
    public static func setMode(index: UInt8) -> BoseMessage {
        BoseMessage(0x1f, 0x03, 0x05, [index, 0x01])
    }

    /// §4: `02 01 05 00` → volcado del bloque 02, que incluye `02 02 03` (batería).
    public static let dumpBlock02 = BoseMessage(0x02, 0x01, 0x05)

    /// §5: `01 01 05 00` → volcado del bloque 01, que incluye `01 07 03` (ecualizador).
    /// Lo envía la app de Bose al arrancar.
    public static let dumpBlock01 = BoseMessage(0x01, 0x01, 0x05)

    /// §5: `01 07 02 02 <valor> <banda>` → `01 07 03 0c` con las 3 bandas.
    /// El valor se codifica como entero con signo de 8 bits (hipótesis §5: mín. 0xf6 = −10;
    /// en la captura solo hay valores positivos). CAMBIA EL ESTADO de los auriculares.
    public static func setEQ(band: UInt8, value: Int) -> BoseMessage {
        precondition((-128...127).contains(value))
        return BoseMessage(0x01, 0x07, 0x02, [UInt8(bitPattern: Int8(value)), band])
    }
}

public struct EQBand: Equatable {
    public let index: UInt8
    public let value: Int
    public let min: Int
    public let max: Int

    public init(index: UInt8, value: Int, min: Int, max: Int) {
        self.index = index; self.value = value; self.min = min; self.max = max
    }
}

public struct ModeSlot: Equatable {
    public let index: UInt8
    public let name: String
}

public struct BatteryEntry: Equatable {
    /// Identificador del componente (01, 02, 03, 04 en la captura).
    /// Qué es cada uno está pendiente de confirmar (§4).
    public let componentID: UInt8
    public let percent: Int
}

public enum BoseDecode {
    /// §3.2/§3.3: `1f 03 03 01 <idx>`.
    public static func currentMode(_ m: BoseMessage) -> UInt8? {
        guard m.matches(0x1f, 0x03, 0x03), m.payload.count == 1 else { return nil }
        return m.payload[0]
    }

    /// §3.3: confirmación de un cambio de modo. En la captura llegaban `1f 03 03 01 <idx>`
    /// y `1f 03 06 01 <idx>`; con bt-control (13-11-2026) solo llega `1f 03 06 01 <idx>`.
    public static func modeChangeAck(_ m: BoseMessage) -> UInt8? {
        guard m.matches(0x1f, 0x03, 0x06) || m.matches(0x1f, 0x03, 0x03), m.payload.count == 1 else { return nil }
        return m.payload[0]
    }

    /// §3.1: `1f 06 03 30 <idx> … <nombre ASCII de 32 bytes desde el byte 6 de la carga>`.
    /// Las ranuras vacías se llaman "None" y se descartan.
    public static func modeSlot(_ m: BoseMessage) -> ModeSlot? {
        guard m.matches(0x1f, 0x06, 0x03), m.payload.count >= 7 else { return nil }
        let nameBytes = m.payload[6...].prefix(32).prefix(while: { $0 != 0 })
        let name = String(decoding: nameBytes, as: UTF8.self)
        guard !name.isEmpty, name != "None" else { return nil }
        return ModeSlot(index: m.payload[0], name: name)
    }

    /// §5: `01 07 03 0c` con grupos `[mín] [máx] [valor] [banda]` (enteros con signo, hipótesis).
    public static func equalizer(_ m: BoseMessage) -> [EQBand]? {
        guard m.matches(0x01, 0x07, 0x03), !m.payload.isEmpty, m.payload.count % 4 == 0 else { return nil }
        let signed = { (b: UInt8) in Int(Int8(bitPattern: b)) }
        return stride(from: 0, to: m.payload.count, by: 4).map {
            EQBand(index: m.payload[$0 + 3], value: signed(m.payload[$0 + 2]),
                   min: signed(m.payload[$0]), max: signed(m.payload[$0 + 1]))
        }
    }

    /// §4: `02 02 03 <n×4>` con grupos `[nivel] ff ff [id]`.
    public static func battery(_ m: BoseMessage) -> [BatteryEntry]? {
        guard m.matches(0x02, 0x02, 0x03), !m.payload.isEmpty, m.payload.count % 4 == 0 else { return nil }
        return stride(from: 0, to: m.payload.count, by: 4).map {
            BatteryEntry(componentID: m.payload[$0 + 3], percent: Int(m.payload[$0]))
        }
    }
}
