import SpriteKit
import ImageIO

/// Lädt vektorisierte Boss-Grafiken (PNG) aus dem GameCore-Ressourcenbundle als `SKTexture`.
///
/// Warum nicht `SKTexture(imageNamed:)`? Dieser Convenience-Initializer sucht im **Haupt**-Bundle der
/// App. Unsere Grafiken liegen aber im **Modul**-Bundle der GameCore-Library (`Bundle.module`,
/// Unterordner `Art`). Außerdem soll GameCore plattformneutral bleiben (macOS **und** iOS) – deshalb
/// laden wir die Datei über `ImageIO` zu einem `CGImage` und bauen daraus die Textur. So vermeiden wir
/// den Umweg über `NSImage`/`UIImage`, der je Plattform unterschiedlich wäre.
@MainActor
enum ArtTexture {

    /// Cache, damit dieselbe Grafik nicht mehrfach dekodiert wird (Bosse können wiederholt spawnen).
    /// `@MainActor`-isoliert (Textur-Laden läuft im Szenen-Aufbau auf dem Main-Thread), analog `RetroFont`.
    private static var cache: [String: SKTexture] = [:]

    /// Lädt die Textur `name` (ohne Endung) aus `Art/`. Liefert `nil`, wenn die Datei fehlt – die
    /// aufrufende Klasse kann dann auf einen einfachen Platzhalter ausweichen.
    static func load(_ name: String) -> SKTexture? {
        if let cached = cache[name] { return cached }
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Art"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        let texture = SKTexture(cgImage: cgImage)
        cache[name] = texture
        return texture
    }
}
