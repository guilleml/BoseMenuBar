// swift-tools-version:5.9
// Herramienta de descubrimiento Bluetooth (solo lectura: no escribe nada en el dispositivo).
import PackageDescription
import Foundation

// CoreBluetooth exige que el binario declare NSBluetoothAlwaysUsageDescription.
// Un ejecutable de línea de comandos no tiene bundle, así que incrustamos el
// Info.plist en la sección __TEXT,__info_plist del binario mediante el linker.
let infoPlist = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Info.plist").path

let package = Package(
    name: "bt-discover",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "bt-discover",
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreBluetooth"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", infoPlist,
                ]),
            ]
        ),
    ]
)
