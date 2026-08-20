# Changelog

All notable changes to Exploids. Dates are ISO 8601 (YYYY-MM-DD).

## [0.14.8] — 2026-08-20

- Fix: the DMG cleanup handler is armed immediately after `hdiutil` mounts an image and falls
  back to the mount point when the device line cannot be parsed, so every post-mount failure
  can detach the image.
- Fix: `./release.sh --publish` now checks `gh` and the canonical GitHub repository before the
  build and notarization. Remote tag inspection and pushing use that same repository instead of
  trusting a mutable local remote named `github`.
- Build: `build-app.sh` changes to its own directory before touching relative paths and trims
  whitespace from `VERSION`, keeping direct and wrapper-driven builds on the same source files.
- Tests: release guards now exercise local-tag matching, early publish prerequisites, failed and
  unparsable DMG mounts, abort cleanup order, and the exact Gatekeeper and `gh release create`
  calls. Shared shell helpers keep source extraction and binary probes consistent across tests.
- Docs: the web-port analysis now records the conditional AppKit keyboard bridge, uses consistent
  SpriteKit occurrence counts, and includes the two PNG boss textures in the porting estimate.

## [0.14.7] — 2026-08-03

- Release: 0.14.6 is deliberately left untouched. Its tag `v0.14.6` and the published DMG both
  come from `5e7c7b0`; later work landed on top while `VERSION` still read 0.14.6, so the tag
  points at an older commit than the current source. Neither the tag nor the published release is
  moved or rebuilt — everything committed after `5e7c7b0` ships as 0.14.7 instead, and 0.14.7 is
  the next release. Nothing has been tagged for it yet.
- Fix: `./release.sh --publish` now refuses to continue when the tag for the current version
  already exists but points at a different commit. Before, the tag step was silently skipped and
  the release uploaded a DMG built from a different source state under that tag — replacing an
  already published asset when the release existed. The check runs before the build, not after
  the notarization.
- Fix: `./install.sh` verifies the notarization ticket and the Gatekeeper verdict at the staging
  path *before* replacing the app in `/Applications`, keeps the previous installation as a backup
  until the final check at the destination passes, and restores it if that check fails. A rejected
  build can no longer displace a working installation.
- Fix: the notarization helper no longer leaves its temporary directory behind — it holds a full
  ZIP copy of the app — when a precondition rejects the bundle or any step fails.
- Fix: `--no-finder-layout` no longer requires and packs the DMG background image. It is only used
  by the Finder layout step and is now created and copied together with it.
- Fix: the bare SwiftPM binary resolves `VERSION` relative to its own location instead of the
  source path recorded at build time, so the build machine's source path is no longer embedded as
  a string in the shipped binary. Behaviour is unchanged: inside a checkout it reports the version,
  a copy moved elsewhere still reports `unknown`.
- Fix: game resources (art, fonts, music, sound effects) are located relative to the running
  executable instead of through `Bundle.module`. SwiftPM bakes the build machine's absolute
  `.build` path into the accessor it generates for `Bundle.module`, so that path ended up as a
  string in every shipped binary — and on the build machine it was even used as a live fallback,
  meaning the app could read resources straight out of the source tree there while no other
  machine could. The replacement also stops the process from being killed by `fatalError` when a
  resource is missing; the callers already fall back to a placeholder.
- Build: `./install.sh` and `./release.sh` are the two entry points and the app is notarized in its
  own right before the DMG is built — first release carrying that split.
- Tests: `Tests/run-shell-tests.sh` gathers the shell integration tests and runs in CI. The CLI
  version check had no caller at all until now; it is joined by regression tests for the install
  swap/rollback and for the notarization cleanup.
- Tests: the "silent before the first singleton access" guarantee is asserted directly instead of
  through a flag that the shared test setup overwrites anyway.
