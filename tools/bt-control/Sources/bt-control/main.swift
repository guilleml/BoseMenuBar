// bt-control: cliente mínimo de línea de comandos.
//
//   bt-control battery                 Lee la batería.
//   bt-control mode                    Muestra el modo actual.
//   bt-control modes                   Lista los modos guardados en los auriculares.
//   bt-control mode <nombre>           Cambia al modo (quiet, aware, immersion o cualquier nombre de la lista).
//
//   Opciones: -v (muestra el tráfico en hexadecimal), --name <subcadena> (por defecto "Bose").
import Foundation
import BoseKit

var args = Array(CommandLine.arguments.dropFirst())
var verbose = false
var deviceName = "Bose"
if let i = args.firstIndex(of: "-v") { verbose = true; args.remove(at: i) }
if let i = args.firstIndex(of: "--name"), i + 1 < args.count {
    deviceName = args[i + 1]; args.removeSubrange(i...(i + 1))
}

func usage() -> Never {
    print("""
    Uso: bt-control [-v] [--name <subcadena>] <comando>
      battery            Lee la batería
      mode               Muestra el modo actual
      modes              Lista los modos de los auriculares
      mode <nombre>      Cambia de modo (quiet | aware | immersion | otro nombre de la lista)
      eq                 Muestra el ecualizador
      eq <banda> <valor> Cambia una banda del ecualizador
    """)
    exit(2)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("Error: \(message)\n".data(using: .utf8)!)
    exit(1)
}

guard let command = args.first else { usage() }

do {
    let device = try BoseConnection.findPairedDevice(nameContaining: deviceName)
    let conn = BoseConnection(device: device)
    if verbose { conn.trace = { print("  [trace] \($0)") } }
    try conn.open()
    // `defer` se ejecuta al salir del ámbito, como un `finally` de Java.
    defer { conn.close() }

    switch (command, args.count) {
    case ("battery", 1):
        for e in try conn.readBattery() {
            print(String(format: "Componente %02X: %d %%", e.componentID, e.percent))
        }
        print("(ID 03 probablemente es el estuche; el resto está pendiente de confirmar. Ver docs/protocol.md §4)")

    case ("modes", 1):
        let current = try conn.readCurrentMode()
        for s in try conn.readModes() {
            print(String(format: "%@ %02X  %@", s.index == current ? "*" : " ", s.index, s.name))
        }

    case ("mode", 1):
        let current = try conn.readCurrentMode()
        let name = try conn.readModes().first { $0.index == current }?.name ?? "?"
        print(String(format: "Modo actual: %@ (índice %02X)", name, current))

    case ("mode", 2):
        let wanted = args[1]
        let modes = try conn.readModes()
        // El índice sale de la lista que devuelven los auriculares, no de una tabla fija.
        guard let slot = modes.first(where: { $0.name.caseInsensitiveCompare(wanted) == .orderedSame }) else {
            fail("No hay ningún modo llamado \"\(wanted)\". Disponibles: \(modes.map(\.name).joined(separator: ", "))")
        }
        try conn.setMode(index: slot.index)
        print(String(format: "Modo cambiado a %@ (índice %02X).", slot.name, slot.index))

    case ("eq", 1):
        for b in try conn.readEqualizer() {
            print("Banda \(b.index): \(b.value)  (rango \(b.min)…\(b.max))")
        }

    case ("eq", 3):
        guard let band = UInt8(args[1]), let value = Int(args[2]) else { usage() }
        let bands = try conn.readEqualizer()
        guard let current = bands.first(where: { $0.index == band }) else {
            fail("No existe la banda \(band). Bandas: \(bands.map { String($0.index) }.joined(separator: ", "))")
        }
        guard (current.min...current.max).contains(value) else {
            fail("Valor fuera de rango (\(current.min)…\(current.max)).")
        }
        for b in try conn.setEqualizer(band: band, value: value) {
            print("Banda \(b.index): \(b.value)")
        }

    default:
        usage()
    }
} catch {
    fail("\(error)")
}
