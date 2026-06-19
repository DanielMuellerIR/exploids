import AVFoundation
import Foundation

/// Spielt die Chiptune-Hintergrundmusik ab: die vorhandenen Tracks laufen abwechselnd in
/// Endlosschleife – durchgehend über Start-, Spiel- und Game-Over-Screen.
///
/// Die Musik lässt sich global mit „M" ein-/ausschalten. Einmal ausgeschaltet, bleibt sie bis zum
/// Programmende aus (reiner Laufzeit-Schalter, kein Persistieren) – außer man schaltet sie wieder ein.
public final class MusicPlayer: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {

    /// Gemeinsame Singleton-Instanz.
    public static let shared = MusicPlayer()

    private var player: AVAudioPlayer?
    private var tracks: [URL] = []
    private var index = 0

    /// Ob Musik aktuell gewünscht ist (Schalter über „M").
    public private(set) var isEnabled = true

    // In Tests bzw. mit --no-sound spielt keine Musik.
    private let isSuppressed: Bool = {
        let env = ProcessInfo.processInfo.environment
        let testing = env["XCTestConfigurationFilePath"] != nil
        let noSound = CommandLine.arguments.contains("--no-sound")
        return testing || noSound
    }()

    private override init() {
        super.init()
        loadTracks()
    }

    /// Lädt die mitgelieferten Musik-Tracks aus dem Modul-Bundle.
    private func loadTracks() {
        // Reihenfolge bestimmt die Abwechslung; weitere Tracks hier ergänzen.
        let names = ["asteroid-storm", "neon-vectors"]
        for name in names {
            if let url = Bundle.module.url(forResource: name, withExtension: "mp3", subdirectory: "Music") {
                tracks.append(url)
            }
        }
    }

    /// Startet die Wiedergabe (falls aktiviert und noch nicht laufend).
    public func start() {
        guard isEnabled, !isSuppressed, !tracks.isEmpty else { return }
        if player?.isPlaying == true { return }
        if let existing = player {
            existing.play() // aus Pause fortsetzen
        } else {
            playCurrent()
        }
    }

    private func playCurrent() {
        guard index >= 0 && index < tracks.count else { index = 0; return }
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: tracks[index])
            newPlayer.delegate = self
            newPlayer.volume = 0.8
            newPlayer.prepareToPlay()
            newPlayer.play()
            player = newPlayer
        } catch {
            print("MusicPlayer: Track konnte nicht geladen werden: \(error)")
        }
    }

    /// Schaltet die Musik ein bzw. aus.
    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            start()
        } else {
            player?.pause()
        }
    }

    /// Umschalten (für die „M"-Taste).
    public func toggle() {
        setEnabled(!isEnabled)
    }

    // MARK: - AVAudioPlayerDelegate

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // Zum nächsten Track wechseln (abwechselnd, dann von vorn).
        if !tracks.isEmpty {
            index = (index + 1) % tracks.count
        }
        if isEnabled && !isSuppressed {
            playCurrent()
        }
    }
}
