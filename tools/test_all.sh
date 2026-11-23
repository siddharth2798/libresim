#!/usr/bin/env bash
# Runs libresim's whole test suite in parallel, sized to this computer (game/tests/parallel/run_parallel.gd):
# one headless, muted Godot worker per logical core minus one, capped by free memory and by the jobs queued,
# longest jobs first (timings kept in .cache/tests/timings.json). Exit code 0 only when every test passed.
#   tools/test_all.sh                 auto-size
#   TEST_JOBS=2 tools/test_all.sh     force 2 workers; TEST_JOBS=1 is the plain single process
# Windows or no bash: godot --headless --audio-driver Dummy --path game -s res://tests/parallel/run_parallel.gd
# Env: GODOT=<path to Godot 4.7> (default ~/.local/bin/godot, then godot on PATH).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$HOME/.local/bin/godot}"
[ -x "$GODOT" ] || GODOT="$(command -v godot || true)"
if [ -z "$GODOT" ]; then echo "test_all: Godot not found (set GODOT=...)" >&2; exit 2; fi
# Godot exits 0 even when the launcher script fails to load, so success also needs the launcher's last line.
LOG="$(mktemp "${TMPDIR:-/tmp}/libresim_tests.XXXXXX")"
"$GODOT" --headless --audio-driver Dummy --path "$ROOT/game" -s res://tests/parallel/run_parallel.gd -- "$@" 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
if ! grep -qE '^(all passed|FAILED) in ' "$LOG"; then
	echo "test_all: the launcher did not finish (see the errors above)" >&2
	[ "$rc" -eq 0 ] && rc=2
fi
rm -f "$LOG"
exit "$rc"
