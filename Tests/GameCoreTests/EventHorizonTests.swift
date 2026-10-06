import XCTest
import SpriteKit
@testable import GameCore

@MainActor
final class EventHorizonTests: GameCoreTestCase {
    private func makeScene(size: CGSize = CGSize(width: 1000, height: 800)) -> (GameScene, SKView) {
        let scene = GameScene(size: size)
        scene.externalStepDriving = true
        let suite = "exploids-event-horizon-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        scene.useUserDefaultsForTesting(defaults)
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        view.presentScene(scene)
        scene.startNewGameForTesting(seed: 42, mode: .eventHorizon)
        scene.isSpawningEnabled = false
        for asteroid in scene.activeAsteroids { asteroid.removeFromParent() }
        scene.activeAsteroids.removeAll()
        return (scene, view)
    }

    func testModeSelectionAndReplayValue() throws {
        XCTAssertEqual(GameMode.eventHorizon.rawValue, 2)
        let (scene, view) = makeScene()
        _ = view
        scene.transitionTo(.startScreen)
        scene.setGameModeForTesting(.ancientAsteroids)
        scene.simulateKeyDown(keyCode: 125)
        XCTAssertEqual(scene.selectedMode, .madMeteoroids)
        scene.simulateKeyDown(keyCode: 125)
        XCTAssertEqual(scene.selectedMode, .eventHorizon)
        XCTAssertTrue(scene.modeSelectionLabel.text?.contains("EVENT HORIZON") == true)
        scene.simulateKeyDown(keyCode: 126)
        XCTAssertEqual(scene.selectedMode, .madMeteoroids)
        let replay = Replay(seed: 42, startLevel: 1, gameMode: .eventHorizon, events: [], frameCount: 10)
        XCTAssertEqual(try Replay(data: replay.encoded()), replay)
    }

    func testShipReflectsAtEveryWallWithoutChangingSpeedOrHeading() {
        let (scene, view) = makeScene()
        _ = view
        for (position, velocity) in [
            (CGPoint(x: 500, y: 200), CGPoint(x: 120, y: 60)),
            (CGPoint(x: -500, y: 200), CGPoint(x: -120, y: 60)),
            (CGPoint(x: 350, y: 400), CGPoint(x: 120, y: 60)),
            (CGPoint(x: 350, y: -400), CGPoint(x: 120, y: -60))
        ] {
            scene.ship.position = position
            scene.ship.velocity = velocity
            scene.ship.zRotation = 0.6
            let heading = scene.ship.zRotation
            scene.reflectEventHorizonShip()
            let bounds = scene.eventHorizonBounds(scene.ship.getWorldVertices(), padding: scene.ship.lineWidth / 2)
            XCTAssertTrue(scene.eventHorizonScreenBounds.insetBy(dx: -0.001, dy: -0.001).contains(bounds))
            XCTAssertEqual(hypot(scene.ship.velocity.x, scene.ship.velocity.y), hypot(velocity.x, velocity.y), accuracy: 0.0001)
            XCTAssertEqual(scene.ship.zRotation, heading)
            if abs(position.x) == 500 {
                XCTAssertEqual(scene.ship.velocity.x, -velocity.x)
                XCTAssertEqual(scene.ship.velocity.y, velocity.y)
            } else {
                XCTAssertEqual(scene.ship.velocity.x, velocity.x)
                XCTAssertEqual(scene.ship.velocity.y, -velocity.y)
            }
        }
    }

    func testCornerReflectsBothComponentsAndCompressedShipStaysInside() {
        let (scene, view) = makeScene()
        _ = view
        for scale: CGFloat in [1, 0.3] {
            scene.ship.setScale(scale)
            scene.ship.position = CGPoint(x: 500, y: 400)
            scene.ship.velocity = CGPoint(x: 120, y: 60)
            scene.reflectEventHorizonShip()
            XCTAssertEqual(scene.ship.velocity, CGPoint(x: -120, y: -60))
            XCTAssertTrue(scene.eventHorizonScreenBounds.insetBy(dx: -0.001, dy: -0.001)
                .contains(scene.eventHorizonBounds(scene.ship.getWorldVertices(), padding: scene.ship.lineWidth / 2)))
        }
    }

