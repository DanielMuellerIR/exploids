// GameScene-Zustands-Tests: Kollision/Restart, Scoring/Splitting, State-Übergänge, Highscore-Eingabe, Schild/Feuer, UFO und Gravity Well.
// Reiner Split aus der früheren GameCoreTests.swift — keine Logikänderung.

import XCTest
import SpriteKit
@testable import GameCore

@MainActor
final class GameSceneStateTests: GameCoreTestCase {

    // MARK: - GameScene State Tests
    
    func testGameSceneCollisionAndRestart() {
        let scene = GameScene(size: CGSize(width: 1000, height: 1000))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        view.presentScene(scene)
        
        // Initial setup
        XCTAssertFalse(scene.isGameOver)
        XCTAssertEqual(scene.activeAsteroids.count, 3)
        XCTAssertFalse(scene.ship.isHidden)
        
        // Place one asteroid exactly on top of the ship
        let asteroid = scene.activeAsteroids[0]
        asteroid.position = scene.ship.position
        
        // Trigger update to check collision (using a distinct timestamp difference > 0)
        scene.update(1.0)
        scene.update(1.01)
        
        // Game Over should be triggered
        XCTAssertTrue(scene.isGameOver)
        XCTAssertTrue(scene.ship.isHidden)
        
        // Simulate pressing 'R' key (which has code 15) to replay
        scene.simulateKeyDown(keyCode: 15)
        
        // Check game is reset
        XCTAssertFalse(scene.isGameOver)
        XCTAssertFalse(scene.ship.isHidden)
        XCTAssertEqual(scene.ship.position, .zero)
        XCTAssertEqual(scene.activeAsteroids.count, 3)
    }
    
    func testLaserAsteroidCollision() {
        let asteroid = Asteroid(sizeClass: .large)
        asteroid.position = .zero
        
        // Laser exactly on top of asteroid center
        let laser1 = Laser(position: .zero, angle: 0.0)
        XCTAssertTrue(CollisionHelper.laserIntersectsAsteroid(laser1, asteroid))
        
        // Laser clearly outside the asteroid
        let laser2 = Laser(position: CGPoint(x: 200.0, y: 200.0), angle: 0.0)
        XCTAssertFalse(CollisionHelper.laserIntersectsAsteroid(laser2, asteroid))
    }
    
    func testAsteroidDestructionAndScoring() {
        let scene = GameScene(size: CGSize(width: 1000, height: 1000))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        view.presentScene(scene)
        
        scene.transitionTo(.playing)
        scene.clearAllEntitiesForTesting()
        
        // Swift array manipulation: make sure active list is empty
        XCTAssertEqual(scene.activeAsteroids.count, 0)
        XCTAssertEqual(scene.activeLasers.count, 0)
        XCTAssertEqual(scene.score, 0)
        
        // Add medium asteroid (50 points) and overlapping laser
        let asteroid = Asteroid(sizeClass: .medium)
        asteroid.position = CGPoint(x: 100.0, y: 100.0)
        scene.addAsteroidForTesting(asteroid)
        
        let laser = Laser(position: CGPoint(x: 100.0, y: 100.0), angle: 0.0)
        scene.addLaserForTesting(laser)
        
        XCTAssertEqual(scene.activeAsteroids.count, 1)
        XCTAssertEqual(scene.activeLasers.count, 1)
        
        // Run update loop
        scene.update(1.0)
        scene.update(1.01)
        
        // Asteroid should split into 2 smaller ones, and laser should be destroyed. Score should be 50.
        XCTAssertEqual(scene.score, 50)
        XCTAssertEqual(scene.activeAsteroids.count, 2)
        XCTAssertEqual(scene.activeLasers.count, 0)
    }
    
    func testGameSceneStateTransitions() {
        let scene = GameScene(size: CGSize(width: 1000, height: 1000))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        view.presentScene(scene)
        
        // Start screen transition
        scene.transitionTo(.startScreen)
        XCTAssertEqual(scene.gameState, .startScreen)
        XCTAssertFalse(scene.isGameOver)
        
        // Playing transition
        scene.transitionTo(.playing)
        XCTAssertEqual(scene.gameState, .playing)
        XCTAssertFalse(scene.isGameOver)
        XCTAssertEqual(scene.score, 0)
        
        // Name entry transition
        scene.transitionTo(.nameEntry)
        XCTAssertEqual(scene.gameState, .nameEntry)
        XCTAssertTrue(scene.isGameOver)
        
        // Game over transition
        scene.transitionTo(.gameOver)
        XCTAssertEqual(scene.gameState, .gameOver)
        XCTAssertTrue(scene.isGameOver)
    }
    
