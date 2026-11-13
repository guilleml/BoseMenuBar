import SwiftUI
import AppKit
import BoseKit

/// Lo que se ve en la propia barra de menús: icono de auriculares + barrita de batería.
struct MenuBarLabel: View {
    /// `@ObservedObject`: la vista se redibuja cuando cambia una propiedad
    /// `@Published` del controlador (patrón observador, como un PropertyChangeListener).
    @ObservedObject var controller: HeadphonesController

    var body: some View {
        // La etiqueta de un MenuBarExtra acaba en el botón de un NSStatusItem, que
        // muestra una sola imagen: con dos `Image` en un HStack la segunda se perdía.
        // Por eso dibujamos los dos símbolos en una única NSImage.
        Image(nsImage: Self.statusImage(percent: controller.isConnected ? controller.earbudsPercent : nil))
    }

    /// SF Symbols trae la batería en 5 escalones; elegimos el más cercano.
    static func batterySymbol(for percent: Int) -> String {
        switch percent {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    static func statusImage(percent: Int?) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        func symbol(_ name: String) -> NSImage? {
            NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        }
        guard let earbuds = symbol("earbuds") else { return NSImage() }
        guard let p = percent, let battery = symbol(batterySymbol(for: p)) else {
            earbuds.isTemplate = true
            return earbuds
        }
        let spacing: CGFloat = 4
        let size = NSSize(width: earbuds.size.width + spacing + battery.size.width,
                          height: max(earbuds.size.height, battery.size.height))
        let image = NSImage(size: size, flipped: false) { _ in
            earbuds.draw(in: NSRect(x: 0, y: (size.height - earbuds.size.height) / 2,
                                    width: earbuds.size.width, height: earbuds.size.height))
            battery.draw(in: NSRect(x: earbuds.size.width + spacing, y: (size.height - battery.size.height) / 2,
                                    width: battery.size.width, height: battery.size.height))
            return true
        }
        // "Template": macOS la tiñe según el modo claro/oscuro de la barra.
        image.isTemplate = true
        image.accessibilityDescription = "Auriculares, batería \(p) %"
        return image
    }
}

/// Contenido del menú desplegable.
struct MenuContent: View {
    @ObservedObject var controller: HeadphonesController
    /// Acción de entorno para abrir una escena `Window` por su id.
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(controller.deviceName ?? "Bose QC Ultra Earbuds")
        Text(controller.statusText)

        if controller.isConnected {
            Divider()
            Text("Izquierdo: \(percentText(controller.leftPercent))")
            Text("Derecho: \(percentText(controller.rightPercent))")
            Text("Estuche: \(percentText(controller.casePercent))")

            Divider()
            // En un menú, un Picker `.inline` se muestra como opciones con marca ✓.
            Picker("Modo", selection: modeBinding) {
                ForEach(controller.selectableModes, id: \.index) { slot in
                    Text(slot.name).tag(Optional(slot.index))
                }
            }
            .pickerStyle(.inline)

            if let other = controller.currentOtherModeName {
                Text("Modo actual: \(other)")
            }

            Divider()
            Button("Ecualizador…") {
                openWindow(id: BoseMenuBarApp.equalizerWindowID)
                // Una app sin Dock (LSUIElement) no pasa a primer plano sola.
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        Divider()
        if controller.isConnected {
            Button("Actualizar") { controller.refresh() }
        } else {
            Button("Reconectar") { controller.reconnectNow() }
        }
        Button("Salir") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// Un `Binding` es una referencia de lectura/escritura a un valor: aquí lee el
    /// modo actual y, al elegir otro, pide el cambio a los auriculares.
    private var modeBinding: Binding<UInt8?> {
        Binding(
            get: { controller.pendingModeIndex ?? controller.currentModeIndex },
            set: { if let i = $0 { controller.setMode(index: i) } }
        )
    }

    private func percentText(_ p: Int?) -> String {
        p.map { "\($0) %" } ?? "–"
    }
}
