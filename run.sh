#!/usr/bin/env bash
# libresim one-shot setup + launch. Idempotent: each step runs only when needed.
#   ./run.sh [options] [--] [game args...]      e.g. ./run.sh --airport=VABB --stand
# See ./run.sh --help. Log: data/run.log. Stamps: data/.stamps/<step>.done (+ .hashes of the scripts)
# Helpers: tools/run_stale.sh (what is stale), tools/run_progress.sh (plan, progress, heartbeat)
set -Eeuo pipefail
if ((BASH_VERSINFO[0] < 4)); then   # macOS ships bash 3.2; this script needs bash 4+ (assoc arrays)
  for b in /opt/homebrew/bin/bash /usr/local/bin/bash; do [[ -x $b ]] && exec "$b" "$0" "$@"; done
  echo "run.sh needs bash 4 or newer: brew install bash"; exit 1
fi
cd "$(dirname "$0")"
ROOT=$PWD

GODOT_VERSION=4.7.2                     # must match docs/USAGE.md section 1
PY=tools/.venv/bin/python
PIP_PKGS="osmium jsbsim mapbox_earcut shapely matplotlib pillow numpy"
PY_MODULES="osmium jsbsim mapbox_earcut shapely matplotlib PIL numpy"   # import names, same order
STAMPS=data/.stamps
HASHPY=python3   # for tools/code_hash.py; set to $SYS_PY below
LOG=data/run.log

# ---------------------------------------------------------------- pipeline table
# Order as in docs/USAGE.md section 3. 17 patches the terrain tiles of 02/11/12 in place, so it
# runs after 12, and after 13 (stands) and 15 (terminal outlines). 09 runs again (runway heights)
# before 14 and 10; 16 (terminal base height) follows 17.
# 19 (WorldCover class tiles, needs network the first time) follows the lc writers (11, 12).
# 20 (road / river tiles) and 21 (shore tiles) read the final land-class water mask, so follow 17.
# 27 (airport pavement masks) reads the final runways.json (second 09) and the stands (13 / 17).
PIPELINE=(05 04 02 03 06 09 11 12 19 13 15 17 20 21 09 27 14 16 10)
# OUT: first entry is the sentinel used when no stamp exists yet (a dir means "a file in it").
# IN : files/globs whose change makes the step stale (script + raw data + helper modules).
# DEP: upstream steps; if one ran this session (or its stamp is newer), this step re-runs.
declare -A OUT IN DEP
OUT[05]="data/processed/airports.json data/processed/navaids.json"
IN[05]="tools/05_airports_navaids.py data/raw/ourairports/*.csv"
OUT[04]="data/processed/osm/aeroways.json data/processed/osm/roads.json data/processed/osm/water.json data/processed/osm/buildings"
IN[04]="tools/04_osm_extract.py data/raw/osm/western-zone-latest.osm.pbf"
OUT[02]="data/processed/terrain/h/0 data/processed/terrain/meta.json"
IN[02]="tools/02_dem_tiles.py tools/flatten.py data/raw/dem/*.tif data/raw/dem90/*.tif";  DEP[02]="04 05"
OUT[03]="data/processed/terrain/img/0"
IN[03]="tools/03_imagery_tiles.py tools/bc1.py data/raw/imagery/s2.tif data/raw/imagery/s2_outer.tif";  DEP[03]="02"
OUT[06]="game/aircraft/c172/aero.json game/aircraft/c172/config.json"   # committed; only if missing
# 06a (only with --a320): A320 aero/config json from the A320-family clone (tools/22_a320_fetch.sh); outputs are committed
OUT[06a]="game/aircraft/a320/aero.json game/aircraft/a320/config.json"
IN[06a]="tools/06_jsbsim_to_json.py tools/jsb_expr.py tools/jsb_turbine.py tools/jsb_a320.py data/raw/fg/a320/FDE/*.xml data/raw/fg/a320/FDE/Config/*.xml data/raw/fg/a320/Engines/*.xml data/raw/fg/a320/Systems/*.xml"
OUT[09]="data/processed/runways.json"
IN[09]="tools/09_runways.py tools/flatten.py";  DEP[09]="02 04 05 17"
OUT[10]="data/processed/buildings"
IN[10]="tools/10_buildings.py tools/terminal_ref.py tools/ref/terminals_reference.json data/raw/imagery/s2.tif";  DEP[10]="02 04 16 17"
OUT[11]="data/processed/terrain/lc/0"
IN[11]="tools/11_landclass.py data/raw/imagery/s2.tif";  DEP[11]="02 03 04"
OUT[12]="data/processed/terrain/h/6 data/processed/terrain/img/6 data/processed/terrain/lc/6"
IN[12]="tools/12_outer.py tools/bc1.py data/raw/imagery/s2_outer.tif";  DEP[12]="02 03 11"
OUT[19]="data/processed/terrain/wc/0"
IN[19]="tools/19_worldcover.py";  DEP[19]="11 12"
OUT[20]="data/processed/terrain/ro/0"
IN[20]="tools/20_roads_rivers.py tools/road_raster.py tools/ways_extract.py data/raw/osm/western-zone-latest.osm.pbf";  DEP[20]="04 11 17"
OUT[21]="data/processed/terrain/sd/0"
IN[21]="tools/21_shore.py";  DEP[21]="11 12 17"
OUT[27]="data/processed/terrain/pv/0"
IN[27]="tools/27_pavement.py tools/pavement_raster.py tools/road_raster.py";  DEP[27]="04 09 13 17"
OUT[17]="data/processed/terrain/fixups.json"   # airport fixups: levelled sites, apron + stand ground, taxiway ground, no water/trees on airfields
IN[17]="tools/17_airport_fixups.py tools/airport_fixups_io.py tools/apron_flatten.py";  DEP[17]="02 04 05 11 12 13 15"  # not 09: it re-runs after 17
OUT[13]="data/processed/airport_ops.json"
IN[13]="tools/13_airport_ops.py tools/jetway_net.py tools/jetway_footprints.py";  DEP[13]="04 05"
OUT[14]="data/processed/ils.json"
IN[14]="tools/14_ils.py";  DEP[14]="09"
OUT[15]="data/processed/terminals/VABB.json"
IN[15]="tools/15_terminals.py tools/osm_geom.py tools/ref/terminals_reference.json";  DEP[15]="04 05"
OUT[16]="data/processed/terminals/landmarks.json"
IN[16]="tools/16_terminal_models.py tools/terminal_styles.py tools/terminal_styles_ref.py tools/terminal_ref.py tools/ref/terminals_reference.json tools/terminal_geom.py tools/glb_writer.py";  DEP[16]="15 17"

