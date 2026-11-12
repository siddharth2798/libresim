#!/usr/bin/env bash
# Tests for run.sh and its helpers (tools/run_stale.sh, run_progress.sh, run_raw.sh, code_hash.py).
# Plain bash, no network, no installs, never touches data/: everything runs in a temp dir.
#   tools/test_run_sh.sh
set -Eeuo pipefail
if ((BASH_VERSINFO[0] < 4)); then
  for b in /opt/homebrew/bin/bash /usr/local/bin/bash; do [[ -x $b ]] && exec "$b" "$0" "$@"; done
  echo "needs bash 4 or newer"; exit 1
fi
cd "$(dirname "$0")/.."
REPO=$PWD
T=$(mktemp -d "${TMPDIR:-/tmp}/run_sh_test.XXXXXX")
trap '[[ -n ${KEEP:-} ]] && echo "kept: $T" || rm -rf "$T"' EXIT   # KEEP=1 keeps the temp dir
FAILS=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1"; FAILS=$((FAILS + 1)); }
check() { local what=$1; shift; if "$@"; then ok "$what"; else bad "$what"; fi; }
has() { grep -q -- "$1" "$2"; }

echo "== (i) syntax"
for f in run.sh tools/run_stale.sh tools/run_progress.sh tools/run_raw.sh tools/test_run_sh.sh; do
  check "bash -n $f" bash -n "$f"
done

echo "== (ii) first-run plan in a scratch copy (empty data/, offline: built-in size estimates)"
S=$T/scratch; mkdir -p "$S/tools" "$T/home/.local/bin"
cp run.sh "$S/"; cp tools/run_stale.sh tools/run_progress.sh tools/run_raw.sh tools/code_hash.py tools/requirements.txt \
  tools/22_a320_fetch.sh tools/01d_fetch_corridor.py "$S/tools/"
printf '#!/bin/sh\necho 4.7.2.stable.official.test\n' >"$T/home/.local/bin/godot"; chmod +x "$T/home/.local/bin/godot"
(cd "$S" && HOME=$T/home RUN_OFFLINE=1 ./run.sh --dry-run --a320 >"$T/plan.txt" 2>&1) || bad "dry run exited non-zero"
sed -n '/\[2\/8\] Plan/,/\[3\/8\]/p' "$T/plan.txt" | sed '$d'
check "plan lists the raw data and a total" has "Total to download: about" "$T/plan.txt"
check "plan says the sizes are estimates when offline" has "RUN_OFFLINE=1: sizes are built-in estimates" "$T/plan.txt"
check "plan lists steps with expected time" has "Expected total: about" "$T/plan.txt"
check "plan includes the A320 data with --a320" has "A320-family" "$T/plan.txt"
check "plan includes the Godot import" has "Godot first-run import" "$T/plan.txt"
check "dry run asked nothing" bash -c "! grep -q 'Continue?' '$T/plan.txt'"
check "dry run wrote only data/run.log" test "$(cd "$S" && find data -type f | sort)" = "data/run.log"
(cd "$S" && HOME=$T/home RUN_OFFLINE=1 ./run.sh --dry-run --region=mumbai_pune >"$T/plan2.txt" 2>&1) || bad "second dry run exited non-zero"
check "--region=mumbai_pune leaves out the corridor" bash -c "! grep -q 'Konkan-Kerala corridor, tools' '$T/plan2.txt' || grep -q 'skip  corridor (--region' '$T/plan2.txt'"
check "no stamps or hashes written" test ! -e "$S/data/.stamps"

echo "== (iii) a comment edit does not make a step stale, a code edit does"
W=$T/work; mkdir -p "$W/tools" "$W/data/raw" "$W/data/.stamps"; cp tools/code_hash.py "$W/tools/"
cat >"$W/tools/x.py" <<'EOF'
"""Step x: does a thing."""
# a comment
def f(a):
    """doc"""
    return a + 1
EOF
echo '{}' >"$W/data/out.json"; echo 'a,b' >"$W/data/raw/in.csv"; touch "$W/data/.stamps/x.done"
touch -t 202001010000 "$W/tools/x.py" "$W/data/out.json" "$W/data/raw/in.csv"; touch -t 202101010000 "$W/data/.stamps/x.done"
run_in_work() { ( cd "$W"; STAMPS=data/.stamps HASHPY=python3
  declare -A OUT=([x]="data/out.json") IN=([x]="tools/x.py data/raw/in.csv") DEP=() FORCE=()
  note() { echo "note: $*"; }; dry() { return 1; }
  source "$REPO/tools/run_stale.sh"; "$@" ); }
check "stamp without hash record: scripts count as unchanged" test -z "$(run_in_work why_run x)"
run_in_work migrate_hashes x | sed 's/^/    /'
check "hash file exists after migration" test -f "$W/data/.stamps/x.hashes"
check "second migration is silent" test -z "$(run_in_work migrate_hashes x)"
cat >"$W/tools/x.py" <<'EOF'
"""Step x: does a different thing, described at length."""

