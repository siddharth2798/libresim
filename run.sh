#!/usr/bin/env bash
# libresim one-shot setup + launch. Idempotent: each step runs only when needed.
#   ./run.sh [options] [--] [game args...]      e.g. ./run.sh --airport=VABB --stand
# See ./run.sh --help. Log: data/run.log. Stamps: data/.stamps/<step>.done
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
LOG=data/run.log

# ---------------------------------------------------------------- pipeline table
# Order as documented in docs/USAGE.md section 3. 17 patches the terrain tiles of 02/11/12 in
# place, so it runs after 12, and it reads the stands (13) and terminal outlines (15), so after
# those; 09 then runs again (runway heights) before 14 and 10; 16 (terminal base height) follows 17.
# 19 (ESA WorldCover class tiles, needs network the first time) follows every lc tile writer (11, 12).
# 20 (road / river distance tiles) and 21 (shore distance tiles) read the final land-class water mask, so they follow 17.
PIPELINE=(05 04 02 03 06 09 11 12 19 13 15 17 20 21 09 14 16 10)
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
# 06a (only with --a320): A320 aero/config json from the FlightGear A320-family clone (tools/22_a320_fetch.sh); outputs are committed
OUT[06a]="game/aircraft/a320/aero.json game/aircraft/a320/config.json"
IN[06a]="tools/06_jsbsim_to_json.py tools/jsb_expr.py tools/jsb_turbine.py tools/jsb_a320.py data/raw/fg/a320/FDE/*.xml data/raw/fg/a320/FDE/Config/*.xml data/raw/fg/a320/Engines/*.xml data/raw/fg/a320/Systems/*.xml"
OUT[09]="data/processed/runways.json"
IN[09]="tools/09_runways.py tools/flatten.py";  DEP[09]="02 04 05 17"
OUT[10]="data/processed/buildings"
IN[10]="tools/10_buildings.py data/raw/imagery/s2.tif";  DEP[10]="02 04 16 17"
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
OUT[17]="data/processed/terrain/fixups.json"   # airport fixups: levelled sites, apron + stand ground, taxiway ground, no water/trees on airfields
IN[17]="tools/17_airport_fixups.py tools/airport_fixups_io.py tools/apron_flatten.py";  DEP[17]="02 04 05 11 12 13 15"  # not 09: it re-runs after 17
OUT[13]="data/processed/airport_ops.json"
IN[13]="tools/13_airport_ops.py";  DEP[13]="04 05"
OUT[14]="data/processed/ils.json"
IN[14]="tools/14_ils.py";  DEP[14]="09"
OUT[15]="data/processed/terminals/VABB.json"
IN[15]="tools/15_terminals.py";  DEP[15]="04 05"
OUT[16]="data/processed/terminals/landmarks.json"
IN[16]="tools/16_terminal_models.py tools/terminal_styles.py tools/terminal_geom.py tools/glb_writer.py";  DEP[16]="15 17"

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

Options:
  --setup-only        do everything but don't launch the game
  --skip-data         skip raw downloads and the pipeline; launch even if data is incomplete
  --region=R          mumbai_pune | all (default all = also fetch the Konkan-Kerala corridor)
  --a320              optional: also fetch the FlightGear A320-family data (GPL-2.0-only, ~2.5 MB, tools/22_a320_fetch.sh,
                      pinned commit) and regenerate game/aircraft/a320/{aero,config}.json (step 06a)
  --force-step=NN     re-run pipeline step NN (e.g. 02, 10); may be repeated
  --dry-run           print which steps would run or be skipped and why; change nothing
  --yes, -y           answer yes to every prompt (sudo installs, Godot download)
  --help, -h          this help
Anything else (or everything after --) is passed to the game, e.g.
  ./run.sh --airport=VABB --stand
  ./run.sh --setup-only --region=mumbai_pune
Log: data/run.log
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
trap 'echo; echo "ERROR in step: $CUR (line $LINENO, exit $?). Full log: $ROOT/$LOG" >&2' ERR
NSTEPS=7
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
mtime_newer() { [[ $1 -nt $2 ]]; }

