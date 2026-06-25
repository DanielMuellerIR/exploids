# Exploids: Native macOS Retro-HighRes Asteroids

Exploids is a native macOS Asteroids clone with a C-64 inspired vector aesthetic executed at modern high resolution and butter-smooth frame rates (supporting Apple Silicon and ProMotion 120Hz). Almost all graphics are procedural vector rendering — only the two bosses use traced vector-contour textures — and all sound effects are synthesized in real time (with an optional recorded-sample SFX mode); the bundled media assets are two chiptune background-music tracks, the two boss textures, and the optional recorded sound effects (see Asset Licensing).

## Tech Stack & Architecture

- **Language**: Swift 6 (strict concurrency compliant).
- **GUI & Windowing**: AppKit (`NSApplication`, `NSWindow`, `NSAppearance`).
- **Render Engine**: SpriteKit (`SKView`, `SKScene`, `SKShapeNode`). Coordinates are centered around `(0, 0)` with standard wrap-around physics boundaries.
- **Audio Engine**: AVFoundation (`AVAudioEngine`, `AVAudioSourceNode`). Procedural synth sounds calculated in real-time on the audio render thread. On **iOS** the background music is **not** played via a separate `AVAudioPlayer` but as an `AVAudioPlayerNode` on the *same* `AVAudioEngine` as the SFX (`SoundManager.makeMusicNode`), so there is a single render path; `SoundManager` also restarts the engine on `AVAudioEngineConfigurationChange` (e.g. plugging/unplugging headphones). On macOS the music keeps using `AVAudioPlayer` (no such issue there).
- **Build System**: Swift Package Manager (SPM) executable package.

---

## iOS Audio: distorted sound under the Xcode debugger (gotcha)

**Symptom:** On a physical iPhone, the background music (and SFX) sound **completely
distorted / unrecognizable** when the app is launched from Xcode with **CMD+R**. Quitting the
app and relaunching it by tapping its icon makes the sound perfectly clean.

**Cause:** The attached **LLDB debugger perturbs the real-time audio render thread** on device.
This is *not* an app bug — every Xcode `CMD+R` reinstalls *and* attaches the debugger, so it
always reproduces; an icon-launch runs without the debugger and is fine. **The shipped/Release
build is unaffected.** The iOS Simulator does **not** reproduce it (audio formats all line up at
48 kHz there).

**How to verify audio from Xcode without the artifact:** Edit Scheme → **Run** → **Info** tab →
uncheck **"Debug executable"**, then run. Audio is clean. Re-enable it for normal debugging.

Do **not** "fix" this in code (it cost a long debugging detour once): all playback formats are
already consistent, and `AVAudioEngineConfigurationChange` does *not* fire in this case.

---

## Asset Licensing

⚠️ **Background music is NON-COMMERCIAL ONLY.** The two chiptune tracks
(`Sources/GameCore/Music/asteroid-storm.mp3`, `neon-vectors.mp3`) were generated with
**musely.ai** on its **Free Plan**. Per https://musely.ai/terms-and-conditions the Free
Plan grants *"Personal, non-commercial use only. No attribution required."*

**Generation parameters (for reproducing / making more tracks in the same style):**
- Style tags: `boss music rush`, `fast`, `c-64`
- Description prompt: *"Manic pulse-wave SID lead, fast broken-chord arpeggios, funky
  syncopated square bass, noise-channel hats and snare, bright minor-key melody, cosmic
  shoot-em-up energy, asteroid-field intensity"*

Implication: the game **must not be distributed commercially** (no paid sales, no
monetized App Store release) while it ships this music. Before any commercial use, replace
the tracks (own/CC0/commercially-licensed music) or obtain a paid musely plan with a
commercial license. All other audio is procedurally synthesized (no third-party rights).

