// Smoke-Tests für die Audio-Schicht (SoundManager, MusicPlayer). Bewusst konservativ:
// sie starten NIE die echte AVAudioEngine (kein Audio-Hardware-Zugriff, CI-tauglich),
// sondern prüfen nur, dass die öffentliche API im gemuteten Zustand nicht abstürzt und
// die reinen Zustands-Schalter (Flags) korrekt sind. Deckt die zuvor komplett
// ungetestete SoundManager/MusicPlayer-Oberfläche mit Basis-Invarianten ab.

import XCTest
@testable import GameCore

@MainActor
final class AudioSmokeTests: GameCoreTestCase {

    // MARK: - SoundManager

    /// Der SoundManager muss schon stumm sein, BEVOR das Singleton zum ersten Mal
    /// angefasst wird — `init()` startet sonst die echte Audio-Engine, und `setUp()`
    /// der Basisklasse kommt dafür zu spät.
    ///
    /// Die Prüfung hängt bewusst nicht an `isMuted`: Das setzt `setUp()` ohnehin auf
    /// `true` und würde eine kaputte Erkennung überdecken. Geprüft wird die Erkennung
    /// selbst, die den Startwert von `isMuted` liefert.
    func testCurrentProcessIsDetectedAsSilentTestRun() {
        XCTAssertTrue(SoundManager.startsMutedForCurrentProcess,
                      "XCTest wird nicht erkannt — der SoundManager würde beim ersten "
                      + "Singleton-Zugriff die echte Audio-Engine starten.")
    }

    /// Alle SFX-Auslöser dürfen bei gemutetem Manager gefahrlos aufgerufen werden
    /// (guard !isMuted → früher return, kein Engine-Start). Basisklasse mutet in setUp.
    func testMutedSoundManagerPlayMethodsDoNotCrash() {
        let sm = SoundManager.shared
        XCTAssertTrue(sm.isMuted, "Basisklasse sollte den SoundManager im setUp muten.")

        sm.playLaser()
        sm.playExplosion()
        sm.playPowerUp()
        sm.playBomb()
        sm.playUfoSound()
        sm.playLevelComplete()
        sm.playImplosion()
        sm.playBossHead()
        sm.stopBossHead()
        sm.stopAllHeadSounds()
        // Kommt bis hierher ohne Absturz/Engine-Start durch → bestanden.
    }

    /// Die Dauer-Zustands-Schalter (Schub-Hum, Kopf-Stimme) dürfen im gemuteten Zustand in
    /// beliebiger Reihenfolge an/aus geschaltet werden, ohne die Engine zu starten.
    func testMutedSoundManagerStateSettersDoNotCrash() {
        let sm = SoundManager.shared
        sm.setThrustActive(true)
        sm.setThrustActive(false)
        sm.setHeadVoice(active: true, openness: 0.5)
        sm.setHeadVoice(active: false, openness: 0.0)
    }

    /// Der Sample-Modus ist ein reiner Laufzeit-Schalter und muss unabhängig vom Audio-Start
    /// zuverlässig gesetzt/gelesen werden können.
    func testSampledSFXFlagRoundTrips() {
        let sm = SoundManager.shared
        let original = sm.useSampledSFX
        sm.useSampledSFX = true
        XCTAssertTrue(sm.useSampledSFX)
        sm.useSampledSFX = false
        XCTAssertFalse(sm.useSampledSFX)
        sm.useSampledSFX = original
    }

    // MARK: - MusicPlayer

    /// Unter XCTest ist der MusicPlayer intern „suppressed" (spielt nichts), aber der
    /// `isEnabled`-Schalter muss die Logik trotzdem korrekt abbilden.
    func testMusicPlayerEnabledFlagRoundTrips() {
        let mp = MusicPlayer.shared
        let original = mp.isEnabled

        mp.setEnabled(false)
        XCTAssertFalse(mp.isEnabled)
        mp.setEnabled(true)
        XCTAssertTrue(mp.isEnabled)

        // toggle() invertiert den aktuellen Zustand.
        let before = mp.isEnabled
        mp.toggle()
        XCTAssertEqual(mp.isEnabled, !before)
        mp.toggle()
        XCTAssertEqual(mp.isEnabled, before)

        mp.setEnabled(original)
    }
}