    func testInitialsEntryAndHighScoreRecording() {
        let scene = GameScene(size: CGSize(width: 1000, height: 1000))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        view.presentScene(scene)
        
        // Clear user defaults first to ensure clean state
        UserDefaults.standard.removeObject(forKey: "exploids_high_scores")
        scene.loadHighScores()
        scene.restartGame()
        
        // Set playing state and award a high score
        scene.transitionTo(.playing)
        scene.addScoreForTesting(12000) // Beats default top score of 10000
        
        // Place one asteroid exactly on top of the ship to trigger crash
        for ast in scene.activeAsteroids {
            ast.removeFromParent()
        }
        let asteroid = Asteroid(sizeClass: .large)
        asteroid.position = scene.ship.position
        scene.addAsteroidForTesting(asteroid)
        
        // Trigger update to process crash
        scene.update(1.0)
        scene.update(1.01)
        
        // Since score is 12000, we should transition to name entry instead of game over
        XCTAssertEqual(scene.gameState, .nameEntry)
        XCTAssertTrue(scene.isGameOver)
        
        // Simulate initials entry: type "T", "E", "S"
        scene.simulateTypeCharacter("t")
        scene.simulateTypeCharacter("e")
        scene.simulateTypeCharacter("s")
        
        // Press Enter to save high score (Return keyCode is 36)
        scene.simulateKeyDown(keyCode: 36)
        
        // Should have transitioned to Game Over state
        XCTAssertEqual(scene.gameState, .gameOver)
        
        // Verify high score list has "TES" with 12000 points in first position
        XCTAssertEqual(scene.highScores.count, 5)
        XCTAssertEqual(scene.highScores[0].initials, "TES")
        XCTAssertEqual(scene.highScores[0].score, 12000)
    }
    
    func testAsteroidSplitting() {
        let scene = GameScene(size: CGSize(width: 1000, height: 1000))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        view.presentScene(scene)
        
        scene.transitionTo(.playing)
        scene.clearAllEntitiesForTesting()
        
        // Spawn a large asteroid
        let parent = Asteroid(sizeClass: .large)
        parent.position = CGPoint(x: 100, y: 100)
        parent.velocity = CGPoint(x: 10, y: 0)
        scene.addAsteroidForTesting(parent)
        
        // Spawn laser hitting it
        let laser = Laser(position: CGPoint(x: 100, y: 100), angle: 0.0, type: .normal)
        scene.addLaserForTesting(laser)
        
        // Update to trigger collision
        scene.update(1.0)
        scene.update(1.01)
        
        // Large asteroid should be destroyed, and 2 medium asteroids should be spawned
        XCTAssertEqual(scene.activeAsteroids.count, 2)
        XCTAssertEqual(scene.activeAsteroids[0].sizeClass, .medium)
        XCTAssertEqual(scene.activeAsteroids[1].sizeClass, .medium)
        XCTAssertEqual(scene.score, 20)
    }
    
    func testDifficultyScaling() {
        let scene = GameScene(size: CGSize(width: 1000, height: 1000))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        view.presentScene(scene)
        
        scene.transitionTo(.playing)
        
        // Initially difficultyFactor should be 1.0
        XCTAssertEqual(scene.difficultyFactor, 1.0, accuracy: 1e-4)

        // difficultyFactor ist eine reine Funktion von playTime → direkt setzen statt Minuten zu
        // simulieren. Mit Fixed-Timestep wären 300/600 s zehntausende echte Schritte (langsam) und das
        // unbespielte Schiff stürbe unterwegs an Asteroiden, sodass playTime einfröre.
        scene.setPlayTimeForTesting(300.0)   // 5 Minuten
        // Factor should be 1.0 + 1.5 * (300 / 600) = 1.75
        XCTAssertEqual(scene.difficultyFactor, 1.75, accuracy: 1e-4)

        scene.setPlayTimeForTesting(900.0)   // 15 Minuten → über dem 600-s-Deckel
        // Factor should be capped at 2.5
        XCTAssertEqual(scene.difficultyFactor, 2.5, accuracy: 1e-4)
    }
    
    /// Feuertaste: Der erste Tastendruck feuert sofort genau einen normalen Laser.
    /// (Der frühere Auflade-Schuss wurde durch Dauerfeuer-beim-Halten ersetzt.)
    func testFirePressFiresOneNormalLaser() {
        let scene = GameScene(size: CGSize(width: 1000, height: 1000))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        view.presentScene(scene)

        scene.transitionTo(.playing)
        scene.clearAllEntitiesForTesting()

        // Feuertaste (49) drücken -> sofort ein normaler Schuss, kein Aufladen.
        scene.simulateKeyDown(keyCode: 49)
        XCTAssertEqual(scene.activeLasers.count, 1)
        XCTAssertEqual(scene.activeLasers[0].type, .normal)

        // Loslassen feuert KEINEN zusätzlichen (Charge-)Schuss mehr.
        scene.simulateKeyUp(keyCode: 49)
        XCTAssertEqual(scene.activeLasers.count, 1)
    }
    
