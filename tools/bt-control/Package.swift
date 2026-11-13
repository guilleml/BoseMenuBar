// swift-tools-version:5.9
import PackageDescription
import Foundation

// Igual que en bt-discover: incrustamos un Info.plist en el ejecutable para que
// macOS acepte el acceso a Bluetooth desde un binario sin bundle.
let infoPlist = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Info.plist").path

let package = Package(
    name: "bt-control",
    platforms: [.macOS(.v13)],
    products: [
        // BoseKit es una biblioteca para poder reutilizarla en la app de la fase 4
        // (equivale a un .jar con el protocolo que comparten dos proyectos Java).
        .library(name: "BoseKit", targets: ["BoseKit"]),
        .executable(name: "bt-control", targets: ["bt-control"]),
    ],
    targets: [
        .target(
            name: "BoseKit",
            linkerSettings: [.linkedFramework("IOBluetooth")]
        ),
        .executableTarget(
            name: "bt-control",
            dependencies: ["BoseKit"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", infoPlist,
                ]),
            ]
        ),
        .testTarget(name: "BoseKitTests", dependencies: ["BoseKit"]),
    ]
)
