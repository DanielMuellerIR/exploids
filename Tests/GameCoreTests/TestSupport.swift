// Gemeinsame Basisklasse aller GameCore-Testdateien (entstanden beim Split der früheren
// GameCoreTests.swift — reiner Umzug, keine Logikänderung).

import XCTest
import SpriteKit
@testable import GameCore

@MainActor
class GameCoreTestCase: XCTestCase {

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
