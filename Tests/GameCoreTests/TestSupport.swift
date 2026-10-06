// Gemeinsame Basisklasse aller GameCore-Testdateien (entstanden beim Split der früheren
// GameCoreTests.swift — reiner Umzug, keine Logikänderung).

import XCTest
import SpriteKit
@testable import GameCore

@MainActor
class GameCoreTestCase: XCTestCase {

    /// Auch Levelwechsel speichern Fortschritt. Jede Testszene braucht deshalb vor presentScene
    /// einen eigenen Speicher, nicht nur Tests, die Highscores ausdrücklich bearbeiten.
    func makeIsolatedScene(size: CGSize) -> GameScene {
        let scene = GameScene(size: size)
        let suite = "exploids-scene-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        scene.useUserDefaultsForTesting(defaults)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return scene
    }

    /// Tests laufen grundsätzlich lautlos: die Spiel-Logik triggert echte SFX (Laser/Explosionen),
    /// die sonst über den geteilten SoundManager auf die Audio-Hardware gehen würden.
    ///
    /// Diese Zuweisung ist nur das zweite Netz. Das erste ist
    /// `SoundManager.startsMutedForCurrentProcess`: Es muss schon vor dem ersten
    /// Singleton-Zugriff greifen, weil `init()` die Engine startet — hier wäre es dafür
    /// zu spät. Genau diese Erkennung prüft `AudioSmokeTests` direkt, damit eine
    /// Regression dort nicht von der Zuweisung hier überdeckt wird. Die Zuweisung bleibt
    /// trotzdem stehen: Sie fängt Tests ab, die `isMuted` selbst umschalten.
    override func setUp() {
        super.setUp()
        SoundManager.shared.isMuted = true
    }
}