    func testExpandedHullAtWallDoesNotReverseAnInwardVelocity() {
        let (scene, view) = makeScene()
        _ = view
        scene.ship.position = CGPoint(x: 495, y: 250)
        scene.ship.velocity = CGPoint(x: -120, y: 60)
        scene.ship.zRotation = 0.6
        scene.reflectEventHorizonShip()
        XCTAssertEqual(scene.ship.velocity, CGPoint(x: -120, y: 60))
        XCTAssertTrue(scene.eventHorizonScreenBounds.insetBy(dx: -0.001, dy: -0.001)
            .contains(scene.eventHorizonBounds(scene.ship.getWorldVertices(), padding: scene.ship.lineWidth / 2)))
    }

    func testOptionDroneLeavesPermanentlyAndTrackingRemainsConsistent() {
        let (scene, view) = makeScene()
        _ = view
        scene.collectPowerUpForTesting(type: .option)
        let drone = scene.options[0]
        drone.position = CGPoint(x: 550, y: 250)
        scene.removeExitedEventHorizonEntities()
        XCTAssertNil(drone.parent)
        XCTAssertTrue(scene.options.isEmpty)
        XCTAssertTrue(scene.entityTrackingConsistentForTesting)
    }

    func testRealSimulationReflectsShipAndDoesNotWrap() {
        let (scene, view) = makeScene()
        _ = view
        scene.ship.position = CGPoint(x: 480, y: 300)
        scene.ship.velocity = CGPoint(x: 300, y: 100)
        for _ in 0..<10 { scene.advanceOneStep() }
        XCTAssertLessThan(scene.ship.velocity.x, 0)
        XCTAssertGreaterThan(scene.ship.velocity.y, 0)
        XCTAssertGreaterThan(scene.ship.position.x, 400)
    }

    func testAsteroidEntersThenLeavesPermanentlyOnlyAfterFullExit() {
        let (scene, view) = makeScene()
        _ = view
        let asteroid = Asteroid(sizeClass: .large)
        asteroid.position = CGPoint(x: 650, y: 250)
        scene.addAsteroidForTesting(asteroid)
        scene.removeExitedEventHorizonEntities()
        XCTAssertNotNil(asteroid.parent, "Einfliegende Asteroiden dürfen außerhalb starten")
        asteroid.position.x = 490
        scene.removeExitedEventHorizonEntities()
        XCTAssertTrue(asteroid.hasEnteredScreen)
        asteroid.position.x = 510
        scene.removeExitedEventHorizonEntities()
        XCTAssertNotNil(asteroid.parent, "Teilweise sichtbare Asteroiden bleiben")
        asteroid.position.x = 600
        scene.removeExitedEventHorizonEntities()
        XCTAssertNil(asteroid.parent)
        XCTAssertTrue(scene.activeAsteroids.isEmpty)
        for _ in 0..<120 { scene.advanceOneStep() }
        XCTAssertTrue(scene.activeAsteroids.isEmpty)
        XCTAssertTrue(scene.entityTrackingConsistentForTesting)
    }

    func testProjectilesAndPowerUpsLeaveThroughAllEdges() {
        let (scene, view) = makeScene()
        _ = view
        for type in [LaserType.normal, .enemy, .catEye] {
            for position in [CGPoint(x: -550, y: 250), CGPoint(x: 550, y: 250),
                             CGPoint(x: 300, y: -450), CGPoint(x: 300, y: 450)] {
                let laser = Laser(position: position, angle: .pi / 4, type: type)
                scene.addLaserForTesting(laser)
                scene.removeExitedEventHorizonEntities()
                XCTAssertNil(laser.parent)
            }
        }
        let visibleLaser = Laser(position: CGPoint(x: 510, y: 250), angle: 0, type: .catEye)
        scene.addLaserForTesting(visibleLaser)
        scene.removeExitedEventHorizonEntities()
        XCTAssertNotNil(visibleLaser.parent, "Der Schwanz eines teilweise sichtbaren Schusses bleibt")
        visibleLaser.position.x = 550
        let powerUp = PowerUp(type: .shield, position: CGPoint(x: 550, y: 250))
        scene.addPowerUpForTesting(powerUp)
        scene.removeExitedEventHorizonEntities()
        XCTAssertNil(visibleLaser.parent)
        XCTAssertNil(powerUp.parent)
        XCTAssertTrue(scene.entityTrackingConsistentForTesting)
    }

