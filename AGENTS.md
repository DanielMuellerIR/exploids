# Exploids: Native macOS Retro-HighRes Asteroids

Exploids is a native macOS Asteroids clone with a C-64 inspired vector aesthetic executed at modern high resolution and butter-smooth frame rates (supporting Apple Silicon and ProMotion 120Hz). Graphics are fully procedural (vector rendering) and all sound effects are synthesized in real time; the only bundled assets are two chiptune background-music tracks (see Asset Licensing).

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

```
exploids/
├── Package.swift              # Swift Package Manager manifest (executable + test target)
├── VERSION                    # single source of truth for the version string
├── build-app.sh               # builds the double-clickable Exploids.app
├── wrappers/
│   └── sign-and-release.sh     # sign + notarize + DMG (+ optional GitHub release)
├── assets/
│   └── generate-dmg-background.swift  # renders the DMG install-window background
├── Sources/GameCore/
│   ├── Main.swift             # app entrypoint and Cocoa application lifecycle
│   ├── GameWindow.swift       # configures the Cocoa window and SKView
│   ├── GameScene.swift        # key inputs, game loop, modes, spawning, collision wiring
│   ├── Ship.swift             # player ship (outline rendering, physics, friction, wrap)
│   ├── Asteroid.swift         # asteroids (procedural shape, splitting, screen-entry)
│   ├── Laser.swift            # projectiles (velocity, lifetime, wrap)
│   ├── PowerUp.swift          # the nine power-up types and their vector glyphs
│   ├── GravityWell.swift      # singularities that pull objects
│   ├── UFO.swift              # enemy saucers and their shots
│   ├── Collision.swift        # world-space collision helpers
│   ├── SoundManager.swift     # real-time procedural SFX synthesizer
│   ├── MusicPlayer.swift      # chiptune background music (M toggle)
│   ├── RetroFont.swift        # registers Press Start 2P (CoreText) for headings
│   ├── Fonts/                 # PressStart2P-Regular.ttf + OFL.txt
│   └── Music/                 # asteroid-storm.mp3, neon-vectors.mp3
└── Tests/
    └── GameCoreTests/
        └── GameCoreTests.swift # 54 unit tests (physics, wrap-around, lasers, power-ups, modes)
```

---

## Current Status: v0.6.1 — Game Modes

Two selectable game modes (start screen: ▲/▼ to switch, ◀/▶ for level, Space to start):
- **Ancient Asteroids**: the classic mode — fixed playfield, objects wrap around the screen edges. Unchanged.
- **Mad Meteoroids**: the whole playfield (asteroids, gravity wells, power-ups, starfield) rotates continuously around the screen center while the player ship stays exempt (Crazy-Comets style). Rotation speed scales with level (~6°/s at L1 up to ~30°/s from L10), with scheduled direction changes (L1–3 constant, then 2-2-2-3-3-4 changes per level, ~every 10s from L10) and occasional "record-scratch" jolts at high levels. UFOs and their shots stay screen-fixed in this first version. The field uses circular wrapping (objects leaving the field radius re-enter on the opposite side) so rotation stays coherent. Implementation note: gameplay objects are kept in one flat coordinate space — their positions/velocities are rotated per frame around the origin rather than parented to a rotating container — so the existing world-space collision system needs no changes. Tuning constants live in the `MadRotation` enum in `GameScene.swift`.

Also fixed: asteroids could spawn mid-screen because off-screen spawns were immediately folded back by edge-wrapping; they now reliably fly in from the edge (see `Asteroid.hasEnteredScreen`).


---

## Roadmap

