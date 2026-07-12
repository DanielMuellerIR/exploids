// Physik-Tests: Schiff, Laser, Kollisionshelfer, Asteroiden (Bewegung/Wrap/Spawn) und Welt-Vertices.
// Reiner Split aus der früheren GameCoreTests.swift — keine Logikänderung.

import XCTest
import SpriteKit
@testable import GameCore

@MainActor
final class PhysicsTests: GameCoreTestCase {

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

}
