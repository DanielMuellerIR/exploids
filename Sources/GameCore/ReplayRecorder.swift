import Foundation

/// Zeichnet einen laufenden Spieldurchlauf auf: Anfangsbedingungen (Seed/Level/Modus), alle
/// Tastenereignisse und das pro Frame angewandte `dt`. Aus dem Gesammelten entsteht am Ende ein
/// `Replay` (siehe `Replay.swift`).
///
/// Der Recorder ist bewusst „dumm": Er weiß nichts über Spiel-Logik, er hängt nur Werte an. Die
/// GameScene ruft `recordEvent` in den Tasten-Handlern und `recordFrame` einmal pro Simulationsframe.
public final class ReplayRecorder {

    private let seed: UInt64
    private let startLevel: Int
    private let gameMode: GameMode

    private var events: [InputEvent] = []
    private var dts: [Float] = []

    public init(seed: UInt64, startLevel: Int, gameMode: GameMode) {
        self.seed = seed
        self.startLevel = startLevel
        self.gameMode = gameMode
    }

    /// Index des nächsten aufzuzeichnenden Frames (= Anzahl bereits aufgezeichneter Frames). Ein
    /// Tastenereignis, das jetzt eintrifft, gehört zu genau diesem (noch kommenden) Frame.
    public var nextFrameIndex: UInt32 { UInt32(dts.count) }

    /// Hält ein Tastenereignis fest (mit dem aktuellen Frame-Index).
    public func recordEvent(keyCode: UInt16, isDown: Bool) {
        events.append(InputEvent(frameIndex: nextFrameIndex, keyCode: keyCode, isDown: isDown))
    }

    /// Hält das in diesem Frame angewandte `dt` fest.
    public func recordFrame(dt: TimeInterval) {
        dts.append(Float(dt))
    }

    /// Baut aus dem bisher Gesammelten eine `Replay`-Aufnahme. Nicht-destruktiv: kann auch
    /// zwischendurch (z. B. in Tests) aufgerufen werden, ohne die Aufnahme zu beenden.
    public func makeReplay() -> Replay {
        Replay(seed: seed, startLevel: startLevel, gameMode: gameMode,
               events: events, dtSequence: dts)
    }
}
