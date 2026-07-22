// Autopilot-/Demo-Modus-Tests: Personas überleben, kein Highscore-/Aufnahme-Eintrag im Demo-Lauf.
// Reiner Split aus der früheren GameCoreTests.swift — keine Logikänderung.

import XCTest
import SpriteKit
@testable import GameCore

@MainActor
final class AutopilotTests: GameCoreTestCase {

    // MARK: - Autopilot / Demo-Modus

    /// Jede Demo-Probe bekommt eine eigene Persistenz-Domain. So kann selbst ein
    /// fehlgeschlagener Progressions-Guard keine echten Spielerwerte veraendern.
    private func makeIsolatedScene(
        size: CGSize = CGSize(width: 1024, height: 768)
    ) -> (scene: GameScene, view: SKView, defaults: UserDefaults, suiteName: String) {
        let suiteName = "io.github.danielmuellerir.exploids.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let scene = GameScene(size: size)
        scene.useUserDefaultsForTesting(defaults)
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        view.presentScene(scene)
        return (scene, view, defaults, suiteName)
    }

    /// Läuft ein Autopilot-Lauf, bis er endet (Game Over) oder das Schrittlimit erreicht ist.
    /// Rückgabe: die überlebte Zeit in Sekunden (Schritte ÷ 120).
    private func runAutopilot(_ persona: AutopilotPersona, seed: UInt64, maxSteps: Int = 78000) -> Double {
        let fixture = makeIsolatedScene()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let scene = fixture.scene
        scene.externalStepDriving = true
        scene.startAutopilotDemoForTesting(persona: persona, seed: seed)
        var step = 0
        while step < maxSteps && scene.gameState == .playing { scene.advanceOneStep(); step += 1 }
        return Double(step) / 120.0
    }

    /// Erfolgskriterium des Features: Der Experte „Ace" soll ab Level 4 eine sehenswerte, mehrere
    /// Minuten lange Demo liefern (Ziel: im Extremfall die vollen ~10 Minuten). Die Schranken sind
    /// bewusst konservativ (gemessen: Ø ~3 min, Bestwert ~9 min), damit der Test nicht flakig wird –
    /// er ist eine Regressions-Absicherung, dass der Autopilot nicht kollabiert.
    func testAutopilotAceSurvivesMinutes() {
        let seeds: [UInt64] = [42, 4242, 8080, 0xBEEF]
        let times = seeds.map { runAutopilot(.ace, seed: $0) }
        let best = times.max() ?? 0
        let avg = times.reduce(0, +) / Double(times.count)
        XCTAssertGreaterThan(best, 120.0, "Ace sollte in mind. einem Lauf klar über 2 Minuten überleben")
        XCTAssertGreaterThan(avg, 45.0, "Ace sollte im Schnitt deutlich über eine halbe Minute überleben")
    }

    /// Auch die schwächste, draufgängerischste Persona darf nicht reihum „sofort" sterben – ein Lauf,
    /// der sekundenschnell endet, ist laut Vorgabe unerwünscht. Über mehrere Seeds gemittelt soll
    /// selbst „Kamikaze" spürbar länger als ein paar Sekunden durchhalten.
    func testWeakestPersonaDoesNotDieInstantly() {
        let seeds: [UInt64] = [42, 4242, 8080, 0xBEEF]
        let avg = seeds.map { runAutopilot(.kamikaze, seed: $0) }.reduce(0, +) / Double(seeds.count)
        XCTAssertGreaterThan(avg, 20.0, "Selbst die riskanteste Persona darf im Schnitt nicht sofort sterben")
    }