# One function per step: adjust args here when a script grows a CLI.
step_05() { $PY tools/05_airports_navaids.py; }
step_04() { $PY tools/04_osm_extract.py; }
step_02() { $PY tools/02_dem_tiles.py; }
step_03() { $PY tools/03_imagery_tiles.py; }
step_06() { $PY tools/06_jsbsim_to_json.py; }
step_06a() { $PY tools/06_jsbsim_to_json.py a320; }
step_09() { $PY tools/09_runways.py; }
step_10() { $PY tools/10_buildings.py; }
step_11() { $PY tools/11_landclass.py; }
step_12() { $PY tools/12_outer.py; }
step_13() { $PY tools/13_airport_ops.py; }
step_14() { $PY tools/14_ils.py; }
step_15() { $PY tools/15_terminals.py; }
step_16() { $PY tools/16_terminal_models.py; }
step_17() { $PY tools/17_airport_fixups.py; }
step_19() { $PY tools/19_worldcover.py; }
step_20() { $PY tools/20_roads_rivers.py; }
step_21() { $PY tools/21_shore.py; }
step_27() { $PY tools/27_pavement.py --force; }  # ~1.5 min: always rebuild

declare -A NAME=([05]="airports, navaids" [04]="OSM extract" [02]="terrain heights" [03]="imagery tiles"
  [06]="c172 flight model json" [06a]="A320 flight model json" [09]="runways" [10]="buildings" [11]="land class"
  [12]="outer terrain" [13]="airport ops, stands" [14]="simulated ILS" [15]="terminal outlines" [16]="terminal models"
  [17]="airport fixups" [19]="WorldCover classes" [20]="roads and rivers" [21]="shore" [27]="airport pavement")