### Open To-Dos (planned, not yet implemented)
- **Turrican-style power-up voice samples**: Generate short, bitcrushed announcer samples ("Power Up!", "Extra Life!", "Game Over!") locally via TTS + post-processing. Full workflow (Qwen3-TTS / F5-TTS on MLX, then `pedalboard` bitcrush) is documented in `turrican-like-powerup-tts.md`. Would replace/augment the current procedural SFX for power-up pickups.
- **Scroll mode (3rd game mode)**: Ship stays centered, the world scrolls so the player can never reach the screen edge (infinite-scroller feel). Core is camera-follow (`cameraNode.position = ship.position`); the work is HUD re-anchoring to the camera node, ship-relative wrapping (to avoid a seam pop), starfield tiling, and shake offset. Estimated ~half a day as a standalone third mode (alongside Ancient Asteroids / Mad Meteoroids). Decide later whether/how it combines with Mad rotation (rotation pivot would need to follow the ship).
- **iOS port + free App Store release** (wanted, first-time App Store submission): The renderer is SpriteKit, so the entire game logic (`GameScene`, all entities, collision, the AVFoundation audio) runs on iOS unchanged — roughly 70% of the code is reusable as-is. What needs rewriting (~30%): the entry point (`Main.swift`, `NSApplication` → UIKit/SwiftUI app lifecycle), `GameWindow.swift` (`NSWindow` → `UIViewController` hosting an `SKView`), the input layer (`keyDown`/`keyUp` → touch), and an `NSColor` → `SKColor` sweep (~21 sites, trivial). Suggested architecture: split `GameCore` into a platform-independent **library target** + thin macOS and iOS app targets (one codebase). **Done (steps 1+2):** `GameCore` is now a platform-independent **library target** (the AppKit shell lives in a separate `ExploidsMac` executable target) and is **verified to compile for iOS** (`swiftc -typecheck` against the iOS simulator SDK, Swift 6). The `NSEvent` `keyDown`/`keyUp` overrides are thin macOS-only bridges behind `#if canImport(AppKit)` over platform-independent `handleKeyDown`/`handleKeyUp`; `simulateKeyDown`/`Up`/`TypeCharacter` call those directly (no synthetic `NSEvent`) and are the iOS input entry point. `NSApp.terminate` → `onQuit` callback (set by the shell); `NSColor` → `SKColor` everywhere; `Package.swift` declares `.iOS(.v17)`. macOS app unchanged: `swift build`/54 tests/`build-app.sh` all green. **Remaining for iOS (step 3):** add an Xcode iOS app target (SwiftPM alone can't produce a device-signable iOS `.app`) that links `GameCore`, hosts an `SKView` in a `UIViewController`, and adds the touch-control overlay; wire it to `simulateKeyDown`/`Up`. **Controls**: input is already abstracted via `simulateKeyDown`/`simulateKeyUp` (`GameScene.swift`), so touch buttons/gamepad just drive the same flags — no logic change. Plan: on-screen buttons (rotate L/R bottom-left, thrust + fire bottom-right; the charge-shot maps perfectly to touch-and-hold) **plus** MFi/Bluetooth `GameController` support (low effort, console-quality for serious players). Risk is purely control *feel* (needs on-device tuning), not technical feasibility. **Prerequisites**: (a) a paid Apple Developer account ($99/yr); (b) **replace the two musely.ai music tracks first** — Free-Plan terms forbid commercial use *and* explicitly list "distribution on … Apple Music"; a free no-IAP app is a gray area, and a retroactive paid upgrade does NOT cover already-generated tracks. Cleanest fix: regenerate own tracks via the local ACE-Step `musicgen` skill (fully owned). First-time submission → expect a learning curve (provisioning profiles, app icons/asset catalog, launch screen, App Store Connect metadata, privacy nutrition labels).

### Promo-GIF einer spannenden Spielszene (TODO)

Wir brauchen ein animiertes GIF (z.B. für README/App-Store-Promo) einer packenden Spielszene.
**Empfohlener Weg (kein neuer Code):** Szene mit der macOS-Bildschirmaufnahme aufnehmen
(`Cmd+Shift+5`, Fensterausschnitt), das `.mov` zur Weiterverarbeitung übergeben → daraus per
`ffmpeg` (palettegen/paletteuse) ein optimiertes, geloopptes GIF (oder APNG/WebP) mit einer
knackigen ~4–6 s Stelle schneiden. Vorteil: null Risiko/Wartung, beste Qualität.
**Alternative (mehr Aufwand):** In-App-Recorder in der macOS-App (SKView-Frames via AVAssetWriter)
für cursor-freie, pixelgenaue Aufnahme — nur bauen, falls die Bildschirmaufnahme nicht reicht.
*Status: offen, Weg noch zu entscheiden.*

### Gegner-Erweiterung: Boss + Miniboss (geplant, in Design)

Stand: 2026-06-23. Entwurf aus Brainstorming; noch nicht implementiert. Andockpunkte im Code:
UFOs sind `SKShapeNode`-Subklassen in `activeUFOs[]` (Spawn aktuell auf max. 2 gedeckelt,
Startposition am Bildschirmrand erzwungen); Mehrfach-Treffer kennt bisher nur der Asteroid.
Der Kopf wäre der **erste Gegner mit Lebenspunkten + Zustandsautomat**.

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
- **3 Treffer**, jeder mit sichtbarem Feedback: kurzer Weiß-Flash + bleibender Vektor-Schaden
  (1: ein Auge zerspringt, 2: Kiefer/Outline reißt, 3: Explosion).
- **Zustandsautomat:** Einschweben (Augen tracken sofort) → **Lauern 5–8 s (zufällig)** =
  Tötungsfenster → **Mund auf (animiert, SKAction)** → **10 UFOs** (Mix aus großen + kleinen,
  zufällig) **gestaffelt über ~2,5 s** ausgespien, dabei **das `activeUFOs`-Limit von 2 umgangen**
  → Rückzug (Einmal-Bedrohung, kein Zyklus).
- **UFO-Spawn-Ursprung = Mund-Mittelpunkt**, mit kurzem Materialisier-Effekt; dann ziehen sie heraus.
- **Kill während des Ausstoßes stoppt die restlichen UFOs sofort.**
- Schiff-Kontakt = Tod. Kopf **wrappt nicht**. In **Mad-Meteoroids rotiert er mit dem Feld** mit.
- **2000 Punkte** fürs Zerstören. Strategie: schnell vor dem Mund-Öffnen töten, sonst wenigstens
  die Armada beim Rauskommen abfangen; Ignorieren kann übel ausgehen.
- **Sound (TODO, noch NICHT umgesetzt):** Beim Mund-Öffnen ein gruseliges, tiefes, sonores
  menschliches **„Moooooo"**. Der Ton beginnt bereits mit **geschlossenen Lippen** (gedämpftes
  Ansetzen wie beim Sprechbeginn) und **ändert sich hörbar im Moment des Öffnens** (Klang wird
  offen/voller) — dieser Übergang soll nachgeahmt werden. Läuft in **Schleife, solange der Kopf
  UFOs ausspuckt**, danach Stop → Mund zu → Rückzug. Erzeugung über den **`sfxgen`-Skill** als
  Sample(s), passend zum vorhandenen Sample-SFX-Set (`Sources/GameCore/SFX/*.m4a`, `useSampledSFX`).