- Tests: `Tests/fleet-rules.sh` pins the two rules that keep releases safe — the notarization
  ticket is required before anything is written to the install directory, and no absolute build
  machine path may reach the shipped bundle. It reads sources only; it never builds, signs,
  notarizes or touches `/Applications`, because a test that had to run the real install path to
  prove the guard would itself be the hazard.
- Fix: the binary probes that look for build machine paths were blind. On macOS, `strings -a` means
  "all sections of the object file", which excludes the symbol table in `__LINKEDIT` — exactly where
  the leaked paths were. Measured on the unstripped release binary: `strings -a` found none,
  `strings -` found 64. Both probes now use `strings -` and first prove they can see at all by
  looking for `__mh_execute_header`, which also remains present with Chained Fixups.
- Build: release bundles remove SwiftPM's debug map with `strip -S`, so paths to source and object
  files on the build Mac are not shipped in the executable.
- Fix: `./release.sh --publish` requires a clean working tree before the build, records the commit
  it builds from, and re-checks both before publishing. It also resolves the tag on the remote and
  compares it with that commit instead of trusting a local tag of the same name: a missing remote
  tag is pushed without force, a diverging one aborts the release. The Gatekeeper verdict on the
  finished DMG is no longer discarded, so a rejected image cannot be published.
- Fix: the writable DMG is detached by an exit handler if anything fails between mounting it and
  ejecting it, instead of being left mounted.
- Tests: the Gatekeeper stub in the install swap test read the wrong argument and therefore never
  fired; two cases now cover a rejection at the staging and at the destination path. New
  `Tests/release-guards.sh` covers the release preconditions, and the CLI version test cleans up
  its temporary copy even when it aborts.

## [0.14.6] — 2026-07-22

- Fix: Attract-mode demos no longer unlock or persist levels for the player, and the selected mode,
  start level and auto-fire setting are restored after both manual abort and demo game over.
- Build: the bare SwiftPM executable now reports `--version` from the central `VERSION` file, just
  like the app bundle; a headless integration check prevents future drift.
- Docs: requirements consistently state the actual macOS 11 minimum, and controls correctly describe
  held fire as continuous fire plus the separate Laser beam power-up instead of the removed charge shot.
- Cleanup: removed the unused per-step `maxThreat` bookkeeping from the demo autopilot.
- Tests: XCTest now suppresses the sound engine before singleton initialization, so headless gameplay
  tests do not briefly open an audio device before the shared test setup mutes it.

## [0.14.4] — 2026-07-12

First signed & notarized release since v0.13.0 — this DMG bundles everything from v0.14.0 through
v0.14.4.

**For players:**
- Fix: watching the title-screen demo no longer leaves a movement key "stuck" when you then start a
  game (the ship could keep rotating on its own).
- Asteroid rendering is a little smoother, especially on lower-end hardware.

Everything else in this range is internal — a large refactor, a new automated test workflow (CI),
and build-portability fixes — with no effect on gameplay. Details below and in the entries for
v0.14.0–v0.14.3.

**Under the hood (v0.14.4):**
- Build/CI: fixed Swift 6 concurrency errors that only surfaced on the stable toolchain
  (Swift 6.1 on the CI runner) and were hidden by newer local toolchains (6.3+, which infer the
  isolation by default). `ReplayPlayer.advanceStep` calls the MainActor-isolated
  `GameScene.injectReplayInput`, and the entire `ExploidsMac` CLI layer (`Main`, `ReplayRenderer`)
  drives a MainActor `GameScene`/SpriteKit — all three are now explicitly `@MainActor`, which builds
  on both toolchains. Caught by the freshly added CI on its very first run.

## [0.14.3] — 2026-07-12
- Cleanup: removed the dead "Wave Cannon / charge shot" feature — the charge level was never
  raised, so the ship charge indicator, the `playChargeShot` SFX + charge-hum synthesis, and the
  unused `chargeshot_0.m4a` sample were all inert. Docs (README / AGENTS.md) corrected accordingly.
