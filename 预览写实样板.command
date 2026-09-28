#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec sh "$task_root/scripts/godot.sh" --resolution 1440x900 --position 80,80 res://scenes/cinematic_sample.tscn "$@"