# a new comment, and a changed one
def f(a):
    """other doc"""

    return a+1   # formatting differs
EOF
touch -t 202201010000 "$W/tools/x.py"
check "comment/docstring/format edit (newer mtime): not stale" test -z "$(run_in_work why_run x)"
sed -i.bak 's/a+1/a+2/' "$W/tools/x.py"; rm -f "$W/tools/x.py.bak"; touch -t 202201020000 "$W/tools/x.py"
r=$(run_in_work why_run x); check "code edit: stale ($r)" test -n "$r"
sed -i.bak 's/a+2/a+1/' "$W/tools/x.py"; rm -f "$W/tools/x.py.bak"; touch -t 202201030000 "$W/tools/x.py"
check "code edit reverted: not stale again" test -z "$(run_in_work why_run x)"
touch -t 202301010000 "$W/data/raw/in.csv"
r=$(run_in_work why_run x); check "newer raw input still uses mtime ($r)" test -n "$r"
mkdir -p "$W/data/d"; touch -t 202001010000 "$W/data/d/a"; touch -t 202005010000 "$W/data/d/b"
r=$(run_in_work newest_file data/d); check "newest_file is portable and right ($r)" test "$r" = "data/d/b"
python3 tools/code_hash.py tools/code_hash.py | sed 's/^/    /'

echo "== (iv) heartbeat (RUN_HEARTBEAT=1, fake 3 s step)"
hb_env() {  # run a snippet with run_progress.sh loaded; fd 3 = $T/term.txt
  ( cd "$W"; LOG=$T/hb.log; : >"$LOG"; exec 3>"$T/term.txt"; HEARTBEAT=${HB:-1}
    note() { echo "$*"; }; source "$REPO/tools/run_progress.sh"; HEARTBEAT=${HB:-1}; "$@" ); }
: >"$T/term.txt"
hb_step() { PLAN_TOTAL_S=100; DONE_S=35; with_heartbeat "step 10" 1200 "" sleep 3; sleep 2; }
hb_env hb_step
n=$(grep -c 'running' "$T/term.txt"); sleep 2; n2=$(grep -c 'running' "$T/term.txt")
sed 's/^/    /' "$T/term.txt"
check "heartbeat printed lines while the step ran ($n)" test "$n" -ge 2
check "heartbeat printed nothing after the step ended" test "$n" = "$n2"
check "lines carry label, time, usual time and overall %" has 'step 10 running .* (usually about 20 min), overall' "$T/term.txt"
check "lines also in the log" has 'step 10 running' "$T/hb.log"
check "no background process left" test -z "$(pgrep -P $$ || true)"
printf 'Processing ... [1/1] : 0...10...20...30' >"$T/script.log"
hb_log() { with_heartbeat "imagery" 60 "$T/script.log" sleep 2; }
: >"$T/term.txt"; hb_env hb_log
check "heartbeat shows the last line of the script's own log" has 'imagery running .* | .*0\.\.\.10\.\.\.20\.\.\.30' "$T/term.txt"
: >"$T/term.txt"
hb_fail() { hb_start "x" 5; sleep 1; hb_stop; }
HB=17 hb_env hb_fail; sleep 1
check "no orphan sleep after hb_stop" test -z "$(pgrep -f 'sleep 17' || true)"
failing() { set -Ee; trap hb_stop EXIT; with_heartbeat "x" 5 "" false; }
(HB=17 hb_env failing) 2>/dev/null || true; sleep 1
check "no orphan sleep after a failing step (EXIT trap)" test -z "$(pgrep -f 'sleep 17' || true)"
cat >"$T/log" <<'EOF'
    (step 10: 80 s)
    (step 15: 191 s)
    (step 10: 1177 s)
EOF
lg() { LOG=$T/log; load_log_secs; echo "${LOGSECS[10]} ${LOGSECS[15]}"; }
check "latest (step NN: S s) of the log wins" test "$(hb_env lg)" = "1177 191"
pct() { PLAN_TOTAL_S=200; DONE_S=50; overall_pct 20 100; }
check "overall % = (done + running) / total" test "$(hb_env pct)" = "35"