- Perf: the asteroid wireframe path is now rebuilt once per rendered frame instead of once per
  120 Hz simulation step (roughly halves the SKShapeNode path rebuilds on a 60 Hz display). Purely
  visual — the golden replay still reproduces bit-exact and GIF/video rendering is unchanged.
- Fix: a failed replay encode when saving a high score is now logged instead of silently swallowed
  (`try?` → `do/catch`); the high score is still stored, just without the replay.

## [0.14.2] — 2026-07-12
- Internal: split the 4.8k-line `GameScene.swift` into thematic `extension GameScene` files
  (HUD, attract/autopilot, glossary, Mad-Meteoroids rotation, test hooks) plus standalone
  `OptionDrone.swift` — pure code move, verified bit-exact against a golden replay.
- Internal: deduplicated the entities' `distance`/`moveToward`/`wrapAround` helpers into a shared
  `VectorMath.swift`, and gathered scattered gameplay magic numbers into a `GameplayTuning` enum.
- Tests: split the 2.3k-line single-file test suite by domain (physics, power-ups/weapons, bosses,
  modes, replay determinism, autopilot, scene state) over a shared `GameCoreTestCase` base, and
  added `AudioSmokeTests` covering the previously untested `SoundManager` / `MusicPlayer` surface
  (muted, no real audio engine). 101 tests, all green.

## [0.14.1] — 2026-07-12
- Build: the macOS app-bundle version now comes from the central `VERSION` file instead of being
  hard-coded in `build-app.sh`; the bundle build number is derived from the git commit count
  (monotonic, no more manual bumping).
- iOS: new `ios/generate.sh` syncs `MARKETING_VERSION` from `VERSION` before generating the Xcode
  project — the iOS version had silently drifted to 0.9.0 while macOS was at 0.14.0.
- CI: added a GitHub Actions workflow that runs the full test suite (`swift test`) on every push
  and pull request (tests are headless and deterministic, so no extra setup is needed).
- Internal: extracted high-score persistence (`HighScoreStore`) and the on-disk replay archive
  (`ReplayArchive`) out of `GameScene` into their own types — no behavior change, all 97 tests pass.

## [0.14.0] — 2026-07-08
- iOS: the demo / attract mode now runs on the mobile build too — after 30 s idle (or via a new
  **DEMO** button on the title screen) an autopilot plays a full game; a touch, or the on-screen
  **ESC**, hands control back. A "> DEMO — <persona>" marker shows while it plays.
- iOS: redesigned in-game HUD to free up the playfield — smaller score, high score hidden during
  play, and level / time / demo shown as one centered line just below ESC (same size, three colors).
- iOS: the on-screen touch controls are dimmer and thinner in-game (visible for orientation, but out
  of the way), and are hidden entirely during a demo — only **ESC** stays so a viewer can stop it.
- iOS: the glossary now opens already scrolled in so its content is visible immediately, and the
  settings screen no longer shows the redundant control hint.
- Fix: after watching a demo, starting a game no longer leaves an autopilot movement key "stuck"
  (the ship kept rotating on its own) — held keys are now cleared on every fresh game and demo abort.

## [0.13.0] — 2026-07-07
- Demo / attract mode on the title screen: after 30 s of no input (or on pressing **D**), an
  autopilot plays a full game on its own. When it dies it does **not** enter the high-score list,
  but the high-score screen is shown for 10 s, then the title screen for 15 s, then the next demo —
  looping. Any key hands control back to a human.
- Four autopilot personas that play with distinct styles (cautious ↔ reckless, skilled ↔ sloppy)
  and each start at a fitting level: **Ace** (L4, the expert — reaches level 10 and can survive the
  full ~10 minutes), **Cowboy** (L6, offensive but clean), **Rookie** (L5, cautious but sloppy) and
  **Kamikaze** (L7, reckless — dies youngest but spectacularly). The autopilot uses a potential-field
  navigator (threats repel, shooters/power-ups weakly attract, look-ahead dodging) that keeps the
  ship weaving through the gaps and firing along its path; it also collects shields/extra-lives.