# ---------------------------------------------------------------- [1] system tools + Godot
OS=$(uname -s); ARCH=$(uname -m)
PM=""
if [[ $OS == Darwin ]]; then
  PM=brew
  # Keep Homebrew quiet and fast for the one install this script may offer: its automatic `brew update`
  # (and the "You have N outdated formulae" report it prints) is skipped, and env hints are off.
  # Only set when the caller has not chosen (Homebrew counts any non-empty value, even 0, as "set"):
  # run `HOMEBREW_NO_AUTO_UPDATE= ./run.sh` (empty) to keep Homebrew's auto-update and its report.
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

# ---------------------------------------------------------------- downloads
fetch() {  # fetch url dest   (resumable; .part until complete)
  local url=$1 dest=$2; mkdir -p "$(dirname "$dest")"
  note "GET $url"
  if command -v curl >/dev/null; then
    curl -fL --retry 5 --retry-delay 3 -C - --progress-bar -o "$dest.part" "$url"
  else
    wget -c --tries=5 --show-progress -q -O "$dest.part" "$url"
  fi
  mv -f "$dest.part" "$dest"
}
raw_item() {  # raw_item "label" is_done_cmd do_cmd
  local label=$1 check=$2 action=$3
  if $check; then note "skip  $label (present)"; return; fi
  if dry; then note "WOULD fetch $label"; return; fi
  CUR="raw data: $label"; note "fetch $label"; timed "$label" "$action"
}
dem30_done() { local t; for t in $DEM30_TILES; do [[ -f data/raw/dem/Copernicus_DSM_COG_10_${t}_DEM.tif ]] || return 1; done; }
dem30_get() { local t n; for t in $DEM30_TILES; do n=Copernicus_DSM_COG_10_${t}_DEM
  [[ -f data/raw/dem/$n.tif ]] || fetch "https://copernicus-dem-30m.s3.amazonaws.com/$n/$n.tif" "data/raw/dem/$n.tif"; done; }
dem90_list() { local la lo; for la in 16 17 18 19 20 21; do for lo in 70 71 72 73 74 75 76; do
  local t=N${la}_00_E0${lo}_00; [[ " $DEM90_SEA " == *" $t "* ]] || echo "$t"; done; done; }
dem90_done() { local t; for t in $(dem90_list); do [[ -f data/raw/dem90/Copernicus_DSM_COG_30_${t}_DEM.tif ]] || return 1; done; }
dem90_get() { local t n; for t in $(dem90_list); do n=Copernicus_DSM_COG_30_${t}_DEM
  [[ -f data/raw/dem90/$n.tif ]] || fetch "https://copernicus-dem-90m.s3.amazonaws.com/$n/$n.tif" "data/raw/dem90/$n.tif"; done; }
osm_done() { [[ -f data/raw/osm/western-zone-latest.osm.pbf ]]; }
osm_get() { fetch "$OSM_PBF_URL" data/raw/osm/western-zone-latest.osm.pbf; }
oa_done() { local f; for f in $OURAIRPORTS; do [[ -f data/raw/ourairports/$f.csv ]] || return 1; done; }
oa_get() { local f; for f in $OURAIRPORTS; do
  fetch "https://davidmegginson.github.io/ourairports-data/$f.csv" "data/raw/ourairports/$f.csv"; done; }
# A320 data: done when the clone is at the commit pinned in tools/22_a320_fetch.sh (PIN=...)
A320_PIN=$(sed -n 's/^PIN=\([0-9a-f]\{40\}\).*/\1/p' tools/22_a320_fetch.sh 2>/dev/null | head -n 1)
a320_done() { [[ -n $A320_PIN && -d data/raw/fg/a320/.git && -f data/raw/fg/a320/A320-200-CFM-set.xml ]] \
  && [[ $(git -C data/raw/fg/a320 rev-parse HEAD 2>/dev/null) == "$A320_PIN" ]]; }
