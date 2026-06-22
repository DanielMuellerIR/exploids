import XCTest
import SpriteKit
@testable import GameCore

@MainActor
final class GameCoreTests: XCTestCase {
    
    // MARK: - Ship Tests
    
    func testShipInitialSetup() {
        let ship = Ship()
        XCTAssertEqual(ship.strokeColor, .cyan)
        // Check transparency in a cross-platform/color-space-safe way
        XCTAssertEqual(ship.fillColor.alphaComponent, 0.0)
        XCTAssertEqual(ship.lineWidth, 2.0)
        XCTAssertEqual(ship.velocity, .zero)
        
        // Check for flame node
        let flameNode = ship.children.first as? SKShapeNode
        XCTAssertNotNil(flameNode)
        XCTAssertEqual(flameNode?.strokeColor, .orange)
        XCTAssertTrue(flameNode?.isHidden ?? false)
    }
    
    func testShipRotation() {
        let ship = Ship()
        ship.zRotation = 0.0
        
        // Rotate left (counter-clockwise, rotationInput = 1.0)
        ship.update(deltaTime: 1.0, isThrusting: false, rotationInput: 1.0)
        XCTAssertEqual(ship.zRotation, ship.rotationSpeed)
        
        // Rotate right (clockwise, rotationInput = -1.0)
        ship.update(deltaTime: 0.5, isThrusting: false, rotationInput: -1.0)
        XCTAssertEqual(ship.zRotation, ship.rotationSpeed - (ship.rotationSpeed * 0.5))
    }
    
    func testShipThrustAcceleration() {
        let ship = Ship()
        ship.velocity = .zero
        ship.zRotation = 0.0 // Facing right (+x direction)
        
        ship.update(deltaTime: 0.1, isThrusting: true, rotationInput: 0.0)
        
        // Velocity should have increased along x axis, y axis should be 0
        XCTAssertGreaterThan(ship.velocity.x, 0.0)
        XCTAssertEqual(ship.velocity.y, 0.0, accuracy: 1e-5)
        
        // Flame node should be visible
        let flameNode = ship.children.first as? SKShapeNode
        XCTAssertFalse(flameNode?.isHidden ?? true)
    }
    
    func testShipFrictionDecay() {
        let ship = Ship()
        ship.velocity = CGPoint(x: 100.0, y: 0.0)
        
        // Apply update with no thrust, causing friction decay
        ship.update(deltaTime: 1.0, isThrusting: false, rotationInput: 0.0)
        
        // Velocity should have decayed by frictionDecayRate
        let expectedVelocityX = 100.0 * ship.frictionDecayRate
        XCTAssertEqual(ship.velocity.x, expectedVelocityX, accuracy: 1e-4)
    }
    
    func testShipVelocityClamping() {
        let ship = Ship()
        ship.maxVelocity = 100.0
        // Set velocity exceeding the max clamp
        ship.velocity = CGPoint(x: 150.0, y: 0.0)
        
        // Perform update
        ship.update(deltaTime: 0.01, isThrusting: false, rotationInput: 0.0)
        
        // Velocity magnitude should be clamped to maxVelocity (since 150.0 decayed is still > 100.0)
        let speed = sqrt(ship.velocity.x * ship.velocity.x + ship.velocity.y * ship.velocity.y)
        XCTAssertEqual(speed, 100.0, accuracy: 1e-3)
    }
    
    func testShipWrapAround() {
        let ship = Ship()
        let screenSize = CGSize(width: 800, height: 600)
        
        // Check wrapping on positive X boundary
        ship.position = CGPoint(x: 401.0, y: 0.0)
        ship.wrapAround(screenSize: screenSize)
        XCTAssertEqual(ship.position.x, -399.0)
        
        // Check wrapping on negative X boundary
        ship.position = CGPoint(x: -401.0, y: 0.0)
        ship.wrapAround(screenSize: screenSize)
        XCTAssertEqual(ship.position.x, 399.0)
        
        // Check wrapping on positive Y boundary
        ship.position = CGPoint(x: 0.0, y: 301.0)
        ship.wrapAround(screenSize: screenSize)
        XCTAssertEqual(ship.position.y, -299.0)
        
        // Check wrapping on negative Y boundary
        ship.position = CGPoint(x: 0.0, y: -301.0)
        ship.wrapAround(screenSize: screenSize)
        XCTAssertEqual(ship.position.y, 299.0)
    }
    
    // MARK: - Laser Tests
    
