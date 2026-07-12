// Modus- und Level-Tests: Mad-/Ancient-Modus, Level-Progression, implodierende/wobbelnde Asteroiden, Escape-Quit und Glossar.
// Reiner Split aus der früheren GameCoreTests.swift — keine Logikänderung.

import XCTest
import SpriteKit
@testable import GameCore

@MainActor
final class ModeTests: GameCoreTestCase {

    // MARK: - Mad Meteoroids Mode Tests

    /// Im Mad-Modus rotiert das Feld um die Bildmitte: ein Asteroid (ohne Eigen-Velocity) muss
    /// seinen Abstand zum Zentrum behalten, aber seinen Winkel ändern.
    func testMadModeRotatesAsteroidsAroundCenter() {
        let scene = GameScene(size: CGSize(width: 1000, height: 800))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        view.presentScene(scene)
        scene.setGameModeForTesting(.madMeteoroids)
        scene.transitionTo(.playing)
        scene.clearAllEntitiesForTesting()

        let ast = Asteroid(sizeClass: .large)
        ast.position = CGPoint(x: 200.0, y: 0.0)
        ast.velocity = .zero
        ast.hasEnteredScreen = true
        scene.addAsteroidForTesting(ast)

        let r0 = hypot(ast.position.x, ast.position.y)
        let a0 = atan2(ast.position.y, ast.position.x)

        scene.update(1000.0)  // initialisiert lastUpdateTime
        scene.update(1000.5)  // dt = 0.5s -> bei Level 1 (6°/s) ca. 3° Drehung

        let r1 = hypot(ast.position.x, ast.position.y)
        let a1 = atan2(ast.position.y, ast.position.x)

        // Rotation erhält den Abstand zum Zentrum.
        XCTAssertEqual(r1, r0, accuracy: 0.5)
        // Winkel hat sich um ~3° geändert (Richtung ist zufällig, daher Betrag).
        let deltaDeg = abs(a1 - a0) * 180.0 / .pi
        XCTAssertGreaterThan(deltaDeg, 1.0)
        XCTAssertLessThan(deltaDeg, 6.0)
    }

    /// Verlässt ein Objekt im Mad-Modus den Feldradius, wird es auf die gegenüberliegende Seite
    /// knapp innerhalb des Radius umgesetzt (kreisförmiges Wrapping).
    func testMadModeCircularWrap() {
        let scene = GameScene(size: CGSize(width: 1000, height: 800))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        view.presentScene(scene)
        scene.setGameModeForTesting(.madMeteoroids)
        scene.transitionTo(.playing)
        scene.clearAllEntitiesForTesting()

        // Feldradius = sqrt(500² + 400²) + 100 ≈ 740.
        let fieldRadius = sqrt(500.0 * 500.0 + 400.0 * 400.0) + 100.0

        let ast = Asteroid(sizeClass: .large)
        ast.position = CGPoint(x: 800.0, y: 0.0) // jenseits des Feldradius
        ast.velocity = .zero
        ast.hasEnteredScreen = true
        scene.addAsteroidForTesting(ast)

        scene.update(1000.0)
        scene.update(1000.1)

        let d = hypot(ast.position.x, ast.position.y)
        XCTAssertLessThanOrEqual(d, fieldRadius, "Objekt muss zurück ins Feld gewrappt werden")
        XCTAssertLessThan(ast.position.x, 0.0, "Wrap setzt auf die gegenüberliegende Seite um")
    }

    /// Regression: Im Ancient-Modus darf KEINE Feld-Rotation stattfinden — ein ruhender Asteroid
    /// innerhalb des Bildschirms bleibt exakt liegen.
    func testAncientModeDoesNotRotate() {
        let scene = GameScene(size: CGSize(width: 1000, height: 800))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        view.presentScene(scene)
        scene.setGameModeForTesting(.ancientAsteroids)
        scene.transitionTo(.playing)
        scene.clearAllEntitiesForTesting()

        let ast = Asteroid(sizeClass: .large)
        ast.position = CGPoint(x: 200.0, y: 0.0)
        ast.velocity = .zero
        ast.hasEnteredScreen = true
        scene.addAsteroidForTesting(ast)

        scene.update(1000.0)
        scene.update(1000.5)

        XCTAssertEqual(ast.position.x, 200.0, accuracy: 0.001)
        XCTAssertEqual(ast.position.y, 0.0, accuracy: 0.001)
    }

