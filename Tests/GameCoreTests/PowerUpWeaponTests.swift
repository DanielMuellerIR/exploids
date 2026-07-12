// Power-Up- und Waffen-Tests: Compress, Screen Bomb, Rear Laser, Extra Life, Laserbeam.
// Reiner Split aus der früheren GameCoreTests.swift — keine Logikänderung.

import XCTest
import SpriteKit
@testable import GameCore

@MainActor
final class PowerUpWeaponTests: GameCoreTestCase {

    // MARK: - New Power-Up Tests

    /// Compress verkleinert das Schiff (Skalierung 0.3) und damit auch die Kollisionsfläche.
    func testCompressPowerUpShrinksShip() {
        let scene = GameScene(size: CGSize(width: 1000, height: 800))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        view.presentScene(scene)
        scene.transitionTo(.playing)

        XCTAssertEqual(scene.ship.xScale, 1.0, accuracy: 0.001)
        scene.collectPowerUpForTesting(type: .compress)
        XCTAssertEqual(scene.ship.xScale, 0.3, accuracy: 0.001)
        XCTAssertEqual(scene.ship.yScale, 0.3, accuracy: 0.001)

        // Kollisionsfläche schrumpft mit (getWorldVertices ist scale-aware).
        scene.ship.position = .zero
        scene.ship.zRotation = 0.0
        let verts = scene.ship.getWorldVertices()
        let maxX = verts.map { abs($0.x) }.max() ?? 0
        XCTAssertLessThan(maxX, 18.0 * 0.5, "Kollisionspunkte müssen mit der Skalierung schrumpfen")
    }

    /// Screen Bomb wendet auf JEDES Objekt genau einen Schuss-Treffer an (wie ein Laser):
    /// kleine Asteroiden verschwinden, große splitten (Original weg, Kinder da), implodierende
    /// wachsen beim ersten Treffer statt zu verschwinden.
    func testScreenBombHitsEveryAsteroidOnceLikeAShot() {
        let scene = GameScene(size: CGSize(width: 1000, height: 800))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        view.presentScene(scene)
        scene.transitionTo(.playing)
        scene.clearAllEntitiesForTesting()

        // Kleiner normaler Asteroid -> verschwindet bei einem Treffer.
        let small = Asteroid(sizeClass: .small)
        small.position = CGPoint(x: -200, y: 0)
        scene.addAsteroidForTesting(small)

        // Großer normaler Asteroid -> splittet (Original weg, mittlere Kinder kommen rein).
        let large = Asteroid(sizeClass: .large)
        large.position = CGPoint(x: 200, y: 0)
        scene.addAsteroidForTesting(large)

        // Implodierender Asteroid -> wächst, kollabiert erst beim 4. Treffer, bleibt also erhalten.
        let imploding = Asteroid(sizeClass: .large, isImplodingType: true)
        imploding.position = CGPoint(x: 0, y: 200)
        scene.addAsteroidForTesting(imploding)

        scene.collectPowerUpForTesting(type: .bomb)

        // Der gemeldete Bug war, dass Objekte unangetastet heil blieben. Jeder Typ muss reagieren:
        XCTAssertFalse(scene.activeAsteroids.contains(small),
                       "Kleiner Asteroid muss durch die Bombe verschwinden")
        XCTAssertFalse(scene.activeAsteroids.contains(large),
                       "Großer Asteroid muss durch die Bombe gesplittet (entfernt) werden")
        XCTAssertTrue(scene.activeAsteroids.contains { $0.sizeClass == .medium },
                      "Der große Asteroid muss mittlere Splitter hinterlassen")
        XCTAssertTrue(scene.activeAsteroids.contains(imploding),
                      "Implodierender Asteroid wächst beim ersten Treffer, verschwindet nicht")
        XCTAssertEqual(imploding.hitCount, 1,
                       "Implodierender Asteroid muss genau einen Bomben-Treffer registrieren")
    }

