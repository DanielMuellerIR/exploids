# Exploids: Native macOS Retro-HighRes Asteroids

Exploids is a native macOS Asteroids clone with a C-64 inspired vector aesthetic executed at modern high resolution and butter-smooth frame rates (supporting Apple Silicon and ProMotion 120Hz). Graphics are fully procedural (vector rendering) and all sound effects are synthesized in real time; the only bundled assets are two chiptune background-music tracks (see Asset Licensing).

## Tech Stack & Architecture

- **Language**: Swift 6 (strict concurrency compliant).
- **GUI & Windowing**: AppKit (`NSApplication`, `NSWindow`, `NSAppearance`).
- **Render Engine**: SpriteKit (`SKView`, `SKScene`, `SKShapeNode`). Coordinates are centered around `(0, 0)` with standard wrap-around physics boundaries.
- **Audio Engine**: AVFoundation (`AVAudioEngine`, `AVAudioSourceNode`). Procedural synth sounds calculated in real-time on the audio render thread.
- **Build System**: Swift Package Manager (SPM) executable package.

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
- **iOS port + free App Store release** (wanted, first-time App Store submission): The renderer is SpriteKit, so the entire game logic (`GameScene`, all entities, collision, the AVFoundation audio) runs on iOS unchanged — roughly 70% of the code is reusable as-is. What needs rewriting (~30%): the entry point (`Main.swift`, `NSApplication` → UIKit/SwiftUI app lifecycle), `GameWindow.swift` (`NSWindow` → `UIViewController` hosting an `SKView`), the input layer (`keyDown`/`keyUp` → touch), and an `NSColor` → `SKColor` sweep (~21 sites, trivial). Suggested architecture: split `GameCore` into a platform-independent **library target** + thin macOS and iOS app targets (one codebase). Build needs an Xcode iOS app target (SwiftPM alone can't produce a device-signable iOS `.app` easily). **Controls**: input is already abstracted via `simulateKeyDown`/`simulateKeyUp` (`GameScene.swift`), so touch buttons/gamepad just drive the same flags — no logic change. Plan: on-screen buttons (rotate L/R bottom-left, thrust + fire bottom-right; the charge-shot maps perfectly to touch-and-hold) **plus** MFi/Bluetooth `GameController` support (low effort, console-quality for serious players). Risk is purely control *feel* (needs on-device tuning), not technical feasibility. **Prerequisites**: (a) a paid Apple Developer account ($99/yr); (b) **replace the two musely.ai music tracks first** — Free-Plan terms forbid commercial use *and* explicitly list "distribution on … Apple Music"; a free no-IAP app is a gray area, and a retroactive paid upgrade does NOT cover already-generated tracks. Cleanest fix: regenerate own tracks via the local ACE-Step `musicgen` skill (fully owned). First-time submission → expect a learning curve (provisioning profiles, app icons/asset catalog, launch screen, App Store Connect metadata, privacy nutrition labels).