    /// Mad-Modus soll fairer sein als Ancient: weniger gleichzeitige Asteroiden, höhere
    /// Power-Up-Chance (beim selben Level).
    func testMadModeReducesAsteroidsAndBoostsPowerUps() {
        let scene = GameScene(size: CGSize(width: 1000, height: 800))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        view.presentScene(scene)

        // Auf Level 5 stellen — dort greift die Mad-Reduktion sichtbar (bei sehr niedriger
        // Asteroiden-Basis trifft sie sonst den Mindestwert 3 und beide Modi sind gleich).
        scene.transitionTo(.startScreen)
        for _ in 0..<4 { scene.simulateKeyDown(keyCode: 124) } // Pfeil rechts: Level 1 -> 5

        scene.setGameModeForTesting(.ancientAsteroids)
        scene.transitionTo(.playing)
        let ancient = scene.currentConfigForTesting()

        scene.transitionTo(.startScreen)
        scene.setGameModeForTesting(.madMeteoroids)
        scene.transitionTo(.playing)
        let mad = scene.currentConfigForTesting()

        XCTAssertEqual(ancient.level, 5)
        XCTAssertEqual(mad.level, 5)
        XCTAssertLessThan(mad.maxAsteroids, ancient.maxAsteroids, "Mad-Modus muss weniger Asteroiden haben")
        XCTAssertGreaterThan(mad.powerUpChance, ancient.powerUpChance, "Mad-Modus muss mehr Power-Ups haben")
    }

    /// Auf dem Game-Over-Screen führt Escape zurück zum Startbildschirm (Modus-/Level-Wahl).
    func testGameOverEscapeReturnsToStartScreen() {
        let scene = GameScene(size: CGSize(width: 1000, height: 800))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        view.presentScene(scene)

        scene.transitionTo(.gameOver)
        XCTAssertTrue(scene.isGameOver)

        scene.simulateKeyDown(keyCode: 53) // Escape
        XCTAssertEqual(scene.gameState, .startScreen)
    }

    /// Der Musik-Schalter merkt sich den Zustand (an/aus) zur Laufzeit.
    func testMusicToggleState() {
        let mp = MusicPlayer.shared
        let initial = mp.isEnabled
        mp.setEnabled(false)
        XCTAssertFalse(mp.isEnabled)
        mp.toggle()
        XCTAssertTrue(mp.isEnabled)
        mp.toggle()
        XCTAssertFalse(mp.isEnabled)
        mp.setEnabled(initial) // Ausgangszustand wiederherstellen
    }

    // MARK: - Level Progression & Imploding Asteroid Tests
    
    func testImplodingAsteroidGrowth() {
        let scene = GameScene(size: CGSize(width: 1000, height: 1000))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        view.presentScene(scene)
        scene.transitionTo(.playing)
        scene.clearAllEntitiesForTesting()
        
        let asteroid = Asteroid(sizeClass: .large, isImplodingType: true)
        asteroid.position = CGPoint(x: 100.0, y: 100.0)
        scene.addAsteroidForTesting(asteroid)
        
        XCTAssertEqual(asteroid.xScale, 1.0)
        XCTAssertEqual(asteroid.yScale, 1.0)
        
        let laser = Laser(position: CGPoint(x: 100.0, y: 100.0), angle: 0.0)
        scene.addLaserForTesting(laser)
        
        scene.update(1.0)
        scene.update(1.01)
        
        XCTAssertEqual(asteroid.hitCount, 1)
        XCTAssertEqual(asteroid.xScale, 1.4, accuracy: 1e-4)
        XCTAssertEqual(scene.activeLasers.count, 0)
    }
    