a320_get() { bash tools/22_a320_fetch.sh; }
jsb_done() { [[ -d data/raw/jsbsim/src/aircraft/c172p && -d data/raw/jsbsim/src/engine ]]; }
jsb_get() { rm -rf data/raw/jsbsim/src
  git clone --depth 1 --filter=blob:none --sparse https://github.com/JSBSim-Team/jsbsim.git data/raw/jsbsim/src
  git -C data/raw/jsbsim/src sparse-checkout set aircraft/c172p engine; }
# gdalwarp creates the .tif before it finishes, so imagery counts as done only with a stamp
# or a "done" line in the fetch log the docs tell you to keep.
img_done() { [[ -f $STAMPS/01b.done ]] || { [[ -f data/raw/imagery/s2.tif ]] && grep -q '^done' data/raw/imagery/fetch.log 2>/dev/null; }; }
img_get() { tools/01b_fetch_imagery.sh 2>&1 | tee data/raw/imagery/fetch.log; mkdir -p $STAMPS; touch $STAMPS/01b.done; }
outer_done() { [[ -f $STAMPS/01c.done ]] || { [[ -f data/raw/imagery/s2_outer.tif ]] && grep -q '^done' data/raw/imagery/fetch_outer.log 2>/dev/null; }; }
outer_get() { tools/01c_fetch_outer_imagery.sh 2>&1 | tee data/raw/imagery/fetch_outer.log; mkdir -p $STAMPS; touch $STAMPS/01c.done; }
CORRIDOR=""
for c in tools/01d_fetch_corridor.py tools/01d_fetch_corridor.sh; do [[ -f $c ]] && { CORRIDOR=$c; break; }; done
# the fetch script logs "all: finished" when every part is downloaded (also true for runs done by hand)
corridor_done() { [[ -f $STAMPS/01d.done ]] || grep -q 'all: finished' data/raw/fetch_corridor.log 2>/dev/null; }
corridor_get() {  # resumable; re-running finishes partial downloads
  if [[ $CORRIDOR == *.py ]]; then $PY "$CORRIDOR"; else bash "$CORRIDOR"; fi
  mkdir -p $STAMPS; touch $STAMPS/01d.done; }

# ---------------------------------------------------------------- pipeline staleness
declare -A RAN=()
expand() { local p; for p in $1; do compgen -G "$p" || true; done; }
ref_of() {  # file whose mtime stands for "when step $1 last completed"
  local s=$1 f
  [[ -f $STAMPS/$s.done ]] && { echo "$STAMPS/$s.done"; return; }
  local best="" o
  for o in ${OUT[$s]}; do   # the newest output file marks when the step last finished
    if [[ -d $o ]]; then f=$(find "$o" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | sed -n 1p | cut -d' ' -f2-); else f=$o; fi
    if [[ -e $f ]] && { [[ -z $best ]] || [[ $f -nt $best ]]; }; then best=$f; fi
  done
  echo "$best"
}
why_run() {  # prints a reason if step $1 must run, nothing if up to date
  local s=$1 o f d ref
  [[ -n ${FORCE[$s]:-} ]] && { echo "forced (--force-step)"; return; }
  for o in ${OUT[$s]}; do
    if [[ -d $o ]]; then [[ -n $(ls -A "$o" 2>/dev/null) ]] || { echo "output $o empty"; return; }
    else [[ -e $o ]] || { echo "output $o missing"; return; }; fi
  done
  [[ $s == 06 ]] && return     # committed outputs: only rebuilt when missing
  ref=$(ref_of "$s"); [[ -n $ref ]] || { echo "no output files"; return; }
  for d in ${DEP[$s]:-}; do
    [[ -n ${RAN[$d]:-} ]] && { echo "upstream $d ran"; return; }
    [[ -f $STAMPS/$d.done && -f $STAMPS/$s.done ]] && mtime_newer "$STAMPS/$d.done" "$STAMPS/$s.done" && { echo "upstream $d is newer"; return; }
  done
  while IFS= read -r f; do
    [[ -n $f ]] && mtime_newer "$f" "$ref" && { echo "$f is newer than last build"; return; }
  done < <(expand "${IN[$s]:-}")
  return 0
}
run_step() {
  local s=$1 reason
  reason=$(why_run "$s")
  if [[ -z $reason ]]; then note "skip  $s (up to date)"; return; fi
  RAN[$s]=1
  if dry; then note "WOULD run $s: $reason"; return; fi
  CUR="pipeline step $s"; note "run   $s: $reason"
  timed "step $s" "step_$s"
  mkdir -p $STAMPS; touch "$STAMPS/$s.done"
  unset "FORCE[$s]"   # --force-step forces it once (09 appears twice)
}