    func testLaserInitialization() {
        let position = CGPoint(x: 10.0, y: 20.0)
        let angle: CGFloat = .pi / 4.0 // 45 degrees
        let speed: CGFloat = 600.0
        let lifetime: TimeInterval = 1.5
        
        let laser = Laser(position: position, angle: angle, speed: speed, lifetime: lifetime)
        
        XCTAssertEqual(laser.position, position)
        XCTAssertEqual(laser.zRotation, angle, accuracy: 1e-5)
        XCTAssertEqual(laser.lifetime, lifetime)
        
        // Speed should match components
        let expectedVx = speed * cos(angle)
        let expectedVy = speed * sin(angle)
        XCTAssertEqual(laser.velocity.x, expectedVx, accuracy: 1e-5)
        XCTAssertEqual(laser.velocity.y, expectedVy, accuracy: 1e-5)
        
        // Check path and styling
        XCTAssertEqual(laser.fillColor.alphaComponent, 0.0)
        XCTAssertEqual(laser.lineWidth, 2.0)
    }
    
    func testLaserUpdateAndExpiration() {
        let laser = Laser(position: .zero, angle: 0.0, speed: 100.0, lifetime: 1.0)
        
        // Initial update
        var expired = laser.update(deltaTime: 0.6)
        XCTAssertFalse(expired)
        XCTAssertEqual(laser.position.x, 60.0, accuracy: 1e-5)
        
        // Update pushing past lifetime
        expired = laser.update(deltaTime: 0.5)
        XCTAssertTrue(expired)
        XCTAssertEqual(laser.position.x, 110.0, accuracy: 1e-5)
    }
    
    func testLaserWrapAround() {
        let laser = Laser(position: CGPoint(x: 500, y: 0), angle: 0.0)
        let screenSize = CGSize(width: 800, height: 600)
        
        laser.wrapAround(screenSize: screenSize)
        XCTAssertEqual(laser.position.x, -300.0)
    }
    
    // MARK: - Collision Tests
    
    func testCollisionHelperSegmentIntersection() {
        // Intersecting segments
        XCTAssertTrue(CollisionHelper.segmentsIntersect(
            CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10),
            CGPoint(x: 0, y: 10), CGPoint(x: 10, y: 0)
        ))
        
