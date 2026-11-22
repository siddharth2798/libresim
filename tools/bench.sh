#!/usr/bin/env bash
# Graphics benchmark: frame times for fixed showcase scenes on each graphics preset and renderer.
# Each run is a separate windowed game (tests/debug_showcase.gd --bench=<s>) that waits for streaming
# to settle, measures with vsync off, then saves a screenshot tagged with preset and renderer.
# Needs a display and the generated data. Close other GPU-heavy apps and Godot runs first.
#   tools/bench.sh                         default matrix (below)
#   PRESETS="high max" RENDERERS=forward_plus SCENES=ghats_chase tools/bench.sh
#   DRIVER=vulkan tools/bench.sh           macOS: through MoltenVK, which has GPU timestamps (Metal shows n/a)
#   AA=fxaa FREESIM_BENCH=/tmp/b-fxaa tools/bench.sh   force the edge filter (smaa | fxaa | off, core/screen_aa.gd --aa=)
#   DRIVER=vulkan GPU_PROFILE=1 tools/bench.sh   + GPU ms of the tonemap / SMAA / scaling passes (passes= column, tests/bench_passes.gd)
# Env: FREESIM_BENCH=/tmp/libresim-bench (logs, PNGs, bench.md), BENCH_S=10, SIZE=1920x1080, GODOT, DRIVER,
#   EXTRA="--no-occlusion --no-vis-ranges" (more game args after --, e.g. the "before" of graphics Phase 2; use another
#   FREESIM_BENCH folder per variant to keep its screenshots).
# Every run is muted (--audio-driver Dummy).
# Vsync: --disable-vsync, and bench_probe.gd switches it off at run time too (the flag alone does not
# always stick on macOS 4.7.2); columns: game/tests/bench_probe.gd.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$HOME/.local/bin/godot}"
OUT="${FREESIM_BENCH:-/tmp/libresim-bench}"
SCENES="${SCENES:-vabb_final_golden ghats_chase cloud_bright_c172 night_approach}"
PRESETS="${PRESETS:-low medium high ultra}"
RENDERERS="${RENDERERS:-mobile forward_plus}"
BENCH_S="${BENCH_S:-10}"
EXTRA="${EXTRA:-}"
SIZE="${SIZE:-1920x1080}"
DRIVER_ARGS=()
[ -n "${DRIVER:-}" ] && DRIVER_ARGS=(--rendering-driver "$DRIVER")
[ -n "${GPU_PROFILE:-}" ] && DRIVER_ARGS+=(--gpu-profile)
USER_ARGS=()
[ -n "${AA:-}" ] && USER_ARGS=(--aa="$AA")
if [ "$(uname)" = Darwin ]; then USERDIR="$HOME/Library/Application Support/Godot/app_userdata/libresim"
else USERDIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/libresim"; fi
mkdir -p "$OUT/.backup"
cp -a "$USERDIR"/*.cfg "$OUT/.backup/" 2>/dev/null
trap 'cp -a "$OUT/.backup"/*.cfg "$USERDIR/" 2>/dev/null' EXIT  # the runs must not change the user's settings
export FREESIM_SHOTS="$OUT" FREESIM_SIZE="$SIZE"
"$GODOT" --headless --audio-driver Dummy --path "$ROOT/game" --import > "$OUT/import.log" 2>&1
[ -n "${APPEND:-}" ] || : > "$OUT/bench.log"  # APPEND=1 keeps earlier rows (before / after runs)
for r in $RENDERERS; do
	for p in $PRESETS; do
		for s in $SCENES; do
			echo "bench: $s $p $r"
			"$GODOT" --audio-driver Dummy --path "$ROOT/game" --rendering-method "$r" ${DRIVER_ARGS[@]+"${DRIVER_ARGS[@]}"} --disable-vsync \
				--resolution "$SIZE" --windowed res://tests/debug_showcase.tscn \
				-- --scene="$s" --quality="$p" --bench="$BENCH_S" ${USER_ARGS[@]+"${USER_ARGS[@]}"} $EXTRA > "$OUT/${s}_${p}_${r}.log" 2>&1
			grep -h "^BENCH" "$OUT/${s}_${p}_${r}.log" | sed "s/\$/ extra=${EXTRA// /,}/" | tee -a "$OUT/bench.log" || echo "bench: $s $p $r FAILED (see $OUT/${s}_${p}_${r}.log)"
		done
	done
done
{
	echo "| scene | preset | renderer | extra | fps | frame ms avg | p95 | p99 | GPU ms avg | GPU p95 | CPU ms | objects | draws |"
	echo "|---|---|---|---|---|---|---|---|---|---|---|---|---|"
	awk '{ delete v; for (i = 2; i <= NF; i++) { split($i, kv, "="); v[kv[1]] = kv[2] }
		printf "| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |\n", v["scene"], v["preset"], v["renderer"] "/" v["driver"], v["extra"], v["fps"], v["ms_avg"], v["ms_p95"], v["ms_p99"], v["gpu_avg"], v["gpu_p95"], v["cpu_avg"], v["objects"], v["draws"] }' "$OUT/bench.log"
} > "$OUT/bench.md"
cat "$OUT/bench.md"
