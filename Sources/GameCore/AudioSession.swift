import Foundation

#if os(iOS)
import AVFoundation

/// iOS benötigt eine konfigurierte und aktivierte AVAudioSession, BEVOR AVAudioEngine (SFX) oder
/// AVAudioPlayer (Musik) Ton ausgeben – sonst bleibt das Gerät stumm. macOS kennt diese API nicht
/// und braucht sie nicht (dort ist diese Datei komplett aus dem Build genommen).
///
/// Kategorie `.playback`: Das Spiel soll Ton geben, auch wenn der seitliche Stummschalter aktiv ist
/// (klassisches Spiel-Verhalten); die Lautstärke regelt der Nutzer per Hardware-Tasten bzw. den
/// In-Game-Musik-Schalter.
enum AudioSessionConfig {

    /// Einmalig (idempotent, thread-sicher) die Session aufsetzen und aktivieren.
    static func activate() {
        lock.lock()
        defer { lock.unlock() }
        guard !configured else { return }
        configured = true
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("AudioSessionConfig: Konfiguration fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    private static let lock = NSLock()
    // Zugriff ausschließlich unter `lock` -> der unsafe-Marker ist hier korrekt (Swift-6-Concurrency).
    nonisolated(unsafe) private static var configured = false
}
#endif
