// Boss-Tests: Kopf-Boss (FloatingHead), Weltraumkatzen (SpaceCat) und Boss-Grafiken aus dem Ressourcenbundle.
// Reiner Split aus der früheren GameCoreTests.swift — keine Logikänderung.

import XCTest
import SpriteKit
@testable import GameCore

@MainActor
final class BossTests: GameCoreTestCase {

    // MARK: - Kopf-Boss (FloatingHead)

    func testFloatingHeadStartsEntering() {
        let head = FloatingHead(screenSize: CGSize(width: 1024, height: 768))
        XCTAssertEqual(head.phase, .entering)
        XCTAssertEqual(head.hitsRemaining, FloatingHead.hitsToDestroy)
        XCTAssertFalse(head.isFinished)
    }

    func testFloatingHeadHitsToDestroy() {
        let head = FloatingHead(screenSize: CGSize(width: 1024, height: 768))
        let n = head.hitsRemaining
        XCTAssertGreaterThanOrEqual(n, 2)
        for _ in 0..<(n - 1) {
            XCTAssertFalse(head.registerHit())   // noch nicht zerstört
        }
        XCTAssertTrue(head.registerHit())        // letzter Treffer zerstört
        XCTAssertEqual(head.hitsRemaining, 0)
        XCTAssertTrue(head.registerHit())        // bleibt zerstört
    }

    func testFloatingHeadEmitsExactlyTenUFOsThenRetreats() {
        let head = FloatingHead(screenSize: CGSize(width: 1024, height: 768))
        head.lurkDuration = 0.1
        head.mouthMoveDuration = 0.05
        head.spawnInterval = 0.05

        var totalEmitted = 0
        var finished = false
        for _ in 0..<2000 {
            totalEmitted += head.update(deltaTime: 0.05, shipPosition: .zero)
            if head.isFinished { finished = true; break }
        }
        XCTAssertEqual(totalEmitted, 10, "Der Kopf soll exakt 10 UFOs ausspeien")
        XCTAssertTrue(finished, "Der Kopf soll sich nach dem Ausstoß zurückziehen und verschwinden")
    }

    func testBombDropsDoNotOrphanPowerups() {
        let scene = GameScene(size: CGSize(width: 1024, height: 768))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        view.presentScene(scene)

        scene.simulateKeyDown(keyCode: 49)   // Space -> Spiel startet (Schiff bei (0,0))
        XCTAssertEqual(scene.gameState, .playing)

        // Viele UFOs ABSEITS vom Schiff: die Bombe zerstört sie alle und droppt (20% je UFO)
        // Power-ups an deren Position – weit genug weg, dass das Schiff nicht stirbt/einsammelt.
        for _ in 0..<50 { scene.addUFOForTesting(at: CGPoint(x: 300, y: 300)) }
        // Bombe genau beim Schiff -> wird eingesammelt -> detonateBomb -> Drops WÄHREND des Einsammelns.
        scene.addPowerUpForTesting(PowerUp(type: .bomb, position: .zero))

        scene.update(0.0)    // initialisiert lastUpdateTime (früher Return)
        scene.update(0.1)    // Einsammeln + Detonation + Drops

        // Invariante: KEIN Power-up darf verwaist im Szenengraph liegen (Anzahl Nodes == Tracking-Array).
        XCTAssertEqual(scene.powerUpNodeCountInSceneForTesting, scene.activePowerUps.count,
                       "Von der Bombe gedroppte Power-ups dürfen nicht aus activePowerUps fallen")
    }

    func testFloatingHeadArmadaBypassesUFOLimit() {
        let scene = GameScene(size: CGSize(width: 1024, height: 768))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        view.presentScene(scene)

        // Spiel starten (Space).
        scene.simulateKeyDown(keyCode: 49)
        XCTAssertEqual(scene.gameState, .playing)

        let head = scene.spawnFloatingHeadForTesting()
        head.spawnInterval = 0.01
        head.beginSpawningForTesting()   // sofort in die Spawn-Phase, Mund offen

        var maxUFOs = 0
        var t = 5.0
        for _ in 0..<12 {
            t += 0.05
            scene.update(t)
            maxUFOs = max(maxUFOs, scene.activeUFOs.count)
        }
        // Reguläre Spawns sind auf 2 gedeckelt; die Armada muss das überschreiten.
        XCTAssertGreaterThan(maxUFOs, 2, "Die Armada soll das reguläre 2er-UFO-Limit überschreiten")
    }

