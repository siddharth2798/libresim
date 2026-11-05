#!/bin/bash
# Visual hardware check of the Thrustmaster Captain Pack on the A320 (tests/check_a320_controls.gd): a window with a
# checklist of every control; each ticks when the game responds correctly. Press Complete when done: the report of
# what was ticked is written to /tmp/a320_check_report.txt (or the path given as the first argument).
#   ./tools/check_a320_controls.sh [report-path] [--air]
cd "$(dirname "$0")/.." || exit 1
GODOT="${GODOT:-$HOME/.local/bin/godot}"
REPORT="${1:-/tmp/a320_check_report.txt}"
[ "$(uname)" = "Darwin" ] && export SDL_JOYSTICK_MFI=0 SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1
shift 2>/dev/null
exec "$GODOT" --path game --windowed --resolution 1280x720 --audio-driver Dummy res://tests/check_a320_controls.tscn -- --out="$REPORT" "$@"
