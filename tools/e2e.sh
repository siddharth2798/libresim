#!/usr/bin/env bash
# End-to-end QA sweep: unit tests, start screen, every airport start, views, time of
# day, weather, gameplay, failures, nav, panels, save/load, replay, recording,
# performance and reference screenshots. Needs a display (windows open briefly).
#   tools/e2e.sh [run-name] [filter]     e.g. tools/e2e.sh run1 ; tools/e2e.sh dbg rwy_VABB
# Output: /tmp/e2e/<run>/ (logs, results, shots), report /tmp/e2e/report.md
# (also /tmp/e2e/<run>/report.md). Reference screenshots: /tmp/e2e/ref (made on first run).
# Env: E2E_JOBS=3 parallel game instances; GODOT=~/.local/bin/godot.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN="${1:-run$(date +%H%M)}"
FILTER="${2:-}"
GODOT="${GODOT:-$HOME/.local/bin/godot}"
PAR="${E2E_JOBS:-3}"
BASE=/tmp/e2e
OUT="$BASE/$RUN"
PY="$ROOT/tools/.venv/bin/python"
[ -x "$PY" ] || PY=python3
USERDIR="$HOME/.local/share/godot/app_userdata/libresim"
rm -rf "$OUT"; mkdir -p "$OUT/logs" "$OUT/results" "$OUT/shots" "$OUT/rec" "$BASE/ref" "$OUT/backup"
echo "e2e: run $RUN -> $OUT ($(cd "$ROOT" && git log -1 --format='%h %s' | cut -c1-80))"
git -C "$ROOT" log -1 --format='%H %ci %s' > "$OUT/git.txt"
git -C "$ROOT" status --short >> "$OUT/git.txt"

# keep the player's own setup and quick-save: the sweep changes them
cp -a "$USERDIR/last_flight.json" "$USERDIR/graphics.cfg" "$USERDIR/options.cfg" "$OUT/backup/" 2>/dev/null
[ -d "$USERDIR/saves" ] && cp -a "$USERDIR/saves" "$OUT/backup/saves"
restore() {
	cp -a "$OUT/backup/last_flight.json" "$OUT/backup/graphics.cfg" "$OUT/backup/options.cfg" "$USERDIR/" 2>/dev/null
	if [ -d "$OUT/backup/saves" ]; then rm -rf "$USERDIR/saves"; cp -a "$OUT/backup/saves" "$USERDIR/saves"; fi
}
trap restore EXIT

# refresh the import / class_name cache first: new class_name files from other work
# would otherwise give "Could not find type" parse errors in a non-editor run
timeout 300 "$GODOT" --headless --path "$ROOT/game" --import > "$OUT/logs/import.log" 2>&1

if [ -z "$FILTER" ] || [ "$FILTER" = unit ]; then
	echo "e2e: unit tests"
	timeout 900 "$GODOT" --headless --path "$ROOT/game" res://tests/run_tests.tscn > "$OUT/logs/unit_tests.log" 2>&1
	echo $? > "$OUT/logs/unit_tests.exit"
fi
if [ -z "$FILTER" ] || [ "$FILTER" = menu ]; then
	echo "e2e: start screen"
	E2E_OUT="$OUT" E2E_PHASE=1 timeout 180 "$GODOT" --path "$ROOT/game" res://tests/e2e/e2e_menu.tscn > "$OUT/logs/menu_phase1.log" 2>&1
	cp "$OUT/logs/menu_phase1.log" "$OUT/logs/menu_fly.log"
	E2E_OUT="$OUT" E2E_PHASE=2 timeout 120 "$GODOT" --path "$ROOT/game" res://tests/e2e/e2e_menu.tscn > "$OUT/logs/menu_phase2.log" 2>&1
fi

"$PY" "$ROOT/tools/e2e_jobs.py" ${FILTER:+"$FILTER"} > "$OUT/jobs.tsv"
run_job() {  # tag expect args(|-separated)
	local tag="$1" args="$3"
	IFS='|' read -r -a a <<< "$args"
	local t0=$(date +%s)
	timeout 600 "$GODOT" --path "$ROOT/game" res://tests/e2e/e2e_runner.tscn -- "${a[@]}" \
		--e2e_out="$OUT" --e2e_tag="$tag" > "$OUT/logs/$tag.log" 2>&1
	local rc=$?
	echo "$rc $(( $(date +%s) - t0 ))" > "$OUT/logs/$tag.exit"
	echo "  $tag rc=$rc $(( $(date +%s) - t0 ))s $(grep -c '^E2E FAIL' "$OUT/logs/$tag.log") failed"
}
echo "e2e: $(grep -c . "$OUT/jobs.tsv") jobs, $PAR in parallel"
while IFS=$'\t' read -r grp tag exp args; do
	[ "$grp" = perf ] && continue
	run_job "$tag" "$exp" "$args" &
	while [ "$(jobs -rp | wc -l)" -ge "$PAR" ]; do wait -n; done
done < "$OUT/jobs.tsv"
wait
while IFS=$'\t' read -r grp tag exp args; do  # performance: alone, nothing else of ours running
	[ "$grp" = perf ] && run_job "$tag" "$exp" "$args"
done < "$OUT/jobs.tsv"

"$PY" "$ROOT/tools/e2e_report.py" "$OUT"
cp "$OUT/report.md" "$BASE/report.md"
echo "e2e: report $BASE/report.md"