# Raw data (section 2 of docs/USAGE.md)
DEM30_TILES="N18_00_E072_00 N18_00_E073_00 N18_00_E074_00 N19_00_E072_00 N19_00_E073_00 N19_00_E074_00"
DEM90_SEA="N16_00_E070_00 N16_00_E071_00 N16_00_E072_00 N17_00_E070_00 N17_00_E071_00 N17_00_E072_00 N18_00_E070_00 N18_00_E071_00 N19_00_E070_00 N19_00_E071_00"  # open sea: no tile in the bucket
OSM_PBF_URL=https://download.geofabrik.de/asia/india/western-zone-latest.osm.pbf
OURAIRPORTS="airports runways navaids airport-frequencies"

# ---------------------------------------------------------------- options
usage() { cat <<'EOF'
Usage: ./run.sh [options] [--] [game args...]

Builds everything libresim needs (system tools, Python venv, raw data, data
pipeline, Godot import) and then launches the game. Each step is skipped when
its outputs are already up to date, so a second run starts the game in seconds.

What you see:
  - First a PLAN: the raw data still to download (sizes, total GB), the pipeline
    steps that will run and why, and the expected time. You are asked to continue
    (--yes skips the question). With nothing to do it says "Everything is up to date".
  - While it works: "[3/17] file (84 MB)" per download with "downloaded 0.62 of
    1.22 GB (51 %)", "step 10: buildings, usually about 20 min, overall 35 %" per
    step, and a "... still running" line every 15 s (RUN_HEARTBEAT=secs).
  - A true first run takes hours (about 2.5 GB, imagery alone 30-60 min, the
    pipeline 1.5 h or more). Later runs start in seconds.
  - Python scripts are compared by code, not by file time: editing a comment or
    docstring never rebuilds anything (hashes in data/.stamps/<step>.hashes).

Options:
  --setup-only        do everything but don't launch the game
  --skip-data         skip raw downloads and the pipeline; launch even if data is incomplete
  --region=R          mumbai_pune | all (default all = also fetch the Konkan-Kerala corridor)
  --a320              optional: also fetch the FlightGear A320-family data (GPL-2.0-only, ~2.5 MB, tools/22_a320_fetch.sh,
                      pinned commit) and regenerate game/aircraft/a320/{aero,config}.json (step 06a)
  --force-step=NN     re-run pipeline step NN (e.g. 02, 10); may be repeated
  --dry-run           print the plan and which steps would run or be skipped and why; change nothing
  --yes, -y           answer yes to every prompt (the plan, sudo installs, Godot download)
  --help, -h          this help
Anything else (or everything after --) is passed to the game, e.g.
  ./run.sh --airport=VABB --stand
  ./run.sh --setup-only --region=mumbai_pune
Log: data/run.log. Offline test of the plan: RUN_OFFLINE=1 (built-in size estimates).
EOF
}
SETUP_ONLY=0 SKIP_DATA=0 REGION=all DRY=0 YES=0 A320=0
declare -A FORCE=()
GAME_ARGS=()
while (($#)); do
  case "$1" in
    --setup-only) SETUP_ONLY=1 ;;
    --skip-data) SKIP_DATA=1 ;;
    --region=*) REGION=${1#*=} ;;
    --a320) A320=1 ;;
    --force-step=*) FORCE[${1#*=}]=1 ;;
    --dry-run) DRY=1 ;;
    --yes|-y) YES=1 ;;
    --help|-h) usage; exit 0 ;;
    --) shift; GAME_ARGS+=("$@"); break ;;
    *) GAME_ARGS+=("$1") ;;
  esac
  shift
done
case "$REGION" in mumbai_pune|all) ;; *) echo "bad --region=$REGION (mumbai_pune|all)"; exit 2 ;; esac
for f in "${!FORCE[@]}"; do [[ -n ${OUT[$f]:-} ]] || { echo "unknown --force-step=$f"; exit 2; }; done

