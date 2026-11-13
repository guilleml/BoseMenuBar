import SwiftUI

/// Punto de entrada. `@main` cumple el papel del `public static void main` de Java.
/// La app no tiene ventana principal: un `MenuBarExtra` y una ventana de
/// ecualizador que solo se abre desde el menú.
/// Sin icono en el Dock gracias a `LSUIElement = YES` (ajustes de compilación).
@main
struct BoseMenuBarApp: App {
    static let equalizerWindowID = "equalizer"

    /// `@StateObject` hace que SwiftUI cree el controlador una sola vez y lo
    /// mantenga vivo mientras viva la app (como un singleton con ámbito de app).
    @StateObject private var controller = HeadphonesController()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: controller)
        } label: {
            MenuBarLabel(controller: controller)
        }
        // `.menu` = menú nativo de macOS (no un panel flotante).
        .menuBarExtraStyle(.menu)

        // `Window` (macOS 13) = ventana única; `openWindow(id:)` la abre o la trae al frente.
        Window("Ecualizador", id: Self.equalizerWindowID) {
            EqualizerView(controller: controller)
        }
        .windowResizability(.contentSize)
    }
}
