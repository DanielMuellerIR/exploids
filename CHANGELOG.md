# Changelog

All notable changes to Exploids. Dates are ISO 8601 (YYYY-MM-DD).

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
