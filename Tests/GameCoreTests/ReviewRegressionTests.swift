import XCTest
import SpriteKit
@testable import GameCore

@MainActor
final class ReviewRegressionTests: GameCoreTestCase {
    private func scene() -> (GameScene, SKView) {
        let scene = GameScene(size: CGSize(width: 1000, height: 800))
        scene.externalStepDriving = true
        let suite = "exploids-review-" + UUID().uuidString
        scene.useUserDefaultsForTesting(UserDefaults(suiteName: suite)!)
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let view = SKView(frame: CGRect(origin: .zero, size: scene.size))
        view.presentScene(scene)
        scene.startNewGameForTesting(seed: 42)
        scene.isSpawningEnabled = false
        scene.clearAllEntitiesForTesting()
        return (scene, view)
    }

    func testPauseFreezesGameTimeAndPowerUpDeadlines() {
        let (scene, view) = scene(); _ = view
        scene.collectPowerUpForTesting(type: .rapid)
        let deadline = scene.rapidFireEndTimeForTesting
        let time = scene.gameTime
        scene.simulateKeyDown(keyCode: 53)
        for _ in 0..<240 { scene.advanceOneStep() }
        XCTAssertEqual(scene.gameTime, time)
        XCTAssertEqual(scene.rapidFireEndTimeForTesting, deadline)
        scene.simulateKeyDown(keyCode: 53)
        scene.advanceOneStep()
        XCTAssertEqual(scene.gameTime, time + GameScene.simStep)
    }

    func testReleasedFireDoesNotRemainHeldAfterPause() {
        let (scene, view) = scene(); _ = view
        scene.autoFire = false
        for _ in 0..<30 { scene.advanceOneStep() }
        scene.simulateKeyDown(keyCode: 49)
        scene.simulateKeyDown(keyCode: 53)
        scene.simulateKeyUp(keyCode: 49)
        scene.simulateKeyDown(keyCode: 53)
        scene.activeLasers.forEach { $0.removeFromParent() }
        scene.activeLasers.removeAll()
        for _ in 0..<60 { scene.advanceOneStep() }
        XCTAssertTrue(scene.activeLasers.isEmpty)
    }

    func testPauseResumeAutoFireAndCheatReplayExactly() throws {
        let (recorded, view) = scene(); _ = view
        for _ in 0..<60 { recorded.advanceOneStep() }
        recorded.handleKeyDown(keyCode: 3, characters: "f", charactersIgnoringModifiers: "f", isCommandDown: false)
        recorded.handleKeyDown(keyCode: 42, characters: "#", charactersIgnoringModifiers: "#", isCommandDown: false)
        for _ in 0..<60 { recorded.advanceOneStep() }
        recorded.simulateKeyDown(keyCode: 49)
        recorded.simulateKeyDown(keyCode: 53)
        for _ in 0..<240 { recorded.advanceOneStep() }
        recorded.simulateKeyUp(keyCode: 49)
        recorded.simulateKeyDown(keyCode: 53)
        for _ in 0..<120 { recorded.advanceOneStep() }
        let replay = try XCTUnwrap(recorded.currentReplayForTesting())
        XCTAssertEqual(replay.frameCount, 240, "Die Pause zählt keine Spielschritte")
        let (playback, playbackView) = scene(); _ = playbackView
        XCTAssertTrue(playback.startReplay(try Replay(data: replay.encoded())))
        playback.clearAllEntitiesForTesting()
        for _ in 0..<replay.frameCount { playback.advanceOneStep() }
        XCTAssertEqual(playback.gameState, recorded.gameState)
        XCTAssertEqual(playback.gameTime, recorded.gameTime)
        XCTAssertEqual(playback.autoFire, recorded.autoFire)
        XCTAssertEqual(playback.extraLivesForTesting, recorded.extraLivesForTesting)
        XCTAssertEqual(playback.activeLasers.map(\.position), recorded.activeLasers.map(\.position))
        XCTAssertEqual(playback.ship.position, recorded.ship.position)
    }

    func testEnemySegmentCrossingHullHitsWithoutContainedEndpoints() {
        for (type, scale) in [(LaserType.catEye, CGFloat(1)), (.enemy, CGFloat(0.04))] {
            let (scene, view) = scene(); _ = view
            scene.ship.setScale(scale)
            let laser = Laser(position: scene.ship.position, angle: .pi / 2, type: type)
            let (a, b) = laser.getWorldSegment()
            XCTAssertFalse(CollisionHelper.isPointInPolygon(a, polygon: scene.ship.getWorldVertices()))
            XCTAssertFalse(CollisionHelper.isPointInPolygon(b, polygon: scene.ship.getWorldVertices()))
            scene.addLaserForTesting(laser)
            scene.advanceOneStep()
            XCTAssertNotEqual(scene.gameState, .playing)
            XCTAssertNil(laser.parent)
        }
    }

    func testAbsorbedAsteroidCannotFeedTwoSeparatedImploders() {
        let (scene, view) = scene(); _ = view
        scene.ship.position = CGPoint(x: -400, y: -300)
        let normal = Asteroid(sizeClass: .large)
        let left = Asteroid(sizeClass: .small, isImplodingType: true)
        let right = Asteroid(sizeClass: .small, isImplodingType: true)
        for (asteroid, x) in [(normal, CGFloat(0)), (left, -30), (right, 30)] {
            asteroid.position = CGPoint(x: x, y: 200)
            asteroid.velocity = .zero
            scene.addAsteroidForTesting(asteroid)
        }
        XCTAssertTrue(CollisionHelper.polygonsIntersect(normal.getWorldVertices(), left.getWorldVertices()))
        XCTAssertTrue(CollisionHelper.polygonsIntersect(normal.getWorldVertices(), right.getWorldVertices()))
        XCTAssertFalse(CollisionHelper.polygonsIntersect(left.getWorldVertices(), right.getWorldVertices()))
        scene.advanceOneStep()
        XCTAssertNil(normal.parent)
        XCTAssertEqual(left.xScale, 1.35, accuracy: 0.0001)
        XCTAssertEqual(right.xScale, 1, accuracy: 0.0001)
        XCTAssertTrue(scene.entityTrackingConsistentForTesting)
    }

    func testImplosionOrderFollowsEntityOrder() {
        for _ in 0..<12 {
            let (scene, view) = scene(); _ = view
            scene.ship.position = CGPoint(x: 0, y: -300)
            for x: CGFloat in [-250, 250] {
                let imploder = Asteroid(sizeClass: .small, isImplodingType: true)
                imploder.setScale(2.7)
                let normal = Asteroid(sizeClass: .small)
                for asteroid in [imploder, normal] {
                    asteroid.position = CGPoint(x: x, y: 200)
                    asteroid.velocity = .zero
                    scene.addAsteroidForTesting(asteroid)
                }
            }
            scene.advanceOneStep()
            XCTAssertEqual(scene.activeGravityWells.map { $0.position.x }, [-250, 250])
        }
    }

    func testHiddenRenderHUDStaysHiddenWhenLifeIsCollected() {
        let (scene, view) = scene(); _ = view
        scene.setHUDHiddenForRender(true)
        scene.collectPowerUpForTesting(type: .extraLife)
        scene.advanceOneStep()
        XCTAssertTrue(scene.livesLabel.isHidden)
    }
}
