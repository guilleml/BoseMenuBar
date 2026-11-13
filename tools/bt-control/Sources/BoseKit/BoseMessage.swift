// Formato de mensaje observado en el canal RFCOMM 2 (ver docs/protocol.md, sección 2):
//
//   [b0 bloque] [b1 función] [op] [longitud] [carga…]
//
// En Swift, `struct` es un tipo valor: se copia al asignarlo, como un `record`
// de Java pero sin referencias compartidas. Es lo idiomático para datos inmutables.

public struct BoseMessage: Equatable, CustomStringConvertible {
    public let block: UInt8
    public let function: UInt8
    public let op: UInt8
    public let payload: [UInt8]

    public init(_ block: UInt8, _ function: UInt8, _ op: UInt8, _ payload: [UInt8] = []) {
        precondition(payload.count <= 0xFF, "la carga no cabe en el byte de longitud")
        self.block = block
        self.function = function
        self.op = op
        self.payload = payload
    }

    public var bytes: [UInt8] { [block, function, op, UInt8(payload.count)] + payload }

    public func matches(_ block: UInt8, _ function: UInt8, _ op: UInt8) -> Bool {
        self.block == block && self.function == function && self.op == op
    }

    public var description: String {
        let head = [block, function, op, UInt8(payload.count)].hexString
        return payload.isEmpty ? head : "\(head) | \(payload.hexString)"
    }
}

/// Reensambla mensajes a partir de trozos de datos recibidos. Un trozo puede
/// traer varios mensajes, o la mitad de uno (lo observado en la captura).
public struct MessageParser {
    private var buffer: [UInt8] = []

    public init() {}

    /// `mutating` es necesario porque modifica el propio struct (tipo valor).
    public mutating func feed(_ data: [UInt8]) -> [BoseMessage] {
        buffer += data
        var out: [BoseMessage] = []
        while buffer.count >= 4 {
            let total = 4 + Int(buffer[3])
            guard buffer.count >= total else { break }
            out.append(BoseMessage(buffer[0], buffer[1], buffer[2], Array(buffer[4..<total])))
            buffer.removeFirst(total)
        }
        return out
    }

    public var pendingBytes: Int { buffer.count }
}

extension Array where Element == UInt8 {
    public var hexString: String { map { String(format: "%02x", $0) }.joined(separator: " ") }
}