    func testAsteroidAbsorption() {
        let scene = GameScene(size: CGSize(width: 1000, height: 1000))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        view.presentScene(scene)
        scene.transitionTo(.playing)
        scene.clearAllEntitiesForTesting()
        
        let imploding = Asteroid(sizeClass: .large, isImplodingType: true)
        imploding.position = CGPoint(x: 0.0, y: 0.0)
        scene.addAsteroidForTesting(imploding)
        
        let normal = Asteroid(sizeClass: .small, isImplodingType: false)
        normal.position = CGPoint(x: 5.0, y: 0.0)
        scene.addAsteroidForTesting(normal)
        
        XCTAssertEqual(scene.activeAsteroids.count, 2)
        
        scene.update(1.0)
        scene.update(1.01)
        
        XCTAssertEqual(scene.activeAsteroids.count, 1)
        XCTAssertTrue(scene.activeAsteroids[0].isImplodingType)
        XCTAssertEqual(scene.activeAsteroids[0].xScale, 1.35, accuracy: 1e-4)
    }
    
    func testLevelTransition() {
        let scene = GameScene(size: CGSize(width: 1000, height: 1000))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        view.presentScene(scene)
        scene.transitionTo(.playing)
        // Schiff soll die 60 s bis zum Level-Ende überleben: mit Fixed-Timestep läuft die Simulation
        // jetzt wirklich jede Sekunde durch (statt in einem Riesenschritt zu „tunneln"), sonst träfe es
        // unterwegs ein Asteroid. Felder leeren + Spawnen aus → leeres, sicheres Spielfeld.
        scene.clearAllEntitiesForTesting()
        scene.isSpawningEnabled = false

        XCTAssertEqual(scene.currentLevel, 1)
        XCTAssertFalse(scene.isLevelClearing)

        scene.update(1.0)
        scene.update(61.1)

        XCTAssertTrue(scene.isLevelClearing)
        XCTAssertEqual(scene.activeAsteroids.count, 0)

        scene.update(65.0)

        XCTAssertFalse(scene.isLevelClearing)
        XCTAssertEqual(scene.currentLevel, 2)
        // Der Level-2-Timer wird auf 60 s zurückgesetzt; mit Fixed-Timestep decrementiert er nach dem
        // Übergang noch den Rest des letzten Advance-Schritts (~0.5 s), daher accuracy statt exakt 60.
        XCTAssertEqual(scene.levelTimeRemaining, 60.0, accuracy: 1.0)
    }
    
    func testLevelSelection() {
        let scene = GameScene(size: CGSize(width: 1000, height: 1000))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        view.presentScene(scene)
        
        UserDefaults.standard.set(3, forKey: "exploids_max_level_reached")
        scene.loadHighScores()
        scene.transitionTo(.startScreen)
        
        XCTAssertEqual(scene.maxLevelReached, 3)
        XCTAssertEqual(scene.selectedStartLevel, 1)
        
        scene.simulateKeyDown(keyCode: 124) // 1 -> 2
        XCTAssertEqual(scene.selectedStartLevel, 2)
        
        scene.simulateKeyDown(keyCode: 124) // 2 -> 3
        XCTAssertEqual(scene.selectedStartLevel, 3)
        
        scene.simulateKeyDown(keyCode: 124) // 3 -> 4 (immediate unlock allows this now)
        XCTAssertEqual(scene.selectedStartLevel, 4)
        
        // Go up to 10
        for _ in 5...10 {
            scene.simulateKeyDown(keyCode: 124)
        }
        XCTAssertEqual(scene.selectedStartLevel, 10)
        
        // Try to go past 10
        scene.simulateKeyDown(keyCode: 124)
        XCTAssertEqual(scene.selectedStartLevel, 10)
        
        scene.simulateKeyDown(keyCode: 123) // 10 -> 9
        XCTAssertEqual(scene.selectedStartLevel, 9)
        
        scene.simulateKeyDown(keyCode: 36)
        XCTAssertEqual(scene.gameState, .playing)
        XCTAssertEqual(scene.currentLevel, 9)
    }
    
