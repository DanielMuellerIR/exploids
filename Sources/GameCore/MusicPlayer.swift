import AVFoundation
import Foundation

/// Spielt die Chiptune-Hintergrundmusik ab: die vorhandenen Tracks laufen abwechselnd in
/// Endlosschleife – durchgehend über Start-, Spiel- und Game-Over-Screen.
///
/// Die Musik lässt sich global mit „M" ein-/ausschalten. Einmal ausgeschaltet, bleibt sie bis zum
/// Programmende aus (reiner Laufzeit-Schalter, kein Persistieren) – außer man schaltet sie wieder ein.
///
/// Plattform-Unterschied bei der Wiedergabe:
/// - **macOS**: eigenständiger `AVAudioPlayer` (funktioniert dort einwandfrei).
/// - **iOS**: die Musik läuft als `AVAudioPlayerNode` an derselben `AVAudioEngine` wie die SFX
///   (siehe `SoundManager.makeMusicNode`). Grund: Ein separater `AVAudioPlayer` neben der laufenden
///   SFX-Engine erzeugt auf iOS Verzerrungen (zwei Render-Pfade auf dieselbe Audio-Hardware). Über
///   einen gemeinsamen Knoten gibt es nur einen Render-Pfad und damit saubere Musik.
public final class MusicPlayer: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {

    /// Gemeinsame Singleton-Instanz.
    public static let shared = MusicPlayer()

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

    #if os(iOS)
    // iOS: Musik als Knoten in der gemeinsamen SFX-Engine. Planung und Completion-Verarbeitung
    // laufen auf der Steuerseite; der Audio-Callback reicht nur die Benachrichtigung weiter.
    private let lock = NSLock()
    private var musicNode: AVAudioPlayerNode?
    private var started = false
    private var needsScheduling = true
    private var scheduleGeneration = 0
    #else
    // macOS: eigenständiger AVAudioPlayer.
    private var player: AVAudioPlayer?
    #endif

    private override init() {
        super.init()
        loadTracks()
    }

    /// Lädt die mitgelieferten Musik-Tracks aus dem Modul-Bundle.
    private func loadTracks() {
        // Reihenfolge bestimmt die Abwechslung; weitere Tracks hier ergänzen.
        let names = ["asteroid-storm", "neon-vectors"]
        for name in names {
            if let url = GameCoreResources.bundle.url(forResource: name, withExtension: "mp3", subdirectory: "Music") {
                tracks.append(url)
            }
        }
    }

    /// Startet die Wiedergabe (falls aktiviert und noch nicht laufend).
    public func start() {
        guard isEnabled, !isSuppressed, !tracks.isEmpty else { return }
        #if os(iOS)
        startEngineMusic()
        #else
        if player?.isPlaying == true { return }
        if let existing = player {
            existing.play() // aus Pause fortsetzen
        } else {
            playCurrent()
        }
        #endif
    }

    /// Schaltet die Musik ein bzw. aus.
    public func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            start()
        } else {
            #if os(iOS)
            lock.lock()
            musicNode?.pause()
            lock.unlock()
            #else
            player?.pause()
            #endif
        }
    }

    /// Umschalten (für die „M"-Taste).
    public func toggle() {
        setEnabled(!isEnabled)
    }

    #if os(iOS)

    // MARK: - iOS: Musik über die gemeinsame Engine

    /// Startet (oder setzt fort) die Musik als Knoten an der SFX-Engine.
    private func startEngineMusic() {
        lock.lock()
        defer { lock.unlock() }

        // Ein Engine-Reset oder Trackende bei ausgeschalteter Musik verwirft die Planung.
        if started {
            if needsScheduling { scheduleCurrentLocked() }
            if !needsScheduling { musicNode?.play() }
            return
        }

        // Knoten anhand des Formats des ersten Tracks erzeugen. Alle Tracks liegen im selben
        // Format vor (48 kHz Stereo), daher genügt das Format des ersten zum Verbinden.
        guard let firstURL = tracks.first,
              let firstFile = try? AVAudioFile(forReading: firstURL),
              let node = SoundManager.shared.makeMusicNode(format: firstFile.processingFormat) else {
            return
        }
        musicNode = node
        node.volume = 0.8
        started = true

        // Nach einem Engine-Neustart (Konfigurationswechsel) muss der Knoten neu eingeplant werden –
        // die Engine hat beim Stopp alle geplanten Daten verworfen.
        SoundManager.shared.onEngineReset = { [weak self] in
            self?.handleEngineReset()
        }

        scheduleCurrentLocked()
        if !needsScheduling { node.play() }
    }

    /// Nach einem Engine-Neustart: den (noch attachten) Knoten neu einplanen und weiterspielen.
    private func handleEngineReset() {
        lock.lock()
        defer { lock.unlock() }
        guard started, let node = musicNode else { return }
        scheduleGeneration += 1 // Completion einer verworfenen Planung darf die Playlist nicht weiterschalten.
        needsScheduling = true
        node.stop()              // verwirft Reste, setzt den Knoten zurück
        if isEnabled && !isSuppressed {
            scheduleCurrentLocked()
            if !needsScheduling { node.play() }
        }
    }

    /// Plant den aktuellen Track ein; im Completion-Handler wird auf den nächsten Track gewechselt
    /// und dieser angehängt – so läuft die Playlist in Endlosschleife. „Locked" = der Aufrufer hält
    /// bereits `lock`.
    private func scheduleCurrentLocked() {
        guard let node = musicNode, index >= 0, index < tracks.count else { return }
        guard let file = try? AVAudioFile(forReading: tracks[index]) else { return }
        let generation = scheduleGeneration
        needsScheduling = false
        node.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            // Planung/Dateizugriffe gehören auf die Steuerseite, nicht in den Audio-Callback.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lock.lock()
                defer { self.lock.unlock() }
                guard generation == self.scheduleGeneration else { return }
                self.needsScheduling = true
                if !self.tracks.isEmpty { self.index = (self.index + 1) % self.tracks.count }
                if self.isEnabled && !self.isSuppressed { self.scheduleCurrentLocked() }
            }
        }
    }

    #else

    // MARK: - macOS: eigenständiger AVAudioPlayer

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

    // MARK: - AVAudioPlayerDelegate (nur macOS)

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // Zum nächsten Track wechseln (abwechselnd, dann von vorn).
        if !tracks.isEmpty {
            index = (index + 1) % tracks.count
        }
        if isEnabled && !isSuppressed {
            playCurrent()
        }
    }

    #endif
}
