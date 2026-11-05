# tools/run_raw.sh: the raw-data items of run.sh (what is missing, how to fetch it). Sourced by
# run.sh after the options are parsed. See docs/USAGE.md section 2 for the same downloads by hand.

fetch() {  # fetch url dest   (resumable; .part until complete)
  local url=$1 dest=$2; mkdir -p "$(dirname "$dest")"
  fetch_begin "$url" "$dest"
  note "GET $url"
  if command -v curl >/dev/null; then
    curl -fL --retry 5 --retry-delay 3 -C - --progress-bar -o "$dest.part" "$url"
  else
    wget -c --tries=5 --show-progress -q -O "$dest.part" "$url"
  fi
  mv -f "$dest.part" "$dest"
  dl_credit "$(wc -c <"$dest")"
}
fetch_list() { local u d; while read -r u d <&9; do fetch "$u" "$d"; done 9< <("$1"); }   # fetch_list <files function>

# One entry per raw item: <id>_done (is it there?), <id>_get (fetch it). Items that are plain
# downloads also have <id>_files, printing "url dest" for each missing file (used for the plan and for the fetch).
RAW_IDS=(dem30 dem90 osm oa jsb a320 img outer corridor)
raw_label() { case $1 in
  dem30) echo "DEM GLO-30 (6 tiles)" ;; dem90) echo "DEM GLO-90 outer ring" ;; osm) echo "OSM western-zone pbf" ;;
  oa) echo "OurAirports CSVs" ;; jsb) echo "JSBSim c172p + engines" ;;
  a320) echo "FlightGear A320-family data (--a320, GPL-2.0-only)" ;;
  img) echo "Sentinel-2 imagery, 01b" ;; outer) echo "Sentinel-2 outer ring, 01c" ;;
  corridor) echo "Konkan-Kerala corridor, $CORRIDOR" ;; esac; }
raw_active() { case $1 in a320) ((A320)) ;; corridor) [[ $REGION == all && -n $CORRIDOR ]] ;; *) return 0 ;; esac; }
# Size (bytes) and time (s) of the items whose size no HTTP HEAD can tell (gdal over WMTS, git, the corridor script);
# estimates from the data on the author's machine and from the notes in docs/USAGE.md section 2.
declare -A EST_BYTES=([jsb]=5000000 [a320]=3000000 [img]=150000000 [outer]=30000000 [corridor]=1400000000)
declare -A EST_SECS=([jsb]=15 [a320]=20 [img]=1800 [outer]=900 [corridor]=2400)
# Pipeline steps that read an item and must re-run when it is downloaded
declare -A RAW_STEPS=([dem30]="02" [dem90]="02" [osm]="04 20" [oa]="05" [img]="03 10 11" [outer]="03 12" [corridor]="02 03 11")
raw_log() { case $1 in img) echo data/raw/imagery/fetch.log ;; outer) echo data/raw/imagery/fetch_outer.log ;;
  corridor) echo data/raw/fetch_corridor.log ;; esac; }

raw_item() {  # raw_item id
  local id=$1 label; label=$(raw_label "$1")
  if "${id}_done"; then note "skip  $label (present)"; return; fi
  if dry; then note "WOULD fetch $label"; return; fi
  CUR="raw data: $label"
  if [[ ${ITEM_MODE[$id]:-} == est ]]; then   # one script, no per-file progress: header, heartbeat, then credit the estimate
    FILE_I=$((FILE_I + 1))
    note "[$FILE_I/$FILE_N] $label (about $(fmt_size "${ITEM_BYTES[$id]}"))"
    with_heartbeat "$label" "${ITEM_SECS[$id]}" "$(raw_log "$id")" timed "$label" "${id}_get"
    dl_credit "${ITEM_BYTES[$id]}"
  else
    note "fetch $label"; timed "$label" "${id}_get"
  fi
  DONE_S=$((DONE_S + ${ITEM_SECS[$id]:-0}))
}
dem30_done() { local t; for t in $DEM30_TILES; do [[ -f data/raw/dem/Copernicus_DSM_COG_10_${t}_DEM.tif ]] || return 1; done; }
dem30_files() { local t n; for t in $DEM30_TILES; do n=Copernicus_DSM_COG_10_${t}_DEM
  [[ -f data/raw/dem/$n.tif ]] || echo "https://copernicus-dem-30m.s3.amazonaws.com/$n/$n.tif data/raw/dem/$n.tif"; done; return 0; }
dem30_get() { fetch_list dem30_files; }
dem90_list() { local la lo; for la in 16 17 18 19 20 21; do for lo in 70 71 72 73 74 75 76; do
  local t=N${la}_00_E0${lo}_00; [[ " $DEM90_SEA " == *" $t "* ]] || echo "$t"; done; done; }
dem90_done() { local t; for t in $(dem90_list); do [[ -f data/raw/dem90/Copernicus_DSM_COG_30_${t}_DEM.tif ]] || return 1; done; }
dem90_files() { local t n; for t in $(dem90_list); do n=Copernicus_DSM_COG_30_${t}_DEM
  [[ -f data/raw/dem90/$n.tif ]] || echo "https://copernicus-dem-90m.s3.amazonaws.com/$n/$n.tif data/raw/dem90/$n.tif"; done; return 0; }
dem90_get() { fetch_list dem90_files; }
osm_done() { [[ -f data/raw/osm/western-zone-latest.osm.pbf ]]; }
osm_files() { osm_done || echo "$OSM_PBF_URL data/raw/osm/western-zone-latest.osm.pbf"; return 0; }
osm_get() { fetch_list osm_files; }
oa_done() { local f; for f in $OURAIRPORTS; do [[ -f data/raw/ourairports/$f.csv ]] || return 1; done; }
oa_files() { local f; for f in $OURAIRPORTS; do
  [[ -f data/raw/ourairports/$f.csv ]] || echo "https://davidmegginson.github.io/ourairports-data/$f.csv data/raw/ourairports/$f.csv"; done; return 0; }
oa_get() { fetch_list oa_files; }
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
img_get() { mkdir -p data/raw/imagery; tools/01b_fetch_imagery.sh 2>&1 | tee data/raw/imagery/fetch.log; mkdir -p $STAMPS; touch $STAMPS/01b.done; }
outer_done() { [[ -f $STAMPS/01c.done ]] || { [[ -f data/raw/imagery/s2_outer.tif ]] && grep -q '^done' data/raw/imagery/fetch_outer.log 2>/dev/null; }; }
outer_get() { mkdir -p data/raw/imagery; tools/01c_fetch_outer_imagery.sh 2>&1 | tee data/raw/imagery/fetch_outer.log; mkdir -p $STAMPS; touch $STAMPS/01c.done; }
CORRIDOR=""
for c in tools/01d_fetch_corridor.py tools/01d_fetch_corridor.sh; do [[ -f $c ]] && { CORRIDOR=$c; break; }; done
# the fetch script logs "all: finished" when every part is downloaded (also true for runs done by hand)
corridor_done() { [[ -f $STAMPS/01d.done ]] || grep -q 'all: finished' data/raw/fetch_corridor.log 2>/dev/null; }
corridor_get() {  # resumable; re-running finishes partial downloads; its log feeds the heartbeat line
  mkdir -p data/raw
  if [[ $CORRIDOR == *.py ]]; then $PY "$CORRIDOR" 2>&1 | tee -a data/raw/fetch_corridor.log
  else bash "$CORRIDOR" 2>&1 | tee -a data/raw/fetch_corridor.log; fi
  mkdir -p $STAMPS; touch $STAMPS/01d.done; }