    func testWobblingAsteroidProgressionAndDetonation() {
        let scene = GameScene(size: CGSize(width: 1000, height: 1000))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        view.presentScene(scene)
        
        scene.transitionTo(.playing)
        scene.isSpawningEnabled = false
        scene.clearAllEntitiesForTesting() // Clear the initial ones so only our test asteroid exists
        
        let asteroid = Asteroid(sizeClass: .small, isWobblingType: true)
        asteroid.position = CGPoint(x: 300, y: 300) // Avoid immediate ship collision
        scene.addAsteroidForTesting(asteroid)
        
        XCTAssertEqual(asteroid.sizeClass, .small)
        XCTAssertEqual(asteroid.wobblePhase, 0)
        
        // Update past 6s -> Should grow to medium
        scene.update(1.0)
        scene.update(7.1)
        XCTAssertEqual(asteroid.sizeClass, .medium)
        XCTAssertEqual(asteroid.wobblePhase, 1)
        
        // Update past 12s -> Should grow to large
        scene.update(13.2)
        XCTAssertEqual(asteroid.sizeClass, .large)
        XCTAssertEqual(asteroid.wobblePhase, 2)
        
        // Update past 18s -> Should detonate
        scene.update(19.3)
        // Asteroid should be removed, and 4 small regular asteroids spawned
        XCTAssertNil(asteroid.parent)
        XCTAssertEqual(scene.activeAsteroids.count, 4)
        for ast in scene.activeAsteroids {
            XCTAssertEqual(ast.sizeClass, .small)
            XCTAssertFalse(ast.isWobblingType)
        }
    }
    
    func testWobblingAsteroidDefusal() {
        let scene = GameScene(size: CGSize(width: 1000, height: 1000))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        view.presentScene(scene)
        
        scene.transitionTo(.playing)
        scene.clearAllEntitiesForTesting() // Clear initial ones
        
        let asteroid = Asteroid(sizeClass: .small, isWobblingType: true)
        asteroid.position = CGPoint(x: 300, y: 300) // Avoid immediate ship collision
        scene.addAsteroidForTesting(asteroid)
        
        // Create laser at the same position to hit it
        let laser = Laser(position: asteroid.position, angle: 0.0)
        scene.addLaserForTesting(laser)
        
        let initialScore = scene.score
        
        scene.update(1.0)
        scene.update(1.01)
        
        // Asteroid should be removed (defused), score +200, and no split children spawned (so count should be 0 active)
        XCTAssertNil(asteroid.parent)
        XCTAssertEqual(scene.activeAsteroids.count, 0)
        XCTAssertEqual(scene.score, initialScore + 200)
    }
    
    func testFrontConeSpawningRejection() {
        let scene = GameScene(size: CGSize(width: 1000, height: 1000))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        view.presentScene(scene)
        scene.transitionTo(.playing)
        
        // Let's spawn 50 asteroids and verify none are in the 45-degree front cone of the ship
        // The ship starts at (0,0) with zRotation = 0.0 (pointing right, along positive X axis)
        scene.ship.position = .zero
        scene.ship.zRotation = 0.0
        
        for _ in 0..<50 {
            scene.clearAllEntitiesForTesting()
            scene.spawnAsteroid()
            
            XCTAssertEqual(scene.activeAsteroids.count, 1)
            let ast = scene.activeAsteroids[0]
            
            // Check position relative to ship
            let dirToAst = atan2(ast.position.y - scene.ship.position.y, ast.position.x - scene.ship.position.x)
            var angleDiff = abs(dirToAst - scene.ship.zRotation)
            while angleDiff > .pi { angleDiff -= 2.0 * .pi }
            while angleDiff < -.pi { angleDiff += 2.0 * .pi }
            
            // Verify angleDiff is not inside the front cone (total 90-degree sector in current code is pi/4.0)
            XCTAssertGreaterThanOrEqual(abs(angleDiff), .pi / 4.0 - 1e-4)
        }
    }
    