## [0.12.1] — 2026-06-25
- Replay fix: a recording now stores the scene size it was played at. The simulation depends on the
  scene size (spawn positions, wrap bounds, enemy entry), so replaying or rendering at a different
  size made the run drift completely. The headless renderer and `--replay-verify` now use the
  recorded size by default; older recordings without the field assume the macOS window default of
  1024×768 (so existing replays render correctly without manual flags).
- The GIF renderer can now decouple simulation size from output size (`--sim-scale` for the sim,
  `--scale` for the GIF), so a faithful 1024×768 run can be rendered to a compact GIF.
- New CLI `--render-video <file> --out <mp4>`: render a whole replay to a real-time h264 video
  (via AVAssetWriter). For long runs that would be absurdly large as a GIF — scrub it to pick a
  GIF segment.

## [0.12.0] — 2026-06-25
- Fixed-timestep simulation: the game loop now advances in fixed steps (1/120 s) driven by a
  time accumulator, decoupled from the display refresh rate, instead of integrating one variable
  step per frame. On 120 Hz this is effectively one step per frame as before; on other refresh
  rates the simulation stays consistent.
- Because every step is the same length, a replay no longer needs the recorded per-frame `dt`
  sequence — it depends only on (seed + inputs). Replay format bumped to v3; older replays
  (v2, variable timestep) are rejected as incompatible.
- The headless GIF renderer drives the simulation one fixed step at a time and picks a capture
  stride automatically so the GIF plays in real time (`--stride` still overrides).
- Replays are now auto-saved to disk on every game over (not only high-score runs), under
  `~/Library/Application Support/Exploids/replays`, so a good run can be turned into a GIF even if
  it didn't make the board. New CLI `--render-last-replay --out <gif>` renders the most recent one.
- New CLI `--reset-highscores` clears the saved high-score list (when the board fills with
  unbeatable scores).
- No gameplay-balance changes intended; this is an engine/feel change to be confirmed by playtest.

## [0.11.1] — 2026-06-24
- Replay fix: the auto-fire setting is now recorded in a replay and restored on playback. Before
  this, a run played with auto-fire on would not reproduce (the replayed ship barely fired and died
  early). Replay format bumped to v2; pre-fix replays are rejected as incompatible.
- Replay GIF renderer gained `--from <frame>`, `--max-frames <n>` and `--auto-fire` options, plus a
  `--replay-verify` diagnostic.
- Note: faithful replay requires the exact binary that recorded the run — a rebuilt binary can drift
  (floating-point reproducibility is binary-specific). In-app replays and GIFs from the same
  installed build are reliable.

## [0.11.0] — 2026-06-24
- Deterministic replay system: every run is recorded (seed + inputs) and the simulation is now
  bit-exact reproducible. High-score runs can be watched again in-app — press 1–5 on the title
  screen to replay an entry; ESC exits.
- Headless GIF rendering: turn a replay into a clean, cursor-free animated GIF from the command
  line (`exploids --render-replay <file> --out <gif>`, plus `--export-replay` and `--render-demo`).
- Under the hood: seeded PRNG for all gameplay randomness and a single accumulated game-time
  clock (no more wall-clock reads in the gameplay path), which also makes the test suite
  deterministic.

## [0.6.1] — 2026-06-20
- Pixel font (Press Start 2P) for the EXPLOIDS / GAME OVER headings.
- High-score name entry fix (first responder).
- Reworked object glossary: every power-up listed individually, with a title strip.
- Fixes: extra life with gravity wells, entzerrtes start-screen layout, "#" extra-life cheat (for testing).

## [0.6.0] — 2026-06-19
- Two selectable game modes: **Ancient Asteroids** (classic) and **Mad Meteoroids** (rotating field).
- Four new power-ups: Rear, Compress, Extra Life and Laser beam.
- App icon (ship + flame) and chiptune background music with an M toggle.
- Flatter difficulty curve; asteroids now reliably fly in from the screen edge instead of spawning mid-screen.