    func testUFOAndBossesCanEnterAndLeaveThroughAnyEdge() {
        let (scene, view) = makeScene()
        _ = view
        let ufo = scene.addUFOForTesting(at: CGPoint(x: 560, y: 250))
        let cat = scene.spawnSpaceCatForTesting()
        let head = scene.spawnFloatingHeadForTesting()
        scene.removeExitedEventHorizonEntities()
        XCTAssertNotNil(ufo.parent)
        XCTAssertNotNil(cat.parent)
        XCTAssertNotNil(head.parent)
        for node in [ufo, cat, head] as [SKNode] { node.position = CGPoint(x: 300, y: 250) }
        scene.removeExitedEventHorizonEntities()
        ufo.position.y = 500
        cat.position.x = -900
        head.position.y = -700
        scene.removeExitedEventHorizonEntities()
        XCTAssertNil(ufo.parent)
        XCTAssertNil(cat.parent)
        XCTAssertNil(head.parent)
        XCTAssertTrue(scene.activeUFOs.isEmpty)
        XCTAssertTrue(scene.activeCats.isEmpty)
        XCTAssertNil(scene.activeHead)
        XCTAssertTrue(scene.entityTrackingConsistentForTesting)
    }

    func testFleeingCatRemainsUntilItsWholeArtworkHasExited() {
        let (scene, view) = makeScene()
        _ = view
        let cat = scene.spawnSpaceCatForTesting(startOnLeft: false)
        cat.beginStalkingForTesting()
        cat.aimDuration = 0
        cat.repositionDuration = 0
        for _ in 0..<30 {
            scene.advanceOneStep()
            if cat.phase == .fleeing { break }
        }
        XCTAssertEqual(cat.phase, .fleeing)
        cat.position = CGPoint(x: 500 - cat.boundaryLocalBounds.minX - 10, y: 250)
        scene.advanceOneStep()
        XCTAssertNotNil(cat.parent, "Die sichtbare Schweifspitze darf nicht vorzeitig verschwinden")
        for _ in 0..<10 { scene.advanceOneStep() }
        XCTAssertNil(cat.parent)
        XCTAssertTrue(scene.activeCats.isEmpty)
        XCTAssertTrue(scene.entityTrackingConsistentForTesting)
    }

    func testCenterHolePersistsThroughLifetimeAndLevelTransition() {
        let (scene, view) = makeScene()
        _ = view
        let well = scene.activeGravityWells[0]
        scene.ship.position = CGPoint(x: 400, y: -300)
        for _ in 0..<2500 { scene.advanceOneStep() }
        XCTAssertEqual(scene.activeGravityWells.count, 1)
        XCTAssertTrue(scene.activeGravityWells[0] === well)
        XCTAssertEqual(well.position, .zero)
        scene.setLevelTimeRemainingForTesting(0)
        scene.advanceOneStep()
        XCTAssertTrue(scene.isLevelClearing)
        for _ in 0..<430 { scene.advanceOneStep() }
        XCTAssertEqual(scene.currentLevel, 2)
        XCTAssertTrue(scene.activeGravityWells[0] === well)
        XCTAssertTrue(scene.entityTrackingConsistentForTesting)
    }

    func testCenterHoleSurvivesShieldHitAndReviveStartsOutsideIt() {
        let (scene, view) = makeScene()
        _ = view
        let well = scene.activeGravityWells[0]
        scene.ship.position = .zero
        scene.ship.shieldLevel = 1
        scene.advanceOneStep()
        XCTAssertEqual(scene.ship.shieldLevel, 0)
        XCTAssertTrue(scene.activeGravityWells[0] === well)
        scene.setExtraLivesForTesting(1)
        scene.damageShipForTesting()
        XCTAssertGreaterThan(hypot(scene.ship.position.x, scene.ship.position.y), well.eventHorizonRadius)
        XCTAssertEqual(scene.extraLivesForTesting, 0)
        XCTAssertTrue(scene.activeGravityWells[0] === well)
    }

