// Autopilot-/Demo-Modus-Tests: Personas überleben, kein Highscore-/Aufnahme-Eintrag im Demo-Lauf.
// Reiner Split aus der früheren GameCoreTests.swift — keine Logikänderung.

import XCTest
import SpriteKit
@testable import GameCore

@MainActor
final class AutopilotTests: GameCoreTestCase {

    // MARK: - Autopilot / Demo-Modus

    /// Läuft ein Autopilot-Lauf, bis er endet (Game Over) oder das Schrittlimit erreicht ist.
    /// Rückgabe: die überlebte Zeit in Sekunden (Schritte ÷ 120).
    private func runAutopilot(_ persona: AutopilotPersona, seed: UInt64, maxSteps: Int = 78000) -> Double {
        let scene = GameScene(size: CGSize(width: 1024, height: 768))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        view.presentScene(scene)
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
        let scene = GameScene(size: CGSize(width: 1024, height: 768))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        view.presentScene(scene)
        scene.externalStepDriving = true
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
    }

}