**Heading font:** `Sources/GameCore/Fonts/PressStart2P-Regular.ttf` (Press Start 2P) is licensed
under the **SIL Open Font License 1.1** (`Fonts/OFL.txt`) — free for any use **including
commercial**, so unlike the music it imposes no commercial restriction. Registered at runtime via
`RetroFont` (CoreText), used for the EXPLOIDS / GAME OVER headings.

**Open-source note:** The project is intended to be released as open source. The music files
are **NOT covered by the project's code license** — they retain musely.ai's separate
non-commercial Free-Plan terms. When adding a `LICENSE` file, state this carve-out explicitly
(e.g. "code under <OSS license>; `Sources/GameCore/Music/*.mp3` under musely.ai Free Plan,
non-commercial"). This prevents a fork from assuming the OSS license grants commercial rights
to the music.

---

## File Structure

The package has three SwiftPM targets: **`GameCore`** (platform-independent engine
library, also compiles for iOS), **`ExploidsMac`** (the macOS AppKit executable shell,
product name `exploids`), and the **`GameCoreTests`** test target. A separate Xcode
project under `ios/` is the iOS app target and links `GameCore` as a package dependency.

```
exploids/
├── Package.swift              # SPM manifest: GameCore lib + ExploidsMac exe + GameCoreTests
├── VERSION                    # single source of truth for the version string
├── build-app.sh               # builds the double-clickable Exploids.app (macOS)
├── wrappers/
│   └── sign-and-release.sh     # sign + notarize + DMG (+ optional GitHub release)
├── assets/
│   └── generate-dmg-background.swift  # renders the DMG install-window background
├── Sources/GameCore/          # platform-independent engine (SpriteKit/AVFoundation)
│   ├── GameScene.swift        # key inputs, game loop, modes, spawning, collision wiring
│   ├── Ship.swift             # player ship (outline rendering, physics, friction, wrap)
│   ├── Asteroid.swift         # asteroids (procedural shape, splitting, screen-entry)
│   ├── Laser.swift            # projectiles incl. .catEye twin-laser (velocity, lifetime, wrap)
│   ├── PowerUp.swift          # the nine power-up types and their vector glyphs
│   ├── GravityWell.swift      # singularities that pull objects
│   ├── UFO.swift              # enemy saucers and their shots
│   ├── FloatingHead.swift     # boss "Der Götze" (spawner with state machine + evade AI)
│   ├── SpaceCat.swift         # space-cat miniboss (stalk/cover/predictive twin-laser)
│   ├── ArtTexture.swift       # loads traced boss PNG contours from Art/ as textures
│   ├── Collision.swift        # world-space collision helpers
│   ├── GameRandom.swift       # seeded PRNG (SplitMix64) — deterministic gameplay RNG
│   ├── Replay.swift           # replay model (Codable, compact binary plist)
│   ├── ReplayRecorder.swift   # records seed + inputs + step count per run (fixed-timestep)
│   ├── ReplayPlayer.swift     # plays a recording back bit-exactly into a GameScene
│   ├── SoundManager.swift     # real-time procedural SFX + optional recorded-sample mode
│   ├── MusicPlayer.swift      # chiptune background music (M toggle)
│   ├── AudioSession.swift     # shared AVAudioSession configuration (iOS)
│   ├── RetroFont.swift        # registers Press Start 2P (CoreText) for headings
│   ├── Fonts/                 # PressStart2P-Regular.ttf + OFL.txt
│   ├── Art/                   # traced boss textures: space_cat.png, zardoz_head.png
│   ├── Music/                 # asteroid-storm.mp3, neon-vectors.mp3
│   └── SFX/                   # optional recorded sound effects (.m4a incl. bosshead_0)
├── Sources/ExploidsMac/       # macOS AppKit shell (executable, product "exploids")
│   ├── Main.swift             # app entrypoint, lifecycle, CLI flags (replay export/render)
│   ├── GameWindow.swift       # configures the Cocoa window and SKView
│   └── ReplayRenderer.swift   # headless GIF rendering (SKRenderer + Metal + ImageIO)
├── ios/                       # iOS app target (Xcode project, links GameCore) — WIP
│   ├── project.yml            # XcodeGen spec
│   └── Exploids/              # AppDelegate, GameViewController (SKView), TouchControlsView
└── Tests/
    └── GameCoreTests/
        └── GameCoreTests.swift # 93 unit tests (physics, wrap, lasers, power-ups, modes,
                                #   bosses, weapon×enemy matrix, replay determinism)
```

**Releases are on-demand only — intentionally no auto-release CI.** A signed,
notarized DMG plus the matching GitHub release is produced by running
`bash wrappers/sign-and-release.sh --publish` (build → codesign → DMG → notarize →
staple → tag `vX.Y.Z` → upload to the release page). This is run manually when a
release is wanted; it is a deliberate decision *not* to trigger releases on every
push (notarization takes minutes and the VERSION-derived tag would collide).

---

## Current Status: v0.12.0

Shipped feature set (signed + notarized macOS release; the iOS target is an early WIP):
two game modes, nine power-ups, gravity wells, enemy UFO saucers, two bosses (the
"Der Götze" head boss and the space-cat minibosses), a charge shot and a sweeping laser
beam, imploding/wobbling special asteroids, a pixel-font HUD with an in-game glossary,
local high-score entry, a recorded-sample SFX mode (alongside the procedural synth), and a
**deterministic replay system** (re-watch high-score runs in-app, render promo GIFs
headlessly — see its section below). 93 unit tests, all green.

Two selectable game modes (start screen: ▲/▼ to switch, ◀/▶ for level, Space to start):
- **Ancient Asteroids**: the classic mode — fixed playfield, objects wrap around the screen edges. Unchanged.
- **Mad Meteoroids**: the whole playfield (asteroids, gravity wells, power-ups, starfield) rotates continuously around the screen center while the player ship stays exempt (Crazy-Comets style). Rotation speed scales with level (~6°/s at L1 up to ~30°/s from L10), with scheduled direction changes (L1–3 constant, then 2-2-2-3-3-4 changes per level, ~every 10s from L10) and occasional "record-scratch" jolts at high levels. UFOs and their shots stay screen-fixed in this first version. The field uses circular wrapping (objects leaving the field radius re-enter on the opposite side) so rotation stays coherent. Implementation note: gameplay objects are kept in one flat coordinate space — their positions/velocities are rotated per frame around the origin rather than parented to a rotating container — so the existing world-space collision system needs no changes. Tuning constants live in the `MadRotation` enum in `GameScene.swift`.

Also fixed: asteroids could spawn mid-screen because off-screen spawns were immediately folded back by edge-wrapping; they now reliably fly in from the edge (see `Asteroid.hasEnteredScreen`).


---

## Roadmap

### Open To-Dos (planned / in progress)
- **Turrican-style power-up voice samples**: Generate short, bitcrushed announcer samples ("Power Up!", "Extra Life!", "Game Over!") locally via TTS + post-processing. Full workflow (Qwen3-TTS / F5-TTS on MLX, then `pedalboard` bitcrush) is documented in `turrican-like-powerup-tts.md`. Would replace/augment the current procedural SFX for power-up pickups.
- **Scroll mode (3rd game mode)**: Ship stays centered, the world scrolls so the player can never reach the screen edge (infinite-scroller feel). Core is camera-follow (`cameraNode.position = ship.position`); the work is HUD re-anchoring to the camera node, ship-relative wrapping (to avoid a seam pop), starfield tiling, and shake offset. Estimated ~half a day as a standalone third mode (alongside Ancient Asteroids / Mad Meteoroids). Decide later whether/how it combines with Mad rotation (rotation pivot would need to follow the ship).
- **iOS port + free App Store release** (wanted, first-time App Store submission): The renderer is SpriteKit, so the entire game logic (`GameScene`, all entities, collision, the AVFoundation audio) runs on iOS unchanged — roughly 70% of the code is reusable as-is. What needs rewriting (~30%): the entry point (`Main.swift`, `NSApplication` → UIKit/SwiftUI app lifecycle), `GameWindow.swift` (`NSWindow` → `UIViewController` hosting an `SKView`), the input layer (`keyDown`/`keyUp` → touch), and an `NSColor` → `SKColor` sweep (~21 sites, trivial). Suggested architecture: split `GameCore` into a platform-independent **library target** + thin macOS and iOS app targets (one codebase). **Done (steps 1+2):** `GameCore` is now a platform-independent **library target** (the AppKit shell lives in a separate `ExploidsMac` executable target) and is **verified to compile for iOS** (`swiftc -typecheck` against the iOS simulator SDK, Swift 6). The `NSEvent` `keyDown`/`keyUp` overrides are thin macOS-only bridges behind `#if canImport(AppKit)` over platform-independent `handleKeyDown`/`handleKeyUp`; `simulateKeyDown`/`Up`/`TypeCharacter` call those directly (no synthetic `NSEvent`) and are the iOS input entry point. `NSApp.terminate` → `onQuit` callback (set by the shell); `NSColor` → `SKColor` everywhere; `Package.swift` declares `.iOS(.v17)`. macOS app unchanged: `swift build`/93 tests/`build-app.sh` all green. **Done (step 3, early WIP):** an Xcode iOS app target now lives under `ios/` (XcodeGen `project.yml`; `AppDelegate`, `GameViewController` hosting an `SKView`, `TouchControlsView` on-screen controls) and links the `GameCore` library; the touch overlay drives `simulateKeyDown`/`Up`. It builds and runs, but is young and **not yet released** — still needs on-device control-feel tuning, app-icon/launch-screen/asset-catalog polish, and the music-license swap below before any App Store submission. **Controls**: input is already abstracted via `simulateKeyDown`/`simulateKeyUp` (`GameScene.swift`), so touch buttons/gamepad just drive the same flags — no logic change. Plan: on-screen buttons (rotate L/R bottom-left, thrust + fire bottom-right; the charge-shot maps perfectly to touch-and-hold) **plus** MFi/Bluetooth `GameController` support (low effort, console-quality for serious players). Risk is purely control *feel* (needs on-device tuning), not technical feasibility. **Prerequisites**: (a) a paid Apple Developer account ($99/yr); (b) **replace the two musely.ai music tracks first** — Free-Plan terms forbid commercial use *and* explicitly list "distribution on … Apple Music"; a free no-IAP app is a gray area, and a retroactive paid upgrade does NOT cover already-generated tracks. Cleanest fix: regenerate own tracks via the local ACE-Step `musicgen` skill (fully owned). First-time submission → expect a learning curve (provisioning profiles, app icons/asset catalog, launch screen, App Store Connect metadata, privacy nutrition labels).

### BUG (BEHOBEN 2026-06-23): verwaiste Power-ups (z.B. [C]) — uneinsammelbar, unsterblich

Symptom: ein Power-up lag fest, ließ sich nicht einsammeln, lief nie ab und überlebte sogar
Game-Over + ESC + Level-Wechsel. **Ursache:** Die Einsammel-Schleife in `GameScene.update`
baute `remainingPowerUps` aus einem Schnappschuss und **überschrieb** danach `activePowerUps`.
Sammelt man eine **Bombe** ein, ruft `collectPowerUp` → `detonateBomb` → `spawnPowerUp` (20%
UFO-Beute), das *während* der Schleife neue Power-ups an `activePowerUps` anhängt — die gingen
beim Überschreiben verloren und blieben als **verwaiste SKNodes** im Szenengraph (nicht in
`activePowerUps` → kein Lifetime-Update, keine Kollision, kein Clear). **Fix:** erst die
einzusammelnden per `filter` bestimmen, dann einsammeln und **identitäts-basiert** aus dem Array
entfernen (`removeAll { $0 === … }`) — bewahrt gleichzeitig gespawnte Power-ups. Regressionstest:
`testBombDropsDoNotOrphanPowerups` (Invariante: PowerUp-Nodes im Szenengraph == `activePowerUps`).

### Promo-GIF einer spannenden Spielszene (TODO)

Wir brauchen ein animiertes GIF (z.B. für README/App-Store-Promo) einer packenden Spielszene.
**Empfohlener Weg (kein neuer Code):** Szene mit der macOS-Bildschirmaufnahme aufnehmen
(`Cmd+Shift+5`, Fensterausschnitt), das `.mov` zur Weiterverarbeitung übergeben → daraus per
`ffmpeg` (palettegen/paletteuse) ein optimiertes, geloopptes GIF (oder APNG/WebP) mit einer
knackigen ~4–6 s Stelle schneiden. Vorteil: null Risiko/Wartung, beste Qualität.
**Alternative (mehr Aufwand):** In-App-Recorder in der macOS-App (SKView-Frames via AVAssetWriter)
für cursor-freie, pixelgenaue Aufnahme — nur bauen, falls die Bildschirmaufnahme nicht reicht.
*Status: teilweise gelöst — das Replay-System rendert inzwischen cursor-freie GIFs headless aus
einem aufgezeichneten Lauf (`exploids --render-replay … --out …` bzw. `--render-demo`, siehe
Replay-Abschnitt). Für ein kuratiertes Promo-GIF einer bestimmten Szene bleibt der
Bildschirmaufnahme-Weg eine Option; finale Auswahl noch offen.*

### Gegner-Erweiterung: Boss + Miniboss

Stand: 2026-06-23. **Kopf-Boss UND Weltraumkatzen sind implementiert** (Details je unten). Andock-
punkte im Code: UFOs sind `SKShapeNode`-Subklassen in `activeUFOs[]` (regulärer Spawn auf max. 2
gedeckelt); Gegner mit Lebenspunkten + Zustandsautomat sind `FloatingHead` (Boss) und `SpaceCat`
(Miniboss).

**Kopf-Boss „Der Götze" (echter Boss).** Geschnitzter Greisen-Totem: wilde Mähne, buschige
überhängende Brauen, tief liegende stiere Augen (rote Pupillen folgen dem Schiff), große
knollige Hakennase, mächtiger wallender Bart mit markantem Kinn. Steinton-Vektor (Bone/Bronze)
mit **animiert öffnendem Mund**. Geschlossen: geschwungene **Doppelbogen-Lippen** (zwei Bögen
oben, ein Bogen unten) in **derselben Linienfarbe wie der restliche Kopf** (kein Sondergelb),
KEINE Zähne. Offen: Schlund mit **gelben Linien** + unregelmäßigen Fängen, UFO materialisiert
mittig. Look Zardoz-inspiriert, aber bewusst eigen. *Status: Look final.*
- **Reiner Spawner** — schießt nie selbst. Größe ~Radius 80 (größter Asteroid = 40).
- **Auftreten:** zufällig einmal in **Level 5–7**, erneut in **Level 10**; in L10 (letztes Level)
  danach **alle 4–7 Min** per Timer. Bewusst selten (nutzt sich sonst ab).
- **10 Treffer** bis zerstört (`FloatingHead.hitsToDestroy`, zentral justierbar — Playtest mit 10,
  evtl. 20). Gleicht aus, dass der Kopf groß ist und Dauerfeuer aktiv ist. Feedback: Weiß-Flash pro
  Treffer + bleibender Vektor-Schaden, der mit sinkendem Leben einsetzt (≤66 % ein Auge, ≤33 %
  zweites Auge + Kiefer), Explosion beim Tod.
- **Zustandsautomat:** Einschweben (Augen tracken sofort) → **Lauern ~3–5 s (zufällig, ø 4)** =
  Tötungsfenster → **Mund auf (animiert)** → **10 UFOs** (Mix aus großen + kleinen,
  zufällig) **gestaffelt über ~2,5 s** ausgespien, dabei **das `activeUFOs`-Limit von 2 umgangen**
  → Rückzug (Einmal-Bedrohung, kein Zyklus).
- **Aktive Ausweich-KI** (während Lauern + Spawnen): Der Kopf **flieht vor dem Schiff** und **weicht
  den Spieler-Schüssen intelligent aus** (gleitet seitlich aus der Schussbahn), bleibt dabei im Bild.
  Bewusst **zügig, aber gedeckelt** (`maxMoveSpeed`), keine Wahnsinns-Geschwindigkeit. So wird er –
  auch über den Umweg „Deckung durch andere Objekte" – manchmal schwer zu treffen. Tunables in
  `FloatingHead` (`fleeStrength`, `dodgeStrength`/`dodgeRadius`, `maxMoveSpeed`, …). Hitbox ~68.
  Er weicht anderen Objekten NICHT aus (darf über ihnen liegen). *Idee „Objekte zerschellen am Kopf"
  bewusst zurückgestellt (würde dem Spieler die Zerstör-Arbeit abnehmen).*
- **UFO-Spawn-Ursprung = Mund-Mittelpunkt**, mit kurzem Materialisier-Blitz; dann ziehen sie heraus.
- **Sanfte UFO-Verfolgung (gilt für ALLE UFOs, regulär + Armada):** UFOs beschleunigen leicht und
  gedeckelt Richtung Spieler (`UFO.homingAccel`/`maxSpeed`), statt nur seitlich wegzufliegen — sie
  kommen „ein bisschen auf uns zu", bleiben aber durch die horizontale Grund-Bewegung killbar und
  verlassen den Schirm. Bewusst moderat, damit es mit vielen Objekten nicht zu schwer wird.
- **Kill während des Ausstoßes stoppt die restlichen UFOs sofort.**
- Schiff-Kontakt = Tod. Kopf **wrappt nicht**. In **Mad-Meteoroids** bewegt er sich mit derselben
  Ausweich-KI (kein zusätzliches Mitrotieren mit dem Feld – das machte schwindelig).
- **2000 Punkte** fürs Zerstören. Strategie: schnell vor dem Mund-Öffnen töten, sonst wenigstens
  die Armada beim Rauskommen abfangen; Ignorieren kann übel ausgehen.
- **Sound:** Beim Mund-Öffnen ein gruseliges, tiefes, sonores menschliches **„Moooooo"** —
  beginnt gedämpft (Lippen zu) und öffnet sich hörbar (voller), läuft solange UFOs ausgespien
  werden, dann Stop → Mund zu → Rückzug.
  - **Prozedural: ERLEDIGT** — `SoundManager.setHeadVoice(active:openness:)` (tiefer, aufsteigender
    Sägezahn-Vokal mit openness-gesteuertem Tiefpass); GameScene triggert es während der Spawn-Phase
    mit `mouthOpenness`.
  - **Timing-Anforderung:** Sample startet, sobald sich der Mund zu öffnen beginnt, und läuft
    weiter, bis ALLE 10 UFOs erschienen sind (~3 s Spawn-Phase). Deshalb **lange Samples** (großzügig)
    mit **Ausfaden am Ende** (Fade wird beim Konvertieren nach `.m4a` via `ffmpeg afade` gesetzt).
  - **Sample-Variante: ERLEDIGT** — die ⭐-Favoriten-Wahl (Gallery-ID `178222118321504`, 7 s) exportiert,
    nach `Sources/GameCore/SFX/bosshead_0.m4a` (44,1 kHz Stereo, End-Fade via `ffmpeg afade`) gewandelt,
    im Manifest eingetragen. Im **Sample-Modus** (`useSampledSFX`) spielt `SoundManager.playBossHead()`
    das lange Mooo **einmal beim Mund-Öffnen** (Flanke in `GameScene.updateFloatingHead`), `stopBossHead()`
    bei Spawn-Ende/Kill/Statuswechsel; im prozeduralen Modus weiter `setHeadVoice(...)`.

**Weltraumkatzen (Minibosse). IMPLEMENTIERT (2026-06-23).** Kleiner als der Kopf-Boss; agieren
völlig gezielt, kein sinnloses Herumtreiben. Code: `Sources/GameCore/SpaceCat.swift` (Entität,
`SKNode`-Zustandsautomat, analog zu `FloatingHead`), Einbindung in `GameScene.updateSpaceCats`/
`fireCatTwinLaser`/`spawnSpaceCat`; Laser-Typ `.catEye` in `Laser.swift`.
- **Verhalten:** pirschen sich an den Spieler heran (halten dabei einen Schuss-Abstand `attackDistance`),
  **suchen Deckung hinter großen/mittleren Asteroiden** (Steering-Kraft Richtung „hinter dem nächsten
  Asteroiden, vom Schiff weg"), **weichen Objekten aus** (Abstoß-Kraft) und **weichen Spielerschüssen
  aus** (seitlich aus der Bahn, wie der Kopf-Boss). Bewegung gedeckelt (`maxMoveSpeed`).
- **Angriff (Laseraugen):** **Zwillings-Laser** — zwei **parallele, längere** orange Streifen
  (`.catEye`, deutlich anders als gelber Spieler- und schmaler roter UFO-Schuss), **halbe
  Spielerschuss-Geschwindigkeit** (`SpaceCat.laserSpeed = 300`). **Predictive Aim:** iterativ
  vorausberechnete Schiffsposition (nutzt `ship.velocity`).
- **Ablauf:** **dreimal** je ein Doppelschuss-Versuch (`totalAttacks`), **dazwischen jeweils
  ausweichen** (`repositioning` mit seitlichem Impuls); danach **Flucht zum Bildschirmrand — kein
  Wrap** (verschwindet, kommt nicht zurück).
- **Entscheidungen zu den vormals offenen Punkten (zentral justierbar, im Playtest abstimmbar):**
  - **HP = 3** (`SpaceCat.hitsToDestroy`, mehr als ein UFO mit 1, weit weniger als der Boss mit 10).
    Nach dem ersten Playtest von 2 auf 3 erhöht (waren zu leicht).
  - **Punkte = 750** (`pointValue`, zwischen kleinem UFO 500 und Boss 2000).
  - **Vektor-Design:** violette sitzende Linien-Katze mit **Körper** (Rumpf + Pfötchen + Schweif) und
    aufgesetztem, bewusst **kleinerem Kopf** (Ohren, Schnurrhaare, glühende orange Schlitz-Augen, die
    beim Feuern/Treffer pulsen). Kollisionsradius 26 (deckt Körper + Kopf ab). Körper nach dem ersten
    Playtest ergänzt (vorher nur ein Kopf).
  - **Auslöser/Häufigkeit:** ab **Level 3**, zeitgesteuert (erster Auftritt 12–25 s nach Eignung,
    danach Abstand 35–60 s), **max. 1 gleichzeitig**, und **nie zusammen mit dem Kopf-Boss**.
- **Kollisionen / Waffenwirkung:** Schiff-Kontakt = Tod (Katze überlebt, Miniboss); Augenlaser-Treffer
  = Tod; alle Spielerschüsse (Normal/Triple/Rapid/Rear/Drohnen) treffen sie; ein Bomben-Treffer zählt
  wie ein direkter Schuss (1 Stufe Schaden); der **Laserbeam** trifft sie ebenfalls (gedrosselt, sonst
  würde der Dauer-Strahl pro Frame Schaden machen). Death-Causes `.spaceCat`/`.spaceCatLaser`.
- **Laserbeam-Fix (Playtest):** Der Beam traf zuvor NUR Asteroiden – UFOs, Katzen und Boss konnten
  damit gar nicht zerstört werden. Jetzt trifft er alle (UFOs sofort, Mehr-HP-Gegner gedrosselt über
  `lastBeamHitTime`). Regressionstests decken die Waffe×Gegner-Matrix + eine „keine verwaisten Nodes"-
  Invariante (`entityTrackingConsistentForTesting`) ab.
- *Offen / Tuning:* Feinabstimmung von Frequenz/Schwierigkeit nach dem Playtest; ggf. Sound für
  den Augenlaser (aktuell der UFO-Sound wiederverwendet); optionaler Glossar-Eintrag.

### Deterministisches Replay-System — IMPLEMENTIERT (v0.11.0–v0.12.0)

Die Spielsimulation ist **bit-exakt reproduzierbar**: ein geseedeter PRNG (`GameRandom`,
SplitMix64) speist alle gameplay-relevanten Zufallszahlen, und die Zeit läuft über eine einzige
akkumulierte `gameTime`. Seit v0.12.0 läuft die Simulation im **Fixed-Timestep**: `update(_:)`
summiert die reale Frame-Zeit in einem Akkumulator und treibt die Sim in festen Schritten
(`GameScene.simStep` = 1/120 s) über `advanceOneStep()` → `stepSimulation(deltaTime:)`. Damit hängt
ein Lauf nur noch an (Seed + Eingaben). Jeder Lauf wird aufgezeichnet (`Replay` / `ReplayRecorder` /
`ReplayPlayer`, nur Seed + Eingaben + `frameCount`, wenige KB) und bei Game Over an den Highscore
gehängt. **In-App-Wiedergabe:** Titelbildschirm, Zifferntaste 1–5 für den Highscore-Eintrag, ESC
verlässt. **Headless-GIF-Rendering:** `ReplayRenderer` (SKRenderer + Offscreen-Metal + ImageIO) im
ExploidsMac-Target treibt die Sim direkt per `advanceOneStep()` (`externalStepDriving`); CLI
`exploids --render-replay <file> --out <gif>` (plus `--export-replay`, `--render-demo`), Capture-Stride
automatisch auf Echtzeit. **Replay-Format v3** (Fixed-Timestep, ohne dt-Folge); v2-Aufnahmen (variabler
Zeitschritt, mit Auto-Feuer) werden als inkompatibel abgelehnt.

**Replay-Archiv (seit v0.12.0):** Bei Game Over wird die Aufnahme JEDES Laufs als Datei nach
`~/Library/Application Support/Exploids/replays` geschrieben (host-gesetzt über `replaySaveDirectory`;
Default aus, damit Tests/Headless nichts schreiben) — unabhängig vom Highscore, damit sich nach einem
guten Spiel ein GIF rendern lässt, ohne dass der Lauf in die Liste muss. CLI:
`exploids --render-last-replay --out <gif>` (rendert die neueste Aufnahme), `--reset-highscores`
(leert die Highscore-Liste; über die App-Binary bei beendetem Spiel ausführen).

**Voller Plan + Erfolgskriterien:** [`docs/replay-system-plan.md`](docs/replay-system-plan.md)
(Phase 1 + 2 + 3 vollständig, inkl. 3.1 Fixed-Timestep). **Spielgefühl** des Fixed-Timestep ist final
über einen Playtest abzunehmen (auf 120 Hz im Idealfall ein Sim-Schritt pro Bild wie zuvor). **Bekannte
Einschränkung:** treue Wiedergabe braucht exakt die Binary, die den Lauf aufgenommen hat — eine neu
gebaute Binary kann driften (Float-Reproduzierbarkeit ist binary-spezifisch); In-App-Replays und GIFs
aus demselben installierten Build sind zuverlässig.