    func testPowerUpRetentionAndLifetimeExtension() {
        let scene = GameScene(size: CGSize(width: 1000, height: 1000))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        view.presentScene(scene)
        
        scene.transitionTo(.playing)
        scene.isSpawningEnabled = false
        scene.clearAllEntitiesForTesting() // Clear initial ones
        
        // Spawn a power-up
        let powerUp1 = PowerUp(type: .shield, position: CGPoint(x: 300, y: 300))
        powerUp1.setRemainingLifetime(to: 5.0) // Has 5 seconds remaining
        scene.addPowerUpForTesting(powerUp1)
        
        let powerUp2 = PowerUp(type: .rapid, position: CGPoint(x: 300, y: 300))
        powerUp2.setRemainingLifetime(to: 20.0) // Has 20 seconds remaining
        scene.addPowerUpForTesting(powerUp2)
        
        // Assert we have 2 power-ups
        XCTAssertEqual(scene.activePowerUps.count, 2)
        
        // Set levelTimeRemaining to 0.5s instead of 60s
        scene.setLevelTimeRemainingForTesting(0.5)
        
        // Update first time to establish baseline time
        scene.update(1.0)
        
        // Update by 0.6s -> levelTimeRemaining goes to 0 -> triggers clearing state
        scene.update(1.6)
        XCTAssertTrue(scene.isLevelClearing)
        
        // During level clearing, power-ups should still exist (retention!)
        XCTAssertEqual(scene.activePowerUps.count, 2)
        
        // Step through the 3.5s transition in 1s steps to simulate smooth gameplay
        scene.update(2.6)
        scene.update(3.6)
        scene.update(4.6)
        scene.update(5.1) // 1.6 + 3.5 = 5.1. Transition ends on this frame!
        
        XCTAssertFalse(scene.isLevelClearing)
        XCTAssertEqual(scene.currentLevel, 2)
        
        // Power-ups should still exist
        XCTAssertEqual(scene.activePowerUps.count, 2)
        
        // powerUp1 wird beim Level-Ende auf 5.0 s Restlaufzeit gesetzt; mit Fixed-Timestep passiert das
        // exakt im Übergangs-Schritt, danach decayt sie nur noch den Rest des Advance (~0.1 s) → ~4.9 s
        // (früher 4.5 s, als der grobe Einzelschritt 0.5 s am Stück abzog).
        let remaining1 = powerUp1.lifetime - powerUp1.elapsedTime
        XCTAssertEqual(remaining1, 4.9, accuracy: 0.1)
        
        // powerUp2 remaining lifetime started at 10.0s (capped from 20s).
        // Total deltaTime elapsed: 0.6 + 1.0 + 1.0 + 1.0 + 0.5 = 4.1s.
        // So remaining2 = 10.0 - 4.1 = 5.9s.
        let remaining2 = powerUp2.lifetime - powerUp2.elapsedTime
        XCTAssertGreaterThan(remaining2, 5.0)
        XCTAssertEqual(remaining2, 5.9, accuracy: 0.1)
    }
    
    func testLevel10InfiniteDifficultyScaling() {
        let scene = GameScene(size: CGSize(width: 1000, height: 1000))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        view.presentScene(scene)
        
        // Select starting level 10 and start
        UserDefaults.standard.set(10, forKey: "exploids_max_level_reached")
        scene.loadHighScores()
        scene.transitionTo(.startScreen)
        // Select level 10
        for _ in 1...9 {
            scene.simulateKeyDown(keyCode: 124)
        }
        XCTAssertEqual(scene.selectedStartLevel, 10)
        
        // Press Enter
        scene.simulateKeyDown(keyCode: 36)
        XCTAssertEqual(scene.gameState, .playing)
        XCTAssertEqual(scene.currentLevel, 10)
        
        let configStart10 = scene.configForLevel(10)
        let configStart11 = scene.configForLevel(11)
        XCTAssertGreaterThan(configStart11.maxAsteroids, configStart10.maxAsteroids)
    }
    