**Weltraumkatzen (Minibosse).** Kleiner als der Kopf-Boss; agieren völlig gezielt, kein sinnloses
Herumtreiben.
- **Verhalten:** pirschen sich an den Spieler heran, **suchen Deckung hinter anderen Objekten**
  (v.a. großen Asteroiden), um Spielerschüssen zu entgehen, und **weichen Objekten aus**. Soll
  fordernd, aber nicht zu schwer sein.
- **Angriff (Laseraugen):** **Zwillings-Laser** — immer **zwei parallele, längere Laserstreifen**
  (deutlich anders als die Spielerschüsse), mit **sehr geringer Frequenz**. **Predictive Aim:**
  extrapolieren die Flugbahn des Spielers — ändert er seine Bewegungsrichtung nicht, treffen sie.
  Ausgleich: die Schüsse fliegen **langsam (halbe Spielerschuss-Geschwindigkeit)**.
- **Ablauf:** **dreimal** je ein Trefferversuch (ein Doppelstrahl pro Versuch), **dazwischen jeweils
  ausweichen**; danach **Flucht zum Bildschirmrand — kein Wrap, sie verschwinden** (kommen nicht
  auf der anderen Seite zurück).
- *Offen:* HP (1–2 Treffer?), genaues Vektor-Design, Auslöser/Häufigkeit.
