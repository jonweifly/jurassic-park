#!/bin/sh
set -eu
task_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec sh "$task_root/scripts/godot.sh" "$@"
