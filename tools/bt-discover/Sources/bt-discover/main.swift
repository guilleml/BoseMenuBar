// bt-discover: lista dispositivos emparejados, servicios SDP (Bluetooth clásico)
// y servicios/características GATT (BLE) de un dispositivo buscado por nombre.
//
// Uso: bt-discover [--name <subcadena>] [--scan <segundos>] [--no-ble] [--no-sdp]
//
// IMPORTANTE: esta herramienta es de solo lectura. No escribe características
// ni abre canales RFCOMM, así que no cambia el estado de los auriculares.

import Foundation

struct Options {
    var name = "Bose"
    var scanSeconds: TimeInterval = 8
    var doSDP = true
    var doBLE = true
}

func parseOptions() -> Options {
    var o = Options()
    var args = CommandLine.arguments.dropFirst().makeIterator()
    while let a = args.next() {
        switch a {
        case "--name": if let v = args.next() { o.name = v }
        case "--scan": if let v = args.next(), let s = TimeInterval(v) { o.scanSeconds = s }
        case "--no-ble": o.doBLE = false
        case "--no-sdp": o.doSDP = false
        case "-h", "--help":
            print("Uso: bt-discover [--name <subcadena>] [--scan <segundos>] [--no-ble] [--no-sdp]")
            exit(0)
        default:
            FileHandle.standardError.write("Argumento desconocido: \(a)\n".data(using: .utf8)!)
            exit(2)
        }
    }
    return o
}

/// IOBluetooth y CoreBluetooth entregan resultados de forma asíncrona sobre el
/// run loop principal. En una app eso lo hace el framework; en un CLI tenemos que
/// "bombear" el run loop nosotros hasta que se cumpla la condición o venza el plazo.
@discardableResult
func pumpRunLoop(timeout: TimeInterval, until done: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !done() && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
    }
    return done()
}

func hex(_ data: Data) -> String {
    data.map { String(format: "%02X", $0) }.joined(separator: " ")
}

let opts = parseOptions()
print("bt-discover — \(ISO8601DateFormatter().string(from: Date()))")
print("Filtro de nombre: \"\(opts.name)\" (sin distinguir mayúsculas)")
print("")

if opts.doSDP {
    ClassicDiscovery(nameFilter: opts.name).run()
}
if opts.doBLE {
    BLEDiscovery(nameFilter: opts.name, scanSeconds: opts.scanSeconds).run()
}