# ---------------------------------------------------------------- main
((DRY)) && echo "DRY RUN: nothing will be installed, downloaded or built."

header 1 "System tools and Godot"
preflight
check_godot

header 2 "Python venv (tools/.venv)"
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
    else timed pip $PY -m pip install "${need[@]}"; fi
  fi
fi

header 3 "Raw data (data/raw)"
if ((SKIP_DATA)); then note "skipped (--skip-data)"
else
  raw_item "DEM GLO-30 (6 tiles)" dem30_done dem30_get
  raw_item "DEM GLO-90 outer ring" dem90_done dem90_get
  raw_item "OSM western-zone pbf (~220 MB)" osm_done osm_get
  raw_item "OurAirports CSVs" oa_done oa_get
  raw_item "JSBSim c172p + engines" jsb_done jsb_get
  ((A320)) && raw_item "FlightGear A320-family data (--a320, GPL-2.0-only)" a320_done a320_get
  raw_item "Sentinel-2 imagery, 01b (20-40 min)" img_done img_get
  raw_item "Sentinel-2 outer ring, 01c (~15 min)" outer_done outer_get
  if [[ $REGION == all ]]; then
    if [[ -n $CORRIDOR ]]; then raw_item "Konkan-Kerala corridor, $CORRIDOR (resumable)" corridor_done corridor_get
    else note "skip  corridor (tools/01d_fetch_corridor.* not present yet)"; fi
  else note "skip  corridor (--region=$REGION)"; fi
fi

header 4 "Data pipeline (tools/NN_*.py)"
if ((SKIP_DATA)); then note "skipped (--skip-data)"
else for s in "${PIPELINE[@]}"; do run_step "$s"; done
  ((A320)) && run_step 06a
fi

header 5 "Godot first-run import"
if [[ -z $GODOT ]]; then note "no Godot available"
elif [[ -d game/.godot/imported ]]; then note "skip  (game/.godot present)"
elif dry; then note "WOULD run: $GODOT --headless --path game --import"
else CUR="Godot import"; timed import "$GODOT" --headless --path game --import; fi

header 6 "Summary"
missing_data=""
for f in data/processed/terrain/meta.json data/processed/runways.json data/processed/airports.json; do
  [[ -f $f ]] || missing_data+=" $f"
done
[[ -n $missing_data ]] && note "WARNING: data incomplete, missing:$missing_data (the game may not start properly)"
note "disk used: data/ $(du -sh data 2>/dev/null | cut -f1)  (raw $(du -sh data/raw 2>/dev/null | cut -f1), processed $(du -sh data/processed 2>/dev/null | cut -f1))"
note "setup time: $((SECONDS - T_ALL)) s; log: $LOG"

header 7 "Launch"
if dry; then note "WOULD run: ${GODOT:-godot} --path game -- ${GAME_ARGS[*]:-}"; exit 0; fi
[[ -x launch.sh ]] && ./launch.sh --register-only 2>/dev/null   # applications-menu entry + "Start libresim" file
if ((SETUP_ONLY)); then note "skipped (--setup-only)"; exit 0; fi
[[ -n $GODOT ]] || { echo "Godot not found; install it (docs/USAGE.md section 1)."; exit 1; }
if [[ -n $missing_data && $SKIP_DATA -eq 0 ]]; then echo "Data is incomplete; re-run, or pass --skip-data to launch anyway."; exit 1; fi
note "$GODOT --path game -- ${GAME_ARGS[*]:-}"
trap - ERR
exec 1>&3 2>&4
exec "$GODOT" --path game -- "${GAME_ARGS[@]}"
