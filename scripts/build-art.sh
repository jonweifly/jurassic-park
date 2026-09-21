#!/bin/sh
# Reproducible source -> native runtime assets. Does not change the baked map or gameplay.
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$task_root"
task_blender="$task_root/.tools/Blender.app/Contents/MacOS/Blender"
"$task_blender" --background --python-exit-code 1 --python art/scripts/build_assets.py
cp art/textures/expedition_albedo.png godot/assets/materials/expedition_albedo.png
cp art/textures/expedition_roughness.png godot/assets/materials/expedition_roughness.png
cp art/textures/expedition_normal.png godot/assets/materials/expedition_normal.png
mkdir -p .tools/optimized
for model in godot/assets/models/*.glb; do
 name=$(basename "$model")
 npx --yes @gltf-transform/cli@4.5.0 dedup "$model" ".tools/optimized/$name"
 npx --yes @gltf-transform/cli@4.5.0 tangents ".tools/optimized/$name" "$model"
done
python3 art/scripts/package_assets.py
python3 art/scripts/validate_glb.py
python3 art/scripts/integrate_assets.py
sh scripts/godot.sh --headless --editor --import
sh scripts/godot.sh --headless --script res://tests/production_assets_test.gd
