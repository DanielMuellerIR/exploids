import Foundation

/// Spielt eine `Replay`-Aufnahme Frame für Frame ab. Der Player ist die Gegenstück-„dumme" Klasse
/// zum Recorder: Er kennt keine Spiel-Logik, sondern speist nur zum richtigen Frame die
/// aufgezeichneten Tastenereignisse ein und liefert das aufgezeichnete `dt`.
///
/// Die GameScene fragt pro Frame `nextFrameDt(injectingInto:)`: Erst werden alle Ereignisse dieses
/// Frames in die Szene eingespeist, dann wird das `dt` zurückgegeben, das die Szene statt der
/// Echtzeit anwenden soll. Liefert die Methode `nil`, ist die Aufnahme zu Ende.
public final class ReplayPlayer {

    public let replay: Replay
    private var nextEventIndex = 0
    private var currentFrame: UInt32 = 0

    public init(replay: Replay) {
        self.replay = replay
    }

    /// Ist die Wiedergabe durch (alle aufgezeichneten Frames abgespielt)?
    public var isFinished: Bool { Int(currentFrame) >= replay.dtSequence.count }

    /// Speist die Tastenereignisse des aktuellen Frames in die Szene ein und gibt das anzuwendende
    /// `dt` zurück. `nil`, wenn keine weiteren Frames mehr vorliegen.
    public func nextFrameDt(injectingInto scene: GameScene) -> TimeInterval? {
        guard Int(currentFrame) < replay.dtSequence.count else { return nil }

        // Alle Ereignisse mit frameIndex == aktuellem Frame einspeisen (Reihenfolge wie aufgezeichnet).
        while nextEventIndex < replay.events.count,
              replay.events[nextEventIndex].frameIndex == currentFrame {
            let e = replay.events[nextEventIndex]
            scene.injectReplayInput(keyCode: e.keyCode, isDown: e.isDown)
            nextEventIndex += 1
        }

        let dt = TimeInterval(replay.dtSequence[Int(currentFrame)])
        currentFrame += 1
        return dt
    }
}
