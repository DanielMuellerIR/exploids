import Foundation

/// Ein einzelnes Tastenereignis innerhalb einer Aufnahme: An welchem Frame es passierte, welche
/// Taste, und ob sie gedrückt (`true`) oder losgelassen (`false`) wurde. `frameIndex` zählt die
/// Simulationsframes ab Spielstart (0-basiert) – beim Abspielen wird das Ereignis genau vor dem
/// Update dieses Frames eingespeist.
public struct InputEvent: Codable, Equatable, Sendable {
    public let frameIndex: UInt32
    public let keyCode: UInt16
    public let isDown: Bool

    public init(frameIndex: UInt32, keyCode: UInt16, isDown: Bool) {
        self.frameIndex = frameIndex
        self.keyCode = keyCode
        self.isDown = isDown
    }
}

/// Vollständige, kompakte Aufnahme eines Spieldurchlaufs. Zusammen mit der unveränderten Binary
/// reicht das aus, um den Lauf bit-genau nachzuspielen (siehe `docs/replay-system-plan.md`).
///
/// - `version`: Logik-Versions-Tag. Ändert sich die Spiel-Logik (andere RNG-Nutzung, andere
///   Physik), wird es erhöht und alte Aufnahmen werden beim Abspielen abgelehnt (sie würden sonst
///   auseinanderdriften).
/// - `seed`: Startwert des deterministischen PRNG (`GameRandom`).
/// - `startLevel` / `gameMode`: Anfangsbedingungen des Laufs.
/// - `events`: alle Tastenereignisse in zeitlicher Reihenfolge.
/// - `dtSequence`: das pro Frame angewandte `dt` (Sekunden, als `Float`). Nötig, solange das Spiel
///   einen variablen Zeitschritt hat (Phase 2); ab Fixed-Timestep (Phase 3) entfällt das.
public struct Replay: Codable, Equatable, Sendable {

    /// Aktuelles Logik-Versions-Tag. **Erhöhen, sobald eine Änderung die Simulation bei gleichem
    /// Seed/Input anders laufen lässt** (sonst werden alte Replays falsch wiedergegeben).
    public static let currentLogicVersion: Int = 1

    public let version: Int
    public let seed: UInt64
    public let startLevel: Int
    public let gameMode: GameMode
    public let events: [InputEvent]
    public let dtSequence: [Float]

    public init(version: Int = Replay.currentLogicVersion,
                seed: UInt64,
                startLevel: Int,
                gameMode: GameMode,
                events: [InputEvent],
                dtSequence: [Float]) {
        self.version = version
        self.seed = seed
        self.startLevel = startLevel
        self.gameMode = gameMode
        self.events = events
        self.dtSequence = dtSequence
    }

    /// Anzahl der aufgezeichneten Simulationsframes.
    public var frameCount: Int { dtSequence.count }

    /// Stimmt die Aufnahme mit der aktuellen Spiel-Logik überein? Bei `false` darf sie nicht
    /// abgespielt werden (würde auseinanderdriften).
    public var isCompatible: Bool { version == Replay.currentLogicVersion }

    // MARK: - Kompakte Kodierung (Binär-Property-List)

    /// Serialisiert die Aufnahme als kompakte Binär-Property-List (Foundation-eigenes Binärformat –
    /// deutlich kleiner als JSON, ohne eigenen Encoder). Geeignet zum Speichern an einem Highscore.
    public func encoded() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(self)
    }

    /// Liest eine Aufnahme aus den von `encoded()` erzeugten Daten zurück.
    public init(data: Data) throws {
        self = try PropertyListDecoder().decode(Replay.self, from: data)
    }
}
