import XCTest
import SpriteKit
import ImageIO
import UniformTypeIdentifiers
@testable import GameCore

@MainActor
final class Review20261007Tests: GameCoreTestCase {
    private func scene(mode: GameMode) -> (GameScene, SKView) {
        let scene = makeIsolatedScene(size: CGSize(width: 1000, height: 800))
        scene.externalStepDriving = true
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
        view.presentScene(scene)
        scene.startNewGameForTesting(seed: 42, mode: mode)
        scene.isSpawningEnabled = false
        scene.clearAllEntitiesForTesting()
        return (scene, view)
    }

    func testCrossingLaserHitsMovingSmallUFOWithoutEndpointContact() {
        let (scene, view) = scene(mode: .ancientAsteroids); _ = view
        scene.ship.position = CGPoint(x: 9, y: -33)
        var rng = GameRandom(seed: 42)
        let ufo = UFO(isSmall: true, startOnLeft: false, screenSize: scene.size, using: &rng)
        ufo.position = CGPoint(x: 2.5, y: 0)
        ufo.velocity = CGPoint(x: -150, y: 0)
        scene.addChild(ufo); scene.activeUFOs.append(ufo)
        let laser = Laser(position: CGPoint(x: 9, y: -15), angle: .pi / 2, type: .normal)
        scene.addChild(laser); scene.activeLasers.append(laser)
        for _ in 0..<8 { scene.advanceOneStep() }
        XCTAssertNil(ufo.parent)
        XCTAssertTrue(scene.activeUFOs.isEmpty)
        XCTAssertEqual(scene.score, ufo.pointValue)
        XCTAssertTrue(scene.entityTrackingConsistentForTesting)
    }

    func testFrontLaserAndBeamStayVisibleAtEveryWallAndCompressScale() {
        for scale: CGFloat in [0.3, 0.5, 1] {
            for (position, angle) in [(CGPoint(x: 500, y: 250), CGFloat(0)),
                                      (CGPoint(x: -500, y: 250), CGFloat.pi),
                                      (CGPoint(x: 250, y: 400), CGFloat.pi / 2),
                                      (CGPoint(x: 250, y: -400), -CGFloat.pi / 2)] {
                let (scene, view) = scene(mode: .eventHorizon); _ = view
                scene.ship.setScale(scale); scene.ship.position = position; scene.ship.zRotation = angle
                scene.reflectEventHorizonShip()
                scene.fireLaserForTesting()
                scene.removeExitedEventHorizonEntities()
                XCTAssertEqual(scene.activeLasers.count, 1, "Skalierung \(scale), Richtung \(angle)")
                scene.fireBeamForTesting()
                XCTAssertFalse(scene.beamNode.isHidden)
                guard let path = scene.beamNode.path else { XCTFail("Beam-Pfad fehlt"); continue }
                let bounds = path.boundingBoxOfPath
                XCTAssertGreaterThan(bounds.width + bounds.height, 0.1, "Beam braucht eine sichtbare Linie")
                XCTAssertTrue(scene.eventHorizonScreenBounds.insetBy(dx: -0.001, dy: -0.001).contains(bounds))
                XCTAssertTrue(scene.entityTrackingConsistentForTesting)
                if scale == 0.3, angle == 0,
                   let directory = ProcessInfo.processInfo.environment["EXPLOIDS_REVIEW_SCREENSHOT_DIR"],
                   let image = view.texture(from: scene)?.cgImage() {
                    let url = URL(fileURLWithPath: directory).appendingPathComponent("exploids-front-weapons.png")
                    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
                    CGImageDestinationAddImage(destination, image, nil)
                    XCTAssertTrue(CGImageDestinationFinalize(destination))
                }
            }
        }
    }
}