    // MARK: - Boss-Grafiken (vektorisierte Konturen aus dem Ressourcenbundle)

    /// Stellt sicher, dass die getracten Boss-Texturen zur Laufzeit aus `Art/` im
    /// Ressourcenbundle ladbar sind (sonst würden Katze/Kopf still auf den Fallback ausweichen).
    /// Belegt zugleich, dass `GameCoreResources.bundle` das Bundle auch im Test-Runner findet —
    /// dort liegt es NEBEN dem .xctest-Bundle, nicht darin.
    func testBossArtTexturesLoadFromBundle() {
        let cat = ArtTexture.load("space_cat")
        let head = ArtTexture.load("zardoz_head")
        XCTAssertNotNil(cat, "space_cat.png fehlt im Art-Bundle")
        XCTAssertNotNil(head, "zardoz_head.png fehlt im Art-Bundle")
        XCTAssertGreaterThan(cat?.size().width ?? 0, 0)
        XCTAssertGreaterThan(head?.size().height ?? 0, 0)
    }

    // MARK: - Weltraumkatzen (SpaceCat)

    func testSpaceCatStartsEntering() {
        let cat = SpaceCat(screenSize: CGSize(width: 1024, height: 768), startOnLeft: true)
        XCTAssertEqual(cat.phase, .entering)
        XCTAssertEqual(cat.hitsRemaining, SpaceCat.hitsToDestroy)
        XCTAssertFalse(cat.isFinished)
    }

    func testSpaceCatHitsToDestroy() {
        let cat = SpaceCat(screenSize: CGSize(width: 1024, height: 768), startOnLeft: true)
        let n = cat.hitsRemaining
        XCTAssertGreaterThanOrEqual(n, 2)
        for _ in 0..<(n - 1) {
            XCTAssertFalse(cat.registerHit())   // noch nicht zerstört
        }
        XCTAssertTrue(cat.registerHit())        // letzter Treffer zerstört
        XCTAssertEqual(cat.hitsRemaining, 0)
        XCTAssertTrue(cat.registerHit())        // bleibt zerstört
    }

    func testSpaceCatFiresThreeTwinShotsThenFlees() {
        let cat = SpaceCat(screenSize: CGSize(width: 1024, height: 768), startOnLeft: true)
        cat.beginStalkingForTesting()
        cat.aimDuration = 0.05
        cat.repositionDuration = 0.05

        var shots = 0
        var finished = false
        var rng = GameRandom(seed: 1)
        for _ in 0..<5000 {
            if let shot = cat.update(deltaTime: 0.05, shipPosition: CGPoint(x: 0, y: 300),
                                     shipVelocity: .zero, using: &rng) {
                shots += 1
                XCTAssertEqual(shot.origins.count, 2, "Doppelschuss = zwei Laser-Ursprünge")
            }
            if cat.isFinished { finished = true; break }
        }
        XCTAssertEqual(shots, 3, "Die Katze soll genau drei Doppelschuss-Versuche abgeben")
        XCTAssertTrue(finished, "Nach dem dritten Versuch soll sie zum Rand fliehen und verschwinden")
    }

    func testSpaceCatTwinLaserIsParallelAndLeadsMovingTarget() {
        let cat = SpaceCat(screenSize: CGSize(width: 1024, height: 768), startOnLeft: true)
        cat.beginStalkingForTesting()
        cat.aimDuration = 0.0   // sofort feuern (kaum Eigenbewegung)

        // Schiff genau ÜBER der Katze, aber nach rechts fliegend -> Voraushalten muss nach rechts
        // zielen (cos des Winkels deutlich > 0), nicht senkrecht nach oben (cos ~ 0).
        let shipPos = CGPoint(x: cat.position.x, y: cat.position.y + 300)
        var rng = GameRandom(seed: 1)
        let shot = cat.update(deltaTime: 0.016, shipPosition: shipPos,
                              shipVelocity: CGPoint(x: 300, y: 0), using: &rng)
        XCTAssertNotNil(shot)
        guard let shot = shot else { return }

        XCTAssertEqual(shot.origins.count, 2)
        let gap = hypot(shot.origins[0].x - shot.origins[1].x,
                        shot.origins[0].y - shot.origins[1].y)
        XCTAssertGreaterThan(gap, 8.0, "Die zwei Laser sollen sichtbar parallel versetzt sein")
        XCTAssertGreaterThan(cos(shot.angle), 0.1, "Predictive Aim soll dem Ziel vorhalten")
    }

