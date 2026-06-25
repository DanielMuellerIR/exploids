import Foundation

/// Spielt eine `Replay`-Aufnahme Schritt für Schritt ab. Der Player ist die Gegenstück-„dumme"
/// Klasse zum Recorder: Er kennt keine Spiel-Logik, sondern speist nur zum richtigen Schritt die
/// aufgezeichneten Tastenereignisse ein. Bei Fixed-Timestep ist jeder Schritt gleich lang
/// (`GameScene.simStep`), darum braucht es kein aufgezeichnetes `dt` mehr.
///
/// Die GameScene ruft pro Simulationsschritt `advanceStep(injectingInto:)`: Erst werden alle
/// Ereignisse dieses Schritts eingespeist, dann wird `true` zurückgegeben (Schritt ausführen).
/// Liefert die Methode `false`, ist die Aufnahme zu Ende.
public final class ReplayPlayer {

    public let replay: Replay
    private var nextEventIndex = 0
    private var currentFrame: UInt32 = 0

    public init(replay: Replay) {
        self.replay = replay
    }

    /// Ist die Wiedergabe durch (alle aufgezeichneten Schritte abgespielt)?
    public var isFinished: Bool { Int(currentFrame) >= replay.frameCount }

    /// Speist die Tastenereignisse des aktuellen Schritts in die Szene ein und schaltet einen Schritt
    /// weiter. Rückgabe `false`, wenn keine weiteren Schritte mehr vorliegen (dann wurde nichts mehr
    /// eingespeist).
    @discardableResult
    public func advanceStep(injectingInto scene: GameScene) -> Bool {
        guard Int(currentFrame) < replay.frameCount else { return false }

        // Alle Ereignisse mit frameIndex == aktuellem Schritt einspeisen (Reihenfolge wie aufgezeichnet).
        while nextEventIndex < replay.events.count,
              replay.events[nextEventIndex].frameIndex == currentFrame {
            let e = replay.events[nextEventIndex]
            scene.injectReplayInput(keyCode: e.keyCode, isDown: e.isDown)
            nextEventIndex += 1
        }

        currentFrame += 1
        return true
    }
}
