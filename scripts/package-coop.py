#!/usr/bin/env python3
"""Package only the runtime project and friend-facing guide, never workspace data."""
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / 'godot'
OUT = PROJECT / 'builds' / 'LostIsle-Coop-Source-Preview.zip'
PACKAGE_ROOT = 'LostIsle'
EXCLUDED = {'.godot', 'builds', 'captures', 'tests', 'tools'}
IMPORT_TOOLS = {'tools/asset_post_import.gd', 'tools/asset_post_import.gd.uid'}
REMOVED_MAP_FILES = {'data/terrain.json', 'scenes/reference_island.tscn'}
OUT.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(OUT, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for file in sorted(PROJECT.rglob('*')):
        rel = file.relative_to(PROJECT)
        if not file.is_file() or file.is_symlink():
            continue
        if any(part in EXCLUDED for part in rel.parts) and rel.as_posix() not in IMPORT_TOOLS:
            continue
        if file.name in {'.DS_Store', 'README.md'} or rel.as_posix() in REMOVED_MAP_FILES:
            continue
        archive.write(file, PACKAGE_ROOT + '/godot/' + rel.as_posix())
    archive.write(ROOT / 'docs/coop-play.md', PACKAGE_ROOT + '/先读我-双人合作.md')
    archive.write(ROOT / 'docs/release/asset-license-audit.md', PACKAGE_ROOT + '/发行前审计.md')
with zipfile.ZipFile(OUT) as archive:
    assert archive.testzip() is None
    assert PACKAGE_ROOT + '/godot/project.godot' in archive.namelist()
    assert PACKAGE_ROOT + '/godot/data/maps/organic_island_v3.json' in archive.namelist()
    assert not any(name.endswith(('/data/terrain.json', '/scenes/reference_island.tscn')) for name in archive.namelist())
    assert PACKAGE_ROOT + '/godot/tools/asset_post_import.gd' in archive.namelist()
    assert all(not any(part in EXCLUDED for part in Path(name).parts)
               or name.removeprefix(PACKAGE_ROOT + '/godot/') in IMPORT_TOOLS
               for name in archive.namelist())
print(f'{OUT}\n{OUT.stat().st_size / 1024 / 1024:.1f} MiB')