# ---------------------------------------------------------------- logging / errors
mkdir -p data
exec 3>&1 4>&2
exec > >(tee -a "$LOG") 2>&1
echo "=== run.sh $(date '+%F %T') args: $*"
CUR="startup"; T_ALL=$SECONDS
source tools/run_stale.sh
source tools/run_progress.sh
trap 'rc=$?; hb_stop; echo; echo "ERROR in step: $CUR (line $LINENO, exit $rc). Full log: $ROOT/$LOG" >&2' ERR
trap hb_stop EXIT
trap 'hb_stop; exit 130' INT TERM
NSTEPS=8
header() { CUR="$2"; echo; echo "[$1/$NSTEPS] $2"; }
note() { echo "    $*"; }
dry() { ((DRY)); }
ask() {  # ask "question" -> 0 on yes
  ((YES)) && { note "$1 [y/N] y (--yes)"; return 0; }
  dry && return 1
  local a=""; if [[ -r /dev/tty ]]; then read -r -p "    $1 [y/N] " a </dev/tty || true; fi
  [[ $a =~ ^[Yy] ]]
}
timed() {  # timed "label" cmd...
  local label=$1 t=$SECONDS; shift; "$@"; note "($label: $((SECONDS - t)) s)"
}

# ---------------------------------------------------------------- [1] system tools + Godot
OS=$(uname -s); ARCH=$(uname -m)
PM=""
if [[ $OS == Darwin ]]; then
  PM=brew
  # Keep Homebrew quiet and fast: skip its automatic `brew update` and outdated-formulae report,
  # and env hints. Only set when the caller has not chosen (any non-empty value counts as "set",
  # even 0): run `HOMEBREW_NO_AUTO_UPDATE= ./run.sh` (empty) to keep the auto-update.
  : "${HOMEBREW_NO_AUTO_UPDATE=1}" "${HOMEBREW_NO_ENV_HINTS=1}"
  export HOMEBREW_NO_AUTO_UPDATE HOMEBREW_NO_ENV_HINTS
elif command -v apt-get >/dev/null; then PM=apt
elif command -v dnf >/dev/null; then PM=dnf
elif command -v pacman >/dev/null; then PM=pacman
fi
pkg_for() {  # pkg_for <need> -> package name for $PM
  case "$PM:$1" in
    apt:gdal) echo gdal-bin ;;          dnf:gdal|pacman:gdal|brew:gdal) echo gdal ;;
    apt:pygdal|dnf:pygdal) echo python3-gdal ;; pacman:pygdal) echo python-gdal ;; brew:pygdal) echo gdal ;;
    apt:python) echo python3 ;;         dnf:python) echo python3 ;; pacman:python|brew:python) echo python ;;
    apt:venv) echo python3-venv ;;      *:venv) echo python ;;
    *:"$1") echo "$1" ;;
  esac
}
install_cmd() {
  case $PM in
    apt) echo "sudo apt-get install -y $*" ;; dnf) echo "sudo dnf install -y $*" ;;
    pacman) echo "sudo pacman -S --needed $*" ;; brew) echo "brew install $*" ;;
    *) echo "(unknown package manager: install $* by hand)" ;;
  esac
}
SYS_PY=python3
[[ $PM == brew ]] && command -v brew >/dev/null && [[ -x "$(brew --prefix)/bin/python3" ]] && SYS_PY="$(brew --prefix)/bin/python3"
HASHPY=$SYS_PY