        // Parallel segments (no intersection)
        XCTAssertFalse(CollisionHelper.segmentsIntersect(
            CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0),
            CGPoint(x: 0, y: 5), CGPoint(x: 10, y: 5)
        ))
        
        // Collinear but separate
        XCTAssertFalse(CollisionHelper.segmentsIntersect(
            CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0),
            CGPoint(x: 20, y: 0), CGPoint(x: 30, y: 0)
        ))
        
        // T-intersection (should intersect)
        XCTAssertTrue(CollisionHelper.segmentsIntersect(
            CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0),
            CGPoint(x: 5, y: 0), CGPoint(x: 5, y: 5)
        ))
    }
    
    func testCollisionHelperPointInPolygon() {
        let polygon = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 0),
            CGPoint(x: 10, y: 10),
            CGPoint(x: 0, y: 10)
        ]
        
        // Inside
        XCTAssertTrue(CollisionHelper.isPointInPolygon(CGPoint(x: 5, y: 5), polygon: polygon))
        
        // Outside
        XCTAssertFalse(CollisionHelper.isPointInPolygon(CGPoint(x: 15, y: 5), polygon: polygon))
        XCTAssertFalse(CollisionHelper.isPointInPolygon(CGPoint(x: 5, y: -2), polygon: polygon))
    }
    
    func testCollisionHelperPolygonIntersection() {
        let polyA = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 0),
            CGPoint(x: 10, y: 10),
            CGPoint(x: 0, y: 10)
        ]
        
        // Intersecting partially
        let polyB = [
            CGPoint(x: 5, y: 5),
            CGPoint(x: 15, y: 5),
            CGPoint(x: 15, y: 15),
            CGPoint(x: 5, y: 15)
        ]
        XCTAssertTrue(CollisionHelper.polygonsIntersect(polyA, polyB))
        
        // Fully inside (no segment intersections, but polyC is inside polyA)
        let polyC = [
            CGPoint(x: 2, y: 2),
            CGPoint(x: 8, y: 2),
            CGPoint(x: 8, y: 8),
            CGPoint(x: 2, y: 8)
        ]
        XCTAssertTrue(CollisionHelper.polygonsIntersect(polyA, polyC))
        XCTAssertTrue(CollisionHelper.polygonsIntersect(polyC, polyA))
        
        // Non-intersecting completely
        let polyD = [
            CGPoint(x: 20, y: 20),
            CGPoint(x: 30, y: 20),
            CGPoint(x: 30, y: 30),
            CGPoint(x: 20, y: 30)
        ]
        XCTAssertFalse(CollisionHelper.polygonsIntersect(polyA, polyD))
    }
    
    // MARK: - Asteroid Tests
    
    func testAsteroidSetupAndMovement() {
        let asteroid = Asteroid(sizeClass: .large)
        XCTAssertEqual(asteroid.sizeClass, .large)
        XCTAssertGreaterThanOrEqual(asteroid.vertices.count, 8)
        XCTAssertLessThanOrEqual(asteroid.vertices.count, 12)
        XCTAssertEqual(asteroid.strokeColor.alphaComponent, 1.0)
        XCTAssertEqual(asteroid.fillColor.alphaComponent, 0.8, accuracy: 1e-4)
        
        // Movement test
        asteroid.position = .zero
        asteroid.zRotation = 0.0
        asteroid.velocity = CGPoint(x: 50.0, y: -50.0)
        asteroid.angularVelocity = 1.0
        
        asteroid.update(deltaTime: 2.0)
        XCTAssertEqual(asteroid.position.x, 100.0, accuracy: 1e-4)
        XCTAssertEqual(asteroid.position.y, -100.0, accuracy: 1e-4)
        XCTAssertEqual(asteroid.zRotation, 2.0, accuracy: 1e-4)
    }
    
    func testAsteroidWrapAround() {
        let asteroid = Asteroid(sizeClass: .large)
        let screenSize = CGSize(width: 800, height: 600)
        // Der Asteroid muss erst als "eingetreten" gelten, damit er am Kanten-Umlauf teilnimmt
        // (frisch gespawnte Asteroiden fliegen erst von außen herein und wrappen noch nicht).
        asteroid.hasEnteredScreen = true

        asteroid.position = CGPoint(x: 401.0, y: 0.0)
        asteroid.wrapAround(screenSize: screenSize)
        XCTAssertEqual(asteroid.position.x, -399.0)

        asteroid.position = CGPoint(x: 0.0, y: -301.0)
        asteroid.wrapAround(screenSize: screenSize)
        XCTAssertEqual(asteroid.position.y, 299.0)
    }

    /// Sichert den Bug ab: Frisch gespawnte Asteroiden außerhalb des Bildschirms dürfen NICHT
    /// sofort durch wrapAround() in die Bildmitte gefaltet werden, sondern müssen erst von der
    /// Kante hereinfliegen. Erst nachdem der Mittelpunkt einmal im Bild war, wird normal gewrappt.
    func testAsteroidDoesNotWrapBeforeEntering() {
        let asteroid = Asteroid(sizeClass: .large)
        let screenSize = CGSize(width: 800, height: 600)

        // Position weit außerhalb (jenseits einer Bildschirmbreite) — würde alt nach (-303, 0)
        // = mitten ins Bild gefaltet. Neu: bleibt unverändert, solange noch nicht eingetreten.
        asteroid.position = CGPoint(x: 497.0, y: 0.0)
        asteroid.wrapAround(screenSize: screenSize)
        XCTAssertEqual(asteroid.position.x, 497.0, "Asteroid darf vor dem Eintritt nicht gewrappt werden")
        XCTAssertFalse(asteroid.hasEnteredScreen)

        // Sobald der Mittelpunkt im sichtbaren Rechteck liegt, gilt er als eingetreten.
        asteroid.position = CGPoint(x: 100.0, y: 50.0)
        asteroid.wrapAround(screenSize: screenSize)
        XCTAssertTrue(asteroid.hasEnteredScreen)
        XCTAssertEqual(asteroid.position.x, 100.0)

        // Danach wird normal an der Kante umgelaufen.
        asteroid.position = CGPoint(x: 401.0, y: 0.0)
        asteroid.wrapAround(screenSize: screenSize)
        XCTAssertEqual(asteroid.position.x, -399.0)
    }

    /// Sichert ab, dass gespawnte Asteroiden auf einen Punkt im inneren Spielfeld zielen, ihre
    /// Bahn also das sichtbare Rechteck durchquert (kein Vorbeifliegen / Zähler-Leak).
    func testSpawnedAsteroidsAimIntoPlayfield() {
        let scene = GameScene(size: CGSize(width: 1000, height: 800))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        view.presentScene(scene)
        scene.transitionTo(.playing)
        scene.ship.position = .zero

        let halfWidth: CGFloat = 500.0
        let halfHeight: CGFloat = 400.0

        for _ in 0..<50 {
            scene.clearAllEntitiesForTesting()
            scene.spawnAsteroid()
            let ast = scene.activeAsteroids[0]

            // Startposition muss außerhalb des sichtbaren Rechtecks liegen (vom Rand einfliegen).
            let startsOffscreen = abs(ast.position.x) > halfWidth || abs(ast.position.y) > halfHeight
            XCTAssertTrue(startsOffscreen, "Asteroid muss außerhalb des Bildschirms spawnen")

            // Geschwindigkeit muss generell zum Spielfeld-Inneren zeigen: die Projektion des
            // Geschwindigkeitsvektors auf die Richtung Start->Zentrum ist positiv.
            let toCenter = CGPoint(x: -ast.position.x, y: -ast.position.y)
            let dot = ast.velocity.x * toCenter.x + ast.velocity.y * toCenter.y
            XCTAssertGreaterThan(dot, 0.0, "Asteroid muss sich in Richtung Spielfeld bewegen")
        }
    }

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

    // MARK: - Ship Transformation Tests
    
    func testShipGetWorldVertices() {
        let ship = Ship()
        ship.position = CGPoint(x: 10.0, y: 20.0)
        ship.zRotation = .pi / 2.0 // Rotated 90 degrees CCW
        
        let worldVertices = ship.getWorldVertices()
        XCTAssertEqual(worldVertices.count, ship.vertices.count)
        
        // Local Tip: (18, 0)
        // Rotated 90 deg: (-0, 18)
        // Translated by (10, 20): (10, 38)
        XCTAssertEqual(worldVertices[0].x, 10.0, accuracy: 1e-4)
        XCTAssertEqual(worldVertices[0].y, 38.0, accuracy: 1e-4)
        
        // Local bottom-left: (-12, 10)
        // Rotated 90 deg: (-10, -12)
        // Translated by (10, 20): (0, 8)
        XCTAssertEqual(worldVertices[1].x, 0.0, accuracy: 1e-4)
        XCTAssertEqual(worldVertices[1].y, 8.0, accuracy: 1e-4)
    }
    
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
        
        // Advance playTime by 300 seconds (5 minutes)
        scene.update(1.0)
        scene.update(301.0)
        
        // Factor should be 1.0 + 1.5 * (300 / 600) = 1.75
        XCTAssertEqual(scene.difficultyFactor, 1.75, accuracy: 1e-4)
        
        // Advance playTime past 600 seconds (10 minutes)
        scene.update(901.0)
        
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
        if let laser = ufo.shoot(target: scene.ship.position, currentTime: now) {
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
        
        XCTAssertEqual(scene.currentLevel, 1)
        XCTAssertFalse(scene.isLevelClearing)
        
        scene.update(1.0)
        scene.update(61.1)
        
        XCTAssertTrue(scene.isLevelClearing)
        XCTAssertEqual(scene.activeAsteroids.count, 0)
        
        scene.update(65.0)
        
        XCTAssertFalse(scene.isLevelClearing)
        XCTAssertEqual(scene.currentLevel, 2)
        XCTAssertEqual(scene.levelTimeRemaining, 60.0)
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
        
        // powerUp1 (which had 5s remaining, minus 4.1s updates = 0.9s) should be extended to 5s remaining
        // However, on the final frame (5.1 - 4.6 = 0.5s delta), after extension to 5s, it is updated (decayed) by 0.5s.
        // So remaining1 = 5.0 - 0.5 = 4.5s.
        let remaining1 = powerUp1.lifetime - powerUp1.elapsedTime
        XCTAssertEqual(remaining1, 4.5, accuracy: 0.1)
        
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
        
        // Remaining lifetime of powerup should be 8.5 - 0.6s delta = 7.9s.
        let remainingBeforeTransition = powerUp.lifetime - powerUp.elapsedTime
        XCTAssertEqual(remainingBeforeTransition, 7.9, accuracy: 0.1)
        
        // Step through the rest of the 3.5s transition:
        scene.update(2.6) // +1.0s -> remaining: 6.9s
        scene.update(3.6) // +1.0s -> remaining: 5.9s
        scene.update(4.6) // +1.0s -> remaining: 4.9s
        scene.update(5.1) // +0.5s -> transition ends!
        
        // Transition ends, so it sets remaining lifetime to 5.0s, and then updates by 0.5s delta.
        // So remaining should be 5.0 - 0.5 = 4.5s.
        XCTAssertFalse(scene.isLevelClearing)
        XCTAssertEqual(scene.activePowerUps.count, 1)
        
        let finalRemaining = powerUp.lifetime - powerUp.elapsedTime
        XCTAssertEqual(finalRemaining, 4.5, accuracy: 0.1)
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

