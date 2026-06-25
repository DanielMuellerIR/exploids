# Changelog

All notable changes to Exploids. Dates are ISO 8601 (YYYY-MM-DD).

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
