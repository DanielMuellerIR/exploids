# Exploids — dauerhafte Projektregeln

Stand: 2026-07-14. Nativer Asteroids-Klon mit C64-inspirierter Vektorgrafik für
macOS und einen frühen iOS-Port. Swift 6, SpriteKit, AVFoundation, SwiftPM.

## Zweck und Architektur

Das SwiftPM-Workspace trennt:

- `Sources/GameCore/`: plattformunabhängige Simulation, Entities, Kollision,
  Audio, deterministischer Zufall, Replay und Persistenz.
- `Sources/ExploidsMac/`: dünne AppKit-Shell und headless Replay-/GIF-Renderer.
- `ios/`: frühe Xcode/iOS-App, bindet `GameCore` ein; noch kein Release.
- `Tests/GameCoreTests/`: Tests nach Physik, Waffen, Bosse, Modi, Replay,
  Autopilot, Szenenzustand und Audio.
- `Tests/*.sh`: Shell-Integrationstests neben `swift test`, gesammelt und
  aufgerufen über `Tests/run-shell-tests.sh`.
- `install.sh`, `release.sh`: Einstiegspunkte für Installation und Release;
  `wrappers/sign-and-release.sh` ist der Unterbau von `release.sh`.
- `notarize-lib.sh`: gemeinsame Signier-/Notarisierungs-Helfer (gesourct).
- `VERSION`: einzige Quelle der Produktversion.

`GameCore` bleibt AppKit-frei und für macOS/iOS kompilierbar. Eingaben laufen über
plattformneutrale `handle`/`simulateKeyDown`-/`simulateKeyUp`-Pfade; Shells übersetzen
nur Tastatur, Touch oder GameController. Quit ist Callback, kein `NSApp` im Core.

## Simulations- und Replay-Verträge

Die Simulation ist deterministisch: `GameRandom` (SplitMix64) liefert jeden
gameplay-relevanten Zufall; Zeit läuft über den Fixed Timestep 1/120 s; Replay speichert
Seed, Eingaben, Schrittzahl und Szenengröße. Renderer und `--replay-verify` müssen die
gespeicherte Größe nutzen, weil Spawn-/Wrap-/Gegnerlogik davon abhängt.

- Nie gameplay-relevantes `SystemRandom`, Wandzeit oder frameabhängige Ziehungen
  einführen. Visuelle Zufälligkeit klar von Simulation trennen.
- Reihenfolge und Anzahl der RNG-Ziehungen sind Teil des Replayformats. Refactors von
  `stepSimulation`, Kollision oder Spawning können bitgenaue Replays brechen, selbst
  wenn das sichtbare Verhalten gleich wirkt.
- Der geplante Split der großen `stepSimulation` ist Hochrisiko: nur in einem eigenen
  Arbeitsblock und nach jedem kleinen Schnitt gegen ein gespeichertes Golden Replay
  mit `exploids --replay-verify <datei>` prüfen.
- Aufnahme und Wiedergabe verwenden denselben Inputpfad. Demo-/Autopilotläufe werden
  weder als Nutzerhighscore noch als Replayarchiv-Eintrag gespeichert.
- Replaydateien sind klein, aber lokale Nutzerdaten unter Application Support. Nie
  automatisch committen oder veröffentlichen.
- Änderungen am Replayformat brauchen Versionierung, Kompatibilitätsentscheidung,
  Encode/Decode-/Drift-Tests und klare Ablehnung inkompatibler Altformate.

## Gameplay-Invarianten

- Zwei Modi bleiben getrennt: Ancient wrappt am festen Feld; Mad rotiert Positionen
  und Geschwindigkeiten im flachen Weltkoordinatensystem. Kein rotierender Parent, der
  die bestehende World-Space-Kollision unbemerkt ändert.
- Level sind zeitbasiert. Autopilot-Balancing darf nicht nur „alle Gegner töten“ als
  Fitness optimieren; Überlebenszeit und mehrere Seeds messen.
- Entity-Arrays und SpriteKit-Szenengraph müssen konsistent bleiben. Spawns während
  einer Collection-Iteration nicht durch anschließendes Snapshot-Überschreiben
  verlieren. Die vorhandene Tracking-Invariante in Tests erhalten.
- Fixed-Timestep nicht aufgrund eines einzelnen subjektiven Rucklerberichts ändern.
  Erst reproduzieren und messen; 120→240 ist eine Simulationsänderung mit Replaygate.
- Der mögliche `isInvincible`-Doppelschaden ist ein offener Befund: Test mit zwei
  Kollisionsarten im selben Frame erstellen, dann nur bei Beleg reparieren.
- Beam-/Waffenwirkung gegen UFO, Katze und Boss ist Matrixverhalten; Änderungen immer
  über Waffen×Gegner-Regressionstests absichern.

## Audio und iOS-Debuggerfalle

