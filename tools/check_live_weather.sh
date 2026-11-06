#!/bin/sh
# Real live-weather calls for the owner's airports. Prints the source line and the mapped keys.
# Not used by the test suite or by tools/e2e.sh.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$HOME/.local/bin/godot}"
exec "$GODOT" --headless --path "$ROOT/game" res://tests/check_live_weather.tscn