    func testPowerUpLowLifetimeExtension() {
        let scene = GameScene(size: CGSize(width: 1000, height: 1000))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        view.presentScene(scene)
        
        scene.transitionTo(.playing)
        scene.isSpawningEnabled = false
        scene.clearAllEntitiesForTesting() // Clear initial ones
        
        // Spawn a power-up with very low remaining lifetime (e.g. 1.0s)
        let powerUp = PowerUp(type: .shield, position: CGPoint(x: 300, y: 300))
        powerUp.setRemainingLifetime(to: 1.0) // Has 1 second remaining
        scene.addPowerUpForTesting(powerUp)
        
        XCTAssertEqual(scene.activePowerUps.count, 1)
        
        // Set levelTimeRemaining to 0.5s instead of 60s
        scene.setLevelTimeRemainingForTesting(0.5)
        
        // Update first time -> 1.0 -> 0.5s remaining on level, power-up updates
        scene.update(1.0)
        
        // Update by 0.6s -> levelTimeRemaining goes to 0 -> triggers clearing state.
        // Power-up remaining lifetime would be 1.0 - 0.6 = 0.4s.
        // But since clearing state is triggered, it should be extended to at least 8.5s.
        scene.update(1.6)
        XCTAssertTrue(scene.isLevelClearing)
        XCTAssertEqual(scene.activePowerUps.count, 1)
        
        // Mit Fixed-Timestep feuert der Level-Clear-Trigger exakt im Schritt, in dem der Timer 0
        // erreicht (nach 0.5 s der 0.6-s-Advance); die Verlängerung auf 8.5 s passiert dort, danach
        // decayt die Power-up nur noch die restlichen ~0.1 s → ~8.4 s (früher 7.9 s im groben Einzelschritt).
        let remainingBeforeTransition = powerUp.lifetime - powerUp.elapsedTime
        XCTAssertEqual(remainingBeforeTransition, 8.4, accuracy: 0.1)
        
        // Step through the rest of the 3.5s transition:
        scene.update(2.6) // +1.0s -> remaining: 6.9s
        scene.update(3.6) // +1.0s -> remaining: 5.9s
        scene.update(4.6) // +1.0s -> remaining: 4.9s
        scene.update(5.1) // +0.5s -> transition ends!
        
        // Beim Level-Ende wird die Restlaufzeit auf 5.0 s gesetzt; mit Fixed-Timestep passiert das exakt
        // im Übergangs-Schritt, danach decayt sie nur noch den Rest des Advance (~0.1 s) → ~4.9 s
        // (früher 4.5 s, als der grobe Einzelschritt 0.5 s am Stück abzog).
        XCTAssertFalse(scene.isLevelClearing)
        XCTAssertEqual(scene.activePowerUps.count, 1)

        let finalRemaining = powerUp.lifetime - powerUp.elapsedTime
        XCTAssertEqual(finalRemaining, 4.9, accuracy: 0.1)
    }
    
