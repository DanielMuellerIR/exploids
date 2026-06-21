# Exploids

**🌐 Sprache / Language:** [English](README.md) · [Deutsch](README.de.md)

<p align="center"><img src="Icon/icon_1024.png" width="180" alt="Exploids app icon"></p>

A native macOS Asteroids-style arcade shooter (Swift 6 · SpriteKit) with a Commodore‑64‑inspired vector look, rendered at modern high resolution and butter‑smooth frame rates (Apple Silicon, ProMotion 120 Hz). Every graphic is procedural vector geometry and every sound effect is synthesized in real time — the only bundled media are two chiptune music tracks. Two game modes, nine power‑ups, gravity wells, enemy saucers and a pixel‑font HUD.

## Download

**[➜ Download the latest signed & notarized DMG](https://github.com/DanielMuellerIR/exploids/releases/latest)** — open it, drag *Exploids* into Applications and double‑click. Signed with a Developer ID and notarized by Apple, so it opens without a Gatekeeper warning. Requires macOS 14 or newer (Apple Silicon).

Prefer to build from source? See [Build & run](#build--run-cli--headless-friendly) below.

## Screenshots

<p align="center"><img src="screenshots/sc0.jpg" width="860" alt="Survival mode in full flow — the ship fires a rainbow stream of shots past a purple gravity well as asteroids and an enemy saucer close in"></p>

| Option drone + shield | In-game glossary |
|:--:|:--:|
| ![Asteroid field with an option drone acquired, the ship shielded and compressed](screenshots/sc1.jpg) | ![In-game glossary of objects and power-ups](screenshots/sc3.jpg) |
| **Laser beam** | **Gravity well + screen bomb** |
| ![The hold-to-fire laser beam sweeping the field](screenshots/sc2.jpg) | ![A gravity well warps space as a screen bomb detonates](screenshots/sc4.jpg) |

## Build & run (CLI / headless‑friendly)

No Xcode project — a Swift Package Manager executable compiled into a `.app` bundle. The whole toolchain is scriptable (handy for automation and AI agents):

```bash
./build-app.sh                                   # build -> Exploids.app (double-clickable)
open Exploids.app                                # launch
.build/release/exploids                          # launch the bare binary (logs in the terminal)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test   # run the 54 unit tests
```

### Signed + notarized DMG

```bash
bash wrappers/sign-and-release.sh                # -> build/Exploids-<version>.dmg, Gatekeeper-clean
bash wrappers/sign-and-release.sh --publish      # also tags + uploads the DMG to GitHub Releases
```

## Game modes

Pick on the start screen (▲/▼ to switch, ◀/▶ for the starting level, Space to start):

- **Ancient Asteroids** — the classic mode. Fixed playfield; objects wrap around the screen edges.
- **Mad Meteoroids** — the whole field (asteroids, gravity wells, power‑ups, starfield) rotates continuously around the screen center while your ship stays exempt (Crazy‑Comets style). Rotation speed ramps with the level, with scheduled direction changes and occasional "record‑scratch" jolts at higher levels.

## Power‑ups

Nine pickups, each with its own vector glyph:

| Glyph | Power‑up | Effect |
|:--:|--|--|
| `S` | Shield | Energy shield absorbs a hit |
| `W` | Spread | Triple spread shot |
| `R` | Rapid | Greatly increased fire rate |
| `O` | Option | A satellite drone fires alongside you |
| `B` | Bomb | Screen‑clearing explosion |
| `L` | Laser beam | Hold to fire a sweeping, edge‑wrapping beam |
| `T` | Rear | Adds a backward‑firing shot |
| `C` | Compress | Shrinks the ship to ~30 % (smaller target) |
| `+` | Extra life | Revive centered with brief invincibility |

## Controls

- **Start screen:** ▲/▼ switch game mode · ◀/▶ (or A/D) choose starting level · Space/Enter start · I glossary
- **In game:** Arrow keys / WASD to fly · Space to fire (hold to charge / sweep the beam) · M toggle music · Esc pause / quit
- High scores are saved locally; enter your name on the board when you make the cut.
- **Cheat:** press `#` for a free extra life — handy for testing, or for a relaxed, no‑pressure run.

## How it compares

Exploids is a hobby clone, not a product. For honest context, with the weak spots named too:

**Versus the original Asteroids (1979)** — the original is monochrome vector graphics with splitting rocks, two saucers, hyperspace and an extra life at 10,000 points. Exploids keeps that core and adds a second, rotating-field mode (Mad Meteoroids), nine power-ups, gravity wells, imploding and wobbling special asteroids, a charge shot and a sweeping laser beam, color, chiptune music, an in-game glossary and local high-score entry.

**Versus Maelstrom** — [Maelstrom](https://github.com/libsdl-org/Maelstrom) (Ambrosia, 1992; a GPL SDL port since 1995, today an SDL2/SDL3 build that runs on Apple Silicon) is the best-known still-maintained open-source Asteroids clone for the Mac, and the fairer yardstick: it already has power-ups, bonus objects and rich sound. Where Exploids actually differs:

- **Rendering:** Exploids is real-time *vector* geometry drawn procedurally at high resolution and 120 Hz ProMotion; Maelstrom is bitmap / sprite raster art.
- **Audio:** Exploids synthesizes its sound effects live on the audio thread (only the two music tracks are files); Maelstrom plays sampled sound.
- **Mechanics:** the rotating Mad Meteoroids mode, gravity wells and imploding asteroids are specific to Exploids.
- **Stack:** native Swift 6 / SpriteKit / AppKit on Apple Silicon, versus a C/SDL port.

**Where Maelstrom is plainly ahead:** it has single- *and* multiplayer (cooperative and competitive), game-controller and touch support, runs on more platforms, and carries 30 years of refinement and community. Exploids is single-player, keyboard-only, macOS-desktop-only, and young. It also ships non-commercial music (see below), a restriction Maelstrom's CC-licensed assets don't impose.

## Licensing

- **Code:** [MIT](LICENSE) — © 2026 Daniel Müller.
- **Heading font** `Sources/GameCore/Fonts/PressStart2P-Regular.ttf` (Press Start 2P): **SIL Open Font License 1.1** (`Sources/GameCore/Fonts/OFL.txt`) — free for any use, including commercial.
- **⚠️ Music** `Sources/GameCore/Music/*.mp3` (two chiptune tracks): generated with **[musely.ai](https://musely.ai)** on its Free Plan — **personal, non‑commercial use only**. These tracks are **not** covered by the MIT code license and keep musely.ai's separate terms. Before any commercial use, replace them with your own / CC0 / commercially‑licensed music. All other audio is synthesized at runtime (no third‑party rights).

## Requirements

macOS **14+**, Apple Silicon. To build: a full Xcode install (the scripts use `DEVELOPER_DIR=/Applications/Xcode.app/...` for the SpriteKit/XCTest toolchain).

---

*Status: private / personal project — a procedural, vector‑style homage to the 1979 Asteroids arcade classic, with no code or assets taken from it.*
