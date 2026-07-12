// Gemeinsame Basisklasse aller GameCore-Testdateien (entstanden beim Split der früheren
// GameCoreTests.swift — reiner Umzug, keine Logikänderung).

import XCTest
import SpriteKit
@testable import GameCore

@MainActor
class GameCoreTestCase: XCTestCase {

    /// Tests laufen grundsätzlich lautlos: die Spiel-Logik triggert echte SFX (Laser/Explosionen),
    /// die sonst über den geteilten SoundManager auf die Audio-Hardware gehen würden.
    override func setUp() {
        super.setUp()
        SoundManager.shared.isMuted = true
    }
}
