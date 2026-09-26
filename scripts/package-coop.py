#!/usr/bin/env python3
"""Package only the runtime project and friend-facing guide, never workspace data."""
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / 'godot'
OUT = PROJECT / 'builds' / 'JurassicCamp-Coop-Source.zip'
EXCLUDED = {'.godot', 'builds', 'captures', 'tests', 'tools'}
IMPORT_TOOLS = {'tools/asset_post_import.gd', 'tools/asset_post_import.gd.uid'}
OUT.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(OUT, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for file in sorted(PROJECT.rglob('*')):
        rel = file.relative_to(PROJECT)
        if not file.is_file() or file.is_symlink():
            continue
        if any(part in EXCLUDED for part in rel.parts) and rel.as_posix() not in IMPORT_TOOLS:
            continue
        if file.name in {'.DS_Store', 'README.md'}:
            continue
        archive.write(file, 'JurassicCamp/godot/' + rel.as_posix())
    archive.write(ROOT / 'docs/coop-play.md', 'JurassicCamp/先读我-双人合作.md')
with zipfile.ZipFile(OUT) as archive:
    assert archive.testzip() is None
    assert 'JurassicCamp/godot/project.godot' in archive.namelist()
    assert 'JurassicCamp/godot/data/terrain.json' in archive.namelist()
    assert 'JurassicCamp/godot/tools/asset_post_import.gd' in archive.namelist()
    assert all(not any(part in EXCLUDED for part in Path(name).parts)
               or name.removeprefix('JurassicCamp/godot/') in IMPORT_TOOLS
               for name in archive.namelist())
print(f'{OUT}\n{OUT.stat().st_size / 1024 / 1024:.1f} MiB')