    /// Rear Laser feuert zusätzlich nach hinten.
    func testRearLaserFiresBackward() {
        let scene = GameScene(size: CGSize(width: 1000, height: 800))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        view.presentScene(scene)
        scene.transitionTo(.playing)
        scene.clearAllEntitiesForTesting()
        scene.ship.position = .zero
        scene.ship.zRotation = 0.0 // Nase zeigt nach +x

        scene.collectPowerUpForTesting(type: .rear)
        scene.fireLaserForTesting()

        // Genau ein Schuss nach vorn (+x) und einer nach hinten (-x).
        XCTAssertEqual(scene.activeLasers.count, 2)
        XCTAssertTrue(scene.activeLasers.contains { $0.position.x < 0 }, "Es muss ein Laser nach hinten feuern")
        XCTAssertTrue(scene.activeLasers.contains { $0.position.x > 0 }, "Es muss ein Laser nach vorn feuern")
    }

    /// Extra Life: tödlicher Treffer führt nicht zum Game Over, sondern zum Revive in der Mitte.
    func testExtraLifeRevivesInsteadOfGameOver() {
        let scene = GameScene(size: CGSize(width: 1000, height: 800))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        view.presentScene(scene)
        scene.transitionTo(.playing)

        scene.collectPowerUpForTesting(type: .extraLife)
        XCTAssertEqual(scene.extraLivesForTesting, 1)

        scene.ship.position = CGPoint(x: 200, y: 100)
        scene.damageShipForTesting() // kein Schild aktiv

        XCTAssertFalse(scene.isGameOver, "Mit Extra-Leben darf kein Game Over eintreten")
        XCTAssertEqual(scene.extraLivesForTesting, 0, "Ein Extra-Leben muss verbraucht sein")
        XCTAssertEqual(scene.ship.position.x, 0.0, accuracy: 0.001, "Revive in der Mitte")
        XCTAssertEqual(scene.ship.position.y, 0.0, accuracy: 0.001, "Revive in der Mitte")

        // Ohne weitere Leben führt der nächste Treffer zum Game Over.
        scene.damageShipForTesting()
        XCTAssertTrue(scene.isGameOver)
    }

    /// Regression: Ein Extra-Leben muss auch den Tod durch ein Gravity Well (Ereignishorizont)
    /// abfangen — dieser Pfad rief früher direkt Game Over auf und umging das Extra-Leben.
    func testExtraLifeSurvivesGravityWell() {
        let scene = GameScene(size: CGSize(width: 1000, height: 800))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        view.presentScene(scene)
        scene.transitionTo(.playing)
        scene.clearAllEntitiesForTesting()

        scene.collectPowerUpForTesting(type: .extraLife)
        scene.ship.position = .zero
        scene.spawnGravityWellForTesting(position: .zero) // Well direkt auf dem Schiff

        scene.update(1.0)
        scene.update(1.01)

        XCTAssertFalse(scene.isGameOver, "Mit Extra-Leben darf der Black Hole kein Game Over auslösen")
        XCTAssertEqual(scene.extraLivesForTesting, 0, "Das Extra-Leben muss verbraucht sein")
    }

    /// Laserbeam zerstört einen Asteroiden, der in der Blickrichtung des Schiffs liegt.
    func testLaserBeamDestroysAsteroidInPath() {
        let scene = GameScene(size: CGSize(width: 1000, height: 800))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        view.presentScene(scene)
        scene.transitionTo(.playing)
        scene.clearAllEntitiesForTesting()
        scene.ship.position = .zero
        scene.ship.zRotation = 0.0 // Strahl geht nach +x

        let target = Asteroid(sizeClass: .large)
        target.position = CGPoint(x: 120, y: 0) // direkt vor dem Schiff, innerhalb halber Bildbreite
        target.velocity = .zero
        target.hasEnteredScreen = true
        scene.addAsteroidForTesting(target)

        let scoreBefore = scene.score
        scene.fireBeamForTesting()

        XCTAssertFalse(scene.activeAsteroids.contains(target), "Asteroid im Strahl muss zerstört werden")
        XCTAssertGreaterThan(scene.score, scoreBefore, "Treffer muss Punkte geben")
    }

}