echo "== (v) whole run in a scratch copy with stub curl, python and godot (nothing real is downloaded or built)"
V=$T/full; mkdir -p "$V/tools/.venv/bin" "$V/stubs" "$V/home/.local/bin"
cp run.sh "$V/"; cp tools/*.py tools/run_*.sh tools/requirements.txt tools/22_a320_fetch.sh "$V/tools/"
printf '#!/bin/sh\ncase "$*" in *--version*) echo 4.7.2.stable.official.test;; esac\nexit 0\n' >"$V/home/.local/bin/godot"
printf '#!/bin/sh\ncase "$*" in *10_buildings*) sleep 3;; esac\nexit 0\n' >"$V/tools/.venv/bin/python"
cat >"$V/stubs/curl" <<'STUB'
#!/bin/sh
# stub: HEAD (-I) answers 1000000 bytes; a download writes 1000000 bytes to the -o file
case "$*" in *-sIL*|*-I*) printf 'HTTP/1.1 200 OK\r\nContent-Length: 1000000\r\n\r\n'; exit 0;; esac
while [ $# -gt 0 ]; do [ "$1" = -o ] && { head -c 1000000 /dev/zero >"$2"; exit 0; }; shift; done
exit 0
STUB
# --yes also answers "install the missing system packages": make every package manager a no-op
printf '#!/bin/sh\ncase "$1" in --prefix) echo /nonexistent;; *) echo "stub $0 $*" >>"$(dirname "$0")/calls";; esac\nexit 0\n' >"$V/stubs/brew"
for c in sudo apt-get dnf pacman; do cp "$V/stubs/brew" "$V/stubs/$c"; done
chmod +x "$V/home/.local/bin/godot" "$V/tools/.venv/bin/python" "$V/stubs/"*
(cd "$V"; mkdir -p data/raw/dem data/raw/dem90 data/raw/osm data/raw/ourairports data/.stamps data/raw/jsbsim/src/aircraft/c172p data/raw/jsbsim/src/engine
 for t in N18_00_E072_00 N18_00_E073_00 N18_00_E074_00 N19_00_E072_00; do touch "data/raw/dem/Copernicus_DSM_COG_10_${t}_DEM.tif"; done   # two tiles missing
 for la in 16 17 18 19 20 21; do for lo in 70 71 72 73 74 75 76; do touch "data/raw/dem90/Copernicus_DSM_COG_30_N${la}_00_E0${lo}_00_DEM.tif"; done; done
 touch data/raw/osm/western-zone-latest.osm.pbf data/raw/ourairports/{airports,navaids,airport-frequencies}.csv   # runways.csv missing
 touch data/.stamps/01b.done data/.stamps/01c.done data/.stamps/01d.done)
(cd "$V" && PATH="$V/stubs:$PATH" HOME=$V/home RUN_HEARTBEAT=1 ./run.sh --yes --setup-only >"$T/full.txt" 2>&1) || bad "full run exited non-zero"
sed -n '/\[2\/8\]/,/\[3\/8\]/p;/\[4\/8\]/,/^\[6\/8\]/p;/Setup finished/p;/Starting libresim/p' "$T/full.txt" | grep -v '^    skip \|GET https\|^$\|^      \|^    run \|^    (step' | head -70
check "plan asked and --yes answered" has "Continue? \[y/N\] y (--yes)" "$T/full.txt"
check "plan counts 3 files to download (2 tiles + runways.csv)" has "\[3/3\]" "$T/full.txt"
check "overall download line" has "downloaded .* (100 %)" "$T/full.txt"
check "step header with expected time and overall %" has "step 10: buildings, usually about 20 min, overall" "$T/full.txt"
check "heartbeat during the 3 s step" has "\.\.\. step 10 running" "$T/full.txt"
check "stamps written for run steps" test -f "$V/data/.stamps/10.done"
check "script hashes written with the stamp" has "10_buildings.py" "$V/data/.stamps/10.hashes"
check "final line says how long setup took" has "Setup finished in" "$T/full.txt"
(cd "$V" && PATH="$V/stubs:$PATH" HOME=$V/home ./run.sh --dry-run >"$T/again.txt" 2>&1) || bad "second dry run failed"
check "second run does not fetch the raw data again" bash -c "! grep -q 'WOULD fetch' '$T/again.txt'"
check "no heartbeat process left" test -z "$(pgrep -f 'sleep 1$' || true)"
check "no real package manager was called" bash -c "! grep -q 'Homebrew\|already installed' '$T/full.txt'"

echo "== (vi) Python packages: tools/requirements.txt covers the pipeline, run.sh reads it"
check "every third-party import of the pipeline is in tools/requirements.txt" python3 -I tools/check_requirements.py
check "scipy is listed (Fedora run failed without it)" grep -qx scipy tools/requirements.txt
R=$T/reqs; mkdir -p "$R"
printf '# comment\n\nnumpy\npillow  # import PIL\nnot_a_real_pkg_xyz>=1.0\n' >"$R/requirements.txt"
got=$(REQS=$R/requirements.txt PY=python3 bash -c "$(sed -n '/^missing_reqs() {/,/^}/p' run.sh); missing_reqs")
want=" not_a_real_pkg_xyz>=1.0"
python3 -c 'import numpy, PIL' 2>/dev/null || want=$(python3 -c 'import numpy' 2>/dev/null && echo " pillow$want" || echo " numpy pillow$want")
check "missing_reqs lists only what does not import ('$got')" test "$got" = "$want"
check "run.sh installs with pip install -r" has 'pip install -r "$REQS"' run.sh

echo
if ((FAILS)); then echo "$FAILS check(s) FAILED"; exit 1; fi
echo "all checks passed"