SFX werden prozedural in Echtzeit berechnet; optional gibt es aufgenommene Samples.
Auf iOS laufen Musik und SFX über denselben `AVAudioEngine`-Renderpfad, Musik als
`AVAudioPlayerNode`; bei `AVAudioEngineConfigurationChange` wird die Engine neu
gestartet. macOS verwendet weiterhin `AVAudioPlayer` für Musik.

Auf einem echten iPhone kann Start per Xcode `Cmd+R` völlig verzerrtes Audio erzeugen,
weil der angehängte LLDB-Debugger den Echtzeit-Audiothread stört. Icon-Start und
Release sind sauber; Simulator reproduziert es nicht. Das ist keine App-Korrektur:
zum Gegencheck im Scheme „Debug executable“ deaktivieren. Nicht erneut Formate oder
Enginecode wegen dieses Debuggerartefakts umbauen.

## Assets, Lizenzen und Veröffentlichung

- Die beiden MP3-Hintergrundtracks unter `Sources/GameCore/Music/` stammen aus einem
  Free-Plan und sind ausschließlich nichtkommerziell lizenziert. Solange sie gebündelt
  sind: keine bezahlte, monetarisierte oder rechtlich unklare App-Store-Veröffentlichung.
- Vor jeder App-Store-/kommerziellen Verteilung beide Tracks durch selbst erzeugte,
  CC0- oder kommerziell sauber lizenzierte Musik ersetzen. Eine spätere bezahlte
  Lizenz ändert die Rechte alter Generierungen nicht automatisch.
- Projektlizenz muss den Musik-Carve-out ausdrücklich nennen; Code-Lizenz nicht auf
  diese Dateien ausdehnen.
- Press Start 2P unter SIL OFL 1.1; `Fonts/OFL.txt` und Attribution erhalten.
- Boss-Texturen und optionale Samples müssen in der Assetübersicht mit Herkunft und
  Lizenz geführt werden. Neue Medien ohne belegte Lizenz nicht committen.
- Öffentliche Dokumente/Artefakte auf private Pfade, interne Hosts, Kontakte und
  Assistentenformulierungen prüfen.

Drei Einstiegspunkte: `build-app.sh` baut nur, `./install.sh` installiert
notarisiert nach `/Applications`, `./release.sh` packt das DMG (installiert nie).
Beide heften zuerst der App selbst ein Ticket an. Profilname aus `NOTARY_PROFILE`
oder `git config exploids.notaryProfile`.

Releases sind absichtlich manuell. `./release.sh --publish`
erstellt Build, Signatur, DMG, Notarisierung, Tag und GitHub-Release und läuft nur nach
ausdrücklichem konkreten Auftrag. Kein Auto-Release bei normalen Pushes.

## Bauen und testen

```bash
swift build
swift test
bash Tests/run-shell-tests.sh
bash build-app.sh
```

`swift test` deckt nur den in `Package.swift` registrierten Target
`Tests/GameCoreTests` ab. Alles daneben — CLI-Versionspfad, Austauschlogik von
`install.sh`, Aufräumen in `notarize-lib.sh`, die beiden Fleet-Regeln in
`Tests/fleet-rules.sh`, die Release-Vorbedingungen in `Tests/release-guards.sh` —
läuft über `Tests/run-shell-tests.sh`; dort gehört jeder neue Shell-Test
eingetragen, sonst hat er keinen Aufrufer. Die Shell-Tests arbeiten mit Attrappen
in Temp-Verzeichnissen: kein Signieren, kein Notarisieren, kein Schreiben nach
`/Applications`.

Wer in einem Test eine Zeichenkette in einer Binärdatei sucht, nimmt `strings -`
und **nie** `strings -a`: Auf macOS heißt `-a` „alle Sektionen der Objektdatei"
und lässt die Symboltabelle in `__LINKEDIT` aus — genau dort standen die
Heimatpfade. Am ungestrippten Release-Binary gemessen (2026-08-05): `-a` fand 0
Treffer, `-` fand 64. Merksatz: `grep` braucht `-a` für Binärdateien, `strings`
darf es nicht haben. Beide Proben prüfen deshalb zuerst am Kontrollfund
`dyld_stub_binder`, ob sie überhaupt sehen.

Ressourcen aus `Sources/GameCore` (Art, Fonts, Music, SFX) immer über
`GameCoreResources.bundle` laden, nie über `Bundle.module`: SwiftPM baut in den
erzeugten `Bundle.module`-Zugriff den absoluten `.build`-Pfad des Build-Rechners
ein, der damit in jedem ausgelieferten Binary steht. `Tests/fleet-rules.sh` hält
das fest.

iOS-Änderungen zusätzlich mit dem Xcode-Projekt/Simulator und auf Gerät prüfen; Audio
auf Gerät ohne Debugger gegenhören. Release-/Notarisierungsbefehle sind kein normaler
Testschritt. Testanzahlen nicht in dauerhafte Doku schreiben.

