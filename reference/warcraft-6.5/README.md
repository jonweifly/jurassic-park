# Local research reference only

Retrieved 2026-09-15 from https://www.cr173.com/soft/427952.html and its published ZIP URL https://cz.197942.com/tcy/zlj65zqhh.zip .

- ZIP SHA256: `d9612e0eed2c5ac2d13e7eb769d9d318b0d607ec6e7bd6fa81e6947bf753d619`
- W3X SHA256: `64d883c68d5195ada51ce3d0bcce50efde45c97dbd6c3590b63beffc3e17ecf7`
- ZIP member: `侏罗纪公园6.5增强汉化版.w3x`.
- Internal title: `侏罗纪公园增强版V6.5汉化修正版`.

This candidate contains additional cheat scripts and is **not verified as a pristine official distribution**. Files were inspected as data only. Do not execute the map or include the archive, JASS, textures, models, or source data in the Godot client distribution.

`war3map.*` were extracted read-only with the Python MPQ reader `mpyq` plus the standard MPQ sector decryption algorithm for `war3map.j`. No gameplay scripts were executed. `parse_objects.py` reads the extracted binary object modifications and WTS strings using the Python standard library. JSON null means an unmodified inherited Warcraft field, not zero.

Detailed facts and caveats: `../../docs/research/jurassic-park-6.5-reference.md`.

2026-09-16: additionally read `war3map.doo` (342,490 bytes) and `war3map.wpm` (262,160 bytes) from the same MPQ, without executing map code. `doodads.json` records decoded placement metadata. Derived coordinate layout is used by original Godot blockout meshes; no Warcraft mesh or texture assets are bundled. See `../../docs/research/jurassic-park-terrain-import.md` for coordinate transforms, approximations and checks.
