#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_godot="$task_root/.tools/Godot.app/Contents/MacOS/Godot"
if [ ! -x "$task_godot" ]; then
  if command -v godot >/dev/null 2>&1; then
    task_godot=$(command -v godot)
  elif [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then
    task_godot=/Applications/Godot.app/Contents/MacOS/Godot
  else
    echo 'Godot 4 is required. Install from https://godotengine.org/download/ or open godot/project.godot in the editor.' >&2
    exit 1
  fi
fi
exec "$task_godot" --path "$task_root/godot" "$@"