    /// Shield ist additiv bis Stufe 3 und jede Stufe absorbiert einen Treffer.
    func testShieldStacksToThreeAndAbsorbsHits() {
        let scene = GameScene(size: CGSize(width: 1000, height: 1000))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        view.presentScene(scene)
        scene.transitionTo(.playing)

        XCTAssertEqual(scene.ship.shieldLevel, 0)
        for _ in 0..<4 { scene.collectPowerUpForTesting(type: .shield) }
        XCTAssertEqual(scene.ship.shieldLevel, 3, "Schild stapelt höchstens bis Stufe 3")

        scene.ship.position = .zero
        scene.damageShipForTesting()
        XCTAssertEqual(scene.ship.shieldLevel, 2, "Ein Treffer verbraucht genau eine Schild-Stufe")
    }

    /// Die „F"-Taste schaltet Auto-Feuer um (Einstellungen / global).
    func testAutoFireToggle() {
        let scene = GameScene(size: CGSize(width: 1000, height: 1000))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        view.presentScene(scene)

        XCTAssertFalse(scene.autoFire, "Engine-Default ist aus")
        scene.simulateTypeCharacter("f")
        XCTAssertTrue(scene.autoFire)
        scene.simulateTypeCharacter("f")
        XCTAssertFalse(scene.autoFire)
    }

    /// Beim Revive (Extra Life) gehen alle aktiven Power-ups verloren.
    func testReviveLosesAllPowerUps() {
        let scene = GameScene(size: CGSize(width: 1000, height: 1000))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        view.presentScene(scene)
        scene.transitionTo(.playing)

        scene.collectPowerUpForTesting(type: .extraLife)
        scene.collectPowerUpForTesting(type: .triple)
        XCTAssertEqual(scene.extraLivesForTesting, 1)
        XCTAssertGreaterThan(scene.tripleShotEndTimeForTesting, 0)
        XCTAssertEqual(scene.ship.shieldLevel, 0, "kein Schild -> der nächste Treffer löst Revive aus")

        scene.ship.position = .zero
        scene.damageShipForTesting()
        XCTAssertEqual(scene.extraLivesForTesting, 0, "Revive verbraucht eine Reserve")
        XCTAssertEqual(scene.tripleShotEndTimeForTesting, 0, "beim Revive gehen Power-ups verloren")
    }

    func testPowerUpCollection() {
        let scene = GameScene(size: CGSize(width: 1000, height: 1000))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        view.presentScene(scene)
        
        scene.transitionTo(.playing)
        scene.clearAllEntitiesForTesting()
        
        // Initially shield is inactive
        XCTAssertFalse(scene.ship.isShieldActive)
        
        // Spawn a shield power-up at the ship's position
        scene.spawnPowerUpForTesting(type: .shield, position: scene.ship.position)
        XCTAssertEqual(scene.activePowerUps.count, 1)
        
        // Run collision update
        scene.update(1.0)
        scene.update(1.01)
        
        // Power-up should be collected and shield should be active
        XCTAssertTrue(scene.ship.isShieldActive)
        XCTAssertEqual(scene.activePowerUps.count, 0)
    }
    
    func testUfoShooting() {
        let scene = GameScene(size: CGSize(width: 1000, height: 1000))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        view.presentScene(scene)
        
        scene.transitionTo(.playing)
        scene.clearAllEntitiesForTesting()
        
        // Spawn a small UFO
        scene.spawnUFOForTesting(isSmall: true, startOnLeft: true)
        XCTAssertEqual(scene.activeUFOs.count, 1)
        
        let ufo = scene.activeUFOs[0]
        ufo.position = CGPoint(x: -200, y: 0)
        
        // Force a shoot check by calling shoot
        let now = ProcessInfo.processInfo.systemUptime
        var rng = GameRandom(seed: 1)
        if let laser = ufo.shoot(target: scene.ship.position, currentTime: now, using: &rng) {
            scene.addLaserForTesting(laser)
        }
        
        // The laser should be an enemy laser pointing towards the ship (at 0, 0)
        XCTAssertEqual(scene.activeLasers.count, 1)
        let laser = scene.activeLasers[0]
        XCTAssertEqual(laser.type, .enemy)
        // UFO at (-200, 0) aiming at (0, 0) should shoot at angle ~0
        XCTAssertEqual(laser.zRotation, 0.0, accuracy: 0.15)
    }
    
    func testGravityWellPull() {
        let scene = GameScene(size: CGSize(width: 1000, height: 1000))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        view.presentScene(scene)
        
        scene.transitionTo(.playing)
        scene.clearAllEntitiesForTesting()
        
        // Spawn gravity well at (200, 0)
        scene.spawnGravityWellForTesting(position: CGPoint(x: 200, y: 0))
        
        // Place ship at (100, 0), velocity = zero
        scene.ship.position = CGPoint(x: 100, y: 0)
        scene.ship.velocity = .zero
        
        // Update game: gravity well should pull ship towards +x (200, 0)
        scene.update(1.0)
        scene.update(1.01)
        
        XCTAssertGreaterThan(scene.ship.velocity.x, 0.0)
        XCTAssertEqual(scene.ship.velocity.y, 0.0, accuracy: 1e-4)
    }

}
