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
    /// v2: Auto-Feuer-Zustand wird in der Aufnahme gespeichert und beim Abspielen wiederhergestellt
    ///     (vorher fehlte er → mit Auto-Feuer gespielte Läufe ließen sich nicht reproduzieren).
    public static let currentLogicVersion: Int = 2

    public let version: Int
    public let seed: UInt64
    public let startLevel: Int
    public let gameMode: GameMode
    public let events: [InputEvent]
    public let dtSequence: [Float]
    /// War Auto-Feuer beim aufgezeichneten Lauf aktiv? Auto-Feuer lässt das Schiff in `update()`
    /// ohne Tastendruck schießen und beeinflusst damit den Spielverlauf (Sim-Zustand). Muss daher
    /// fürs Replay festgehalten und wiederhergestellt werden. Bei alten Aufnahmen ohne dieses Feld
    /// (vor dem Fix) wird `false` angenommen.
    public let autoFire: Bool

    public init(version: Int = Replay.currentLogicVersion,
                seed: UInt64,
                startLevel: Int,
                gameMode: GameMode,
                events: [InputEvent],
                dtSequence: [Float],
                autoFire: Bool = false) {
        self.version = version
        self.seed = seed
        self.startLevel = startLevel
        self.gameMode = gameMode
        self.events = events
        self.dtSequence = dtSequence
        self.autoFire = autoFire
    }

    // Rückwärtskompatible Dekodierung: Aufnahmen von vor dem autoFire-Fix haben das Feld nicht →
    // dann `false`. Alle anderen Felder sind Pflicht.
    private enum CodingKeys: String, CodingKey {
        case version, seed, startLevel, gameMode, events, dtSequence, autoFire
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try c.decode(Int.self, forKey: .version)
        self.seed = try c.decode(UInt64.self, forKey: .seed)
        self.startLevel = try c.decode(Int.self, forKey: .startLevel)
        self.gameMode = try c.decode(GameMode.self, forKey: .gameMode)
        self.events = try c.decode([InputEvent].self, forKey: .events)
        self.dtSequence = try c.decode([Float].self, forKey: .dtSequence)
        self.autoFire = try c.decodeIfPresent(Bool.self, forKey: .autoFire) ?? false
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