    func testPlayerLaserDestroysSpaceCatAfterEnoughHits() {
        let scene = GameScene(size: CGSize(width: 1024, height: 768))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        view.presentScene(scene)

        scene.simulateKeyDown(keyCode: 49)   // Space -> Spiel startet (Schiff bei (0,0))
        XCTAssertEqual(scene.gameState, .playing)

        // Deterministisch: keine weiteren Spawns, Spielfeld leerräumen, damit kein Asteroid die
        // Spielerschüsse abfängt, bevor sie die Katze treffen.
        scene.isSpawningEnabled = false
        scene.clearAllEntitiesForTesting()

        let cat = scene.spawnSpaceCatForTesting(startOnLeft: true)
        cat.position = CGPoint(x: 220, y: 0)   // abseits vom Schiff, damit es nicht rammt
        let scoreBefore = scene.score

        // Genau hitsToDestroy überlappende Spielerschüsse -> Katze zerstört (HP-getrieben, robust
        // gegen künftige HP-Änderungen).
        for _ in 0..<SpaceCat.hitsToDestroy {
            scene.addLaserForTesting(Laser(position: CGPoint(x: 220, y: 0), angle: 0, type: .normal))
        }

        scene.update(1.0)    // initialisiert lastUpdateTime (früher Return; nicht 0, sonst Sentinel)
        scene.update(1.05)   // Bewegung + Kollision + Zerstörung

        XCTAssertTrue(scene.activeCats.isEmpty, "Die Katze soll nach genug Treffern zerstört sein")
        XCTAssertGreaterThanOrEqual(scene.score - scoreBefore, cat.pointValue,
                                    "Das Zerstören soll Punkte geben")
        XCTAssertTrue(scene.entityTrackingConsistentForTesting, "Keine verwaisten Nodes nach dem Kill")
    }

    func testBeamDestroysUFO() {
        let scene = GameScene(size: CGSize(width: 1024, height: 768))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        view.presentScene(scene)
        scene.simulateKeyDown(keyCode: 49)
        scene.isSpawningEnabled = false
        scene.clearAllEntitiesForTesting()

        // UFO entlang des Strahls (Schiff bei (0,0), Blickrichtung +x).
        scene.addUFOForTesting(at: CGPoint(x: 200, y: 0))
        scene.fireBeamForTesting(currentTime: 1.0)

        XCTAssertTrue(scene.activeUFOs.isEmpty, "Der Laserbeam muss UFOs zerstören können")
        XCTAssertTrue(scene.entityTrackingConsistentForTesting)
    }

    func testBeamDestroysSpaceCatThrottled() {
        let scene = GameScene(size: CGSize(width: 1024, height: 768))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        view.presentScene(scene)
        scene.simulateKeyDown(keyCode: 49)
        scene.isSpawningEnabled = false
        scene.clearAllEntitiesForTesting()

        let cat = scene.spawnSpaceCatForTesting(startOnLeft: true)
        cat.position = CGPoint(x: 200, y: 0)   // entlang des Strahls

        // Ein einzelner Beam-Frame darf die Katze NICHT sofort zerschmelzen (Drosselung).
        scene.fireBeamForTesting(currentTime: 1.0)
        XCTAssertFalse(scene.activeCats.isEmpty, "Ein einzelner Beam-Frame darf die Katze nicht sofort töten")

        // Über mehrere gedrosselte Treffer (Zeit jeweils > beamHitInterval) wird sie zerstört.
        for i in 1...SpaceCat.hitsToDestroy {
            scene.fireBeamForTesting(currentTime: 1.0 + Double(i) * 0.2)
        }
        XCTAssertTrue(scene.activeCats.isEmpty, "Anhaltender Laserbeam muss die Katze zerstören")
        XCTAssertTrue(scene.entityTrackingConsistentForTesting)
    }

