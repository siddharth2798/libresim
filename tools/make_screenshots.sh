#!/usr/bin/env bash
# README screenshots: real in-game captures at 1920x1080 on the Ultra graphics preset, saved as
# docs/screenshots/NN-name.jpg (1600x900, quality 85). Each scene is a separate game run
# (game/tests/debug_showcase.gd, scene list in game/tests/showcase_scenes.gd) that waits for the
# terrain, trees and buildings to finish streaming before it saves a PNG. Needs a display and the
# generated data (docs/USAGE.md); windows open briefly, one after the other.
#   tools/make_screenshots.sh              all scenes
#   tools/make_screenshots.sh monsoon ...  only these scenes (names as in SHOTS below)
# Env: FREESIM_SHOTS=/tmp/libresim-shots  raw PNG folder; GODOT=~/.local/bin/godot.
# Your settings are backed up first and restored at the end (the capture reads no saved options:
# graphics come from --quality=ultra, the flight from the scene definition).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$HOME/.local/bin/godot}"
PY="$ROOT/tools/.venv/bin/python"
[ -x "$PY" ] || PY=python3
export FREESIM_SHOTS="${FREESIM_SHOTS:-/tmp/libresim-shots}"
export FREESIM_SIZE=1920x1080
DEST="$ROOT/docs/screenshots"
USERDIR="$HOME/.local/share/godot/app_userdata/libresim"
BACKUP="$FREESIM_SHOTS/.backup"

# scene name : final file name (the order of the README gallery)
SHOTS=(
	"vabb_final_golden:01-vabb-golden-hour-final"
	"ghats_chase:02-western-ghats"
	"night_approach:03-night-approach"
	"vabb_terminal:04-mumbai-terminal"
	"voci_stand:05-kochi-gate"
	"monsoon:06-monsoon-approach"
	"training_landing:07-training-landing"
	"moving_map:08-moving-map"
	"start_home:09-start-screen"
	"start_flight:10-airport-picker"
)

mkdir -p "$FREESIM_SHOTS" "$BACKUP" "$DEST"
rm -rf "$BACKUP"/*
cp -a "$USERDIR"/*.cfg "$USERDIR"/*.json "$BACKUP/" 2>/dev/null
[ -d "$USERDIR/saves" ] && cp -a "$USERDIR/saves" "$BACKUP/saves"
restore() {
	cp -a "$BACKUP"/*.cfg "$BACKUP"/*.json "$USERDIR/" 2>/dev/null
	[ -d "$BACKUP/saves" ] && { rm -rf "$USERDIR/saves"; cp -a "$BACKUP/saves" "$USERDIR/saves"; }
}
trap restore EXIT

timeout 300 "$GODOT" --headless --path "$ROOT/game" --import > "$FREESIM_SHOTS/import.log" 2>&1

for entry in "${SHOTS[@]}"; do
	scene="${entry%%:*}"
	if [ $# -gt 0 ] && [[ ! " $* " == *" $scene "* ]]; then continue; fi
	echo "screenshots: $scene"
	rm -f "$FREESIM_SHOTS/$scene.png"
	timeout 400 "$GODOT" --path "$ROOT/game" --resolution 1920x1080 --windowed res://tests/debug_showcase.tscn \
		-- --scene="$scene" --quality=ultra > "$FREESIM_SHOTS/$scene.log" 2>&1
	grep -E "SETTLED|SHOT|ERROR|WARNING" "$FREESIM_SHOTS/$scene.log" | head -5
	[ -f "$FREESIM_SHOTS/$scene.png" ] || echo "screenshots: $scene FAILED (see $FREESIM_SHOTS/$scene.log)"
done

"$PY" - "$FREESIM_SHOTS" "$DEST" "${SHOTS[@]}" <<'EOF'
import sys
from pathlib import Path
from PIL import Image
src, dest, shots = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3:]
total = 0
for s in shots:
    scene, name = s.split(":")
    png = src / (scene + ".png")
    if not png.exists():
        continue
    out = dest / (name + ".jpg")
    Image.open(png).convert("RGB").resize((1600, 900), Image.LANCZOS).save(out, "JPEG", quality=85, optimize=True, progressive=True)
    total += out.stat().st_size
    print(f"  {out.name}: {out.stat().st_size // 1024} KB")
print(f"screenshots: {total / 1e6:.2f} MB in {dest}")
EOF
