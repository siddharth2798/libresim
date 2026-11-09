#!/usr/bin/env bash
# Shoots the loader films (game/tests/showcase_film_scenes.gd) into game/ui/loader/<aircraft>_<place>/NNN.jpg:
# 5 s at 24 fps, 1600x900, Max preset, game time locked to the frame rate (--fixed-fps). Needs a visible window:
# an occluded or locked screen stops presenting and the frame grab waits forever. Then imports the frames.
#   tools/shoot_loader_films.sh [scene ...]     (default: all six)
set -euo pipefail
cd "$(dirname "$0")/../game"
GODOT="${GODOT:-$HOME/.local/bin/godot}"
SCENES=("$@")
[ ${#SCENES[@]} -eq 0 ] && SCENES=(a320_ghats c172_ghats a320_cochin c172_cochin a320_gate c172_gate)  # clip names
for s in "${SCENES[@]}"; do
  rm -rf "ui/loader/$s"
  FREESIM_SHOTS="$PWD/ui/loader" "$GODOT" --path . --fixed-fps 24 --audio-driver Dummy res://tests/debug_showcase.tscn -- \
    --scene="film_$s" --quality=max --film=5 2>&1 | grep -E "^FILM|ERROR" || true
done
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
du -sh ui/loader/*