    /// Ein Demo-Lauf (Autopilot) darf KEINEN Highscore eintragen: Bei Game Over wird nicht in die
    /// Initialen-Eingabe (`.nameEntry`) gesprungen, sondern direkt in den Game-Over-Screen (dort ist
    /// die Highscore-Liste zu sehen). Zudem wird der Lauf nicht aufgezeichnet/archiviert.
    func testAutopilotDemoSkipsHighscoreEntryAndRecording() {
        let fixture = makeIsolatedScene()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        let scene = fixture.scene
        scene.externalStepDriving = true
        scene.transitionTo(.startScreen)
        scene.setGameModeForTesting(.madMeteoroids)
        scene.selectedStartLevel = 3
        scene.autoFire = false
        scene.startAutopilotDemoForTesting(persona: .ace, seed: 3)
        XCTAssertEqual(scene.autopilotPersonaNameForTesting, "ACE")   // Demo aktiv

        // Ein paar Schritte spielen, dann Game Over deterministisch erzwingen (kein Extra-Leben) –
        // unabhängig davon, wie gut der Autopilot gerade spielt.
        for _ in 0..<20 { scene.advanceOneStep() }
        var guardCount = 0
        while scene.gameState == .playing && guardCount < 5 { scene.damageShipForTesting(); guardCount += 1 }

        XCTAssertEqual(scene.gameState, .gameOver, "Demo-Game-Over darf nicht in die Namenseingabe springen")
        XCTAssertNil(scene.autopilotPersonaNameForTesting, "Nach dem Demo-Lauf ist kein Autopilot mehr aktiv")
        XCTAssertNil(scene.lastReplay, "Ein Demo-Lauf wird nicht aufgezeichnet/archiviert")
        XCTAssertEqual(scene.selectedMode, .madMeteoroids, "Game Over muss den gewaehlten Modus restaurieren")
        XCTAssertEqual(scene.selectedStartLevel, 3, "Game Over muss den gewaehlten Startlevel restaurieren")
        XCTAssertFalse(scene.autoFire, "Game Over muss die Auto-Feuer-Auswahl restaurieren")
    }

    /// Regression fuer zwei Demo-Grenzen zugleich: Ein Levelaufstieg des
    /// Autopiloten darf nichts freischalten, und eine menschliche Eingabe muss
    /// anschliessend alle vom Demo-Start ueberschriebenen Menuewerte restaurieren.
    func testDemoLevelUpDoesNotPersistProgressAndAbortRestoresSelection() {
        let fixture = makeIsolatedScene()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suiteName) }
        fixture.defaults.set(3, forKey: HighScoreStore.maxLevelKey)

        // didMove hat vor dem Setzen bereits geladen; aus der isolierten Suite
        // noch einmal einlesen, damit In-Memory- und Persistenzstand beide 3 sind.
        let scene = fixture.scene
        scene.loadHighScores()
        scene.transitionTo(.startScreen)
        scene.setGameModeForTesting(.madMeteoroids)
        scene.selectedStartLevel = 3
        scene.autoFire = false
        scene.attractModeEnabled = true
        scene.externalStepDriving = true

        scene.startAutopilotDemoForTesting(persona: .ace, seed: 0xD3A0)
        scene.isSpawningEnabled = false
        scene.clearAllEntitiesForTesting()
        scene.setExtraLivesForTesting(99)
        scene.setLevelTimeRemainingForTesting(0)
        for _ in 0..<430 { scene.advanceOneStep() } // 3,5-s-Levelblende bei 120 Hz abschliessen

        XCTAssertEqual(scene.currentLevel, 5, "Fixture muss einen echten Demo-Levelaufstieg erreichen")
        XCTAssertEqual(scene.maxLevelReached, 3, "Demo darf den In-Memory-Fortschritt nicht erhoehen")
        XCTAssertEqual(fixture.defaults.integer(forKey: HighScoreStore.maxLevelKey), 3,
                       "Demo darf keinen Fortschritt in UserDefaults persistieren")

        scene.simulateKeyDown(keyCode: 53) // beliebige menschliche Eingabe bricht Attract ab
        XCTAssertEqual(scene.gameState, .startScreen)
        XCTAssertEqual(scene.selectedMode, .madMeteoroids)
        XCTAssertEqual(scene.selectedStartLevel, 3)
        XCTAssertFalse(scene.autoFire)
    }

}