    func testImplosionsAndRandomSpawningNeverCreateExtraHoles() {
        let (scene, view) = makeScene()
        _ = view
        let well = scene.activeGravityWells[0]
        let asteroid = Asteroid(sizeClass: .large, isImplodingType: true)
        asteroid.position = CGPoint(x: 300, y: 250)
        scene.addAsteroidForTesting(asteroid)
        for _ in 0..<4 { scene.collectPowerUpForTesting(type: .bomb) }
        XCTAssertNil(asteroid.parent)
        XCTAssertEqual(scene.activeGravityWells.count, 1)
        XCTAssertTrue(scene.activeGravityWells[0] === well)
        scene.startNewGameForTesting(seed: 5678, startLevel: 9, mode: .eventHorizon)
        scene.ship.position = CGPoint(x: 400, y: -300)
        scene.setExtraLivesForTesting(100)
        scene.isSpawningEnabled = true
        for step in 0..<4000 {
            scene.advanceOneStep()
            XCTAssertEqual(scene.activeGravityWells.count, 1, "Schritt \(step)")
            XCTAssertEqual(scene.activeGravityWells[0].position, .zero)
            XCTAssertTrue(scene.entityTrackingConsistentForTesting)
        }
    }

    func testBeamStopsAtEdgeAndCannotHitOppositeSide() {
        let (scene, view) = makeScene()
        _ = view
        scene.ship.position = CGPoint(x: 460, y: 300)
        scene.ship.zRotation = 0
        let asteroid = Asteroid(sizeClass: .small)
        asteroid.position = CGPoint(x: -470, y: 300)
        scene.addAsteroidForTesting(asteroid)
        scene.fireBeamForTesting()
        XCTAssertNotNil(asteroid.parent)
        XCTAssertLessThanOrEqual(scene.beamNode.path!.boundingBoxOfPath.maxX, 500)
        XCTAssertGreaterThan(scene.beamNode.path!.boundingBoxOfPath.minX, 450)
    }

    func testEventHorizonReplayReproducesSimulationAcrossSceneSizes() throws {
        for seed: UInt64 in [42, 5678] {
            for size in [CGSize(width: 480, height: 360), CGSize(width: 1000, height: 800)] {
                let (scene, view) = makeScene(size: size)
                _ = view
                scene.isSpawningEnabled = true
                scene.autoFire = true
                scene.startNewGameForTesting(seed: seed, mode: .eventHorizon)
                scene.simulateKeyDown(keyCode: 13)
                scene.simulateKeyDown(keyCode: 0)
                for _ in 0..<500 {
                    scene.advanceOneStep()
                    if scene.gameState != .playing { break }
                }
                let replay = try XCTUnwrap(scene.currentReplayForTesting() ?? scene.lastReplay)
                XCTAssertGreaterThan(replay.frameCount, 100)
                let (playback, playbackView) = makeScene(size: CGSize(width: 640, height: 480))
                _ = playbackView
                playback.isSpawningEnabled = true
                XCTAssertTrue(playback.startReplay(try Replay(data: replay.encoded())))
                for _ in 0..<replay.frameCount { playback.advanceOneStep() }
                XCTAssertEqual(playback.size, size)
                XCTAssertEqual(playback.ship.position, scene.ship.position)
                XCTAssertEqual(playback.ship.velocity, scene.ship.velocity)
                XCTAssertEqual(playback.gameState, scene.gameState)
                XCTAssertEqual(playback.score, scene.score)
                XCTAssertEqual(playback.gameTime, scene.gameTime)
                XCTAssertEqual(playback.activeAsteroids.map(\.position), scene.activeAsteroids.map(\.position))
                XCTAssertEqual(playback.activeLasers.map(\.position), scene.activeLasers.map(\.position))
                var a = scene.rng, b = playback.rng
                XCTAssertEqual(a.next(), b.next())
                XCTAssertTrue(playback.entityTrackingConsistentForTesting)
            }
        }
    }
}
