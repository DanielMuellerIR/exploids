# Plan: Deterministisches Replay-System

Stand: 2026-06-25. **Status: Phase 1 + 2 + 3 vollständig abgeschlossen** (inkl. 3.1 Fixed-Timestep,
umgesetzt in v0.12.0; Spielgefühl über Playtest abzunehmen). Dieses Dokument ist die
Arbeitsgrundlage; jeder Unterschritt hat ein prüfbares Erfolgskriterium.

**Umsetzungsnotiz Phase 2 (erledigt):** `Replay` (Codable, kompakte Binär-Plist) + `ReplayRecorder`
+ `ReplayPlayer`. Jeder Lauf wird aufgezeichnet (Seed + Eingaben + Float-`dt`-Folge), bei Game Over
finalisiert und an den Highscore gehängt. Wiedergabe per `startReplay()`: `update()` verwirft den
Echtzeit-`dt`, wendet den aufgezeichneten an und speist die Eingaben ein – **bit-exakt** (dt wird
auf Float-Präzision quantisiert, damit die Float-Aufnahme exakt reproduziert). In-App: Highscore per
Zifferntaste 1–5 ansehen, „▶ REPLAY"-Overlay, ESC verlässt.

**Umsetzungsnotiz Phase 3 (3.2–3.5 erledigt):** Headless-GIF-Renderer (`ReplayRenderer` im
ExploidsMac-Target): `SKRenderer` + Offscreen-Metal-Textur, `update(atTime:)` treibt Replay-Frame
+ SKActions, `render(...)` zeichnet, ImageIO kodiert ein animiertes GIF. HUD ausblendbar
(`setHUDHiddenForRender`). CLI: `exploids --render-replay <file> --out <gif> [--scale S --fps N
--stride N --show-hud]`, `--export-replay <i> --out <file>`, `--render-demo --out <gif>` (skriptet
intern einen Lauf – Pipeline-Selbsttest). Verifiziert: erzeugt gültige GIFs mit echtem Spielinhalt
(Schiff/Asteroiden/Laser/Effekte), cursorfrei.

**Umsetzungsnotiz 3.1 (erledigt, v0.12.0):** Fixed-Timestep. `update(_:)` summiert die reale
Frame-Zeit in einem Akkumulator und treibt die Simulation in festen Schritten (`GameScene.simStep`
= 1/120 s) über `advanceOneStep()` → `stepSimulation(deltaTime:)`. Damit hängt ein Lauf nur noch an
(Seed + Eingaben): das `Replay` speichert statt der dt-Folge nur noch `frameCount` (Format v3, alte
v2-Aufnahmen werden abgelehnt). Headless Renderer und Tests treiben die Sim direkt per
`advanceOneStep()` (kein Echtzeit-Akkumulator, `externalStepDriving`). Den Catch-up nach einem
Hänger deckeln die App-Hosts über `maxFrameDelta` (0.25 s); Tests lassen ihn aus (Default
`.infinity`), um per großem `update(_:)`-Sprung deterministisch vorzuspulen. 93 Tests grün;
**Spielgefühl über Playtest abzunehmen.**

