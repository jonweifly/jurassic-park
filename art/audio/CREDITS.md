# Dinosaur voice sources

Author: **CaveboyTup**. Both source works are published under **CC0 1.0** (https://creativecommons.org/publicdomain/zero/1.0/).

- **T-rex Calls**: https://opengameart.org/content/t-rex-calls
  - File: `sources/t-rex_calls.mp3`
  - Author describes the work as made with CC0 samples of alligator, lion and elk.
- **Small Dino Raspy Calls**: https://opengameart.org/content/small-dino-raspy-calls
  - File: `sources/small_dino_raspy_calls.mp3`
  - Author describes the work as synthesized from CC0 horse snorts.

Retrieved 2026-09-19. Original pages, exact download URLs and SHA-256 checksums are kept in `sources/` and `sources/licenses.json`.

Game adaptations: selected and crossfaded roar/exhalation excerpts, moderate speed changes for body size, sub-rumble removal, presence EQ, soft compression, loudness normalization and endpoint fades. The four species / two variants are built reproducibly by `art/scripts/build_dinosaur_audio.py`. `dinosaur-manifest.json` records the resulting sources, duration, level and hashes. These are designed creature effects based on animal samples, not recordings of prehistoric dinosaurs or audio copied from a film.

The previous oscillator-generated dinosaur calls have been retired. `generate_environment_media.py` now only builds weather audio and terrain material channels and cannot overwrite these calls.