Änderungsspezifische Gates:

- Simulation/Kollision/RNG: relevante Unit-Tests plus Golden-Replay-Verifikation;
  mehrere Seeds und Szenengrößen.
- Replay: Encode/Decode, Inputfolge, Schrittzahl, Szenengröße und headless Render;
  neue Binary reproduziert Goldenlauf bitgenau oder Formatänderung wird explizit.
- Entities/Power-ups/Bosse: Array↔Szenengraph-Invariante und Waffenmatrix.
- Audio: gemuteter Smoke-Test ohne echte Engine; macOS echter Start; iOS Simulator
  und Gerät ohne LLDB bei Renderpfadänderungen.
- iOS-Eingabe: Touch-hold/release, gleichzeitige Aktionen, App-Lifecycle und optional
  GameController über denselben Core-Inputpfad.
- UI/Gameplaygefühl: automatisierte Tests ersetzen nicht 120-Hz-/Geräte-Playtest,
  aber subjektiver Test ersetzt keine deterministische Regression.
- Assets: Lizenzbeleg, Bundle-Scan und kommerzielle Zulässigkeit vor Distribution.
- Build-/Install-/Release-Skripte: `bash -n` plus `Tests/run-shell-tests.sh`. Ein
  echter Release- oder Notarisierungslauf ist kein Testschritt; Fehlerpfade werden
  mit Attrappen in Temp-Verzeichnissen nachgestellt.

## Code- und Git-Regeln

- Swift-6-Strict-Concurrency erhalten. Echtzeit-Audiothread nicht blockieren,
  allozieren oder mit UI-/Dateiarbeit belasten.
- Identifier Englisch, Doku/Kommentare Deutsch; komplexe Simulation/RNG/Audio-
  Invarianten anfängerfreundlich erklären. Kommentare bei Refactor/Rename erhalten.
- Kleine, testbare Schnitte. Hochrisiko-`stepSimulation` nicht nebenbei refactoren.
- Nur konkrete Todo-Pfade stagen; fremdes WIP, Replays, Builds und lokale Medien
  unangetastet. Kein `git add .`, `git add -A`, Reset oder Clean.
- Nach verifizierter Verhaltensänderung `VERSION` passend erhöhen, committen und nur zu
  den kanonischen privaten Fleet-Remote pushen. Reine AGENTS-/Doku-Reorganisation braucht keinen Produktversions-
  Bump. GitHub/`origin`, Tag, Notarisierung und Release nur ausdrücklich.

## Aktiver Backlog

Kanonisch in `backlog.md`: `isInvincible`-Befund testgetrieben klären; Hochrisiko-
Simulationsextraktion nur mit Golden Replay; iOS-Steuergefühl/Assets/Releasefähigkeit;
Musik vor App Store ersetzen; Balance/Fixed-Timestep beobachten; Promo-GIF auswählen;
Scroll-Modus später. Veraltete Versions-/Publish-Todos und erledigte Featurechronik
gehören in Changelog/Releases, nicht hierher.

## Progressive Details und Scope

- Replayplan und Format: [`docs/replay-system-plan.md`](docs/replay-system-plan.md).
- Voice-Sample-Workflow: [`turrican-like-powerup-tts.md`](turrican-like-powerup-tts.md).
- Release: Wrapper und öffentliche README.
- Implementierte Features/Buggeschichte: Changelog und Git-Historie.

`.agents/AGENTS.md` liegt in einem gitignorierten lokalen Tool-Verzeichnis und ist
nicht Teil des Repos: lokale/nicht autoritative Sonderregel, weder in Root-Regeln
übernehmen noch veröffentlichen. Dasselbe gilt für ignorierte `.claude`-Konfiguration.

Die frühere Status-, Feature- und Testchronik liegt unverändert unter
`docs/archive/agent-context-legacy-2026-07-14.md`; sie ist Referenz, keine aktive
Anweisung.

## Verzeichnisstruktur

- [`README.md`](README.md) / [`README.de.md`](README.de.md): Nutzer- und Projektüberblick.
- `Package.swift`: Targets, Plattformen und Abhängigkeiten.
- [`CHANGELOG.md`](CHANGELOG.md): veröffentlichte Änderungen.
- `build-app.sh`: App-Build.
- [`backlog.md`](backlog.md): verifizierte offene Arbeit.
- [`docs/replay-system-plan.md`](docs/replay-system-plan.md): Replayvertrag und Format.
- [`turrican-like-powerup-tts.md`](turrican-like-powerup-tts.md): Voice-Sample-Workflow.
- [`docs/archive/agent-context-legacy-2026-07-14.md`](docs/archive/agent-context-legacy-2026-07-14.md): frühere Chronik, nicht autoritativ.