**Umsetzungsnotiz Phase 1 (erledigt):** PRNG `GameRandom` (SplitMix64) eingeführt; alle
gameplay-relevanten `.random`-Aufrufe ziehen aus einem pro Lauf geseedeten `rng` (Entities über
`init(..., using rng:)` + Convenience-Init für Tests). Zeit vereinheitlicht auf akkumulierte
`gameTime` (keine `systemUptime`/rohe `currentTime`-Lesestellen im Gameplay-Pfad mehr).
Determinismus-Probe in `GameCoreTests` (gleicher Seed ⇒ bit-identisch; anderer Seed ⇒ Divergenz;
inkl. Mad-Modus). **Bewusst NICHT geseedet** (separater Stream, ohne Sim-Einfluss): Ship-Flacker,
SoundManager-Jitter, Kamera-Shake, Sternenfeld. Testaufruf braucht Xcode-SDK:
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift test`.

## Ziel

Die Spielsimulation **bit-exakt reproduzierbar** machen, sodass:
1. Ein Spieldurchlauf als **kleine Aufnahme** (Seed + Tastenereignisse, wenige KB) gespeichert
   werden kann.
2. Läufe, die in der **Highscore** landen, **in der App erneut abgespielt** werden können – exakt
   so, wie sie gespielt wurden.
3. Aus einem Highscore-Lauf ein **sauberes Promo-GIF** erzeugt werden kann (headless, cursorfrei,
   reproduzierbar).

**Harte Anforderung:** „exakt genauso wie passiert". Das ist **alles-oder-nichts** – schon eine
einzige nicht reproduzierte Zufalls- oder Zeitquelle lässt den Lauf nach wenigen Frames vollständig
auseinanderdriften. Deshalb steckt der Aufwand **nicht im Aufnehmen** (das ist trivial und winzig),
sondern darin, die Simulation vollständig **deterministisch** zu machen.

## Ausgangslage (im Code gemessen, 2026-06-24)

| Aspekt | Status | Konsequenz |
|---|---|---|
| **65 Zufallsaufrufe** (`.random`) mit globalem System-RNG | nicht reproduzierbar | müssen über einen geseedeten PRNG laufen |
| Verteilung: GameScene 40, Asteroid 8, Ship 4, SoundManager 4, PowerUp 3, UFO 3, SpaceCat 2, FloatingHead 1 | | SoundManager 4 = reiner Audio-Jitter (vom Determinismus ausgenommen) |
| **Zeitbasis gemischt**: teils `ProcessInfo.systemUptime`, teils der SpriteKit-`currentTime` aus `update(_:)` | beide an Echtzeit/Frame-Timing gekoppelt | müssen auf eine akkumulierte **Spielzeit** umgestellt werden |
| **Variabler Zeitschritt** (`deltaTime = currentTime - lastUpdateTime`) | Physik hängt am Frame-Timing | dt mitaufzeichnen (Phase 2) **oder** Fixed-Timestep (Phase 3) |
| **Input bereits abstrahiert** (`simulateKeyDown/Up`, `handleKeyDown/Up`) | ✓ | Aufnahme ist trivial |
| Float-Determinismus | gleiche Binary + gleiche CPU-Architektur (Apple Silicon) = deterministisch | für In-App-Replay und lokales GIF kein Problem; cross-Architektur nicht garantiert |

## Architektur-Entscheidungen (vorab festgelegt)

- **PRNG:** ein kleiner, schneller, voll spezifizierter Generator (z. B. SplitMix64 oder
  xoshiro256\*\*), der Swifts `RandomNumberGenerator` implementiert. Damit funktioniert die
  vorhandene Schreibweise `Int.random(in: …, using: &rng)` unverändert weiter.
- **Eine Quelle der Wahrheit für Zeit:** eine akkumulierte `gameTime` (Summe der angewandten `dt`).
  *Sämtliche* Spiel-Logik liest Zeit nur noch aus `gameTime`, nie aus `systemUptime` oder dem rohen
  `currentTime`.
- **Replay-Format:** `version` (Logik-/Build-Tag) + `seed` + `startLevel` + `gameMode` +
  Tastenereignisse `[(frameIndex, keyCode, isDown)]`. In Phase 2 zusätzlich die `dt`-Folge; ab
  Phase 3 (Fixed-Timestep) entfällt die `dt`-Folge.
- **Versionsbindung:** Jede Aufnahme trägt das Logik-Versions-Tag. Beim Abspielen wird ein Mismatch
  erkannt und das Replay abgelehnt (Logikänderung macht alte Aufnahmen ungültig).
- **Audio bleibt außen vor:** Sound wird beim Replay aus Spielereignissen neu getriggert, nicht
  aufgezeichnet. Audio-Zufall (SoundManager) muss daher nicht geseedet werden.

---

## Phase 1 — Determinismus-Fundament

Macht die Simulation reproduzierbar **bei gegebenem Seed + Input + dt-Folge**. Eigenständig
wertvoll: macht **alle Tests deterministisch** und ist die Voraussetzung für Phase 2 und 3.

### 1.1 — Geseedeten PRNG `GameRandom` einführen
- **Datei:** neu `Sources/GameCore/GameRandom.swift`.
- **Vorgehen:** `struct GameRandom: RandomNumberGenerator` mit `init(seed: UInt64)` und `mutating
  func next() -> UInt64` (SplitMix64). Keine Abhängigkeit von globalem Zustand.
- **Erfolgskriterium:** Unit-Test — zwei Instanzen mit gleichem Seed liefern identische Sequenzen;
  unterschiedliche Seeds liefern unterschiedliche; `Int.random(in:using:)` damit reproduzierbar.

### 1.2 — Eine `GameRandom`-Instanz in GameScene verankern
- **Datei:** `Sources/GameCore/GameScene.swift`.
- **Vorgehen:** `private var rng: GameRandom` + `private(set) var currentSeed: UInt64`. Beim frischen
  Spielstart Seed festlegen: entweder neu würfeln (einmalig aus System-RNG) **oder** einen injizierten
  Seed übernehmen (für Replay). Einstiegspunkt erweitern, z. B. `startNewGame(seed: UInt64? = nil)`.
- **Erfolgskriterium:** `currentSeed` ist nach Spielstart gesetzt und auslesbar (Test-Helfer); ein
  injizierter Seed wird übernommen.

### 1.3 — Gameplay-`.random`-Aufrufe auf `rng` umstellen
Die 65 Aufrufe einzeln umziehen. **Entitäten erzeugen Zufall in ihren Initializern** – deren
`init`/Factory-Methoden müssen den Generator als `using rng: inout GameRandom` (bzw. als
`RandomNumberGenerator`) hereinbekommen. Pro Teilschritt nach der Umstellung die Test-Suite grün
halten.

- **1.3a** GameScene (40 Aufrufe): Asteroiden-Spawn (Position/Geschwindigkeit/Typ), UFO-Typ/-Seite,
  Power-up-Drops/-Typen, Boss-Timing, Katzen-Timing, Gravity-Well-Positionen, Wobble-Detonation usw.
- **1.3b** `Asteroid.swift` (8): Form-Perturbation, Split-Geschwindigkeiten.
- **1.3c** `UFO.swift` (3): Spawn-Y, Schlinger-Phase, Schuss-Winkelfehler.
- **1.3d** `PowerUp.swift` (3): Typauswahl u. a.
- **1.3e** `SpaceCat.swift` (2): `startOnLeft`, Ausweich-Seite beim Repositionieren.
- **1.3f** `FloatingHead.swift` (1): Lauer-Dauer.
- **1.3g** `Ship.swift` (4): voraussichtlich Explosions-/Partikel-Jitter → **klassifizieren**
  (siehe Tabelle unten): sichtbar → seeden (für exaktes GIF), rein kosmetisch-irrelevant ggf. später.
- **1.3h** `SoundManager.swift` (4): **nicht** seeden (reiner Audio-Jitter, vom Replay ausgenommen).
- **Erfolgskriterium je Teilschritt:** Test-Suite bleibt grün; die Determinismus-Probe aus 1.5
  deckt nach und nach mehr ab.

### 1.4 — Wall-Clock-Zeit durch Spielzeit ersetzen
- **Datei:** `GameScene.swift` (14 Zeit-Lesestellen).
- **Vorgehen:** `private var gameTime: TimeInterval = 0` einführen, am Anfang von `update(_:)` um den
  aktuellen `dt` erhöhen. **Alle** Stellen umstellen, die heute `ProcessInfo.processInfo.systemUptime`
  **oder** den rohen `currentTime` für Logik nutzen:
  Power-up-Ablaufzeiten (`beamEndTime`, `compressEndTime`, `rapidFireEndTime`, `tripleShotEndTime`,
  `rearLaserEndTime`, `invincibilityEndTime`), Spawn-Timer (`lastSpawnTime`, `lastUFOSpawnTime`,
  `lastGravityWellSpawnTime`), Boss-/Katzen-Timer (`nextBossTimeLevel10`, `nextCatTime`,
  `lastBeamHitTime`). Künftig durchweg gegen `gameTime` rechnen.
- **Erfolgskriterium:** Timer verhalten sich im normalen Spiel unverändert; ein Grep über den
  Gameplay-Pfad findet **keine** rohen Echtzeit-Lesestellen mehr; Determinismus-Probe (1.5) inkl.
  Power-up-Ablauf besteht.

### 1.5 — Determinismus-Regressionstest (Schlussstein)
- **Datei:** `Tests/GameCoreTests/GameCoreTests.swift`.
- **Vorgehen:** Zwei unabhängige `GameScene`-Instanzen mit **gleichem Seed** und **gleicher
  Input-/dt-Folge** über N Frames (z. B. 600) laufen lassen; danach einen **Snapshot/Hash** des
  relevanten Zustands vergleichen (Positionen, Geschwindigkeiten, Objektzahlen, Score, RNG-Zustand).
- **Erfolgskriterium:** Beide Läufe sind identisch. Gegenprobe: eine Zufallsquelle bewusst
  unseeded lassen → Test schlägt fehl (beweist, dass der Test „Zähne" hat).

**Phase-1-Ergebnis:** Simulation reproduzierbar bei (Seed, Input, dt-Folge). Tests deterministisch.
Noch kein Replay.

---

## Phase 2 — Aufnahme → Wiedergabe (gleiche Binary)

### 2.1 — Replay-Datenmodell definieren
- **Datei:** neu `Sources/GameCore/Replay.swift`.
- **Vorgehen:** `struct Replay: Codable` mit `version`, `seed`, `startLevel`, `gameMode`,
  `events: [InputEvent]` (`InputEvent = (frameIndex: UInt32, keyCode: UInt16, isDown: Bool)`) und –
  solange variabler Zeitschritt – `dtSequence: [Float]`. Kompakte (Binär-)Kodierung.
- **Erfolgskriterium:** Round-Trip-Test (encode → decode == Original); Größenabschätzung
  dokumentiert (~1–3 KB Inputs, ~15 KB inkl. dt-Folge bei 2 Min).

### 2.2 — Eingaben während des Spiels aufzeichnen
- **Datei:** neu `ReplayRecorder` (eigene Datei) + Hooks in `GameScene`.
- **Vorgehen:** Frame-Zähler in `update(_:)`. Bei Spielstart Seed/Level/Modus festhalten; in
  `handleKeyDown/Up` jedes Ereignis mit aktuellem `frameIndex` anhängen; pro Frame den `dt` anhängen.
- **Erfolgskriterium:** Eine skriptgesteuerte Sitzung erzeugt eine Ereignisliste, die exakt den
  gesendeten Eingaben entspricht.

### 2.3 — Replay-Abspieler
- **Datei:** neu `ReplayPlayer`.
- **Vorgehen:** Frische `GameScene` mit Seed/Level/Modus initialisieren; je Frame den aufgezeichneten
  `dt` und die für diesen Frame fälligen Eingaben einspeisen, dann `update()` aufrufen. Live-Eingaben
  während des Replays sperren.
- **Erfolgskriterium:** Aufnahme → Wiedergabe → Endzustands-Hash identisch zum Original (Erweiterung
  der Probe aus 1.5 um Record+Replay).

### 2.4 — Replays mit Highscores persistieren
- **Dateien:** Highscore-Modell + Persistenz in `GameScene.swift`.
- **Vorgehen:** `HighScore` optional um ein `Replay` (bzw. eine Referenz) erweitern. Endet ein Lauf
  als Highscore, das aufgezeichnete Replay anhängen. Versions-Tag mitspeichern, bei Mismatch das
  Abspielen sperren.
- **Erfolgskriterium:** Ein Highscore-Lauf speichert sein Replay; nach Neuladen spielt es identisch.

### 2.5 — In-App-Replay-UI
- **Dateien:** Highscore-Screen + Spielansicht in `GameScene.swift`.
- **Vorgehen:** Auf dem Highscore-Screen einen Eintrag wählen → „Replay ansehen" → `ReplayPlayer`
  treibt die Spielansicht (rein lesend, „REPLAY"-Overlay, mitlaufender Score). Steuerung: Replay
  verlassen, optional Pause.
- **Erfolgskriterium:** Manuell sichtbar korrekt **und** ein headless-Test, dass das Replay die
  Szene auf den aufgezeichneten Score treibt.

**Phase-2-Ergebnis:** Highscore-Läufe in der App exakt nachspielbar (gleiche Binary).

---

## Phase 3 — Fixed-Timestep + headless GIF

> **ERLEDIGT (2026-06-25, v0.12.0).** 3.1 ist umgesetzt: Fixed-Timestep über einen Akkumulator;
> die Aufnahmen tragen keine `dt`-Folge mehr (nur `frameCount`, Format v3). Auf 120 Hz im Idealfall
> ein Sim-Schritt pro Bild wie zuvor; das Spielgefühl ist final über einen Playtest abzunehmen.

### 3.1 — Update-Schleife auf Fixed-Timestep umstellen
- **Datei:** `GameScene.swift`.
- **Vorgehen:** Variable-`dt`-Integration durch einen **Akkumulator mit festem Schritt** ersetzen
  (z. B. `simStep = 1/120 s`): realen `dt` aufsummieren, Simulation in festen Schritten voranbringen,
  Darstellung interpolieren. Danach braucht das Replay **keine `dt`-Folge** mehr (nur Seed + Inputs).
- **Risiko (höchstes im Projekt):** Das **Spielgefühl muss identisch bleiben**. Sorgfältiges Tuning;
  die Determinismus-Probe als Wächter.
- **Erfolgskriterium:** Spielgefühl unverändert (manuell, Playtest ausstehend); Determinismus-Probe
  besteht **nur** mit Seed + Inputs (ohne dt) — erfüllt; alle 93 Tests grün. **✓ (v0.12.0)**

### 3.2 — Simulation von der Darstellung entkoppeln (headless-fähig)
- **Datei:** `GameScene.swift`.
- **Vorgehen:** Ein `stepSimulation(inputs:)`-Einstieg, der ohne lebende `SKView`/Display-Link
  voranschreitet.
- **Erfolgskriterium:** Ein headless-Test spielt ein komplettes Replay ohne `SKView` durch.

### 3.3 — Offscreen-Frame-Aufnahme
- **Dateien:** neues Render-Tool / Erweiterung im Mac-Target.
- **Vorgehen:** Szene je Sim-Frame (oder jeden N-ten) in einen Offscreen-Puffer rendern
  (`SKView`/`SKRenderer` → `CGImage`).
- **Erfolgskriterium:** Aus einem Replay deterministisch eine PNG-Frame-Folge erzeugen.

### 3.4 — GIF-Assemblierung + CLI
- **Datei:** neues Tool unter `tools/` oder ein Mac-Target-Flag.
- **Vorgehen:** Frames per ImageIO zu animiertem GIF kodieren. **Headless-CLI** (passt zur
  Agent-/Headless-Linie des Projekts), z. B. `exploids --render-replay <datei> --out <gif>` mit
  Optionen für Tempo, Ausschnitt/Crop und **Ausblenden des Debug-Overlays** (nodes/fps).
- **Erfolgskriterium:** Aus einem gespeicherten Highscore-Replay headless ein sauberes GIF erzeugen,
  reproduzierbar.

### 3.5 — Feinschliff Promo-GIF
- **Vorgehen:** HUD/Debug-Overlay für den Render ausblendbar; guten Ausschnitt/Länge wählen; besten
  Highscore-Lauf aussuchen.
- **Erfolgskriterium:** Ein vorzeigbares, cursorfreies Promo-GIF aus einem echten Highscore-Lauf.

**Phase-3-Ergebnis:** Replays brauchen nur Seed + Inputs; Highscore-Läufe headless als GIF
renderbar.

---

## Nachtrag 2026-06-24: zwei real aufgetretene Grenzen (beim ersten echten Lauf entdeckt)

Beim Versuch, einen echten ~11-Minuten-Highscore-Lauf als GIF zu rendern, kamen zwei Dinge ans
Licht, die die kurzen Unit-Tests nicht abdeckten:

1. **Auto-Feuer war nicht Teil der Aufnahme (Bug, behoben in v0.11.1).** `autoFire` ist eine
   Einstellung, die das Schiff in `update()` ohne Tastendruck feuern lässt — also Sim-relevant —,
   wurde aber nicht im `Replay` gespeichert. Ein mit Auto-Feuer gespielter Lauf ließ sich dadurch
   nicht reproduzieren (das Replay-Schiff feuerte kaum und starb früh). Fix: `autoFire` ins Format
   aufgenommen (v2) und beim `startReplay` wiederhergestellt; Regressionstest ergänzt. **Lehre:**
   Jede Einstellung, die die Simulation beeinflusst, MUSS in die Aufnahme — ein erneuter Audit der
   Settings (aktuell: nur `autoFire` ist sim-relevant; Musik/SFX-Stil sind reine Audio-Optionen)
   ist Pflicht, bevor man sich auf Replays verlässt.
2. **Float-Determinismus ist BINARY-spezifisch, nicht nur architektur-spezifisch.** Ein Lauf, der
   von Binary A aufgezeichnet wurde, reproduziert sich auf einem NEU gebauten Binary B nicht
   zuverlässig — winzige Float-Unterschiede schaukeln sich über zehntausende Frames auf, bis das
   Schiff anders stirbt. In-App-Replay und GIF-Render aus DEMSELBEN installierten Build sind
   zuverlässig; ein Replay über einen Rebuild hinweg ist es nicht. Das Versions-Tag deckt nur
   Logik-Änderungen ab, NICHT die Binary-Identität. (Konkret nicht mehr rekonstruierbar: der erste
   echte v0.11.0-Lauf, da pre-autoFire-Fix UND vom inzwischen ersetzten Build aufgezeichnet.)

## Querschnitt: Risiken & Caveats

- **Float-Determinismus** gilt nur für dieselbe Binary auf derselber CPU-Architektur (Apple Silicon).
  Für In-App-Replay und lokales GIF kein Problem; ein über Macs/Architekturen geteiltes Replay ist
  nicht garantiert bit-gleich.
- **SKAction/visuelle Effekte** dürfen die **Spiel-Logik nicht beeinflussen** (Effekte werden aus
  Spielereignissen getrieben, nicht umgekehrt). Heute überwiegend erfüllt – bei der Umstellung
  bewusst halten.
- **Versionsbindung:** Replays sind an das Logik-Versions-Tag gebunden; Mismatch ablehnen.
- **Audio** bleibt außerhalb des Determinismus (Re-Trigger aus Ereignissen).
- **Größter Brocken** ist das Durchreichen des `rng` durch die 65 Stellen (Phase 1.3); der Rest ist
  überschaubar.

## Reihenfolge, Aufwand, Einstieg

- **Reihenfolge zwingend:** Phase 1 → 2 → 3. Phase 1 ist aber **eigenständig** schon ein Gewinn
  (deterministische Tests).
- **Grobschätzung:** Phase 1 ≈ 1,5 Tage · Phase 2 ≈ 1 Tag · Phase 3 ≈ 1,5–2 Tage.
- **Einstieg nächste Session:** mit **1.1** (PRNG) und **1.2** (in GameScene verankern) beginnen,
  dann **1.5** (Determinismus-Probe) früh aufsetzen, damit 1.3/1.4 dagegen abgesichert umgezogen
  werden können.

## RNG-Klassifikation (bei der Umsetzung auszufüllen)

Pro Fundstelle entscheiden: **G** = gameplay-relevant (muss geseedet werden) · **V** = nur sichtbar
(für exaktes GIF seeden) · **A** = nur Audio (ausgenommen).

| Datei | Anzahl | Erst-Einschätzung |
|---|---|---|
| GameScene.swift | 40 | überwiegend **G** (Spawns, Drops, Timing) |
| Asteroid.swift | 8 | **G** (Form/Split beeinflussen Kollision/Optik) |
| Ship.swift | 4 | vermutlich **V** (Explosions-/Partikel-Jitter) |
| SoundManager.swift | 4 | **A** (ausgenommen) |
| PowerUp.swift | 3 | **G** (Typauswahl) |
| UFO.swift | 3 | **G** (Spawn/Schuss) |
| SpaceCat.swift | 2 | **G** (Seite/Ausweichen) |
| FloatingHead.swift | 1 | **G** (Lauer-Dauer) |