preflight() {
  local missing=()
  command -v "$SYS_PY" >/dev/null || missing+=(python)
  command -v gdalwarp >/dev/null || missing+=(gdal)
  command -v "$SYS_PY" >/dev/null && ! "$SYS_PY" -c 'from osgeo import gdal' 2>/dev/null && missing+=(pygdal)
  command -v "$SYS_PY" >/dev/null && ! "$SYS_PY" -c 'import venv, ensurepip' 2>/dev/null && missing+=(venv)
  command -v curl >/dev/null || command -v wget >/dev/null || missing+=(curl)
  command -v git >/dev/null || missing+=(git)
  command -v unzip >/dev/null || missing+=(unzip)
  note "OS $OS/$ARCH, package manager: ${PM:-none}, python: $SYS_PY"
  if ((${#missing[@]} == 0)); then note "system tools OK (gdal $(gdalwarp --version | cut -d' ' -f2 | tr -d ,))"; return; fi
  local pkgs; pkgs=$(for m in "${missing[@]}"; do pkg_for "$m"; done | sort -u | tr '\n' ' ')
  local cmd; cmd=$(install_cmd "$pkgs")
  note "missing: ${missing[*]}"; note "install with: $cmd"
  if dry; then return; fi
  if [[ -n $PM ]] && ask "Run '$cmd' now?"; then
    note "running: $cmd"; eval "$cmd"
  elif ((SKIP_DATA == 0)); then
    echo "Install the packages above and re-run (or use --skip-data to just launch)."; exit 1
  fi
}

GODOT=""
find_godot() {
  if [[ -x $HOME/.local/bin/godot ]]; then GODOT=$HOME/.local/bin/godot
  elif command -v godot >/dev/null; then GODOT=$(command -v godot)
  fi
}
install_godot() {
  local name url dir=$HOME/.local/share/godot
  if [[ $OS == Darwin ]]; then name="Godot_v${GODOT_VERSION}-stable_macos.universal"
  elif [[ $ARCH == aarch64 || $ARCH == arm64 ]]; then name="Godot_v${GODOT_VERSION}-stable_linux.arm64"
  else name="Godot_v${GODOT_VERSION}-stable_linux.x86_64"; fi
  url="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/${name}.zip"
  note "Godot $GODOT_VERSION not found. It can be downloaded from $url into $dir (symlink ~/.local/bin/godot)."
  dry && return
  ask "Download Godot $GODOT_VERSION now?" || { echo "Install Godot $GODOT_VERSION (docs/USAGE.md section 1) and re-run."; exit 1; }
  mkdir -p "$dir" "$HOME/.local/bin"
  fetch "$url" "$dir/$name.zip"
  unzip -oq "$dir/$name.zip" -d "$dir" && rm -f "$dir/$name.zip"
  if [[ $OS == Darwin ]]; then ln -sf "$dir/Godot.app/Contents/MacOS/Godot" "$HOME/.local/bin/godot"
  else ln -sf "$dir/$name" "$HOME/.local/bin/godot"; fi
  GODOT=$HOME/.local/bin/godot
}
check_godot() {
  find_godot
  [[ -z $GODOT ]] && install_godot
  [[ -z $GODOT ]] && return
  local v; v=$("$GODOT" --version 2>/dev/null | tail -n 1)
  if [[ $v == "$GODOT_VERSION".* ]]; then note "Godot $v ($GODOT)"
  else note "WARNING: $GODOT reports '$v', expected $GODOT_VERSION.x; it may not open the project correctly."; fi
}

# ---------------------------------------------------------------- raw data (downloads)
source tools/run_raw.sh

# ---------------------------------------------------------------- pipeline
run_step() {
  local s=$1 reason
  reason=$(why_run "$s")
  if [[ -z $reason ]]; then note "skip  $s (up to date)"; return; fi
  RAN[$s]=1
  if dry; then note "WOULD run $s: $reason"; return; fi
  CUR="pipeline step $s"; note "run   $s: $reason"
  local exp; exp=$(exp_secs "$s")
  step_line "step $s" "${NAME[$s]:-}" "$exp"
  with_heartbeat "step $s" "${exp:-0}" "" timed "step $s" "step_$s"
  mkdir -p $STAMPS; touch "$STAMPS/$s.done"; record_hashes "$s"
  DONE_S=$((DONE_S + ${exp:-0}))
  if [[ $s == 19 && $WC_PLANNED == 1 ]]; then dl_credit "$WC_BYTES"; WC_PLANNED=0; fi   # step 19 fetched the WorldCover tiles
  unset "FORCE[$s]"   # --force-step forces it once (09 appears twice)
}

# ---------------------------------------------------------------- main
((DRY)) && echo "DRY RUN: nothing will be installed, downloaded or built."

header 1 "System tools and Godot"
preflight
check_godot

header 2 "Plan"
if ((SKIP_DATA)); then note "skipped (--skip-data)"
else
  load_log_secs
  for s in "${PIPELINE[@]}" 06a; do migrate_hashes "$s"; done   # stamps from before the hash records: record, do not rebuild
  build_raw_plan; build_step_plan; print_plan
  if ! plan_has_work; then note "Everything is up to date."
  elif dry; then note "(dry run: nothing is downloaded or built; the lists below show what each part would do)"
  elif ((DL_TOTAL > 0 || PLAN_TOTAL_S > 120)); then
    ask "Continue?" || { echo "Stopped: not confirmed, nothing was changed. (./run.sh --yes skips the question; --skip-data just launches.)"; exit 0; }
  fi
fi

header 3 "Python venv (tools/.venv)"
if ((SKIP_DATA)); then note "skipped (--skip-data)"
else
  if [[ ! -x $PY ]]; then
    if dry; then note "WOULD create venv: $SYS_PY -m venv --system-site-packages tools/.venv"
    else timed venv "$SYS_PY" -m venv --system-site-packages tools/.venv; fi
  fi
  if [[ -x $PY ]]; then
    read -ra mods <<<"$PY_MODULES"; read -ra pkgs <<<"$PIP_PKGS"; need=()
    for i in "${!mods[@]}"; do $PY -c "import ${mods[$i]}" 2>/dev/null || need+=("${pkgs[$i]}"); done
    $PY -c 'from osgeo import gdal' 2>/dev/null || note "WARNING: GDAL Python bindings not visible in the venv (install $(pkg_for pygdal))"
    if ((${#need[@]} == 0)); then note "venv OK (all packages importable)"
    elif dry; then note "WOULD pip install ${need[*]}"
    else with_heartbeat "pip install" 0 "" timed pip $PY -m pip install "${need[@]}"; fi
  fi
fi

header 4 "Raw data (data/raw)"
if ((SKIP_DATA)); then note "skipped (--skip-data)"
else
  for id in "${RAW_IDS[@]}"; do if raw_active "$id"; then raw_item "$id"; fi; done
  if [[ $REGION != all ]]; then note "skip  corridor (--region=$REGION)"
  elif [[ -z $CORRIDOR ]]; then note "skip  corridor (tools/01d_fetch_corridor.* not present yet)"; fi
fi

header 5 "Data pipeline (tools/NN_*.py)"
if ((SKIP_DATA)); then note "skipped (--skip-data)"
else for s in "${PIPELINE[@]}"; do run_step "$s"; done
  ((A320)) && run_step 06a
fi

header 6 "Godot first-run import"
if [[ -z $GODOT ]]; then note "no Godot available"
elif [[ -d game/.godot/imported ]]; then note "skip  (game/.godot present)"
elif dry; then note "WOULD run: $GODOT --headless --path game --import"
else
  CUR="Godot import"; step_line "Godot import" "" "${TYPICAL[import]}"
  with_heartbeat "Godot import" "${TYPICAL[import]}" "" timed import "$GODOT" --headless --path game --import
  DONE_S=$((DONE_S + ${TYPICAL[import]}))
fi

header 7 "Summary"
missing_data=""
for f in data/processed/terrain/meta.json data/processed/runways.json data/processed/airports.json; do
  [[ -f $f ]] || missing_data+=" $f"
done
[[ -n $missing_data ]] && note "WARNING: data incomplete, missing:$missing_data (the game may not start properly)"
note "disk used: data/ $(du -sh data 2>/dev/null | cut -f1)  (raw $(du -sh data/raw 2>/dev/null | cut -f1), processed $(du -sh data/processed 2>/dev/null | cut -f1))"
note "Setup finished in $(fmt_dur $((SECONDS - T_ALL))); log: $LOG"

header 8 "Launch"
# macOS: SDL3 in Godot lists no Thrustmaster (HID) pad unless its GameController driver is off, and
# joystick events only reach the active app unless background events are on. Keep SDL's HIDAPI driver ON. (docs/USAGE.md)
if [[ $(uname) == Darwin ]]; then export SDL_JOYSTICK_MFI=0 SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1; fi
if dry; then note "WOULD run: ${GODOT:-godot} --path game -- ${GAME_ARGS[*]:-}"; exit 0; fi
[[ -x launch.sh ]] && ./launch.sh --register-only 2>/dev/null   # applications-menu entry + "Start libresim" file
if ((SETUP_ONLY)); then note "skipped (--setup-only)"; exit 0; fi
[[ -n $GODOT ]] || { echo "Godot not found; install it (docs/USAGE.md section 1)."; exit 1; }
if [[ -n $missing_data && $SKIP_DATA -eq 0 ]]; then echo "Data is incomplete; re-run, or pass --skip-data to launch anyway."; exit 1; fi
note "$GODOT --path game -- ${GAME_ARGS[*]:-}"
term_line "    Starting libresim ... the game window opens in a few seconds."
trap - ERR EXIT
exec 1>&3 2>&4
exec "$GODOT" --path game -- "${GAME_ARGS[@]}"
