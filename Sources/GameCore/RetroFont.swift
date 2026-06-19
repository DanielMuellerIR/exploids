import CoreText
import Foundation

/// Registriert und benennt den gebündelten Retro-Pixel-Font (Press Start 2P, OFL).
/// SKLabelNode findet einen Font nur über seinen PostScript-Namen, und der Font ist nicht
/// systemweit installiert – daher muss er beim Start einmalig in den Prozess registriert werden.
/// `@MainActor`, weil alle Aufrufer (Scene-Setup) ohnehin auf dem Main-Thread laufen.
@MainActor
enum RetroFont {

    /// PostScript-Name des gebündelten Pixel-Fonts (für `SKLabelNode.fontName`).
    static let pixel = "PressStart2P-Regular"

    private static var registered = false

    /// Registriert den Font einmalig im Prozess. Idempotent.
    static func registerIfNeeded() {
        guard !registered else { return }
        registered = true

        guard let url = Bundle.module.url(forResource: "PressStart2P-Regular", withExtension: "ttf", subdirectory: "Fonts") else {
            print("RetroFont: Schriftdatei nicht im Bundle gefunden")
            return
        }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            // Bereits registriert o. Ä. ist unkritisch; nur echte Fehler loggen.
            print("RetroFont: Registrierung fehlgeschlagen: \(String(describing: error?.takeRetainedValue()))")
        }
    }
}
