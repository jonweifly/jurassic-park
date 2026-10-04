#!/usr/bin/env python3
"""Export and package Godot 4.4.1 internal previews for desktop platforms."""
import argparse
import plistlib
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GODOT = ROOT / '.tools/Godot.app/Contents/MacOS/Godot'
BUILD = ROOT / 'godot/builds'
PLATFORMS = {
    'macos': ('macOS', 'macos-export.zip', 'LostIsle-macOS-Internal-Preview.zip'),
    'windows': ('Windows Desktop', 'LostIsle-Preview.exe', 'LostIsle-Windows-Internal-Preview.zip'),
    'linux': ('Linux/X11', 'LostIsle-Preview.x86_64', 'LostIsle-Linux-Internal-Preview.zip'),
}
NOTICES = [
    ('docs/release/preview-readme.md', '先读我-内部试玩.md'),
    ('docs/release/asset-license-audit.md', '发行前审计.md'),
    ('docs/release/third-party-notices.md', '第三方许可.md'),
    ('art/audio/CREDITS.md', '恐龙音效来源.md'),
]


def check_engine() -> None:
    if not GODOT.is_file():
        raise SystemExit('Godot 4.4.1 is required at .tools/Godot.app')
    version = subprocess.check_output([str(GODOT), '--version'], text=True).strip()
    if not version.startswith('4.4.1.'):
        raise SystemExit(f'Expected Godot 4.4.1, found {version}')
    templates = Path.home() / 'Library/Application Support/Godot/export_templates/4.4.1.stable'
    if not (templates / 'version.txt').is_file():
        raise SystemExit('Install matching Godot 4.4.1 export templates before packaging')


def export(platform: str, stage: Path) -> Path:
    preset, name, _ = PLATFORMS[platform]
    target = stage / name
    subprocess.run(
        ['sh', str(ROOT / 'scripts/godot.sh'), '--headless', '--export-release', preset, str(target)],
        cwd=ROOT,
        check=True,
        stdout=subprocess.DEVNULL,
    )
    if not target.is_file() or target.stat().st_size < 100_000:
        raise SystemExit(f'{preset} export is missing or unexpectedly small')
    return target


def package(platform: str) -> Path:
    _, _, zip_name = PLATFORMS[platform]
    BUILD.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='lost-isle-preview-') as temp:
        stage = Path(temp)
        exported = export(platform, stage)
        bundle = stage / Path(zip_name).stem
        bundle.mkdir()
        if platform == 'macos':
            subprocess.run(['ditto', '-x', '-k', str(exported), str(stage / 'macos-extracted')], check=True)
            apps = list((stage / 'macos-extracted').glob('*.app'))
            if len(apps) != 1:
                raise SystemExit('Expected exactly one macOS app in the official export')
            app = bundle / 'LostIsle-Preview.app'
            apps[0].rename(app)
            info_path = app / 'Contents/Info.plist'
            with info_path.open('rb') as stream:
                info = plistlib.load(stream)
            info.update({
                'CFBundleDisplayName': '失落岛屿：生存营地',
                'CFBundleIdentifier': 'com.lostisle.survivalcamp.preview',
                'LSApplicationCategoryType': 'public.app-category.games',
            })
            with info_path.open('wb') as stream:
                plistlib.dump(info, stream)
            subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(app)], check=True)
            subprocess.run(['codesign', '--verify', '--deep', str(app)], check=True)
        else:
            shutil.move(exported, bundle / exported.name)
            pack = exported.with_suffix('.pck')
            if not pack.is_file():
                raise SystemExit(f'{platform} export is missing its PCK sidecar')
            shutil.move(pack, bundle / pack.name)
        for source, name in NOTICES:
            shutil.copy2(ROOT / source, bundle / name)
        archive_path = BUILD / zip_name
        if platform == 'macos':
            subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(bundle), str(archive_path)], check=True)
        else:
            with zipfile.ZipFile(archive_path, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
                for file in sorted(bundle.rglob('*')):
                    if file.is_file():
                        archive.write(file, file.relative_to(stage))
            with zipfile.ZipFile(archive_path) as archive:
                if archive.testzip() is not None:
                    raise SystemExit(f'{platform} preview archive failed CRC verification')
        return archive_path


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=['all', *PLATFORMS], default='all')
    parser.add_argument('--publish', action='store_true', help='Reserved for a fully cleared commercial build')
    args = parser.parse_args()
    if args.publish:
        parser.error('Public release is blocked: asset authorship, target-platform QA and store rights checks remain open')
    check_engine()
    for platform in PLATFORMS if args.platform == 'all' else [args.platform]:
        result = package(platform)
        print(f'{result} ({result.stat().st_size / 1024 / 1024:.1f} MiB)')