    func testNoOrphanEntitiesAfterBombOnMixedField() {
        let scene = GameScene(size: CGSize(width: 1024, height: 768))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        view.presentScene(scene)
        scene.simulateKeyDown(keyCode: 49)
        scene.isSpawningEnabled = false
        scene.clearAllEntitiesForTesting()

        // Gemischtes Feld weit weg vom Schiff (damit das Schiff nicht stirbt/einsammelt).
        for i in 0..<4 {
            let ast = Asteroid(sizeClass: .large, isImplodingType: false, isWobblingType: false)
            ast.position = CGPoint(x: 250 + CGFloat(i) * 30, y: 250)
            scene.addAsteroidForTesting(ast)
        }
        for _ in 0..<3 { scene.addUFOForTesting(at: CGPoint(x: 300, y: -250)) }
        let cat = scene.spawnSpaceCatForTesting(startOnLeft: true)
        cat.position = CGPoint(x: -300, y: 250)
        scene.spawnPowerUpForTesting(type: .shield, position: CGPoint(x: -300, y: -250))

        // Bombe genau beim Schiff -> wird eingesammelt -> Detonation -> Wirkung auf alle Objekte.
        scene.addPowerUpForTesting(PowerUp(type: .bomb, position: .zero))

        scene.update(1.0)
        scene.update(1.05)

        // Invariante: KEIN Entity-Typ darf verwaiste Nodes im Szenengraph hinterlassen.
        XCTAssertTrue(scene.entityTrackingConsistentForTesting,
                      "Nach einer Bombe auf gemischtem Feld dürfen keine verwaisten Nodes übrig bleiben")
        // Die Bombe wirkt wie ein direkter Schuss: UFOs sind sofort weg.
        XCTAssertTrue(scene.activeUFOs.isEmpty, "Die Bombe muss alle UFOs erledigen")
    }

    func testSpaceCatLaserKillsShipWithOwnDeathCause() {
        let scene = GameScene(size: CGSize(width: 1024, height: 768))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        view.presentScene(scene)

        scene.simulateKeyDown(keyCode: 49)
        XCTAssertEqual(scene.gameState, .playing)
        scene.isSpawningEnabled = false
        scene.clearAllEntitiesForTesting()

        // Katzen-Augenlaser (.catEye) direkt auf das Schiff (bei (0,0)).
        scene.addLaserForTesting(Laser(position: .zero, angle: 0, type: .catEye,
                                       speed: SpaceCat.laserSpeed, lifetime: 3.0))
        scene.update(1.0)
        scene.update(1.05)

        XCTAssertEqual(scene.lastDeathCause, .spaceCatLaser,
                       "Treffer durch Katzen-Augenlaser soll die eigene Todesursache setzen")
    }

    func testCatEyeLaserDoesNotHitAsteroidsOrUFOs() {
        let scene = GameScene(size: CGSize(width: 1024, height: 768))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        view.presentScene(scene)

        scene.simulateKeyDown(keyCode: 49)
        XCTAssertEqual(scene.gameState, .playing)
        scene.isSpawningEnabled = false
        scene.clearAllEntitiesForTesting()

        let ast = Asteroid(sizeClass: .large, isImplodingType: false, isWobblingType: false)
        ast.position = CGPoint(x: 120, y: 0)
        scene.addAsteroidForTesting(ast)
        scene.addUFOForTesting(at: CGPoint(x: 120, y: 0))

        // Katzen-Augenlaser über Asteroid + UFO – er ist ein Gegner-Schuss und darf keines treffen.
        scene.addLaserForTesting(Laser(position: CGPoint(x: 120, y: 0), angle: 0, type: .catEye,
                                       speed: SpaceCat.laserSpeed, lifetime: 3.0))
        scene.update(1.0)
        scene.update(1.05)

        XCTAssertEqual(scene.activeAsteroids.count, 1, "Katzen-Augenlaser darf keine Asteroiden zerstören")
        XCTAssertEqual(scene.activeUFOs.count, 1, "Katzen-Augenlaser darf keine UFOs zerstören")
    }

}