    func testSpawningSafetyFallback() {
        let scene = GameScene(size: CGSize(width: 1000, height: 1000))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 1000))
        view.presentScene(scene)
        scene.transitionTo(.playing)
        
        // Position the ship and set its rotation
        scene.ship.position = CGPoint(x: 100, y: 100)
        scene.ship.zRotation = .pi / 4.0
        
        // We will call spawnAsteroid and verify the spawned asteroid is safe
        scene.clearAllEntitiesForTesting()
        scene.spawnAsteroid()
        
        XCTAssertEqual(scene.activeAsteroids.count, 1)
        let ast = scene.activeAsteroids[0]
        
        // 1. Verify it's spawned outside the screen diagonal (diagonal of 1000x1000 is sqrt(500^2 + 500^2) = 707.1)
        let distFromCenter = sqrt(ast.position.x * ast.position.x + ast.position.y * ast.position.y)
        XCTAssertGreaterThanOrEqual(distFromCenter, 707.0)
        
        // 2. Verify it's not in the front cone
        let dirToAst = atan2(ast.position.y - scene.ship.position.y, ast.position.x - scene.ship.position.x)
        var diff = dirToAst - scene.ship.zRotation
        while diff > .pi { diff -= 2.0 * .pi }
        while diff < -.pi { diff += 2.0 * .pi }
        XCTAssertGreaterThanOrEqual(abs(diff), .pi / 4.0 - 1e-4)
    }
    
    // MARK: - Escape Quit & Glossary Tests
    
    func testPowerUpResetsOnRestart() {
        let scene = GameScene(size: CGSize(width: 800, height: 600))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.presentScene(scene)
        scene.transitionTo(.playing)
        
        // Activate power-ups
        scene.setPowerUpTimersForTesting(triple: 100.0, rapid: 150.0)
        XCTAssertEqual(scene.tripleShotEndTimeForTesting, 100.0)
        XCTAssertEqual(scene.rapidFireEndTimeForTesting, 150.0)
        
        // Restart the game
        scene.transitionTo(.startScreen)
        scene.transitionTo(.playing)
        
        // Verify power-up timers are reset to 0.0
        XCTAssertEqual(scene.tripleShotEndTimeForTesting, 0.0)
        XCTAssertEqual(scene.rapidFireEndTimeForTesting, 0.0)
    }
    
    func testEscKeyDuringPlayingTriggersQuitConfirmation() {
        let scene = GameScene(size: CGSize(width: 800, height: 600))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.presentScene(scene)
        scene.transitionTo(.playing)
        XCTAssertEqual(scene.gameState, .playing)
        
        // Simulate Esc key (keyCode 53)
        scene.simulateKeyDown(keyCode: 53)
        XCTAssertEqual(scene.gameState, .quitConfirmation)
    }
    
    func testQuitConfirmationNavigation() {
        let scene = GameScene(size: CGSize(width: 800, height: 600))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.presentScene(scene)
        scene.transitionTo(.playing)
        
        // Esc to quit confirmation
        scene.simulateKeyDown(keyCode: 53)
        XCTAssertEqual(scene.gameState, .quitConfirmation)
        
        // Typing Esc again should resume playing state
        scene.simulateKeyDown(keyCode: 53)
        XCTAssertEqual(scene.gameState, .playing)
        
        // Esc to quit confirmation
        scene.simulateKeyDown(keyCode: 53)
        XCTAssertEqual(scene.gameState, .quitConfirmation)
        
        // Typing Y should return to startScreen
        scene.simulateTypeCharacter("y")
        XCTAssertEqual(scene.gameState, .startScreen)
    }
    
    func testGlossaryOpenAndNavigation() {
        let scene = GameScene(size: CGSize(width: 800, height: 600))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        view.presentScene(scene)
        scene.transitionTo(.startScreen)
        XCTAssertEqual(scene.gameState, .startScreen)
        
        // Press I to open glossary (start at the bottom scroll limit)
        scene.simulateTypeCharacter("i")
        XCTAssertEqual(scene.gameState, .glossary)
        XCTAssertEqual(scene.glossaryContainerYForTesting, -600.0)

        // Press Up Arrow (126) -> scroll up
        scene.simulateKeyDown(keyCode: 126)
        XCTAssertEqual(scene.glossaryContainerYForTesting, -580.0)

        // Press Down Arrow (125) -> scroll down
        scene.simulateKeyDown(keyCode: 125)
        XCTAssertEqual(scene.glossaryContainerYForTesting, -600.0)

        // Press Down Arrow again -> should wrap around to the top limit (1900)
        scene.simulateKeyDown(keyCode: 125)
        XCTAssertEqual(scene.glossaryContainerYForTesting, 1900.0)

        // Press Up Arrow at top limit -> should wrap around to the bottom limit (-600)
        scene.simulateKeyDown(keyCode: 126)
        XCTAssertEqual(scene.glossaryContainerYForTesting, -600.0)

        // Press I to return to title
        scene.simulateTypeCharacter("i")
        XCTAssertEqual(scene.gameState, .startScreen)

        // Open again
        scene.simulateTypeCharacter("i")
        XCTAssertEqual(scene.gameState, .glossary)

        // Test auto scrolling inside update loop (currentTime starts at 0 -> 10s, then 11s)
        scene.update(10.0)
        XCTAssertEqual(scene.glossaryContainerYForTesting, -600.0)
        scene.update(11.0) // 1 second passes -> Y should increase by 35.0
        XCTAssertEqual(scene.glossaryContainerYForTesting, -565.0, accuracy: 0.1)
        
        // Press Escape to return to title
        scene.simulateKeyDown(keyCode: 53)
        XCTAssertEqual(scene.gameState, .startScreen)
    }

}
