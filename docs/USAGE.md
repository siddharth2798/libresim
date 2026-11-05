# libresim: setup, running and usage

libresim is a local Cessna 172 flight simulator (with an optional A320) for the Mumbai–Pune region and the Mumbai–Kochi corridor. This file is the user manual and the developer reference. Design and roadmap: `PLAN.md`. Coding conventions: `CLAUDE.md`.

- **Players:** Quick start, section 4 (running, keys, screens), section 7 (troubleshooting).
- **Developers:** sections 2 and 3 (data pipeline), the aircraft data sections, tests, 4b (packages).

## Quick start

**Without a terminal.** Double-click in the project folder:

- **Linux:** `Start libresim.desktop`. If the data is ready, the game opens (output in `data/run.log`). Otherwise a terminal runs `./run.sh` (asks before any `sudo` install) and starts the game when done. GNOME: right-click the file once and choose **Allow Launching**. COSMIC and KDE: just double-click (mark it trusted if asked).
- **macOS:** `Start libresim.command` (opens Terminal for the setup, then the game; if macOS blocks it, right-click, Open).
- Each launch adds **libresim** to the applications menu (`~/.local/share/applications/libresim.desktop`). `./launch.sh --register-only` adds only the menu entry.
- The launcher finds the game folder from its own location, else from `~/.config/libresim/root` (written on every launch).

**From a terminal.** One command installs what is missing, downloads the raw data, builds the game data and starts the game:

```bash
./run.sh                              # set up everything (first run: ~1-2 h, mostly downloads), then fly
./run.sh --airport=VABB --stand       # game options pass straight through (section 4)
./run.sh --dry-run                    # show what would run or be skipped, and why
```

A step runs only when its outputs are missing or older than its scripts or inputs (stamps in `data/.stamps/`), so later runs start the game in seconds. Options: `--setup-only`, `--skip-data` (launch without touching data), `--region=mumbai_pune|all` (default `all` also fetches the Konkan-Kerala corridor), `--a320` (also fetch the A320 data and regenerate its json), `--force-step=NN` (re-run one pipeline step), `--yes` (answer yes to prompts), `--help`. Missing system packages (GDAL, python3-venv, curl, git, unzip) are detected for apt, dnf, pacman and Homebrew: the install command is printed and run with `sudo` only after you say yes. If Godot 4.7.2 is missing it offers to download it into `~/.local/bin`. Blender is not needed. Everything is logged to `data/run.log`.

**macOS:** `run.sh` needs bash 4+ and Homebrew GDAL: `brew install bash gdal python`. It re-runs itself under Homebrew's bash (`/opt/homebrew/bin/bash` on Apple Silicon, `/usr/local/bin/bash` on Intel) and builds the venv from Homebrew's `python3` (its site-packages hold GDAL's Python bindings).

Sections 2 and 3 describe the steps `run.sh` automates.

## 1. Requirements (Pop!_OS / Ubuntu 24.04)

| What | How | Notes |
|---|---|---|
| GDAL + Python bindings | `sudo apt install gdal-bin python3-gdal` | GDAL 3.8 |
| QGIS (optional) | `sudo apt install qgis` | only to inspect data |
| Godot 4.7.2 (standard build) | `~/.local/share/godot/`, symlink `~/.local/bin/godot` | install below |
| Python venv | `python3 -m venv --system-site-packages tools/.venv && tools/.venv/bin/pip install osmium jsbsim mapbox_earcut shapely` | `--system-site-packages` lets it use the apt GDAL bindings |
| Blender 4.x + AC3D add-on | `sudo apt install blender`; add-on: https://github.com/NikolaiVChr/Blender-AC3D (branch `4.0`) into `data/raw/fg/addon/` | only to regenerate the aircraft models |
| Disk | ~1.5 GB raw + ~0.4 GB processed (+ 0.18 GB raw / 0.08 GB processed for WorldCover, + 0.37 GB for road / river tiles, 0.06 GB for shore tiles) | |

`~/.local/bin` is not on PATH by default. Run Godot by its full path (`~/.local/bin/godot`) or add `export PATH="$HOME/.local/bin:$PATH"` to `~/.bashrc`.

Install Godot on a fresh machine:

```bash
mkdir -p ~/.local/share/godot ~/.local/bin && cd ~/.local/share/godot
curl -LO https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip
unzip Godot_v4.7.2-stable_linux.x86_64.zip && rm Godot_v4.7.2-stable_linux.x86_64.zip
ln -sf ~/.local/share/godot/Godot_v4.7.2-stable_linux.x86_64 ~/.local/bin/godot
```

## 2. Getting the raw data (one time)

Everything goes in `data/raw/` (git-ignored). Sources: `tools/01_fetch_notes.md`. Run from the repo root.

```bash
# DEM: Copernicus GLO-30, 6 tiles (no account needed)
mkdir -p data/raw/dem && cd data/raw/dem
for t in N18_00_E072_00 N18_00_E073_00 N18_00_E074_00 N19_00_E072_00 N19_00_E073_00 N19_00_E074_00; do
  curl -fLO https://copernicus-dem-30m.s3.amazonaws.com/Copernicus_DSM_COG_10_${t}_DEM/Copernicus_DSM_COG_10_${t}_DEM.tif
done; cd -

# OpenStreetMap: western India (~220 MB)
mkdir -p data/raw/osm
curl -fL -o data/raw/osm/western-zone-latest.osm.pbf https://download.geofabrik.de/asia/india/western-zone-latest.osm.pbf

# OurAirports
mkdir -p data/raw/ourairports
for f in airports runways navaids airport-frequencies; do
  curl -fL -o data/raw/ourairports/$f.csv https://davidmegginson.github.io/ourairports-data/$f.csv
done

# JSBSim aircraft data (sparse clone: c172p + engines only)
git clone --depth 1 --filter=blob:none --sparse https://github.com/JSBSim-Team/jsbsim.git data/raw/jsbsim/src
git -C data/raw/jsbsim/src sparse-checkout set aircraft/c172p engine

# Satellite imagery: Sentinel-2 cloudless 2024 (EOX), reprojected to the world frame (~20-40 min, ~0.5 GB)
tools/01b_fetch_imagery.sh      # set LAYER=s2cloudless-2023_3857 to use a different year
tools/01c_fetch_outer_imagery.sh   # outer ring at 80 m (~490 x 490 km), ~15 min; re-run if it reports download errors (it resumes)

# Outer-ring elevation: Copernicus GLO-90 tiles 16-21 N, 70-76 E
mkdir -p data/raw/dem90 && cd data/raw/dem90
for lat in 16 17 18 19 20 21; do for lon in 70 71 72 73 74 75 76; do t=N${lat}_00_E0${lon}_00
  curl -fsLO https://copernicus-dem-90m.s3.amazonaws.com/Copernicus_DSM_COG_30_${t}_DEM/Copernicus_DSM_COG_30_${t}_DEM.tif || true  # open-sea tiles don't exist
done; done; cd -
```

### Corridor (Mumbai → Kochi)

```bash
tools/.venv/bin/python tools/01d_fetch_corridor.py all   # GLO-30 + GLO-90 + 20 m / 80 m imagery + southern-zone OSM; ~40 min, resumable
```

Downloads about 1.1 GB of DEM tiles, 163 MB of corridor imagery, 20 MB of outer-south imagery and 558 MB of OSM. Missing GLO-30 cells are open sea, listed in `data/raw/dem/missing_sea.txt`.

## 3. Building the game data

Run from the repo root, **in this order** (later steps read earlier outputs). `./run.sh` does this for you.

```bash
PY=tools/.venv/bin/python
$PY tools/05_airports_navaids.py   # -> data/processed/airports.json, navaids.json (both regions)
$PY tools/04_osm_extract.py        # -> data/processed/osm/ (runways, roads, water, buildings), both regions; ~6.5 min; [--thin] = corridor density policy
$PY tools/02_dem_tiles.py          # -> terrain/h/ heightmaps, runways flattened; corridor ~2 min
$PY tools/03_imagery_tiles.py      # -> terrain/img/ BC1 .dds tiles (needs s2.tif; corridor: s2_corridor.vrt) ~15 s + 2 min
$PY tools/06_jsbsim_to_json.py     # [aircraft id, default c172] -> game/aircraft/<id>/aero.json, config.json (committed)
$PY tools/09_runways.py            # -> runways.json (merged runways + taxiways; after 02 and 04)
$PY tools/10_buildings.py          # -> buildings/ 3D meshes in the BLD2 layout (after 02, 04); ~2.5 min on 8 processes, 364 MB + 79 MB collision.
                                   #   Roofs come from s2.tif / s2_corridor.vrt; tiles without heights are skipped; geometry in tools/building_geom.py
$PY tools/11_landclass.py          # -> terrain/lc/ water and tree-density masks (after 02-04); ~30 s + 2 min
$PY tools/12_outer.py              # -> terrain levels 3-6 over ~980 x 1475 km to Kochi (real 90 m data, filled beyond); ~7 min
$PY tools/19_worldcover.py         # -> terrain/wc/ ESA WorldCover 2021 v200 class tiles (CC BY 4.0), one per lc tile (after 11 and 12).
                                   #   First run needs network (GDAL /vsicurl/ reads of public COG tiles, no account, ~150 MB into data/raw/worldcover/,
                                   #   resumable; --download-only only fetches). Codes: 0 nodata, 1 tree, 2 shrub, 3 grass, 4 crop, 5 built-up, 6 bare,
                                   #   7 snow, 8 water, 9 wetland, 10 mangrove, 11 moss. 1758 tiles, 76 MB, ~1 min. --force rebuilds.
                                   #   The terrain shader varies the ground per class; without wc/ the ground looks as before. Credit: CREDITS.md
$PY tools/13_airport_ops.py        # -> airport_ops.json: stands, gates, jetbridges, hold points, taxi graph; ~35 s
                                   #   stand_geom / stand_links / stand_remote / airport_stands.py derive airliner stands where OSM maps jet bridges but
                                   #   no stands (Kochi, Kannur). ./run.sh re-runs 13 when 13_airport_ops.py changes; after editing a stand_*.py or
                                   #   airport_stands.py run 13 by hand (or --force-step=13).
                                   #   jetway_net.py splits each OSM jet-bridge network into movable bridges and fixed links ("jetlinks") that run 2 m
                                   #   into the terminal wall; `python tools/jetway_net.py` re-does only that, in place.
                                   #   Check: godot --headless --path game res://tests/debug_jetway_audit.tscn
$PY tools/14_ils.py                # -> ils.json: SIMULATED ILS for runways >= 2000 m (after 09)
$PY tools/15_terminals.py          # -> terminals/<ICAO>.json terminal footprints (VABB, VAPO, VOCI via cached Overpass, plus every airport in
                                   #   tools/ref/terminals_reference.json); ~15 min
$PY tools/16_terminal_models.py    # -> terminals/<ICAO>.glb landmark terminal models + landmarks.json (after 17); then re-run 10_buildings.py
$PY tools/20_roads_rivers.py       # -> terrain/ro/0/ road and river masks (after 04, 11, 12, 17). OSM highway and waterway lines of both regions
                                   #   (first run ~5 min, cached in osm/ways.npz by tools/ways_extract.py), one PNG per level-0 tile: 1920 x 1920,
                                   #   4 m texels, two channels = signed distance to the ribbon edge (0.16 m steps within 4 m) and ribbon class.
                                   #   Roads stop at water (bridges stay), aprons, runways, taxiways; minor roads and waterways stop at aerodrome
                                   #   fences. 2213 tiles, 373 MB, ~7-11 min. --force rebuilds, --only tx_ty,...
$PY tools/21_shore.py              # -> terrain/sd/ shore distance (signed m, +127 m deep side) and openness per water land-class tile;
                                   #   1564 tiles, 58 MB, ~2 min. Drives shore foam, shoal colour, calmer backwaters
$PY tools/27_pavement.py --force   # -> terrain/pv/0/ airport pavement masks (after 04, 09, 13, 17): 38 PNGs, 1920 x 1920 RGBA, 4 m texels:
                                   #   edge distance, stand lead-in offset, slab direction, concrete / asphalt + stand wear. OSM aeroway areas
                                   #   cached in osm/aeroway_areas.json (--refresh-osm). ~1.5 min
$PY tools/26_terrain_textures.py   # only to change the set (output is in git): CC0 ambientCG ground textures -> game/world/textures/terrain/
                                   #   detail_mod.webp + detail_nrm.webp (11-layer arrays) + SOURCES.md; downloads into data/raw/textures once
$PY tools/17_airport_fixups.py     # patches terrain h/lc levels 0-2 in place, both regions (after 02, 09, 11, 12, 13, 15): levelled sites
                                   #   (VANM 8 m, VOKN, VOSR) without water / trees, taxiway ground smoothed, apron ground levelled
                                   #   (tools/apron_flatten.py: stands, gates, apron polygons, taxilanes and a margin round terminals / hangars lose
                                   #   the DSM's roofs, walls and parked aircraft; 30 m blend, all three LODs), no water on paving, no trees inside
                                   #   airports. Re-runnable (starts from the saved originals), ~3 min. Then re-run 09, 14, 16 and 10.
                                   #   ./run.sh order: ... 11 12 13 15 17 09 14 16 10
$PY tools/apron_roughness.py       # optional QA: stand-area relief, apron polygon std, terminal base height per airport

# Aircraft 3D models (FlightGear c172p, GPL), committed as .glb; only to regenerate:
blender -b --factory-startup --python tools/blender/convert_c172p.py            # exterior.glb
blender -b --factory-startup --python tools/blender/convert_c172p_interior.py   # interior.glb
# fgdata jetway: blender -b --factory-startup --python tools/blender/convert_ac.py -- <in.ac> <out.glb>
$PY tools/07_preview.py 1          # -> preview_L1.png (sanity check)
$PY tools/08_jsbsim_reference.py   # optional: standalone JSBSim climb numbers
$PY tools/18_compare_fdm.py        # optional: 11 scripted manoeuvres in our FDM and JSBSim c172p; PNG plots + metrics.md in /tmp/fdm_compare (docs/FDM-VS-FLIGHTGEAR.md)
```

Notes:
- **World frame:** local Transverse Mercator centred at 18.75N 73.40E, so map metres are game ENU metres (x east, y north). Juhu ≈ (-59540, 38628), VABB ≈ (-55997, 37576), VAPO ≈ (54856, -18505).
- **Regions:** 02, 03 and 11 take `--region mumbai_pune|konkan_kerala|all` (default all) and `--workers N`. `mumbai_pune` writes `terrain/meta.json` (levels 0-4; 12_outer replaces 3+). `konkan_kerala` writes `terrain/meta_konkan_kerala.json` (levels 0-2, tiles `[min, max, flags]`, flags bit 0 = img, bit 1 = lc; level-0 corridor tiles have neither and borrow from their level-1 parent). Corridor tiles that border Mumbai-Pune tiles are stitched to their edges; Mumbai-Pune tiles are never written by the corridor run. Corridor flattening uses runways.json (09), then OSM runways, then OurAirports ends: after a fresh 09 re-run 02/03/11 for the corridor.
- 03 skips existing img tiles: delete `terrain/img/` (or the corridor's `img/{1,2}/`) to rebuild them.
- `07_preview.py quicklook [level=2] [out.png]` mosaics every `meta*.json` at one level. `07_preview.py <level> x0 y0 x1 y1` zooms into a box, e.g. `07_preview.py 0 -62000 35000 -52000 41000` shows the Mumbai airports.
- To change the region or tile layout, edit `tools/common.py` and re-run 02-03.
- Delete `data/processed/` at any time; the scripts regenerate it.

### A320 data (optional, `./run.sh --a320`)

The A320 flight model comes from the FlightGear "A320-family" JSBSim files (licence **GPL-2.0-only**: `third_party/a320-family/`, `docs/LICENSING.md`). `data/raw/fg/a320` is untrusted data: it is decoded, never executed.

```bash
tools/22_a320_fetch.sh              # sparse checkout of FDE/ Engines/ Systems/ at the pinned commit (~2.5 MB); --force re-fetches
$PY tools/06_jsbsim_to_json.py a320 # -> game/aircraft/a320/{aero,config}.json (committed; c172 json untouched)
$PY tools/test_jsb_convert.py       # converter tests (c172 json must stay byte-identical)
$PY tools/23_a320_reference.py      # JSBSim oracle run -> tools/a320_reference.json + tools/ref/*.csv (a few minutes)
```

`./run.sh --a320` runs the first two (fetch is skipped at the pinned commit; json step 06a re-runs only when the converter or the clone changed).

The converter makes two deliberate changes to the upstream data (its SPECS entry): `thrust_pos_m` puts the thrust on the model's engine centrelines (y ±5.63 m instead of ±2.8775 m), and `rudder_k` (3) scales the rudder terms so an engine failure at V2 stays controllable. The oracle run keeps the upstream data. Why: `docs/A320-STATUS.md`, `tests/test_a320_engine_out.gd`.

`23_a320_reference.py` flies the real A320 (FBW, FADEC, engines) headless in the JSBSim python package: trims, alpha limits, takeoff roll, climbs, FBW step responses, thrust formula. It is the tuning oracle for the hand-written control laws (`--only trim,stall,takeoff,climb,steps,thrust` selects parts). The first run builds `data/raw/fg/a320_root` (symlinks to the clone plus a stub system for ~700 FlightGear-side properties, ~3 min, cached). Details and the property bridge: `tools/A320_DATA_NOTES.md`.

### A320 model (optional)

The exterior and flight deck are converted from the FlightGear A320-family models (GPL-2.0-only; credits and change log in `third_party/a320-family/SOURCE.md`). Needs Blender 5.x (tested 5.2.3 LTS, run headless, not on PATH). No add-on: `tools/blender/ac3d_parse.py` reads the AC3D files.

```bash
tools/24_a320_models_fetch.sh                       # adds Models/ (~87 MB) to data/raw/fg/a320; run tools/22_a320_fetch.sh first
$PY -I tools/24_a320_textures.py                    # cleaned textures -> data/processed/a320/tex (white livery, no registration / logos)
B=/Applications/Blender.app/Contents/MacOS/Blender
$B -b --factory-startup --python tools/blender/convert_a320.py          # -> game/aircraft/a320/models/exterior.glb (+ exterior_pivots.json)
$B -b --factory-startup --python tools/blender/convert_a320_cockpit.py  # -> models/interior.glb (+ interior_info.json: eye, display rectangles; interior_pivots.json: moving controls)
$PY -I tools/24_a320_sections.py                    # -> game/aircraft/a320/model_sections.json (draft model / cockpit / lights / registration / cameras)
godot --path game res://tests/debug_a320_model.tscn --audio-driver Dummy -- --out=<dir> --pose=clean|down|spoil   # screenshots + pivot / triangle check
```

Budgets: exterior 71.9k triangles, 9 materials, 4096 px fuselage atlas (for the registration), 2048 px rest; flight deck 94.6k triangles, 16 materials, <= 2048 px. glb origin = JSBSim structural origin (`model.origin_m` `[0,0,0]`). `model_sections.json` is a draft: its `_needs` list names the small `aircraft_model.gd` / `registration_paint.gd` extensions the pivots need (extra drives, piecewise `map`, `rotate`).

## 4. Running the simulator

```bash
cd game
~/.local/bin/godot --path .          # run the game
~/.local/bin/godot -e --path .       # open the Godot editor
```

The first run imports the project (a few seconds). The data is read from `../data/processed`, so build it first (section 3).

### Start screen

The logo splash shows first, then the home screen with two cards: **Free flight** and **Training**. Click one, or press **1** / **2** (or Left / Right) and **Enter**; the last choice is focused. Links below open **Saved flights**, **Controls** and **Options**; **Handbook**, **Credits** and **Quit** are in the top bar. Tab and arrows reach everything. **◀ Back** or **Esc** returns to home.
- **Fly again (R)** (Free flight card) starts your last Free-flight setup (`user://last_flight.json`) after the same check as **Fly now**. Not shown when the save is missing or damaged.
- **Continue: <lesson> (C)** (Training card) starts the lesson after the last one you flew, with full guidance. The card lists every lesson's stars (`user://training.json`). Not shown before the first or after the last lesson.

**Free flight** has a left rail: Aircraft → Airport & start → Weather & time → Failures (optional) → Recording (optional). Aircraft is first because the airport page depends on it (air-start values, runway-length check and stands follow the aircraft).
- Each entry shows its live value (e.g. `VABB · stand 12`) and a mark: green circle = ready, amber triangle = look at it, red triangle = problem, hollow ring = optional, nothing chosen. Hover for the reason. Problems are also listed under the steps as buttons that jump to the step.
- **Next ▶** moves on, **◀ Back** goes back (first step: home). The filled **Fly now ▶** in the bottom bar starts the flight from any step; it is amber **Fly anyway ▶** when the setup has a problem. The bar also shows the setup as chips (each jumps to its step).
- Keys: **1**–**5** jump to a step (not while typing), **Page Up / Page Down** step, **Ctrl+Enter** flies, **Esc** goes back one step. The last setup is saved (`user://last_flight.json`).
- Hover tips explain things. "More weather" and aircraft "Details" toggles keep their state for the session.

**"Fly anyway?"** Fly asks (never blocks) when the setup is over MTOW (`mtow_kg`), the CG is outside the envelope (`cg_envelope`), the runway is shorter than the aircraft's minimum (runway starts only), the tailwind is above 5 kt, or the crosswind is above the aircraft's limit (C172 15 kt, A320 33 kt). Wind checks apply to runway and air starts, not stand starts; gusts do not count. Visibility under 1.6 km is only a warning. **Go back** has the focus (Esc too). Lessons and saved flights skip the check.

1. **Aircraft**
   - Every `game/aircraft/<id>/aircraft.json` is listed with name, category and three key figures. **Full specification** shows the description and every specification row.
   - **Registration** is the call sign painted on the tail and used on the radio. Untouched, it follows the aircraft (C172 VT-LBR, A320 VT-ZZA). A typed one (3 to 7 letters or digits, one optional dash after the first one or two characters, e.g. `VT-ABC`, `N172SP`) stays when you change aircraft and is saved with the setup; `--callsign=VT-ABC` sets it too. An airliner is still called by its airline name on the radio ("Skyline 123"). A change shows at the next flight start. The same field is in Options → Radio / ATC.
   - Fuel and loads: one slider each. Payload changes mass, CG and performance. A badge (Within limits / Over MTOW / CG out of limits), a weight bar and a red message give the same text as the rail mark. The **weight & balance chart** shows the C172S normal and utility CG envelopes with the takeoff and landing points (landing assumes 5 gal per tank) and turns red when overweight or out of CG limits. An aft CG makes pitch light and less stable.
2. **Airport & start**
   - **Search:** type an ICAO code, part of a name or a city (`vabb`, `shivaji`, `calicut`; every word must match). Up / Down, Enter, Esc. Airports too short for the aircraft are dimmed.
   - **Diagram:** north-up runways, taxiways and stands with an arrow at your start. Click a runway end (or the strip: the nearer end) or a stand dot to pick it.
   - **Start at:**
     - **Runway:** the chosen end, engine running. One chip per end shows length and wind (`head 8 · cross 3 kt`; red when Fly would ask; `· short` when too short). Tick "cold & dark" to start with everything off.
     - **Stand & gate:** a stand from OSM (jetbridge gate, remote bay or GA parking). Stand starts are **always cold & dark with the parking brake set**.
     - **In the air:** height above the field and distance on final. They start at the aircraft's defaults (C172: 1,500 ft, 5 nm, 90 KIAS; A320: 3,500 ft, 11 nm, 205 KIAS, gear up; about a 3° path) and follow the aircraft until you edit one (**Default** goes back). The speed has no control: it follows the aircraft unless `--air-kt` or a lesson sets it, and is clamped to 1.2 × `limits.vs1_kias` .. 0.9 × `limits.vne_kias` (C172 57.6 to 146.7 KIAS) with a log warning (`AirStart.spawn`).
   - **Stand names:** a real OSM ref is kept; a stand without one gets **Gate n** (jetbridge) or **Bay n**, numbered west to east, then south to north, skipping numbers real refs use; a repeated ref becomes `ref (2)`. "near Terminal 1" names the nearest terminal within 2.5 km. Lists: gates first for an airliner, bays first for the C172, GA tie-downs first for a light aircraft; then natural order (Bay 2 before Bay 10).
3. **Weather & time**
   - **Presets:** Clear, Fair, Scattered, Broken (passing showers), Overcast (drizzle), Winter haze, Monsoon (heavy rain under a low deck, lightning). A line says what the preset is, or "Custom".
   - **Time:** presets, the **day strip** and a "Time (IST)" slider. The strip is a 24 h bar (night, twilight, day) with sunrise and sunset above it; click or drag sets quarter hours (focused: Left / Right 15 min, Page Up / Page Down 1 h). **Dawn** and **Dusk** are the real sunrise and sunset for the **Month** (mid-February 07:10 and 18:40 IST; June about 06:00 and 19:15). One sky serves the whole map (18.75 N, 73.4 E): times depend on the date, not the airport.
   - **Wind:** presets, "Wind from" and "Wind speed" sliders, the **wind dial** and "90° crosswind". The dial is a compass with the chosen runway and an arrow showing where the wind blows; click or drag sets the direction in 10° steps (focused: Left / Up, Right / Down). The head / crosswind line turns amber from 80 % of the crosswind limit or with more than 2 kt tailwind, red above the limit or with tailwind above 5 kt (what Fly asks for). A stand start has no runway: the wind shows alone.
   - **More weather** (collapsed): cloud cover, base, visibility, rain, turbulence, thermals, storm cells, icing, gusts, QNH, temperature, clock rate, month.
4. **Failures** (optional)
   - Pick an area (left), switch a failure on and choose its trigger: **At start**, **After time** (min), **Altitude** (ft AGL) or **Airspeed** (kt). The **Armed** list (right) shows what you will get, each with a **×**; **Clear all scheduled failures** also turns random failures off. There are 26 failures; the areas come from the aircraft (the A320 also shows hydraulics, fire and more). C172:

     | Area | Failures |
     |---|---|
     | Engine | total, partial power/rough running, left and right magneto |
     | Fuel | left and right tank leak |
     | Electrical | alternator, battery |
     | Vacuum & gyros | vacuum pump, attitude gyro, heading gyro, turn coordinator |
     | Pitot-static | pitot blocked, static blocked |
     | Flight controls | flaps jammed, trim jammed, left and right brake |
     | Avionics | COM1, COM2, NAV1, NAV2, ADF, DME, transponder, GPS |

   - **Random failures:** how many, a time window (min) and which systems may fail. You are not told which are armed.
   - **Tell me when something fails** shows a notice; off, you diagnose from the instruments.
5. **Recording** (optional)
   - **Record this flight** records the session, picture and sound. **F8** starts / stops it in flight (a red ● REC shows time and size); `--record` turns it on.
   - Folder (default `recordings/` in the game folder; read-only installs (AppImage, .app) use `~/.local/share/godot/app_userdata/libresim/recordings`), resolution (720p, 1080p, native window), frame rate (24, 30, 60 fps). The options are only dimmed while recording is off: F8 still records with them.
   - Files are `libresim_<date>_<time>.mkv` (MJPEG + 16-bit PCM), written by the game, no extra software needed; they play in VLC and mpv. About 5 MB/s at 720p30. The file is a stream, so it stays playable if the game is killed. Frames are read back and encoded on worker threads, so the frame rate is barely affected.
   - **Convert to MP4:** with `ffmpeg` installed, a much smaller MP4 (H.264 + AAC) is made when recording stops.

**Controls** (home → Controls; in flight **J**, opens on the joystick tab): tabs **Keyboard**, **Joystick & gamepad**, **Other keys** (fixed hotkeys). **Controls for** (C172S / A320-family) lists the other aircraft's actions without changing your setup. **Search actions** (Ctrl+F / Cmd+F) filters by action name or bound key.
- **Keyboard:** click a slot (up to 3 keys per action, Shift / Ctrl / Alt allowed), press the new key. Esc cancels, Delete clears, conflicts show in orange, **Reset keys to defaults**. Keys match by physical position. Saved in `user://key_bindings.json`.
- **Joystick & gamepad:** connected devices are listed; hot-plug works. Each action has **Bind** (move an axis or press a button; Esc or 10 s cancels), clear, a live bar and **Tune** (invert; range: full, half for levers, trigger for toe brakes; deadzone; expo curve). Resets: gamepad = left stick roll/pitch, right stick X yaw, triggers toe brakes, LB/RB flaps, A brakes, X parking brake, Y/B views, D-pad trim and magnetos; joystick = X/Y roll/pitch, twist yaw, throttle axis. A bound axis takes over from the keyboard; unbound actions stay on the keyboard. Saved in `user://input_bindings.json`. The Thrustmaster Captain Pack has its own profile (below).

**Options** (home → Options; same pages in the pause screen) has six tabs and saves at once (`user://options.cfg`, `user://audio.cfg`):
- **Sound:** volume and mute per bus (Master, Engine, Wind & environment, Cockpit, Radio, Menus).
- **Graphics:** preset (Low to Max), **Renderer, next start** (Mobile / Forward+; "Restart libresim to apply") and the post-effect switches (section 5).
- **Display & units:** **UI size** (Auto, or 100 / 125 / 150 / 200 % of the system display scale; Auto keeps text, HUD and menus the same relative size from small windows to 4K and ultrawide; the 3D view always renders at full resolution; saved as `ui_scale`), HUD at start, units (stored for later; the C172 panel stays ft, kt, inHg).
- **Flight controls:** yoke keys, input smoothing, auto-coordination ("Control feel").
- **Radio / ATC:** call sign, **radio assist** (default on), ATC voice.
- **Training aids:** callouts (K) and "Speak them". **Voice** ("Speak them", "ATC voice"; both off by default) uses the system text-to-speech and probes the system once when switched on (about 0.5 s); with no voice found it stays silent with a note. Linux needs `speech-dispatcher` and a voice: `sudo apt install speech-dispatcher espeak-ng` (Fedora `sudo dnf install ...`, Arch `sudo pacman -S ...`), then restart. Windows and macOS use built-in voices. Code: `core/speech_service.gd` (one door for callouts and ATC; `tests/test_speech.gd`).

**Saved flights** (home → Saved flights): cards with picture, name, airport, aircraft and date, newest first. **Fly from this save** (or double click / Enter) resumes exactly there. **Delete** asks first (**Yes, delete** / **Keep it**). Saves are in `user://saves/`. Make one with Esc → Save flight or F11.

**Training mode** (home → Training, or `--lesson=takeoff|cruise|landing[,full|light|off]`): three short lessons at Pune in calm, clear weather; your Free-flight setup is not changed. Any lesson can be started.

| Lesson | You practise |
|---|---|
| **Takeoff** | Full power, staying on the centreline, rotating at 55 kt, climbing at Vy (74 kt), reaching 500 ft |
| **Cruise** | Level flight, cruise power, trim, a 90° turn, a 500 ft climb and descent |
| **Landing** | Slowing down, flaps, the 3° glide path and centreline, the threshold, the flare, touchdown and roll-out |

The landing lesson starts 3 nm out (1,000 ft, 80 kt, flaps up, on the 3° path). Steps: **Slow down** (about 1,700 RPM, 58 to 78 kt), **Flaps and trim** (flaps 20° with `]` or `F7` twice, about 65 kt; `End` nose-up trim, `Home` nose-down), **Fly the glide path** (within 1.5°, stable by 0.8 nm out), **Cross the threshold** (about 60 kt), **Flare and touch down**, **Roll out** (brake with `B` to 10 kt or less).
- A **lesson card** (left) lists steps, the instruction and a hint, and ticks steps off. **Live gauges** show your value against target and tolerance (green inside, amber near, red far). **3D markers:** dashed centreline, glide-path rings (cyan ahead, yellow next, green flown, red missed), an aim-point box, a beacon in the cruise lesson. **Coach messages** ("Rotate now!", "High. Reduce power, lower the nose") and optional speech; callouts are always on in a lesson.
- **Help level:** *Full guidance*, *Hints only* (card, hints, callouts) or *Minimal* (step list only).
- **Result:** 1–3 stars from the graded numbers (centreline error, rotation and climb speed, sink rate, touchdown point, ...), with **Try again**, **Next lesson**, **Keep flying**, **Menu**.
- Steps are in order but not strict: if you already meet a later step's conditions, earlier ones tick for you.
- **A lesson never leaves you stuck:** if you can no longer finish it (touched down or left the runway too early, far too low or high, floated off the end, settled back after rotating, flew into the ground, crashed) it ends with a "not completed" card (what happened, in which step, what to work on). **Try again** and **F5** put the aircraft back at the lesson start from any state.
- Lessons are data in `game/training/lessons.json`: steps (`any_order` for tolerant ones), conditions, gauges, grades, `abort` rules. `--air-kt=` sets the IAS of an airborne start.

**In flight:**
- **Esc** opens the pause screen: the flight stops behind a blurred backdrop, resuming is instant. The left column: **Resume flight**, **Options**, **Weather & time** (F10), **Controls & keys** (J), **Save / Load flight** (F11), **Failures** (F9), **Checklists** (F2), **Instant replay** (R), **Restart flight** (F5), **Quit to main menu**, **Quit game**; the page shows on the right. ↑ ↓ move down the list, ← → cross between list and page, **Enter** selects, the mouse works. **Esc** backs out one level (text field, page, resume). Other keys are ignored while paused; a pad pause button works like Esc. Restart and the two Quit entries need a second click ("Click again to confirm", cancelled by Esc or after 3 s).
- **Save / load:** Esc → Save / Load flight, **F11** quick-save, **Shift+F11** quick-load. A save keeps position, motion, engine state, fuel, damage, switches, radios, failures, weather and time (`user://saves/`).
- **Replay (R):** the last 10 minutes from any camera. **Space** plays / pauses, **← / →** seek ±5 s, **[ / ]** speed 0.25x–4x, the timeline can be scrubbed. **Take control** resumes flying from that moment with its exact speed and attitude; **Exit replay** returns to where you were.
- **F9** failures panel: every system OK, FAILED or armed; fail or repair any live; pending random failures.
- **Notification cards** (top centre): failures, damage, the landing debrief. Blue info, amber caution, red warning; repeats merge ("×3"), at most 3 show, they fade in seconds. STALL is a pulsing banner; a bottom hint says when the engine stopped.
- **Crash card:** dims the scene and gives the reason, impact numbers and damage, with **Restart** (F5), **Watch replay** (R) or **New flight**.

Command-line flight options (below) skip the start screen. Add `--menu` to open it pre-filled instead.

### Flying: command line and keys

```bash
cd game
~/.local/bin/godot --path .                                   # start screen
~/.local/bin/godot --path . -- --airport=VAJJ                 # skip it: Juhu, longest runway, engine idling
~/.local/bin/godot --path . -- --airport=VABB --runway=27     # Mumbai runway 27
~/.local/bin/godot --path . -- --airport=VAPO --air=2000      # airborne, 5 nm final to Pune at 2000 ft AGL
~/.local/bin/godot --path . -- --aircraft=a320 --airport=VABB --stand   # the A320 at a gate, cold (batteries on, engines off)
~/.local/bin/godot --path . -- --aircraft=a320 --airport=VABB --air=8000        # A320 airborne at 8,000 ft, 11 nm out, 205 KIAS, gear up
```

| Option (after `--`) | Meaning |
|---|---|
| `--airport=ICAO` | VAJJ (default), VABB, VAPO, VANM, VAAV (Aamby Valley), … any airport in `runways.json` |
| `--aircraft=ID` | `c172` (default) or `a320` |
| `--runway=NN` | runway end, e.g. `08`, `26`, `14`, `32`; default = the longest runway |
| `--air[=ft]` | start airborne on final at that height above the field (default: the aircraft's own, C172 1500 ft) |
| `--air-nm=N` | with `--air`: distance out on final in nm (C172 5, A320 11) |
| `--air-kt=N` | with `--air`: KIAS at the start (C172 90, A320 205; another speed sets an airliner's gear by speed: up at 200 kt or more, flaps 0) |
| `--stand[=REF]` | start parked at a stand (always cold & dark): `--airport=VABB --stand` (a jetbridge gate), `--stand="Bay 40"`, Juhu `--stand=GA3` |
| `--cold` | cold and dark: everything off, parking brake set (use the "Before Starting Engine" and "Starting Engine" checklists) |
| `--callsign=VT-ABC` | call sign painted on the tail and used on the radio |
| `--livery=…` | paint colours: see "Aircraft data: livery" |
| `--view=NAME` | initial camera: cockpit, chase (default), orbit, free, tower, wing, tail, flyby |
| `--quality=low\|medium\|high\|ultra\|max` | graphics preset (otherwise the one saved from F10) |
| `--tod=h` | local time (IST), e.g. `--tod=7.2` sunrise and `--tod=18.7` sunset in mid-February, `--tod=21` night |
| `--day=N` | day of the year (default 45 = 14 Feb): sun times and moon phase (`--day=3` = full moon) |
| `--wind=DDD/SS[GNN]` | surface wind, e.g. `--wind=270/15G25` (wind aloft is set a bit stronger and veered) |
| `--vis=m` | visibility in metres |
| `--rain=R` | rain 0–1 (after `--weather` to override the preset); below 0.3 it comes and goes in showers |
| `--clouds=C@ft` | cloud cover 0–1 at a base in ft AMSL, e.g. `--clouds=0.6@3500` |
| `--icing=0..1` | supercooled water in cloud (see "Icing and rain") |
| `--weather=NAME` | clear, fair, scattered, broken, overcast, monsoon |
| `--fail=ID[,ID…]` / `--fail=ID@min` | failures at start / after N minutes, e.g. `--fail=vacuum_pump,mag_left` (ids: `game/systems/failure_catalog.gd`) |
| `--random-failures` | one random failure 2–30 min after start |
| `--lesson=…` | start a training lesson (see "Training mode") |
| `--menu` | open the start screen pre-filled with these options |
| `--record` | record the session (video + sound) |
| `--clean` | hide all UI (screenshots) |
| `--lights-debug` | print aerodrome-light build times and what the nearest PAPI shows the camera |
| `--shot=file.png --time=s` | testing: fly hands-off `s` seconds, save a screenshot, quit |

**Flight controls (keyboard).** Flight keys can be rebound (Controls → Keyboard); the "Other keys" tab lists the fixed hotkeys.

| Key | Action |
|---|---|
| ↑ / ↓ (or numpad 8 / 2) | Pitch: ↓ pulls back (nose up), ↑ pushes (nose down). Hold to deflect, release to re-centre |
| ← / → (or numpad 4 / 6) | Roll (ailerons) |
| Z / X (or numpad 0 / Enter) | Rudder left / right; also nosewheel steering on the ground |
| Page Up / Page Down (or = / −) | Throttle up / down |
| ' / ; | Mixture richer / leaner |
| Home / End (or numpad 7 / 1) | Pitch trim: nose down / nose up |
| ] or F7 / [ or F6 | Flaps down / up one notch (0°, 10°, 20°, 30°; electric, takes a few seconds) |
| B (hold) | Both brakes |
| , / . (hold) | Left / right brake (differential steering) |
| Shift+B | Toggle parking brake |
| Ctrl+click (cockpit view) | Zoom on the instrument or switch under the cursor; Ctrl+click again or V to return. The wheel zooms toward the cursor |
| Shift+M / Shift+V | Master switch (BAT + ALT) / avionics master |
| Shift+F / Ctrl+F | Fuel selector cycle / fuel shutoff valve |
| Ctrl+B / N / S / L / T / H | Beacon / nav / strobes / landing / taxi light / pitot heat |
| Alt+T / Alt+R / Alt+W / Alt+O | Airliner only: take-off light / runway turn-off lights / wing and engine scan lights / logo lights |
| Ctrl+W / Alt+E / Alt+D | Airliner only: wing anti-ice / engine 1 / engine 2 anti-ice |
| M | Cycle magnetos OFF → L → R → BOTH |
| S (hold) | Starter |
| Y | Toggle mouse yoke (mouse position = control column) |
| L / Shift+L | PANEL light dimmer brighter / dimmer (10 % steps) |
| C / Shift+C, or 1–8 | Camera: 1 cockpit, 2 chase, 3 orbit, 4 free (WASD move, Q/E down/up, right-drag look, Shift speed, wheel sets speed), 5 tower, 6 wing, 7 tail, 8 fly-by |
| Tab / Shift+Tab | 2D panel layout in outside views: Full, Split, Compact, Minimal (ASI, AI, ALT top-right), Off. Remembered |
| Right-mouse drag | Look around (cockpit, orbit, free, wing, tail). Wheel: cockpit zoom, orbit distance, free-camera speed |
| V | Re-centre the view |
| T | Taxi guidance: green route line to the into-wind runway and a "Taxi via …, hold short" card (8-12 s; 12 s the first time after landing). T again clears it. Route and distance left stay as a tiny line in the radio bar |
| Backspace | Dismiss the taxi / pushback message (it also goes when you start taxiing or reach the stand; it stays in the radio History) |
| P | Pushback (parking brake off): a tug pushes you back and swings the tail toward the taxiway. P again stops |
| ` (backquote) | Open / close the radio (see "Radio and ATC") |
| K | Training callouts on / off |
| F2 | Checklists window (see "Checklists") |
| H / F1 / F3 | Flight-data bar (IAS, GS, ALT, AGL, VS, HDG) / key-help card / performance overlay (off by default) |
| N | Moving map (see "Navigation and radios") |
| J | Controls panel |
| F5 / F8 / F9 / F10 / F11 / F12 | Reset to start / record / failures panel / settings / quick-save (Shift+F11 load) / credits and licences |
| R | Instant replay |
| Esc | Pause screen (Esc again: back, then resume) |

**F10 settings:** graphics preset and renderer, time of day and time rate, wind and gusts, wind aloft, turbulence, visibility, clouds, QNH, temperature, failures.

**Control feel** (Options → Flight controls):
- *Yoke keys:* **Spring** (default): arrow keys and Z/X re-centre on release. **Sticky**: they stay where you leave them (as in FlightGear); tap the opposite key to come back, it stops at centre.
- *Input smoothing:* off / **light** (0.05 s, default) / strong (0.12 s): a low-pass on keyboard, joystick and mouse-yoke input. The control actuators are also rate-limited as in FlightGear's c172p: full elevator travel in 0.3 s, aileron and rudder in 0.15 s.
- *Auto-coordination:* the rudder follows the aileron (0.5 × aileron). Use it if you have no pedals.

**A first flight from Juhu:** Page Up to full throttle (about 2300 RPM static). Keep straight with Z/X. At 55 kt hold ↓ gently to rotate. Climb at 74 kt (Vy). Trim with Home/End until hands-off level, then reduce to about 2400 RPM for cruise. The Ghats are 45 km east; Pune (VAPO) is about 120 km east-southeast.

**Starting the engine** (stand starts and `--cold`): BAT on (Shift+M), mixture rich (hold '), throttle cracked (Page Up), magnetos BOTH (M three times), hold S. The engine fires after a fraction of a second of cranking and idles by itself when you let go (the e2e job `coldstart_keys_VAJJ` does exactly this with real key presses). Runway and air starts begin with the engine running.

### Airport operations

- **Stands:** VABB 114 stands (52 gates with jetbridges), VANM 87, VAPO 24 (11 gates), Calicut 36 (14 gates), Manohar (Goa) 16 (6 gates), Mangaluru 15 (6 gates), Dabolim 11, and generated GA parking at Juhu and other small fields. Kochi (VOCI) and Kannur (VOKN) have jet bridges in OSM but no mapped stands, so their airliner stands are derived from the bridges: Kochi 11 jetbridge gates (refs 2, 3, 4, B1 to B8; the C172 sits at the L1 door, nose to the terminal), a walk-out gate (1) and 26 remote bays (R1 to R26); Kannur 3 gates. Every stand is joined to the taxi graph, so T and the ATC "taxi to the apron" route to it.
- **Taxi guidance:** the route runs over the real OSM taxiway network and names the taxiways ("via A, B").
- **Pushback:** a yellow towbarless tug.
- **Follow-me car:** after you request taxi (T) it drives ahead of you, waits if you fall behind and turns off at the hold-short point.
- **Training callouts** (off by default; **K** or Options): a real C172 has none, an instructor would. *Takeoff:* Airspeed alive (40 kt), Rotate (55 kt), Positive rate. *Approach:* Five hundred, One hundred, Fifty, Thirty, Twenty, Ten (feet above ground, once each, descending only). *Cautions:* Sink rate, Low airspeed, Bank angle near the ground. "Speak them" uses the system voice (Options → Voice).
- **Touchdown effects:** each main wheel puffs tyre smoke (more with speed and sink rate) and leaves a rubber mark: under ~80 fpm nothing, smooth a faint scuff, firm a clear dark mark, hard a long heavy streak. Up to 40 marks are kept per session.
- **At the airport:** jetbridges, stand lead-in lines with stand numbers, yellow lead-on lines that continue over the runway where a taxiway meets it, windsocks that turn with the wind.
- **Ground vehicles:** at jetway gates a ground power unit at the nose, a baggage tug with carts aft, and a fuel truck on some stands; fuel trucks at some GA and remote stands, apron buses and a fire truck by the tower. The jetways are the real FlightGear model, hinged at the OSM rotunda, with a fixed walkway on columns to the terminal wall where OSM maps one (Mumbai T2's piers, Goa, Kochi); the A320 at a gate has its jetway extended to the L1 door. Only the pushback tug and the follow-me car drive. Not done: moving service vehicles, AI traffic (ATC stage A2) and recorded radio voices (A3). The vehicles are built in code (`world/ground_vehicles.gd`, `vehicle_*.gd`, `veh_*.gd`, shader `vehicle.gdshader`); `tests/debug_vehicle_lineup.tscn` shows them side by side (`-- --night` for the night look).
- **Landmark terminals:** Mumbai (T2, T1), Pune (new integrated terminal and old terminal), Kochi (T3, T1, T2), Kannur (gabled canopy) and Dabolim (curved roof) are dedicated models of the real buildings; other airports have plain blocks at their researched height and roof colour (`tools/ref/terminals_reference.json`, `docs/TERMINALS.md` §6). View a terminal with `--scene=term_<icao>_apron` / `term_<icao>_appr` (`tests/showcase_terminal_scenes.gd`) or alone with `godot --path game res://tests/debug_terminal.tscn -- --icao=VOCI --out=/tmp`. Details: `docs/TERMINALS.md`.

### Radio and ATC

**ATC** (`` ` ``) is a controller with memory, in text and optionally in the system voice. Details, phrase file and state machine: `docs/ATC.md`.
- **The radio bar** (top-left, always there in free flight) shows `COM1 118.100 · Pune Tower` (green when a unit answers, amber "no facility", red when COM1 is off or failed), the suggested next call ("Next: ask Ground for taxi") and, for 20 s, the latest controller message.
- **Calls:** click the bar or press `` ` `` to open a list of at most four plain calls with the suggested one first ("Ask Ground for taxi", "Report ready for departure", "Report final"). **↑ ↓** move, **Enter** or **1-4** call, **Esc** or `` ` `` close; it closes after a call. While it is open the arrows do not pitch and the number keys do not change the camera. Small row: **Say again** (A), **History** (H: the last 30 transmissions), **Voice** on/off (V). What you hear arrives as one card at the top centre (gone after 6-8 s).
- **Departure:** ATIS → VFR clearance (squawk, runway, readback) → pushback and taxi (the route line and follow-me car start with the call) → "contact Tower" at the holding point → ready for departure → line up and wait → cleared for takeoff with wind → "contact Approach" or "frequency change approved, squawk VFR". **Arrival:** inbound call → join / straight-in and QNH → "report final" at about 5 nm → cleared to land → "vacate runway, contact Ground" → taxi to the apron → parked.
- **Radio assist** (Options, on by default): a call tunes COM1 for you ("COM1 tuned to 118.100 Pune Tower") and the bar suggests the next call. **Off** is the realistic radio: you tune COM1, nothing is suggested, the list offers **Tune COM1 to <unit>** when needed, and a call on the wrong unit is redirected.
- Airports with no published frequency answer on any COM1 frequency (Juhu, Navi Mumbai). Small fields and heliports have no ATC: your calls are blind transmissions. A dead or switched-off COM1 sends nothing.
- **Free flight:** taking off, landing or entering a runway without clearance gives one short note per flight, never a block. **In a lesson ATC stays out of the way:** no unprompted calls, the bar is hidden (`` ` `` still opens the list), clearances count as given.
- The call sign defaults to VT-FSM when an aircraft names none (Options → Radio / ATC).

### Checklists

**F2** opens the checklist window (C172S POH, preflight to securing). Items the sim can detect tick themselves (green, locked); others tick on click or Enter. Ctrl+PgUp/PgDn (or **‹ ›**) change list, Enter ticks the next item, Shift+Enter takes the last tick back, **–** or Shift+F2 collapses the window, **×** or F2 closes it.
- The window docks at the right edge the first time. Drag it by the title bar (it snaps to screen edges with an 8 px margin and never leaves the screen); resize from any edge or corner (minimum 250 x 130 UI units). The **Opacity** slider (or the wheel over the title bar) makes the background see-through, the text stays opaque.
- Only the window's own rectangle takes the mouse; elsewhere the mouse and mouse yoke work as before, and the yoke holds still while the cursor is over the window. It is hidden during pause.
- Position, size, opacity and collapsed state are saved in `options.cfg` (`checklist_*`; delete those keys to dock it again). Code: `ui/checklist_geom.gd` (clamp / snap / resize rules, `tests/test_checklist_window.gd`), `ui/checklist_window.gd`, `ui/checklist_panel.gd`.

### Beyond the detailed region

- **Detailed area:** about 145 × 115 km, 30 m terrain and 10 m imagery.
- **Outer ring:** 90 m terrain and 80 m imagery out to about 245 km (Nashik, Ahmednagar, Satara, Kolhapur, the Konkan coast).
- **Beyond that,** to about 490 km, terrain is filled from the nearest real data with generated relief and texture, so there is no edge.

### Landing, takeoff and damage

Mistakes end the flight as in reality. Thresholds come from the C172S POH and FAR 23.

**Landing gear:**
- Touchdown sink rate above about 590 fpm at a main wheel is a **hard landing**: the airframe is damaged and needs inspection.
- Above about 900 fpm (about 510 fpm at the nose wheel) the **gear collapses**. Gear loads beyond the design limit also collapse it.
- **Crosswind:** touching down while drifting sideways more than about 6 kt damages the gear; more than about 10 kt folds it (ground loop).

**Strikes:**
- **Prop strike** (tip touches the ground, e.g. nose wheel first or porpoising): the engine is destroyed, and above about 25 kt the aircraft noses over (crash).
- **Wingtip strike** above 10 kt (ground loop) is a crash. A **tail strike** damages the airframe. **Ditching** (touching water) is a crash.

**What counts as a crash (obstacles):** touching any solid ends the flight, in the air or on the ground, at any speed. The card names the part and the thing ("The right wingtip hit trees at 82 kt"); the replay shows the same line.
- **The whole airframe counts:** propeller disc, nose, cowling, fuselage, both wings (edges, struts), fin, stabilizers and wheels.
- **Solids:** trees (as drawn: canopy and height), 3D OSM buildings (footprint and roof height), the landmark terminal models (real shape: you can taxi under an 8 m canopy, not into a wall), jetways, parked ground vehicles, apron floodlight masts and windsock poles. Not solid: runway and approach lights, PAPIs, signs, the follow-me car and the pushback tug.
- **No height gate:** a tall building beside a cliff is hit however far the ground is below you. Building collision data loads around the aircraft (and where it is heading), not the camera; the tile under a freshly placed aircraft is read at once.
- **Normal ground operations never crash:** stands, the pushback swing, taxiways and runways are corridors where OSM buildings and trees (not survey-grade) are forgiven, vehicles and masts that would stand in them are left out, and an overlap that exists while you sit parked is forgiven until you drive away. Terminals, jetways and vehicles stay solid.

**In-flight limits:**
- More than 2 s above **Vne 163 KIAS** damages the airframe; at **185 KIAS** the structure fails.
- **Flaps above VFE** (110 kt at 10°, 85 kt beyond) for 2 s damage and jam them.
- **Load factor** beyond +3.8 / −1.52 g overstresses the airframe; 1.5× those values breaks it (flight loads only).

**After every landing** a debrief shows sink rate, g, airspeed, pitch, bank, centreline offset and distance past the threshold, with a grade: BUTTER (under 120 fpm), SMOOTH (under 300), FIRM (under 600), HARD (under 900), DAMAGED. **After a crash** the cause and event log show; F5 restarts.

**Accuracy checks** (headless test cards):

| Check | Result | Reference |
|---|---|---|
| Takeoff ground roll | ~865 ft | POH 960 ft |
| Landing ground roll (flaps 30, full braking) | ~610 ft | POH 575 ft |
| Stall speeds, climb, cruise, glide | within 10–15 % | POH |
| Flared 300 fpm landing | no damage | — |
| 1200 fpm unflared arrival | gear collapse | — |
| Pushing onto the nose wheel | nose gear collapse / prop strike | — |
| Ditching, Vne dive, full-aft pull at 145 kt, flaps 30 at 120 kt, uncorrected 15 kt crosswind touchdown | each detected | — |

Not modelled: tyre bursts, engine damage from over-temperature or over-speed, bird strikes.

### Instruments and cockpit

The panel is a C172S steam-gauge layout: six-pack (airspeed, attitude, altimeter, turn coordinator, heading indicator, VSI), tachometer, engine/fuel cluster (fuel L/R, oil temperature and pressure, EGT, fuel flow, vacuum, ammeter) and a wet compass strip. It shows on the 3D panel in the cockpit view (C) and as a 2D strip in outside views (Tab).

**Clickable knobs** (cockpit or 2D panel; click the left / right half, or use the mouse wheel):

| Gauge | Action | Other |
|---|---|---|
| Altimeter | Kollsman −/+ 0.01 inHg (Shift: 0.10) | |
| Heading indicator | Card −/+ 1° (Shift: 10°) | Middle-click syncs it to the compass |

**What the instruments model:**
- **Airspeed:** C172S position error (about 6 kt low near the stall); pitot pressure falls at high angle of attack.
- **Altimeter:** Kollsman setting and slight lag. **VSI:** about 6 s to settle.
- **Attitude indicator:** vacuum-driven gyro with 3°/min erection, so it shows small turn and acceleration errors. After a vacuum failure it spins down, wanders and shows a GYRO flag.
- **Heading indicator:** drifts about 4° per 15 min; re-sync it to the compass.
- **Compass:** pendulous card with northerly turning and acceleration errors, swing and overshoot.
- **Turn coordinator:** electric rate gyro canted 30°, with the slip ball.

### Navigation and radios

The panel carries the right-hand column and radio stack of a real C172S:

- **VOR1** (KI-208) on NAV1 and **VOR2/ILS** (KI-209, with glideslope) on NAV2. OBS: click left / right half or wheel, ±1° (Shift ±10°). TO/FROM and OFF flags.
- **ADF** (KI-227): the needle shows the NDB's relative bearing. HDG knob turns the card (5°, Shift 10°).
- **Radio stack:** GPS line, two KX-155 COM/NAV radios, KR-87 ADF, KT-76A transponder, KI-266 DME (follows NAV1).
  - **Tuning:** the wheel over a standby frequency tunes it (COM 25 kHz, NAV 50 kHz, ADF 1 kHz; Shift for 1 MHz / 100 kHz); the ⇄ arrow swaps active and standby.
  - **Transponder:** the wheel over a digit changes it (0–7); clicking the mode box cycles OFF/SBY/ON/ALT.
  - Default frequencies: COM1 118.10/121.90, NAV1 116.60/113.90, NAV2 108.10/109.30, ADF 381, squawk 7000.
- **Reception:** navaids come from OurAirports. Range depends on altitude and terrain line of sight (checked every 0.5 s): flying low behind the Western Ghats loses Pune VOR. The radios need avionics power.
- **ILS:** OurAirports has no ILS data, so `tools/14_ils.py` generates **simulated** localizers and glideslopes (3°) for long runways. Frequencies and idents are not real; the map labels them "simulated".
- **GPS direct-to and route:** in the moving map click an airport or navaid for direct-to; Shift+click adds a further leg. The GPS line shows bearing, distance and ETE of the active leg and moves to the next leg within 1 nm of the active waypoint (`avionics/route_plan.gd`; props `controls/gps/target`, `controls/gps/route_next`).
- **Moving map (N):** a large overlay opened centred on the aircraft, about 20 nm across (wider if a route needs it).
  - **Contents:** satellite imagery, airports and runways, VOR / NDB, ILS feathers, your track, the aircraft symbol, north arrow and scale bar. Label priority: route names, airports, navaids; heliports show below 15 nm across, navaid names below 140 nm.
  - **Zoom:** wheel (around the cursor), `+` / `-` (also `=`, number pad) or buttons; 0.3 to 300 nm. While the map is open `=`, `-` and Num +/- zoom instead of moving the throttle (Page Up / Page Down still do) and the mouse yoke is ignored.
  - **Pan and follow:** drag with the left button. Panning leaves follow mode; **Space** or the Follow button recentres. **O** switches north up / heading up. **G** fits the whole route.
  - **Route (magenta line):** aircraft to active waypoint in bold, later legs thinner, a label per leg (magnetic bearing, distance, ETE; 90 kt when nearly stopped), a diamond with ident and distance at each waypoint. **Backspace** or Clear route cancels it. The bottom shows total distance and ETE.
  - **Keys:** N open/close, wheel or +/- zoom, Space follow, O orientation, G fit route, Backspace clear route. Tests: `tests/test_map.gd`; showcase scenes `map_open`, `map_zoom_in`, `map_zoom_out`, `map_route`, `map_heading_up`.

### Systems, weather and failures

**Switch panel** (bottom row; click to toggle):
- **Electrical:** BAT and ALT masters, AVN (avionics). **Lights:** BCN, LAND, TAXI, NAV, STRB and the PANEL dimmer (click left/right half, wheel, or L / Shift+L). **Other:** PITOT HT, fuel SHUTOFF valve, ALT STAT (alternate static).
- **Rotary selectors** (click left/right half or wheel): MAGS OFF/R/L/BOTH, FUEL OFF/LEFT/RIGHT/BOTH.

**What is modelled:**
- **Electrical:** 24 V battery (35 Ah), 60 A alternator. The alternator needs more than about 1000 RPM, so the ammeter shows discharge at idle. LOW VOLTS comes on below 24.5 V. The starter needs battery power; flaps and turn coordinator need bus power.
- **Fuel:** left and right tanks feed per the selector. The engine runs about 6 s on line fuel after starvation and restarts while windmilling when fuel returns.
- **Failures:** 26, with schedules and random ones (Start screen step 4; F9 in flight).
- **Weather** (F10 or command line):
  - **Wind:** logarithmic surface profile blending into the wind aloft, plus gusts and turbulence.
  - **Terrain effects:** ridge lift on windward slopes (the Ghats give about 3 m/s in a 20 kt westerly), sink and mechanical turbulence on the lee side.
  - **Atmosphere:** QNH and temperature affect density altitude and the altimeter. The Kollsman window starts at QNH.
  - **Sky:** a cumulus layer drifting with the wind aloft. Visibility drives haze: everything fades to the horizon colour with extinction 3 / visibility (5 % contrast at the visibility distance).
- **Time of day:** real sun position for Mumbai/Pune (IST). Default 10:00 on 14 February. The F10 time rate can speed it up.
- **Night:** a real moon (position and phase for the date, glitter path on water), stars, warm city glow on the horizon and cloud undersides, and a night ambient level and exposure so terrain, coastlines and clouds stay readable.
- **Cloud cover and rain** (`world/weather_visuals.gd`, `weather_fx.gd`):
  - Broken and thicker cover dims and diffuses the sun: under Overcast there are no hard shadows or sun disc, the sky and cloud base turn grey. Above the tops the sun is back.
  - **Inside cloud** (`world/cloud_look.gd`, `cloud_inside.gd`, `cloud_wisps.gd`; `tests/test_weather_visuals.gd`): the cockpit keeps a realistic short visibility (about 100 m in dense cloud); fog ramps with the camera's cloud density (in 0.6 s, out 1.2 s). Outside views cap the extinction around the aircraft so it stays visible (about 13x the camera distance, never under 3x). The inside is lighter overhead and toward the sun, darker below and in cumulonimbus and storm cores. Cloud wisps stream past as a motion cue (`wisps` in the preset table: 0 / 40 / 80 / 120 on Low / Medium / High / Ultra).
  - **Rain** falls only below the cloud tops: streaks lean with the wind and stretch with airspeed (count by preset), drops bead on the windshield when parked and run back with airspeed, wet terrain, roofs and trees get darker and glossier and dry slowly, rain lowers visibility. Monsoon storms have lightning.
- **Weather physics** (clouds act on the aircraft; `world/cloud_field.gd`, `cloud_convection.gd`, `cloud_storm.gd`, `cloud_physics.gd`, run by `world/weather.gd` each physics tick; tests `tests/test_cloud_weather.gd`):
  - **Settings:** `weather/convection` (thermals 0..1: Clear 0.2, Fair 0.5, Scattered 0.7, Broken 0.6, Overcast 0.1, Winter haze 0.1, Monsoon 0.5) and `weather/storms` (microburst cells 0..1: Monsoon 0.7, else 0). Sliders "Thermals" and "Storm cells" on the Weather page and in F10. Older setups and saves load with both 0; lessons set both to 0.
  - **Cloud at the aircraft:** the CPU copy of the cloud shader's density (same noise, base `weather/cloud_base_ft`, thickness 900 m) is evaluated at the aircraft. Type: `clear` (cover < 0.1), `stratiform` (overcast, or a high deck with little convection, or no sun), `cumulus` (daytime, convection >= 0.3), `cumulonimbus` (cover >= 0.9, rain >= 0.6 and convection >= 0.4 or storms >= 0.3: the Monsoon preset).
  - **Turbulence:** the Dryden sigma (Turbulence slider) is multiplied inside cloud (stratiform x1.5, cumulus x2.2, cumulonimbus x2.5), by up to half that within 300 m of a cloud, and by up to 1.4 under a cumulus base by day. A storm core adds strong turbulence.
  - **Thermals:** by day (none below 2° sun elevation, full at 40°): convection x surface (water 0.15, forest 0.7-0.8, bare / urban / crops 1.0) x warmth, less under a thick deck. Updrafts of about 1-3 m/s (up to 5 under strong cumulus) in 1-3 km cells under and inside the cloud, weak sink (0.3-1 m/s) between them; strongest mid boundary layer, none above the cloud top or above 4000 m AGL. Added to `environment/wind_ned` like ridge lift.
  - **Storm cells (microbursts):** only in cumulonimbus conditions, about one cell per 10 x 10 km (radius 1-3 km, drifting at 0.6 x the wind aloft): downdraft up to ~10 m/s at the core, outflow shear up to ~13 m/s near the surface, strong turbulence, heavier rain. Cards: "Entering cloud" / "Leaving cloud" (at most every 20 s) and "Wind shear", behind the notify option.
  - **Props at the aircraft:** `environment/ac_cloud_density` (0..1), `ac_in_cloud`, `cloud_base_m`, `cloud_top_m` (AMSL), `cloud_kind`, `turbulence_scale`, `thermal_mps` (+ up), `storm_intensity`, `storm_core`, `storm_shear_mps`; `environment/cloud_drift`. `environment/in_cloud` stays the camera's (fog).
  - **Not modelled:** cloud lifecycle (clouds only drift), terrain-triggered thermals, rotor or wave, hail, anvils.
- **Aerodrome lighting (night):** built per airport within 25 km: runway edge lights (last 600 m yellow on instrument runways), threshold / end bars, centreline lights and touchdown-zone barrettes on ILS runways, ALSF-II-style approach lights with sequenced flashers on ILS ends (a 420 m simple system elsewhere), a PAPI left of each runway (2 red + 2 white on a 3° path, visible by day), blue taxiway edge and green centreline lights, red stop bars and runway guard lights at holding points (night, visibility under 5 km), rotating beacons. Lights are directional, fade in haze and dim by day.
- **Apron floodlights** (`world/apron_light_layout.gd` places, `apron_floodlights.gd` draws, `apron_lamps.gd`, `stand_boards.gd`, `apron_mask.gd`): every stand of a lit airport gets light: 15-28 m masts between airliner stands (about one per two stands), 10 m poles on GA aprons, floods on the terminal facade above contact stands with a lit stand-number board. A mast never stands in a corridor, in a stand's parking box or within 7 m of a jetway, and is no taller than (distance from the runway edge − 30 m) / 4; masts and poles are solid. Lamp colour per airport: `airport_ops.json` `apron_lamps` ("led" ~4000 K / "hps" sodium) or a hash of the ICAO code. On from just before sunset. Near the camera the banks are real SpotLights (preset `real_lights`: 2 Low, 4 Medium, 10 High, 16 Ultra, 24 Max, at most 4 on Mobile; `apron_shadows`: the 1 (Ultra) or 2 (Max) nearest banks cast shadows); elsewhere a light volume (`light_pool.gdshader`) adds the same light from the depth buffer, cross-faded by distance. Not modelled: docking guidance boards.
- **Aircraft lights** (night): red / green nav lights (110° forward sectors), white tail light (140° aft), red beacons (C172 fin top; A320 crown and belly), white double-flash strobes (wingtips; A320 tail cone too), drawn as glowing points with a minimum on-screen size so the aircraft is visible from miles away. Landing and taxi lights are spot lights with a faint beam and a lit pool ahead (fading out above ~80 m AGL). The A320 adds retractable landing lights (lit once extended), taxi + take-off and two runway turn-off lights on the nose gear, logo lights and wing / engine scan lights. Every light sits on its housing in the model (`tests/test_aircraft_light_placement.gd`; `tools/glb_probe.py` measures a model; scenes `lights_a320_front`, `lights_c172_tip`, ... in `tests/showcase_light_scenes.gd`).
  - **Lights at start** (night or dusk, sun below 5°): nav + beacon always; strobes for air and runway starts; landing light for runway starts and air starts below 3000 ft AGL; taxi light for runway starts (the A320 also gets take-off, runway turn-off and logo lights). Cold & dark and stand starts: everything off. By day: beacon only.
- **Cockpit at night:** instruments are internally lit and follow the PANEL dimmer (default 70 %; unpowered = dark), radio displays stay lit, a warm glareshield flood lights panel and yokes.

**Realism notes:**
- With only the pilot aboard (default load) the CG sits slightly left and engine torque also rolls the aircraft left. Fixed aileron / rudder tabs (`controls.aileron_rigging` 0.033, `rudder_rigging` 0.004) cancel this at about 100 KIAS in level flight. Slower or at climb power it rolls gently left; faster, slightly right. Hands off from trim the bank after 60 s is about −10° at 90 KIAS, 0° at 100, +10° at 110. JSBSim's c172p does the same (nearly neutral spiral mode): `docs/FDM-VS-FLIGHTGEAR.md`.
- The aircraft turns left on the takeoff roll (P-factor and torque): use right rudder (X).
- **Sound** uses real recordings: the C172 engine (start, crank, idle, run, cut, pitched by RPM), stall horn, gyro spin-up, flap motor, trim wheel, tyre roll, touchdown squeal, wind by airspeed, switch clicks and levers (cockpit only). Sources and licences: `game/aircraft/c172/sounds/SOURCES.md`.

### Icing and rain

Ice forms in cloud with static air temperature between about +2 and −20 C. In the tropics that is high: with a 30 C day the freezing level is near FL150 and the band runs to about FL250, so the A320 can ice in cloud at FL150-FL250 and the C172 hardly ever does. **Icing** (0-100 %, Weather page and F10; `--icing=0..1`) sets how much supercooled water the cloud holds. Presets: Clear / Fair 0, Scattered 0.2, Broken 0.4, Overcast 0.5, Winter haze 0.2, Monsoon 0.7; storm cells add their own share; older saves have 0.

- **Accretion** (`systems/icing.gd`, numbers in `icing_rates.gd`): rate = cloud density x airspeed x liquid water (stratiform 0.4, cumulus 1, storm 1.5) x availability x temperature factor (peak −3 to −15 C). Dense cumulus at availability 1 fills the airframe in about 5 min, freezing rain (rain below 0 C) in about 2 min. Out of conditions ice sublimates in about 30 min and melts within minutes above +5 C.
- **Effects at full airframe ice** (`fdm/environment_effects.gd`): drag `drag_k` (C172: +35 % CD0, +22 % total drag at 100 KIAS), lift near the stall x(1 − `clmax_k`) with stall alpha down 11 % (CLmax −27 %; stall speed +12 % in the flight test: 53.8 → 60.2 KCAS), lift slope −3 %, earlier stall warning. Inlet ice scales piston power or turbine thrust by `1 − power_loss_k x ice` (C172 −25 %, A320 −20 %; turbine EGT rises by `egt_k`). Heavy rain (`environment/precip` above 0.6) costs up to 3 % lift and +0.0012 CD (1 % N1 on a turbine).
- **Pitot and static ice:** a probe above 0.7 ice (static 0.9) behaves like `failures/pitot_blocked` / `static_blocked` until it falls below 0.4 (0.6). The alternate static source bypasses an iced static port.
- **Protection** (`aircraft.json` `icing`, all keys optional, defaults in `Icing.DEFAULTS`): `protection` is `none`, `pitot_only` (C172: PITOT HT with bus power; optional `controls/alt_air` lever clears induction ice) or `wing_and_engine` (A320: wing and engine anti-ice from running engines' bleed air, costing thrust: `bleed_wing` 1.5 % and `bleed_engine` 2 % per engine; probes heat automatically). Other keys: `drag_k`, `clmax_k`, `power_loss_k`, `egt_k`, `pitot_heat_prop`, `wing_anti_ice_prop`, `engine_anti_ice_prop` (`%d` = engine number), `bleed_*`, `rain_cl_k`, `rain_cd_k`, `rain_n1_k`.
- **Airliner switches:** Ctrl+W wing anti-ice, Alt+E / Alt+D engine 1 / 2 (rebindable; `controls/anti_ice/{wing, eng_1, eng_2}`; probe heat `controls/anti_ice/probe` is on from the start). The E/WD memo shows ICE DETECTED (amber until anti-ice is on) and ANTI ICE. The C172 has only PITOT HT.
- **Props:** `icing/{airframe, pitot, static, engine_<n>}` (0..1), `icing/{rate, conditions, ice_detected, pitot_blocked, static_blocked, bleed_penalty, bleed_penalty_<n>}`. Read: `environment/ac_cloud_density` (in cloud above 0.05), `cloud_kind`, `storm_intensity`, `precip`, `weather/icing`, `atmosphere/temperature_k`. The state is saved with a flight (`icing`). Cards: "Ice accretion - leave icing conditions", "Pitot icing - airspeed unreliable", "Engine icing".
- **Not modelled:** ice weight, ice on the tail (the elevator is not degraded), A320 FBW protections moving with ice, de-icing boots, runway and ground ice, structural or engine ice damage, wiper / windshield heat, humid-air carburettor ice. Rates and effects are plausible, not tuned to an aircraft's data.

### Post effects

Code: `core/post_fx.gd` (`PostFx.apply(root, preset)`, after the graphics preset), rules in `core/post_fx_rules.gd`, looks in `core/post_fx_look.gd` (pure, `tests/test_post_fx.gd`), effects in `world/postfx/`. Each effect has an option in `user://options.cfg` and runs only when the option is on, the preset is high enough and the renderer can draw it:

| Option (default) | Lowest preset | Renderer | What |
|---|---|---|---|
| `bloom` (on) | Medium | both | Environment glow |
| `motion_blur` (on) | High | Forward+ | per-pixel blur along the velocity buffer, camera reprojection for the sky; 180° shutter normalised to 60 fps; reset on floating-origin shifts and view switches |
| `sun_shafts` (on) | Medium | both (Mobile if its colour buffer is a storage image) | screen-space rays from the sun, occluded by terrain, cockpit and cloud |
| `sharpen` (on) | High, with TAA or render scale != 1 | both | contrast-adaptive sharpening after TAA |
| `color_grading` (on) | Low | both | contrast / saturation / white balance by sun height, cloud and rain; brightness untouched |
| `heat_shimmer` (on) | High | Forward+ | over sunny ground when low, and behind running exhausts (`exhausts` in aircraft.json) |
| `lens_rain` (on) | Medium | both | drops on the lens in outside views only |
| `lens_effects` (off) | Low | both | vignette, chromatic aberration, film grain |
| `depth_of_field` (off) | Low | both | focus on the aircraft; replay and free camera only |
| `volumetric_fog` (on) | High | Forward+ | near-field froxel fog (below) |

**Volumetric fog** (`world/volumetric_fog.gd`, `vfog_rules.gd` (pure maps, `tests/test_volumetric_fog.gd`), `vfog_composite.gd/.gdshader`, `vfog_air.gdshader`, `vfog_rain.gdshader`): Godot's Environment volumetric fog with FogVolumes, driven from the weather props every frame. It gives light shafts under broken cloud, rain curtains under storm cells, streaks in heavy rain, puffs in cloud and glow round real lights at night. Preset key `vfog` = froxel quality: 0 Low / Medium (off, Mobile), 1 High (64² × 64 froxels, 5 km), 2 Ultra (96² × 96, 10 km), 3 Max (128² × 128, 14 km), with temporal reprojection. Morning mist is built but off (`VfogRules.MIST_ENABLED`; it still shows a hard edge a few km out, see `docs/GRAPHICS-PLAN.md` G5).
- Godot accumulates FogVolume density in fixed point (about 1/1024 per m; smaller values vanish), so thin air is the Environment's `volumetric_fog_density` and the FogVolumes only carry dense things or cut the thin air away (one box round the camera in cloud shadows and above the haze top; up to 4 cylinders under the nearest storm cells).
- Materials with `render_mode fog_disabled` (terrain, buildings, trees, runways, vehicles, cloud pass, rain, light points) skip Godot's volumetric fog. `VfogComposite` (child of the camera, first of the transparents) puts it back with n + 1 full-screen planes at fixed depths; the albedo is pre-inverted, so it needs plain exponential Environment fog (`VfogComposite.env_fog_invertible`, otherwise the fog switches off with a warning). Pixels nearer than the aircraft keep the engine's own fog.
- `--no-vfog` (user arg) turns the effect off for before / after renders.
- Godot 4.7 quirks: global shader uniforms read wrong values in `shader_type fog` shaders (pass cloud-shadow inputs as material parameters); a `Color` given to a `vec3` uniform arrives linearised again (pass a `Vector3`).

## 4a. Developer reference (tools, tests, aircraft data)

### Terrain viewer

A free camera without an aircraft, for inspecting scenery:

```bash
~/.local/bin/godot --path . res://world/terrain_viewer.tscn -- --at=-15000,-20000,1400 --heading=70 --pitch=-12
```

`--at=east,north,altitude` is in world metres (altitude above mean sea level). Keys: right-mouse look, W/A/S/D move, E/Q up/down, Shift ×10, Ctrl ×0.1, wheel changes speed, G drops to 50 m AGL, R resets, F3 overlay.

### Automated tests

```bash
cd game
~/.local/bin/godot --headless --path . res://tests/run_tests.tscn               # all tests
~/.local/bin/godot --headless --path . res://tests/run_tests.tscn -- --only=fdm  # tests named test_fdm*
~/.local/bin/godot --headless --path . res://tests/run_tests.tscn -- --suite=test_replay  # suite files whose name contains this
```

The runner prints PASS/FAIL per test and exits non-zero on failure. The run must end without "ObjectDB instances leaked" / "resources still in use at exit" (the e2e "no script errors" check fails on them): a test that builds a Node must free it, and a callback that captures `self` makes a reference cycle. `-- --leaks` lists the tests that leave orphan nodes.

Main suites (many more are in `game/tests/`; each has a header):

| Suite | Covers |
|---|---|
| `tests/test_core.gd` | Geo projection, floating origin, terrain heights, runway flatness |
| `tests/test_fdm_cards.gd` | POH performance cards (below) |
| `tests/test_flight.gd` | Takeoff from Juhu on the real terrain and runway |
| `tests/test_instruments.gd` | Altimeter and Kollsman, ASI, VSI lag, vacuum-failure gyro drift, compass error |
| `tests/test_systems.gd` | Alternator failure, battery drain, fuel starvation and restart, wind profile, Ghats ridge lift |
| `tests/test_landing.gd` | Normal landing and POH roll; hard landing, nose-first and prop strike, ditching, Vne, overstress, flap overspeed |
| `tests/test_engine_start.gd` | Cold start: starter turns the engine above firing speed, it fires and idles at every throttle, nothing starts without mixture / magnetos / fuel |
| `tests/test_apron_lights.gd` | Apron floodlights: masts, poles, corridors, facade floods, lamp type, real-lamp budget, cross-fade, airside mask |
| `tests/test_apron_flat.gd` | Apron ground from the real terrain cache: stand-area relief at VABB and VANM, terminal base height (needs steps 17 + 16) |
| `tests/test_fdm_handsoff.gd` | Hands-off for 60 s at 3000 ft: neutral at 100 KIAS, bank about −10° and heading about −70° at 90 KIAS, pinned to JSBSim's c172p |

**Flight-model test cards** (`tests/test_fdm_cards.gd`: the C172 with a test autopilot, 2550 lb, sea level, ISA, against the POH):

| Card | Model | POH |
|---|---|---|
| Static RPM, full throttle | 2300 | 2300–2420 |
| Magneto drop at run-up | ~90 RPM | 50–150 |
| Takeoff ground roll, flaps 10 | ~865 ft | 960 ft |
| Climb at Vy (74 KIAS) | ~670 fpm | 730 fpm |
| Cruise, 75 % power, 6000 ft | ~126 KTAS | 122 KTAS |
| Stall, clean / flaps 30 | 53.6 / 47.6 KCAS | 53 / 48 KCAS |
| Glide ratio, engine off | 8.6 | ~9 |
| Hands-off after trimming | ±33 ft over 60 s | stable |

### README screenshots and benchmark

`tools/make_screenshots.sh [scene ...]` regenerates the gallery in `docs/screenshots/` from the real game. Each scene (list and camera settings in `game/tests/showcase_scenes.gd`, runner `game/tests/debug_showcase.gd`) is one game run at 1920x1080 on the Ultra preset: it places the aircraft, hides the UI except what the scene shows, waits until the terrain, tree and building streamers are idle and saves a PNG (to `$FREESIM_SHOTS`, default `/tmp/libresim-shots`). The script then writes 1600x900 progressive JPEGs (quality 85, Pillow from `tools/.venv`). It needs a display and the generated data, opens a window per scene, and backs up and restores your `*.cfg` / `*.json` settings and saves. The gallery has 16 images: 01-10 the C172 and the start screen; 11-16 the A320 (`a320_gate`, `a320_cockpit`, `a320_chase`, `a320_final`, `a320_aircraft_page`) and a custom call sign on the C172 (`c172_tail`).
- Scene names are in `game/tests/showcase_scenes.gd` and the other `showcase_*_scenes.gd` files (e.g. `term_<icao>_apron`, `ramp_<aircraft>_<icao>`, `flyby_*`, `cloud_*`, `fog_*`, `sky_*`, `lights_*`, `apron_*`, `coast_*`, `trees_close`, `city_district`).
- A scene picks its aircraft with `setup.aircraft` and the call sign with `setup.callsign`; `props` sets property-tree values (gear, flaps), `att` the attitude of the frozen aircraft, `scroll` scrolls a start-screen page. For a new camera add `"variants"` to a scene and run `godot --path game res://tests/debug_showcase.tscn -- --scene=<name> --quality=ultra`.
- `tools/bench.sh` (docs/GRAPHICS-PLAN.md G0) runs the showcase scenes with `--bench=<s>` on each preset and renderer, vsync off (`--disable-vsync` plus a run-time switch), and writes `bench.md` (fps, frame ms avg / p95 / p99, GPU ms, CPU ms; columns in `game/tests/bench_probe.gd`). On macOS the default Metal driver has no GPU timestamps in Godot 4.7 (GPU columns read `n/a`); `DRIVER=vulkan tools/bench.sh` (MoltenVK) has them.
- The runner is split into `showcase_setup.gd` (session, menu pages, UI, scripted flight), `showcase_camera.gd`, `showcase_stream.gd` (streaming settle) and `showcase_views.gd` (follow-me, map, panel, pause, checklist, taxi banner).

### Adding an aircraft

An aircraft is a folder `game/aircraft/<id>/`; nothing else in the game names an aircraft. Everything is read through `AircraftDef` (`game/aircraft/aircraft_def.gd`: `load_def(id)`, `current()`, `path(key)`, `config()`, `section(name)`, `section_or(name, defaults)`; an unknown id falls back to the c172). Generic code (cockpit, lights, audio, glass, reflections) is in `game/aircraft/common/`, the model loader is `game/aircraft/aircraft_model.gd`.

```
game/aircraft/<id>/
  aircraft.json    what the game shows and needs: name, specs, limits, systems, ... (sections below)
  config.json      flight model: mass, gear, tanks, engines, controls
  aero.json        aerodynamic tables (JSBSim form, tools/06_jsbsim_to_json.py)
  hull.json        collision outline (optional)   checklists.json   panel.json   (optional)
  models/exterior.glb, models/interior.glb, sounds/   (optional; a placeholder airframe is drawn without a glb)
```

Any file name can be overridden with a `files` map in `aircraft.json` (`{"config": "other.json"}`).

`aircraft.json` sections: `model`, `cockpit`, `lights`, `audio` ("Aircraft data: model, cockpit, lights, audio"), `limits`, `damage`, `systems`, `payload`, `start`, `failures` ("Aircraft data: limits, systems, payload"), `ground`, `pushback`, `ramp`, `exhausts`, `registration`, `icing`, `fcs`, `replay`, `livery`, `cameras`, `atc`, `radio_type`, and `controls.flaps_lever` (Captain Pack, below). Defaults are the C172's.

**`ground`** (structural-frame metres about the CG; code `world/ground_params.gd`):
- Footprint that stands, taxi corridors and jetways are sized for: `ahead_m` (3.3, forward incl. margin), `behind_m` (7.4, to the tail), `across_m` (6.7, half span), `height_m` (2.5, what a jetway or tunnel must clear).
- `tow_ahead_m`: tug position ahead of the CG during pushback. `tug_scale` (1): size of the tug model; `tow_ahead_m` is its origin, so for a scaled tug add its cradle (about 2.9 m x scale) to the nose gear position.
- `min_runway_m` (0): the start screen marks shorter runways "too short for this aircraft"; they are never the default pick and rank last for the wind-based runway choice of taxi guidance and ATC. C172 175.3 (575 ft, POH landing roll at sea level, no margin), A320 1800.
- `cg_to_door_m` (0): L1 door ahead of the CG. At a jetbridge gate (whose stand point is the door's place on the centre line) the CG is placed that far behind it. `door_y_m` (0): lateral offset of the L1 door from the centre line, negative = left (the jetway hood face docks at this offset minus 0.15 m outside the skin).
- `door_height_m` (absent = `height_m`): what a jetway part must clear before it counts as solid in a corridor. **Its presence also makes the jetways of a gate dock to this aircraft** (cab floor to this sill height); the C172 has none, so its jetways stay at rest (straight toward the cab end, the hood 5 m short of it).
- `nose_gear_m` (0): nose wheel ahead of the CG, where the stand stop bar is drawn. `taxi_half_m` (8): half width of the taxiway corridor where OSM obstacles are forgiven.
- `max_taxi_kt` (absent = no advice): shows "Taxi speed N kt, keep it under M kt" while a taxi route is active. `follow_gap_m` (absent = max(35, `ahead_m` + 25)): the follow-me car leads by that much, starts 5 m further ahead and peels off 10 m before it. `hold_short_m` (40): distance of the "Hold short" call.
- `stand_class`: `"any"` (no preference: first jetbridge gate is the default stand; taxi-to-apron prefers ramp stands), `"gate"` (jetbridge gates and remote bays, no GA tie-downs, gates first; taxi-to-apron prefers gates), `"ga"` (tie-downs first). A stand is a gate if `jetbridge`, GA if its ref starts with GA or it is synthesised, else remote (`world/ground_choice.gd`).
- Top-level `pushback`: `{"straight_m": 30, "radius_m": 18, "speed_mps": 1.4}` (straight back, then a 90° swing around the CG's arc; stand corridors are sampled along it with the full footprint). Jetway docking: a 6 s extend / retract when the aircraft parks at or leaves the gate (`world/jetway_docks.gd`, `docs/A320-STATUS.md`).
- Not done: a taxiway width filter in the route search; a stand size class in `tools/airport_stands.py`.

**Other top-level keys:**
- `radio_type` (how the pilot calls the aircraft, e.g. "Cessna 172", the `{type}` slot in `atc/phraseology.json`). `atc` `{profile: "ga" | "airline", wake: L|M|H|J}`; an airliner adds `telephony` (fictional airline name), `flight_no`, `callsign_style: "airline"` (radio call sign "Skyline 123"; IFR phrases, no VFR circuit: "Airline profile" in `docs/ATC.md`).
- `cameras`: `chase` `[back_m, up_m, follow_per_s]` (third value optional, default 4: the camera trails by speed / rate), `wing` `[x, y, z, yaw_deg, pitch_deg]` (pair optional, default 20° left / 8.6° down), `tail` `[x, y, z]`, `orbit_m`; render frame about the CG (x right, y up, z aft). Default: the C172's scaled by wingspan. `flyby` (optional, `ui/flyby_placement.gd` DEFAULTS): the fly-by camera (8) stands `lead_s` (5) s of ground speed ahead, clamped to `ahead_sizes` [3, 40] aircraft sizes, `side_sizes` (2.3) off the track and `up_sizes` (0.45) above the pass point; size = max(wingspan, `ground` ahead_m + behind_m). Zoom keeps the size at `frame` (0.42) of the frame height between `fov_min` / `fov_max` (10 / 55°). It lifts 3 m (+5 % of size) above terrain and obstacles, picks the best of 18 candidates (skipping hidden or in-cloud ones) and re-places at `replace_k` (0.9) x the placement distance past it; a jump over 25 m counts as a camera cut for the post effects (`tests/test_flyby_placement.gd`).
- `start`: `pitch_trim` of a parked start; `start.air` (see "limits, systems, payload"). In `limits`: `vr_kias` (Rotate call), `vs0_kias` (Airspeed-alive call).
- `registration` paints the tail number on the exterior texture at flight start (`aircraft/common/registration_paint.gd`): `source` `"callsign"` (the pilot's call sign; `text` is the aircraft's own registration shown until one is typed: C172 VT-LBR, A320 VT-ZZA) or `"fixed"` (+ `text`: pilot cannot change it); `texture` (atlas, relative to the aircraft folder); `targets` `[{erase [x,y,w,h] (pixels of the old number plus a margin), text [x,y,w,h] (box the new one is fitted into, aspect kept), align left|right|center, color [r,g,b], italic}]`. A target also takes `rotate: 90 | 180 | 270` (turned atlas island), `erase_axis: "x"` (wipe a vertical number between the clean columns beside it) and its own `texture` (the C172 repaints the number on both wing undersides too). No section = the model keeps its own number. `baked` = the atlas already carries this number, paint nothing (only the C172: 4X-CHV). Check a target by eye: `godot --path game --windowed --audio-driver Dummy res://tests/debug_registration.tscn -- --aircraft=c172 --out=<dir> --texts=VT-LBR,N172SP`.

**`ramp`** (optional): where the ramp crew services the parked aircraft and what it must keep clear (`world/ramp_points.gd`, `ramp_layout.gd`, `ramp_crew.gd`). Frame `[forward, right]` metres about the CG on the stand, heights in metres above ground. Keys: `fuselage_half_m`; `wing` and `tailplane` `{outline: [[f, r], ...] (right side, mirrored), low_m: [root, tip] (underside height; a vehicle 0.4 m lower may stand under it)}`; `engines` `[{at: [f, r], length_m, radius_m, intake_m, exhaust_m}]` (each engine listed, no mirroring; danger zones ahead and behind are kept clear); `gpu` (ground-power receptacle), `refuel` (coupling or filler cap), `cargo` `[[f, r], ...]` (a baggage tractor and two carts each), `doors` `[[f, r], ...]` (the first gets the apron bus at a remote stand), `tug` (false = no tug ahead of the nose). `gpu` / `refuel` may be `null`.
- Every missing key is derived from the aircraft's size (config.json, engines, gear, `ground` footprint): a straight wing at the aero reference point; aircraft longer than 20 m also get a GPU near the nose, a coupling under the right wing, forward and aft holds on the right and the L1 door; smaller ones none.
- Layout: tug ahead of the nose wheel, GPU beside the receptacle, a hydrant dispenser (jetbridge gate, airliner) or fuel truck at the coupling, baggage trains at the cargo doors, the bus at a remote stand. Each slides away from its point until it is 0.8 m clear of the airframe keep-out, other crew vehicles and every registered solid; one with no room within 14 m along / 4 m out is left out.
- The crew comes when the aircraft stands on a stand point (CG within 3 m, heading within 20°) with the parking brake set and engines stopped (a stand start: at once) and leaves when the brake is released, an engine starts or the aircraft leaves. While there it is solid (`ObstacleRegistry` group `ramp:<ICAO>`) but allowed in its own stand's corridor. Prop `ops/ramp_crew` names the stand and vehicle count. Fixed-offset vehicles at other stands (`AirportOps.SERVICE`) stay. Not modelled: belt loaders, catering trucks, cones.
- C172: receptacle on the left forward fuselage, left-wing filler cap, no holds or doors, `tug: false`. A320: GPU at the nose (right), coupling under the right wing outboard of the engine, holds on the right, L1 / L4 on the left, CFM56 nacelles with 3 m intake and 6 m exhaust zones. Test: `tests/test_ramp_service.gd`.

**`exhausts`** (optional) gives the heat shimmer behind running engines (`world/postfx/heat_shimmer.gd`): `{"strength": 1.0, "list": [{"pos": [x, y, z], "dir": [x, y, z], "radius": m, "kind": "jet" | "piston", "engine": n}]}`. `pos` / `dir` are in the model frame of `models/*_pivots.json` (FlightGear: x aft, y right, z up, metres from the VRP; `dir` defaults to straight aft); `engine` is 1-based and the plume is as hot as that engine's `engines/<n>/running` and `egt_k`. Optional per entry: `length_m` (default 30 x radius for a jet, 25 x for a piston stub), `spread` (end radius / nozzle radius: 2.5 jet, 4 piston), `strength` (1 jet, 0.35 piston). Up to 4 plumes; no section = no shimmer. Other post effects need no aircraft data.

**`config.json` engines.** The older single-engine form `{"engine": {...}, "propeller": {...}}` is one piston engine. For any number of engines use a list (each engine carries its own `propeller` block):

```json
"engines": [
  {"type": "piston", "pos_m": [-0.96, -1.6, 0.68], "maxhp": 180, "...": "as the c172 engine block", "propeller": {"diameter_m": 1.9, "...": "..."}},
  {"type": "turbine", "pos_m": [1.0, 1.6, 0.9], "thrust_n": 12000, "max_rpm": 100, "idle_n1": 0.22,
   "spool_up_s": 5, "spool_down_s": 3, "tsfc_kg_per_n_s": 1.6e-5, "alt_exponent": 0.8, "mach_lapse": 0.3, "windmill_drag_n": 36, "start_n1": 0.25}
]
```

`pos_m` is the thrust point in structural metres (x aft, y right, z up). `type` is `piston` (engine plus propeller, `fdm/engine_piston.gd`) or `turbine` (no propeller; `fdm/engine_turbine.gd`: N1 spool, thrust from N1 with density and Mach lapse, fuel flow = `tsfc * thrust`, windmilling drag when failed or out of fuel). Optional `cruise_rpm` / `start_rpm` set the thruster speed of an airborne / ground start. Engine 1 uses `controls/throttle`, `mixture`, `starter`; engines 2..N use `controls/throttle_2` ... (falling back to the engine-1 lever) and `failures/engine_2` ... `tanks` is any list (`pos_m`, `capacity_kg`, `contents_kg`); a tank's side (left / right / centre) comes from its y position; the fuel system (`systems.fuel.feed`: `selector` or `all`) decides which tanks feed.

`gear` entries take an optional `role`: wheels `nose`, `main`, `tail`; structure points `wingtip`, `tail_skid`, `skid`. If missing it is derived: a steered wheel ahead of the fixed wheels is `nose`, behind them `tail` (a taildragger, using the nose wheel's weaker-leg limits), structure points by name (`TIP`, `TAIL`). `brake_group` is `LEFT`, `RIGHT`, `BOTH` or `NONE`.

**Generating the flight model.** `config.json` and `aero.json` of a JSBSim-based aircraft come from `tools/06_jsbsim_to_json.py [id]`: add an entry to `SPECS` (JSBSim aircraft, engine and propeller file names, rigging, gear damping, V-speeds, ...) and run `$PY tools/06_jsbsim_to_json.py <id>` (default `c172`; the committed c172 files regenerate byte for byte). Other aircraft write the two JSON files by hand. `tests/test_generic_aircraft.gd` builds a twin piston, a taildragger and a twin turbine from the c172 data in code (`AircraftDef.make`): a good template for checking a new configuration.

### Tuning the aircraft

Behaviour is data, so tune without touching code:
- `game/aircraft/c172/config.json`: mass, inertia, gear springs and friction, surface limits, flap timing, engine and prop. `propeller.ct_factor_vs_j` (thrust multiplier versus advance ratio) and `cp_factor` are the main performance knobs.
- `game/aircraft/c172/aero.json`: aerodynamic coefficient tables and constants, from JSBSim.
- Both files are regenerated by `tools/06_jsbsim_to_json.py`: put permanent changes in that script (or stop regenerating).
- `controls.full_travel_s`: actuator rate limits (seconds for full −1..1 travel; pitch 0.3, roll and yaw 0.15, from FlightGear's c172p).
- Re-run the test cards and `tools/18_compare_fdm.py` after any change.

### Aircraft data: limits, systems, payload

Numbers that belong to one aircraft are in its `aircraft.json` (via `AircraftDef`); scripts hold only defaults.

- `limits`: `vne_kias`, `vd_kias`, `vfe_kias` (`[[max flap deg, KIAS], ...]`), `g_pos`, `g_neg` (damage model), `vs0_kias`, `vs1_kias`, `vno_kias`, `asi_min_kias`, `asi_max_kias` (ASI arcs and scale; the white arc ends at the last `vfe_kias` speed), `max_crosswind_kt` (C172 15, A320 33; missing = 15; used by the "Fly anyway" check and the wind dial), `tach` (`max_rpm`, `green` `[lo, hi]`, `red`) and `gauges` (`fuel_gal`, `oil_temp_f`, `oil_press_psi`, `egt_f`, `fuel_flow_gph`, `suction_inhg`, `ammeter_a`, each `{min, max, green: [lo, hi], red}`; `red` optional; a gauge left out is not shown on the engine strip).
- `damage`: `hard_landing_ms`, `collapse_ms`, `nose_collapse_ms`, `collapse_drop_m`, `side_damage_ms`, `side_collapse_ms`, `main_load_w`, `nose_load_w`, and `prop_hubs_m` (one `[x, y, z]` structural position per engine, for the prop-strike check).
- `systems.electrical`: `battery_ah`, `alt_max_a`, `alt_rpm_min`, `alt_rpm_ramp`, `bus_volts`, `bat_v_empty`, `bat_v_full`, `bat_ohm`, `charge_gain`, `charge_min_a`, `starter_a`, `flap_motor_a`, `low_volts`, `powered_volts`, `starter_min_volts`, `loads` (amps per consumer). Defaults: `systems/electrical.gd`.
- `systems.pitot_static`: `pos_err_kcas` and `pos_err_dkt` (airspeed position error table, kt; none = no error). `systems.fuel`: see `systems/fuel.gd`.
- `short_name` and `preview.jpg`: the aircraft page shows one chip per installed aircraft (picture, `short_name`, first part of `category`). `preview.jpg` (1680 x 350) is rendered from the aircraft's own exterior model: `godot --path game --resolution 1680x350 --windowed --audio-driver Dummy res://tests/render_aircraft_previews.tscn [-- --ids=c172,a320]`; run it after adding an aircraft or changing its model or paint. Without a picture the page still works.
- `payload`: `fuel_kg_per_gal`, `cruise_gph` and `reserve_gal` (endurance estimate), `fuel_slider` (`min`, `max`, `step`, `unit`; fuel per tank) and `stations`, a list of `{key, label, max, step, masses}`. `key` is the `Session.setup` entry (kept in saved flights), `masses` the names of the `config.json` point masses the station's kg is split over. W&B, the start screen and the flight loading all read this list.
- `payload` extras for an airliner: `fuel_unit: "kg"` makes the fuel slider and `Session.setup.fuel_gal` the TOTAL fuel in kg (wing tanks first in proportion to capacity, then centre, pipe tanks empty: `WeightBalance.fuel_per_tank`); `cruise_kgh` / `reserve_kg`; `defaults` (`{fuel_gal, cabin_kg, cargo_kg, ...}` applied by `Session.apply_payload_defaults` when the aircraft is chosen or with `--aircraft=`); `cg_envelope` (A320: `mac {lemac_x_m, mac_m}` reports CG in % MAC, `weight_unit "kg"` + `max_kg` + `landing_fuel_kg`, `cg_label` / `cg_unit`, `chart {x, y, x_step, y_step}`; all optional, defaults = the C172's inches / lb chart). The A320 envelope is approximate (public shape, assumed LEMAC): say so wherever it is shown.
- `start.air` (the default "In the air" start; all keys optional): `alt_ft` (height above the field), `dist_nm`, `kias`, `gear` (`"up"` | `"down"`; fixed gear ignores it), `flaps` (detent index), `limits {alt_ft: [min, max], dist_nm: [min, max]}` for the start-screen controls. Choose a stabilised-approach start: the 3° path is about 318 ft per nm (C172: 1500 ft, 5 nm, 90 KIAS, limits 300..12,000 ft and 1..25 nm; A320: 3500 ft, 11 nm, 205 KIAS, gear up, flaps 0, limits 1,000..15,000 ft and 3..40 nm).
  - A missing key is derived by `aircraft/air_start.gd` (`AircraftDef.air_start()`): `kias` from the older `start.air_kt`, else 1.3 x `limits.vs1_kias` rounded to 5 kt (no vs1: 90); `dist_nm` from that speed (under 120 kt 5 nm, up to 160 kt 8, above 11); `alt_ft` = `dist_nm` x 318 rounded to 100 ft; gear down, flaps 0, limits 300..12,000 ft / 1..25 nm. A new aircraft needs no block. With another speed (`--air-kt`, a lesson) the gear follows the speed and flaps are 0.
  - `Session.apply_air_defaults()` copies the numbers into `Session.setup.air_ft / air_nm / air_kt` while `air_custom` is false. An old `last_flight.json` without the flag counts as custom unless it holds exactly 1500 / 5 / 90; without `air_kt_given` its speed is kept only if it is not any installed aircraft's own air-start speed and lies in the safe range.
  - Test `tests/test_air_start_defaults.gd`; scene `godot --headless --path game res://tests/debug_air_start.tscn --audio-driver Dummy -- --airport=VABB --runway=27 --air --aircraft=a320`.
- `fcs {"law": "airbus_fbw"}` (control law, below); `callouts {alive_kt, rotate_kt, v1_kt, low_kt, heights}` (training callouts of `ui/callouts.gd`; `v1_kt` adds "V one", `heights` the radio-altitude calls).
- `failures`: optional `{"disabled": [ids]}` removes failures from the catalogue (`systems/failure_catalog.gd`); engines 2..N get `engine_<n>` / `engine_partial_<n>` automatically.

### Start screen: developer notes

Rules that players see are in "Start screen" (section 4). Every page writes the same `Session.setup` keys; saves and `last_flight.json` are unchanged by the UI. Shared controls (API in each file header): `ui/menu/segmented.gd`, `switch_row.gd`, `page_styles.gd`, `menu_tabs.gd` (`MenuTabs.setup(as_rail, sticky)`), `option_rows.gd` (`OptionRows.switch / choice / tab_body`). Code is in `game/ui/menu/` unless noted.

- **Readiness** (`core/setup_checks.gd`, `SetupChecks`, pure; tests `test_setup_checks.gd`, `test_fly_confirm.gd`): `checks(Session.setup)` returns `[{step: "aircraft" | "airport" | "weather", level: "bad" | "warn", id, text}]` (empty = ready); `worst(list)`, `reasons(list)` (texts of the "bad" ones), `step_level(list, step)`. The runway comes from `runways.json` (the setup's runway, else the longest). `fly_confirm.gd` (`FlyConfirm`) is the dialog; `start_screen.gd` `_fly` shows it for Fly and Ctrl+Enter.
- **Flow chrome** (`start_flow.gd`, wiring only): texts, levels and tooltips are pure functions in `flow_values.gd` (`tests/test_flow_chrome.gd`); `status_dot.gd`; `flow_rail.gd` (`FlowRail.reason_btns`, `reason_items`, rebuilt only when the list changes so focus stays); `flow_chips.gd` (`FlowChips.fit_widths`: pure one-row layout; `tests/test_flow_reasons.gd`). Everything repaints when a page emits `changed` and when `Session.setup` changes (one hash per frame). Training, Saved flights, Options and Controls use the plain frame `page_frame.gd`.
- **Home:** `home_shortcuts.gd` (`HomeShortcuts`, pure: what exists, the texts, `lesson_marks`), `home_screen.gd` (signals `fly_again`, `continue_lesson`; `refresh()`; `HomeScreen.scale_for` 1.0 at 1280 x 720, up to 1.4 big, down to 0.5 small), `choice_card.gd`, `home_tile.gd`. A damaged `last_flight.json` falls back per value to defaults and to the default aircraft. Scene `tests/debug_home.tscn` (`HOME_DATA=1|0`, `HOME_FOCUS=fly|continue|more`; scratch files).
- **Weather step:** `conditions_page.gd` (statics `weather_match / time_match / wind_match / preset_time` are used by the rail and chips), `weather_choices.gd`, `wind_math.gd` (`WindMath`: components via `SetupChecks.wind_components`, level from `limits.max_crosswind_kt`), `day_math.gd` (`DayMath`: sunrise and sunset from `WeatherVisuals.sun_rise_set`, bands from `SkyTime.sun_position`; `SkyTime.LAT/LON`), `wind_dial.gd`, `day_strip.gd`, `preset_row.gd`. Tests `test_wind_dial.gd`, `test_day_strip.gd`.
- **Call sign:** `Session.setup.callsign` (`""` = untouched). `core/callsign.gd` (`Callsign`, pure, `tests/test_callsign.gd`): `clean(text)` = `AtcSpeech.normalize_callsign` (`""` when invalid), `filter_typing` (A-Z 0-9 `-`, at most 8 characters), `typed()`, `default_of(def)`, `effective(def)`, `store(text)`, `FALLBACK` VT-FSM, `migrate_legacy()` (moves a call sign typed in the old `options.cfg` `callsign` into the setup once). `RegistrationPaint.text_for` and `AtcSession.callsign()` both call it. The paint cache key includes the text. The A320 atlas has no number, so its VT-ZZA is painted like any text; only the C172 atlas has one baked. Field: `callsign_field.gd` (`CallsignField`): `var cs := CallsignField.new().setup("Call sign")`, then `parent.add_child(cs)`; `cs.edit` is the LineEdit; signal `callsign_changed(value)`; `refresh()` after an aircraft change. It is on the Aircraft step and in Options → Radio (`atc/atc_options_box.gd`). `aircraft_details.gd` is the specification overlay.
- **Airport step** (`airport_page.gd`; keys `airport`, `runway`, `stand`, `start`, `cold`, `air_ft`, `air_nm`, `air_custom`): `airport_data.gd`, `airport_search.gd`, `airport_diagram.gd`, `airport_map_math.gd` (`pick()` tolerances 11 px stand, 15 px ident, 12 px strip; headless-tested), `airport_start_panel.gd`, `stand_list.gd`, `glide_math.gd`, `glide_profile.gd`. Map, search, chips and lists all end in `AirportPage.pick_airport / pick_runway / pick_stand` (`tests/test_airport_map.gd`). Cities: `game/world/airport_cities.json`. Tests `test_airport_search.gd`, `test_stand_names.gd` (needs `data/processed`), `test_stand_display.gd`.
  - **Stand names** (`world/stand_names.gd`, `StandNames`, pure, computed at start; `data/processed` unchanged): `Session.setup.stand` holds the name (a real ref is its own name); `AirportOps.find_stand` also finds a made-up name or `ref (2)`. `StandNames.label(name)` is the one display rule ("stand 12" for a plain ref; "Bay 3", "Gate 4", "Bay 40" as they are), used by the rail, chips, home shortcut, `Session.summary()`, ATC's "where" ("at Bay 3"; "the apron" only away from every stand), the taxi banner (`GroundOps.apron_text`: "Taxi to the apron (Bay 3) via B"; `AtcReplies.parse_route` reads it case-insensitively) and the prop `ops/stand`. `StandNames.name_of(stands, st)` / `AirportOps.stand_name(icao, st)` name one stand. Painted stand numbers and boards show real refs only.
- **Options and Controls** (`options_page.gd`, `options_graphics.gd`, `ui/post_fx_toggles.gd`; `controls_page.gd`, `key_bindings_section.gd`, `controls_row.gd`, `keyboard_reference.gd`, `ControlsHeader`, `controls_filter.gd` (pure: every space-separated word must be found, case blind, in action name, id or bound key)). Tabs: **Left / Right** on a focused tab (Up / Down on the Options rail) select the neighbour and wrap; **Ctrl+Tab / Ctrl+Shift+Tab** switch from anywhere. The tab bar is sticky (pages scroll inside; `follow_focus` keeps the focused row visible). `ControlsPage.show_aircraft(id)` rebuilds the tabs for that aircraft's `AircraftControls` without writing `Session.setup` or a binding. Tests `test_menu_tabs.gd`, `test_controls_filter.gd`.
- **Failures page** (`failures_page.gd`, `failure_row.gd`, `failures_armed.gd`, pure `failures_logic.gd`): areas come from `FailureCatalog.categories()` (ids in the aircraft's `failures.disabled` stay hidden); a trigger starts at its default (10 min / 1000 ft / 100 kt). Setup keys: `failures` (`{id: [mode, value]}`, mode 1 to 4), `random` (`enabled`, `count`, `from_min`, `to_min`, `categories`), `notify`. **Recording page** (`recording_page.gd`): keys `record`, `record_dir`, `record_height`, `record_fps`, `record_mp4`. **Training page** (`training_page.gd`, `lesson_card.gd`, `lesson_info.gd`, `lesson_map.gd`; lessons from `TrainingLogic.lessons_for`). **Saved flights page** (`saves_page.gd`, `save_card.gd`, `saves_logic.gd`; `SituationStore.dir` is a static that tests and probes redirect).

### Thrustmaster TCA Captain Pack X (Airbus): sidestick and quadrant

Controls page > Joystick & gamepad > **Reset: Airbus Captain Pack** (`core/input_profiles.gd`, `InputProfiles.captain_pack(os)`) loads the profile for the Thrustmaster TCA Captain Pack X, Airbus Edition. **Set the switch on the back of the sidestick to PC** (in Xbox mode macOS and Linux see no joystick at all). **Plug the quadrant into the computer or hub directly**, not into the sidestick's USB-A ports: it then shows up as its own pad, `TCA Q-Eng 1&2`. Pads are found by name ("sidestick", "q-eng"; a binding's `name`), then by guid, then by index, so the two USB devices resolve in any plug-in order. An action only acts on an aircraft that offers it, so one physical control can mean something else per aircraft.
- Sidestick: roll, pitch, twist = rudder, trigger = brakes (hold), hat = pitch trim, red button = cockpit view, left grip button = next view, right base keys X = map, Y = flaps up, A = flaps down, B = parking brake toggle, menu button = pause. The base wheel, the left base keys and the grip's other buttons are unbound.
- **Numbers are measured** (owner's hardware, macOS 27.2, Godot 4.7.2 = SDL3, capture 2026-11-04, `tools/hid_probe.swift` raw HID capture and `tests/probe_pads.gd`; Godot's values equal the raw normalised HID values, and Godot numbers axes by ascending HID usage, so the quadrant's descriptor order 0,1,2,3 is Godot axes 0,1,2,5). **Linux numbering has not been checked**: press Bind on any row to capture the real one and record lasting differences in `OS_OVERRIDES` (`core/input_profiles.gd`).
- **Move each lever once** after starting: on macOS a lever reports nothing until it has moved, and until then libresim ignores it (the keyboard still works). Latching switches and selectors are read from the hardware when the flight starts, when F5 restarts it and when a pad is plugged in (see the table); the flaps lever acts only when moved.
- **Lo / Hi** (axis rows, inside Tune): put a lever at its idle end and press Lo, at full and press Hi (a `*` shows it is set). Raw values beyond an end clamp (`lo` may be above `hi`: the quadrant levers read falling when pushed forward). A new Bind or clear drops `lo`, `hi`, `rev`, `clicks`, `detents` and `values` (`InputBindings.CAL_KEYS`).
- Binding data (all in the profile, per lever): thrust levers carry `lo` (raw at idle, lever 1 +0.465 = the middle of its resting range +0.445 .. +0.488, lever 2 +0.47), `hi` (raw at TOGA, -1.0), `rev` (raw at full reverse, +1.0) and `clicks` (`{raw, detent, play}`: the physical clicks and the sim detent each one is). `LeverDetents.forward_pos` maps the raw value piecewise through idle -> 0, the click -> that detent's position over +-`play` of raw, TOGA -> 1, so the CLB and FLX/MCT clicks land exactly on the A320's CL (0.556) and FLX/MCT (0.778) detents; clicks whose detent the aircraft does not have are skipped (the C172 is linear idle..TOGA). Behind idle (`LeverDetents.IDLE_BAND` = 0.05 of raw travel of idle play) it is reverse, growing linearly to REV MAX at `rev`. The speed brake lever carries `detents` + `values` (nearest stop wins, `InputBindings.notched`); the flaps lever carries `detents` (raw per notch).
- Per aircraft data: `aircraft.json` `controls.flaps_lever` = `{"settings": [sim flap setting per lever notch], "on_ground": {"<notch>": setting}}` (A320: `[0, 1, 3, 4, 5]`, `{"1": 2}`); an aircraft without it sends notch i as setting i (the C172: FULL stays at 3). Latching switches are `ControlActions.LEVELS` (prop, off value, on value, `sync` at first sight: `both` / `on` / none) and selector switches `ControlActions.SELECTORS` (one held button per position, none = rest); both are offered per aircraft by action group, so the keyboard and other pads are unchanged.
- **Final mapping** (raw = Godot axis / button numbers; M = measured, A = assumption):

  | Control | Raw | C172 | A320 (sim value) |
  |---|---|---|---|
  | Thrust lever 1 (axis 0) | idle +0.48, CLB click -0.01, FLX/MCT click -0.485, TOGA -1.0, reverse back to +1.0 (M) | throttle linear, idle 0 .. TOGA 1; reverse zone = 0 | throttle_1 position: IDLE 0, CL 0.556, FLX/MCT 0.778, TOGA 1; behind idle controls/reverse_1 up to 1 (REV MAX) |
  | Thrust lever 2 (axis 1) | idle +0.47, CLB -0.02, FLX/MCT -0.48, TOGA -1.0 (M; TOGA assumed as lever 1) | not offered | same for throttle_2 / reverse_2 |
  | Flaps lever (axis 2) | -1.0, -0.456, -0.051, +0.47, +1.0 (M) | flaps 0, 1, 2, 3 (FULL notch = 3) | notches 0, 1, 2, 3, FULL = settings 0, 1, 3, 4, 5; notch 1 on the ground = setting 2 (1+F) (A) |
  | Speed brake lever (axis 5) | -1.0, -0.523, -0.031, +0.465, +1.0 (M) | mixture, analog, RET = rich (cutoff fully back) | controls/speedbrake 0, 0.25, 0.5, 0.75, 1 (A: the sim has no ARM and no detents) |
  | ENG 1 / ENG 2 master (buttons 2 / 3) | latching, pressed = ON (M) | button 2 = magnetos BOTH / OFF | engine_master_1 / _2 (first sight: pressed sets ON, released changes nothing) |
  | Engine mode (buttons 6 / 7) | CRANK = 6 held, IGN/START = 7 held, NORM = none (M) | button 7 = starter (hold) | controls/engine_mode 1 CRANK, 2 IGN/START, 0 NORM |
  | Gear lever (button 20) | latching, pressed = DOWN (M) | not offered | controls/gear 1 down / 0 up; first sight sets the sim from the lever |
  | Auto brake dial (buttons 21-25) | one-hot: 21 BTV, 22 LOW, 23 "2", 24 "3", 25 HI; DISARM = none (M) | not offered | controls/autobrake DISARM 0, BTV 1, LOW 1, 2 -> 2, 3 -> 2, HI 3 (sim: 0 off, 1 LO 1.7 m/s2, 2 MED 3 m/s2, 3 MAX) (A) |
  | Park brake switch (button 19) | latching (M) | parking brake | parking brake (first sight sets it) |
  | Unbound | lever zone buttons (lever 1: 8-11, lever 2: 12-15, speed brake 26-30), 16-18 rudder trim area, pushbuttons | | |

  Assumptions to confirm on the hardware: the flaps lever notch 1 gives CONF 1+F on the ground and CONF 1 in the air (real Airbus: lever 1 = 1+F for take-off, CONF 1 in the air), the six auto brake positions fold onto the sim's three, the speed brake snaps to quarter steps, the reverse zone starts 0.05 of raw travel behind idle and is proportional (the lever has one reverse position; a partly pulled lever gives partial reverse; the A320's REV IDLE detent -0.1 holds), and the pitch direction (forward = -1, not inverted: the capture does not say which way the owner pushed).
- **Live check**: `tests/probe_a320_controls.tscn` runs the real `JoystickControls` on the live pads with the Captain Pack profile (never your saved bindings; nothing is saved) and prints a line for each property that changes with the hardware values behind it:
  `SDL_JOYSTICK_MFI=0 SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1 ~/.local/bin/godot --path game --windowed --resolution 960x540 --audio-driver Dummy res://tests/probe_a320_controls.tscn -- [--aircraft=a320|c172] [--seconds=60] [--air] [--out=log.txt]` (`--air` = wheels off the ground, so flaps notch 1 gives CONF 1). It lists the pads and which pad / axis / button each key action resolved to, then `t=<s> <property> <old> -> <new> [lever position and detent name / flap setting name] | hw: pad0 axis0=-0.485 ...`. Move each control once and read the lines; the first lines at start-up show the switch sync.
- **macOS: joysticks and the Thrustmaster pads.** On macOS 27 SDL3 inside Godot 4.7.2 lists no joystick at all unless `SDL_JOYSTICK_MFI=0` is in the environment before Godot starts (its GameController-framework driver otherwise hides these HID devices; keep SDL's HIDAPI driver on, switching it off breaks detection again), and joystick events only reach the active window unless `SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1`. `./run.sh`, `launch.sh` and therefore `Start libresim.command` export both on macOS; start Godot by hand with `SDL_JOYSTICK_MFI=0 SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1 ~/.local/bin/godot --path game`. The Controls page says so when no pad is connected on macOS. **An exported macOS app** gets the same two variables from its `Info.plist`: `tools/package/patch_macos_env.py` adds them as `LSEnvironment` (Launch Services applies that to the process it starts, which is what a double-click does) and `make_release.sh` runs it on the exported `.app` before the ad-hoc re-sign (editing `Info.plist` would invalidate a signature). Verified on 2026-11-05 on macOS 27.2 with a copy of Godot.app: launched through Launch Services (`open -n -a`), the copy without the entry listed no pads and the copy with it listed both Thrustmaster devices. Not run here: the full `make_release.sh` (no export templates on this machine), so the patch step inside a real export is untested; `python3 tools/package/test_patch_macos_env.py` tests the patch on a sample plist. Side effect: with `SDL_JOYSTICK_MFI=0` Apple-certified (MFi) controllers are read through SDL's HID drivers instead of the GameController framework. `packaging/linux/` is Linux and unchanged.
- **Auto-detect** (`core/captain_detect.gd`, `ui/menu/captain_offer.gd`, `ui/menu/captain_watch.gd`): when a pad whose name contains the profile's device names (`sidestick` or `q-eng`, read from `InputProfiles.PROFILES`; one of the two is enough) is connected, the start screen offers the profile by itself, so you do not have to find **Reset: Airbus Captain Pack**. The prompt "Thrustmaster Captain Pack found" appears at most once per launch, over the home screen or any step (not over the Controls page, the "Fly anyway?" question or a flight that is loading); it checks on the first frame, every 0.5 s for the first 5 s (SDL on macOS lists pads a moment after start) and whenever a pad connects. It does not appear when the saved `input_bindings.json` already is the Captain Pack (`throttle`, `flaps_lever` and `speedbrake` bound by the `q-eng` pad name and `roll` by `sidestick`; deadzones, curves and calibration may differ) or after an answer. Three answers (Esc = Not now): **Use the Captain Pack profile** writes the table through the same code as the reset button (`InputProfiles.apply_to` + `InputBindings.save_bump`, which bumps `input/bindings_rev` so a running flight reloads it) and stores `applied`; **Not now** stores nothing (asks again next start); **Don't ask again** stores `declined`. The answer is the `captain_pack` key of `options.cfg` (`""` = not asked, `applied`, `declined`; the Reset: Airbus Captain Pack button also sets `applied`, the generic reset buttons leave it alone). **To get the prompt again**: on the Controls page, Joystick & gamepad tab, a small link **Offer the Captain Pack profile again** appears under the pad list while a Captain Pack is connected and the answer is `declined` (it clears the key; the offer comes at the next start); or set `captain_pack=""` (or delete the line) in `options.cfg`. The prompt body adds "Linux numbering is not verified for this hardware." on Linux. The start screen shows no in-game notification after "Use" (those exist only in flight).
  Tests: `tests/test_captain_detect.gd` (10: present / applied / should_offer truth table, silent upgrade, shared profile code, Controls reset and link) and `tests/test_captain_offer.gd` (8: the three buttons, Esc, focus ring, start-screen wiring, the 5 s poll); scratch paths only (`CaptainDetect.pads_provider` and `CaptainDetect.bindings_path` are the seams, `Session.interactive_override = 0` keeps `options.cfg` untouched). Screenshot: `FREESIM_FAKE_CAPTAIN=1 [=linux] FREESIM_SHOTS=<dir> [FREESIM_SIZE=1920x1080] godot --audio-driver Dummy --path game res://tests/debug_menu.tscn` saves `menu_captain_offer.png` (fake pads, scratch bindings path, nothing real read or written).
- Tests: `tests/test_input_captain_pack.gd` (13: calibration, pad matching, profile, detents, switches; scratch paths only, it never touches the real `input_bindings.json`), `tests/test_input_captain_a320.gd` (6: offers, thrust levers against the sim detents, reverse, C172 throttle direction, flaps incl. FULL, speed brake) and `tests/test_input_captain_switches.gd` (6: Controls page macOS hint, engine mode, auto brake, gear, masters and park brake sync, C172 magneto switch; shared fixtures `tests/captain_fixtures.gd`, the pad is `JoystickControls.fake_buttons`).

**Lever 2 before it has moved.** macOS sends no initial report for an axis, so a lever reads as "not reported" until it has moved once. With separate thrust levers (A320) and a lever-2 axis bound, an unreported lever 2 rests at idle; it never copies lever 1 (found in the live check of 2026-11-05: lever 2 followed lever 1 until it had been touched). Only an aircraft with no lever-2 axis bound at all lets the throttle axis move every lever. Lever 1's calibrated idle (`lo`) is +0.465, the middle of its resting range +0.445 .. +0.488, so the lever seats in the IDLE detent wherever it comes to rest.

**Visual hardware check (A320).** `./tools/check_a320_controls.sh` opens a window with a checklist of every Captain Pack control (43 items: sidestick directions, both thrust levers through CLB / FLX/MCT / TOGA / IDLE / reverse, the five flaps notches, the five speed brake stops, engine mode, gear, auto brake positions, engine masters, parking brake). Each item ticks green when the game's own response proves the control works (the real `JoystickControls` with the profile, nothing saved); the groups show the live values. There is no timer: press **Complete** (or close the window) and the report of what ticked and what did not goes to `/tmp/a320_check_report.txt`; **Reset ticks** starts again. `--air` runs with the wheels off the ground. The checklist logic is `tests/captain_check.gd` (tested by `test_captain_check`); `--shot=<png>` of `tests/check_a320_controls.tscn` saves a picture of the window.

### Start screen: UI scale, focus and test tools

- **UI scale** (`core/ui_scale.gd`, autoload `UiScale`, with the `canvas_items` / `expand` stretch mode in `project.godot`): the UI works in units = window / UI scale (1280 x 720 at 125 % = 1024 x 576 units; 150 % 853 x 480; 200 % 640 x 360); the percentage is relative to the system scale. The start screen sits in one guard scroll area: a page that needs more room than the window has (the Free flight steps need about 1040 to 1240 units of width) scrolls sideways instead of pushing Next, Fly and Quit off screen. 100 / 125 / 150 % at 1920 x 1080 and 100 % at 1280 x 720 fit everything. Known limits at 1280 x 720: Free flight steps and Training from 125 / 150 % (sideways scroll), the pause screen's Options and Settings from 150 %, almost every page at 200 %.
- **Keyboard focus:** Tab / Shift+Tab visit every shown control once and wrap (`tests/test_focus_order.gd` walks the real focus chain on every page). Free flight: rail, page, footer. Controls: tabs, "Controls for", search, rows. Home: cards, shortcuts, links, then Handbook / Credits / Quit (`HomeScreen.outer`). The "Fly anyway?" question keeps Tab and arrows inside its two buttons. The focus ring is 3 px accent, white on filled accent or amber buttons.
- **Glyphs:** see "UI font (Fira Sans)".

Debug scenes (windowed; scratch data only, they never write your files; run `godot --audio-driver Dummy --path game <scene>`; shots go to `FREESIM_SHOTS=<dir>`, optional `FREESIM_TAG=<prefix>`, `FREESIM_SIZE=1920x1080`):

| Scene (`res://tests/`) | Shows | Variables |
|---|---|---|
| `debug_menu.tscn` | the five Free-flight steps | `FREESIM_FLOW_ONLY=1`, `FREESIM_AIRCRAFT=a320`, `FREESIM_OVERWEIGHT=1`, `FREESIM_OPEN=1` (spec overlay), `FREESIM_CALLSIGN=VT-SID`, `FREESIM_AIRPORT=VAPO`, `FREESIM_START=stand` |
| `debug_weather.tscn` | the weather step for any setup | `FREESIM_AIRCRAFT`, `FREESIM_WIND=000/25`, `FREESIM_RUNWAY=27`, `FREESIM_START=stand`, `FREESIM_TIME=21.5`, `FREESIM_DAY=45`, `FREESIM_WEATHER=Broken`, `FREESIM_OPEN=1` |
| `debug_airport.tscn` | the airport step, one run for all combinations | `FREESIM_AIRCRAFTS=c172,a320`, `FREESIM_AIRPORTS=VABB,VAPO,VOCI`, `FREESIM_MODES=runway,stand,air`, `FREESIM_SIZES=1280x720,1920x1080`, `FREESIM_WIND=270/12`, `FREESIM_HOVER=1` |
| `debug_tabs.tscn` | every Options and Controls tab (`options_<tab>.png`, `controls_<tab>.png`) | `FREESIM_AIRCRAFT` |
| `debug_u7a.tscn` | Failures / Recording / Training / Saved flights pages (sample saves use `docs/ui-rework/assets/saves/`) | `U7A_PAGE=failures\|recording\|training\|saves`, `U7A_ARMED=3`, `U7A_REMOVE=1`, `U7A_RANDOM=1`, `U7A_AIRCRAFT=a320`, `U7A_REC=1`, `U7A_LESSON=2`, `U7A_SAVES=0..5`, `U7A_PICK=n`, `U7A_FOCUS=1` |
| `debug_focus.tscn` | focus ring sheet `<prefix>focus_sheet.png` | |
| `debug_ui_walk.tscn` | every page at a UI scale (home, flight steps, training, saves, Options / Controls tabs, credits, J overlay, pause) plus an audit per page (`tests/ui_audit.gd`) | `FREESIM_SIZE=1280x720`, `FREESIM_UISCALE=125%`, `WALK_ONLY=home,flight,training,saves,options,controls,credits,overlay,pause` |

**The real start path:** `godot --headless --fixed-fps 120 --audio-driver Dummy --path game res://tests/probe_real_start.tscn -- --flow=fly_now|fly_again|continue|fly_anyway` presses the start screen's own buttons, waits for the flight scene, runs 2 s of physics, counts logged errors and prints `REAL START PASS|FAIL` (about 5 s each). `tests/test_real_flight_start.gd` runs the four flows in child processes, checks that your own files were not touched (a failed flow is retried once: the headless renderer sometimes logs a one-off "wrong RID" error) and passes with a note when `data/processed` is missing.

**e2e on macOS:** `tools/e2e.sh` backs up and restores `~/.local/share/godot/app_userdata/libresim` (the Linux user folder). On macOS the game's folder is `~/Library/Application Support/Godot/app_userdata/libresim`, so a plain run changes your options, last flight and saves. Use a scratch home and muted audio: `HOME=<scratch dir> GODOT=<script that runs godot --audio-driver Dummy "$@"> tools/e2e.sh <run> menu` (`menu` runs only the start-screen part).

### Aircraft data: FDM props

Aircraft whose `config.json` has the A320 shapes get extra FDM parts; absent keys = the C172's behaviour (asserted unchanged by the tests).
- `controls.flaps` a Dictionary with `detents` → `AirlinerControls` (`fdm/flight_controls_airliner.gd`): per-surface `SurfaceActuator`s from `controls.surfaces` (lag, rate, clip; aileron / elevator + = trailing edge down, rudder + = nose right, THS nose up = negative), flap and slat detents, 5+5 spoiler panels, speedbrake. The `law` seam: `FlightControls.law.update(dt, fdm)` writes `fcs.cmd` / `fcs.spoiler_cmd` and replaces the direct stick mapping.
- any `gear[].retractable` → `RetractableGear` (`fdm/gear_retractable.gd`, via `Gears.make(cfg)`): retract / extend over `controls.gear_transit`, locked down on the ground, nose wheel `gear[].steer {tiller_deg, pedal_deg, fade_mps}`, `gear[].brake_mu`, anti-skid, autobrake LO / MED / MAX.
- an engine with `thrust_table` → `EngineTurbineFadec` (`fdm/engine_turbine_fadec.gd`; limits from top-level `fadec_limits` through `fdm/turbine_fadec.gd`): JSBSim thrust tables over Mach and density altitude, N1 spool-rate tables, N2, EGT, TSFC x sqrt(T/288.15), start sequence, reverse. `engines[].orient_deg` gives the thrust line. Top-level `apu` adds `systems/apu.gd` (`fdm/apu_model.gd`).
- Expressions and 3-D tables: `fdm/expr.gd`, `fdm/table.gd`. `Aero.strict = true` makes an unknown property name an error (tests).
- **Props read** (`fdm/fdm_airliner_props.gd`): `controls/gear` `speedbrake` `autobrake` `tiller` `engine_master_<n>` `engine_mode` (0 NORM, 1 CRANK, 2 IGN/START) `reverse_<n>` `flex_temp_c` `lights/landing`, `failures/engine_fire[_<n>]`, `systems/hydraulics/antiskid`. The lever of engine n is `controls/throttle_<n>` − `controls/reverse_<n>`.
- **Props published:** `engines/<n>/{n1,n2 (percent),egt_k,ff (kg/s),oil,thrust_n,running,reverser,lever}` (engine 1 also as `engine/*`), `fdm/{mach,slat_deg,spoiler (per panel deg),spoiler_left_deg,spoiler_right_deg,speedbrake,stabilizer_deg,flap_lever,flap_deg,gear_pos,gear_state,door_pos,autobrake_on,ground_speed_mps}`, `apu/{running,starting,n_pct,ff_kgs}`.
- Saved and replayed: FlightControls `slat_deg slat_cmd spoiler spoiler_cmd speedbrake speedbrake_cmd gear_pos gear_cmd thrust_lever`; gear `gear_pos gear_cmd gear_state door_pos`.
- Not modelled: engine feed from the pipe tanks (excluded from the default feed; `fuel.gd` feeds all tanks equally), bleed air, oil / fire systems.

### Aircraft data: flight control law (fly-by-wire)

`aircraft.json` `"fcs": {"law": "airbus_fbw", ...}` installs `FbwLaw` (`fdm/fbw_law.gd` + `fbw_{params,sense,pitch,roll,yaw,trim,protection,reversion}.gd`) as `FlightControls.law` of an `AirlinerControls`; absent = direct stick-to-surface control (the C172). Every other `fcs` key is optional and overrides `FbwParams.DEFAULTS` (nested dictionaries merge): `nz_max / nz_max_flaps / nz_min*`, `pitch_limit_deg`, `vmo_kt / mmo` (default from `limits.speeds`), `ground_blend_s`, `ground_gain` (direct elevator vs CAS kt), `flare`, and the groups `pitch` (`kn ki kq kiq q_max_dps trim_k trim_dead_deg k_alpha alpha_lead_s k_theta`), `roll` (`rate_dps kp ki kff k_bank hold_deg limit_deg limit_prot_deg taper_deg level_deg spoiler_start spoiler_max_deg`), `yaw` (`k_r k_beta limit_deg travel_kt`), `alpha_deg.rows` (`[slat, flap, alpha_prot, alpha_max, alpha_stall]` deg per configuration), `speed_prot`.

- **Laws** (`FbwReversion`): NORMAL; ALTERNATE (load factor law and auto-trim, roll direct, no protections); DIRECT (stick to surface, trim wheel). Reversion from `failures/{adr, adirs, elac (or elac_1 + elac_2), sec, hyd_g, hyd_b, hyd_y, fac}`: ADR / ADIRS / ELAC lost or two hydraulic circuits → ALTERNATE; ELAC + SEC or all three circuits → DIRECT; ALTERNATE with gear down → DIRECT; `fcs/law_force` (0..2) forces at least that law. `fac` only removes the yaw damper and rudder travel limit.
- **Pitch:** stick = load factor demand `cos(gamma) / cos(phi) + increment` (neutral = hold the flight path, also in a bank), rate loop with speed-scheduled gains (`q_ref / qbar`), THS auto-trim, ground mode = direct (scheduled gain) blended over `ground_blend_s`, flare mode (nose-down bias below 50 ft RA, gear down, levers back). **Roll:** stick = roll rate (15°/s), bank hold on release (wings level below 2.5°, back to 33° above it), limit 67° (45° in the alpha / speed protections), roll spoilers on panels 2-5. **Yaw:** pedals with a speed travel limit, yaw damper, turn coordination.
- **Protections** (normal law): high angle of attack (stick maps to alpha between `alpha_prot` and `alpha_max`, alpha floor latch), high speed (nose-up bias above VMO + 6 kt / MMO + 0.01), bank, pitch attitude (−15 / +30°), load factor (+2.5 / −1 g, +2 / 0 g with slats or flaps).
- **Props published:** `fcs/law` ("NORMAL" / "ALTERNATE" / "DIRECT"), `fcs/law_id` (0..2), `fcs/law_reason`, `fcs/ground_mode`, `fcs/flare`, `fcs/alpha_{prot,max,floor,stall}_deg`, `fcs/alpha_floor` (bool, for the A/THR), `fcs/stall_warning`, `fcs/prot/{alpha,speed,bank,pitch,nz}`, `ap/cmd/takeover`.
- **Autopilot interface:** with `ap/cmd/active` the law takes `ap/cmd/nz_g` (g increment) and `ap/cmd/roll_rate_dps` (+ right) instead of the stick; a sidestick deflection above 0.1 sets `ap/cmd/takeover` (the autoflight disengages) and gives the stick back at once.
- Tuned against `tools/a320_reference.json` (JSBSim A320): roll rate 7.4 / 15.3°/s for half / full stick (ref 7.35 / 15.0), alpha limits from the JSBSim tables; pitch is faster than the reference (63 % of a load factor step in about 1 s vs 1.9 s). Tests: `tests/test_fbw_a320*.gd`.

### Aircraft data: replay

Instant replay (R) records the C172 channel list (`systems/replay_layout.gd`, never changed, so C172 recordings keep their layout) plus the optional `replay` section of `aircraft.json` (all keys optional):
- `lerp`, `rad`, `deg`, `bool`, `int`: extra prop keys by kind (`rad` / `deg` are angles interpolated the short way; `bool` / `int` are held between frames).
- `enums`: `{"ap/fma/lateral": ["", "HDG", "NAV", "LOC"]}`: a string prop recorded as an index into its list (a value not in the list is not recorded).
- `units`: per-engine channels `engines/<n>/rpm | thrust_n | fuel_flow_kgs | egt_k | oil_press_pa | oil_temp_k | running` and `controls/throttle_<n>`, `mixture_<n>`, `starter_<n>`. Default: on when the aircraft has more than one engine. With more than two tanks every tank is also recorded as `fuel/tank_kg#<i>`.
- `fcs`: `true` (the list `ReplayChannels.EXTRA_FCS_FIELDS`: `slat_deg`, `spoiler`, `speedbrake`, `gear_pos`, `thrust_lever`) or a list of `FlightControls` field names; a field the aircraft's `fcs` lacks is skipped; an array field gets a channel per element. They play back like the elevator.

Taking control resumes every engine (rpm, running, EGT, oil, levers) and every tank from the replay frame. `tests/test_replay_generic.gd` pins the C172 channel list.

### Aircraft data: saved flights (the saveable rule)

A system node that keeps state between ticks (battery charge, APU, hydraulics, autoflight) joins the group `saveable` in `_ready` (`add_to_group(SituationSystems.GROUP)`) and implements `save_key() -> String` (stable name), `save_state() -> Dictionary` (JSON-safe) and `load_state(d)` (every key optional). `core/situation_systems.gd` then saves it with a flight (`systems.<key>` in the file); nothing else changes. Props under `engines/`, `ap/`, `apu/`, `fcu/` and `hyd/` are saved too. Optional FCS / gear fields (slats, spoilers, speedbrake, gear position) are saved when the object has them (names in `SituationFdm.OPTIONAL_FCS_KEYS` / `OPTIONAL_GEAR_KEYS`). Saves from before the hook (flat `soc`, `suction`, `fuel_line`, ...) still load.

### Aircraft data: model, cockpit, lights, audio

Files are found by `AircraftDef.path(key)`: `models/exterior.glb`, `models/interior.glb`, `sounds/`, `panel.json` in the aircraft folder (override with a `files` map). Without an exterior glb a `PlaceholderAirframe` (`game/aircraft/placeholder_airframe.gd`) is drawn from `config.json` (wingspan, chord, tail arm, gear contacts, one propeller or nacelle per engine) with moving control surfaces. Generic code: `game/aircraft/common/`, `aircraft_model.gd`, `ui/instrument_panel.gd`.

- `model`:
  - `surfaces` `{pivot: {drive, sign}}`: glb node `pivot_<pivot>` turns about its X axis by `sign` x the control position (`drive` = `elevator`, `aileron`, `rudder` in radians, or `flap_deg`). `propellers` `[{pivot, engine (0 = engine 1), sign, visual_rate}]` (spin = `sign * rpm/60 * TAU * dt * visual_rate`; a turbofan's `rpm` is N1 percent: `visual_rate` about 0.75 for a fan, 0.13 for a propeller). Optional `origin_m` places the glb origin (default `metrics.vrp_m`). The glb uses FlightGear's frame (x aft, y right, z up from the origin). A missing pivot is skipped.
  - Airliner drives (`aircraft/model_drives.gd`): `slat_deg`, `stabilizer_deg`, `spoiler_<l|r><n>_deg`, `gear_pos` / `reverser` (0..1, with a piecewise `map` `[[value, degrees], ...]`), `nose_steer_deg`, `wheel_nose_rad` / `wheel_main_l_rad` / `wheel_main_r_rad` (rolling angle from ground speed; ignored below 0.05 m/s; uses the measured tyre radii). A leg pivot may carry `compress: "<gear contact name>"`: the leg is raised by that contact's spring compression, so tyres stand on the ground (static deflection 0.12 m nose / 0.28 m mains on the A320).
  - **Tyre contact:** fixed gear (the C172) needs nothing: glb meshes named like wheel / tyre / fairing / brake / strut nearest each contact move together (or list them in `model.wheels`: `{"<contact>": [node names]}`). `aircraft/common/tyre_contact.gd` measures each tyre (axle, radius) from the meshes and puts its lowest point on the FDM ground under its axle every frame; an optional `lift_m` on a leg overrides the measurement. Ground is one surface for physics and pictures: the FDM's `height_at` interpolates the terrain mesh's own triangles and the runway / taxiway / stand paint meshes are draped on them (`world/ground_drape.gd`, `docs/TYRE-CONTACT-PLAN.md`). Tests `tests/test_tyre_contact.gd` (every aircraft, 2 cm), `tests/test_ground_contact.gd` (1 cm at VABB / VAPO / VOCI). Check: `godot --path game --rendering-method forward_plus --resolution 1920x1080 res://tests/debug_tyres.tscn --audio-driver Dummy -- --aircraft=a320 --airport=VABB --stand --clean --shots=<dir> --tag=a320_stand [--place=grass|slope] [--far]` (prints each tyre's bottom minus the ground; PNGs of every wheel, a low view of the mains, `--far` adds views from 1.5 and 4.5 km).
- Look at an aircraft: `godot --path game res://tests/debug_a320_look.tscn --audio-driver Dummy -- --aircraft=a320 --airport=VABB --stand --clean --shots=<ABSOLUTE dir> --views="name|chase;name2|free|ex,ey,ez|tx,ty,tz" [--lights --tod=21] [--jetway] [--at=10]` (free views in structural metres; `--lights` switches exterior lights on and freezes the flashes bright; `--jetway` prints the jetway mesh corner nearest the L1 door and, for each docked jetway, a `DOCK` line with its hood face, cab floor and gap to the L1 door).
- `cockpit`: `eye` (model frame), `panel_mesh` (the panel's mesh node, so gauge quads clear its bezels) and `spots` `{item: {pos, size, round}}`: where on the interior glb each panel item shows (`pos` model frame, `size` = face width in m). Without an interior glb or spots, a flat placeholder panel is used.
- `cockpit.screens` (glass displays measured on the glb: `{name: {centre, width, height, u_dir, v_dir, normal}}`, model frame): a spot's `screen` (default: its own name) puts the display on a quad of that size and tilt; a spot's `item` names the panel item it shows (the first officer's PFD shows `pfd`).
- `cockpit.levers` (optional; the C172 has none): `{pivot: {drive, map, [move], [sign], [lag], [rate]}}` moves the interior glb node `pivot_<pivot>` in the cockpit view only (`aircraft/common/cockpit_levers.gd`, `CockpitLevers`, built by `Cockpit`). `drive` is a property path or paths joined by ` + ` / ` - ` (a thrust lever is `controls/throttle_1 - controls/reverse_1`, position −1..1; booleans read 0/1); `map` is `[[value, degrees], ...]` (piecewise linear, clamped) about the pivot's +X, or metres along it with `"move": "translate"` (rudder pedals); `lag` is a low-pass time constant (s), `rate` a travel limit (deg/s or m/s). Nested pivots (sidestick pitch then roll, reverser flap on a thrust lever) are separate entries. The A320 moves thrust levers and reverser flaps (TLA 0..45°, reverse to −23°), both sidesticks (±16° pitch, ±20° roll), speedbrake, flaps lever (detents 0,1,1+F,2,3,FULL), gear lever, parking brake, engine masters, engine mode, rudder trim, pitch trim wheel (follows `fdm/stabilizer_deg`), tillers and rudder pedals (slide with `controls/yaw`; toe brakes tilt with `controls/brake_left/right`). Autobrake buttons and lights stay static. Pivots, axes and limits are recorded in `models/interior_pivots.json` (generated with `interior.glb` by `convert_a320_cockpit.py` from `tools/blender/a320_lever_table.py`). Look at them: `godot --path game res://tests/debug_levers.tscn --audio-driver Dummy -- --aircraft=a320 --airport=VABB --stand --clean --shots=<abs dir> --views="name|prop=value,...|eye x,y,z|target x,y,z;..."` (eye and target in structural metres; empty eye = the pilot's view with `||yaw,pitch`).
- `panel.json` (extra keys `size`, `rect`, `span`, `kind` for glass displays: "Aircraft data: displays"): the instrument panel layout: `cell`, `pad`, `switch_h` (px), `radio_w` (cells), `cols`, `rows`, `gauges` (`{name: {script, cell: [col, row], meta}}`, scripts in `ui/gauges/`) and optional `strip` (`{script, cell, span}`), `switches`, `radios`. The item names are what `cockpit.spots` and the 2D overlay layouts (`ui/panel_overlay.gd`) refer to.
- `lights`: `nav` (`{pos, side: left|right|tail, color: red|green|white, size, bulb, range, omni_off}`), `beacon` and `strobe` (same fields; several allowed), `lamps` (`{switch, pos, energy, range, angle, beam, tilt, yaw | aim, skin, pool}`; `skin: true` lights the aircraft itself, e.g. logo / wing scan lights). Any light: `switch` (`controls/lights/<name>`: nav, beacon, strobe, landing, taxi, takeoff, rwy_turnoff, wing, logo; a list = lit when any is on), `lit` (a Props bool that must also be true, e.g. `systems/lights/landing_l_on`), `gear: true` (only with gear down), `parent` (a model pivot such as `gear_nose`: the light moves with it). Positions are structural metres (x aft, y right, z up) on the housing in the exterior glb: measure with `tools/.venv/bin/python tools/glb_probe.py <id> extremes | materials | box ... | ray ...` (header of `aircraft_lights.gd`).
- `audio`: `engine` and `wind` mappings (volume / pitch against rpm and airspeed; keys and defaults at the top of `common/aircraft_audio.gd`). The wavs come from `sounds/`; a missing file is silent. An `audio` with a `layers` list (the A320 pack; draft `game/aircraft/a320/audio_section.json`) uses the data-driven layer engine (`common/audio_layers.gd`, pure curve / gate / trigger functions in `common/audio_curves.gd`, schema in that header): each layer is `{file, bus, loop, drive, volume, pitch, gain, view, muffle_hz, per_engine, gate, trigger}`. `drive` is a Props key (`engines/{n}/n1`) or `[op, ...]`; `volume` / `pitch` are `[[x, y], ...]` tables; `per_engine` makes one copy per engine panned left / right; `gate` conditions (view, ground, props, min / max, in-transit `between`, `moving`) and `trigger` edges (rising / falling / change) fire one-shots; the cockpit view low-passes layers with `muffle_hz` and applies the `view.cockpit` factor. `file` may be a `res://` path to reuse another aircraft's sound. A320 sources: `game/aircraft/a320/sounds/SOURCES.md`, rebuilt and audited by `tools/25_a320_sounds.py` (`--fetch`, `--build`, default audit).

### Aircraft data: livery (paint colours)

The pilot-chosen paint colours are data: `aircraft.json` `"livery"`, made for the C172 by `tools/25_livery_masks.py` (`tools/.venv/bin/python -I tools/25_livery_masks.py [--preview <dir>]`; `--preview` writes colour overlays of the masks). Logic: `aircraft/common/livery.gd` (`Livery`, pure); GPU pass: `livery_paint.gd` + `livery.gdshader`. Plan: `docs/LIVERY-PLAN.md`. There is no start-screen UI for colours yet: use `--livery` or a saved setup.

- **Section:** `atlases` `[{id, texture}]` (exterior atlases that carry paint, path relative to the aircraft folder) and `regions` `[{key, label, default [r,g,b] 0..1, masks [{atlas, mask, luma}]}]`. A region may be on several atlases (the C172's blue is on three), each with its own mask PNG; one `key` is what the pilot picks. `mask` is an 8-bit grey PNG of the atlas size (0 untouched, 255 recoloured, soft edges) in `livery/<atlas>_<region>.png`. `luma` is the mean Rec.709 luminance (sRGB, 0..1) of the atlas under the mask at full strength (>= 242): the shading reference. At most 4 regions per atlas (shader slots). Unknown or malformed parts are ignored (`Livery.parse`); no section = no livery.
- **C172 regions:** `body` (white paint: fuselage, wing, fin, tailplane, wheel fairings), `accent` (the blue: nose and cowl, side sweeps, deck stripe, wing-tip caps, fin and tailplane stripes), `stripe` (grey pin stripe), `struts` (optional: white wing struts and main gear legs, fuselage atlas only; the nose gear leg is bare steel and stays). Kept out of every mask: tyres, propeller, spinner, hub, lamps, glass, antennas, the baked "Cessna" logo and "SKYHAWK" glyphs, and the registration boxes. Masks come from colour thresholds inside island rectangles (lists at the top of the tool); a new aircraft with a paint layer needs its own. They derive from the GPL-2.0-or-later c172p atlases (`third_party/c172p/SOURCE.md`); no repo texture changes, the recolour is made in memory.
- **Choice and rule:** the choice is `{region key: "#rrggbb"}`. `Livery.colors_of(lv, stored)` merges it over the factory colours (bad hex and unknown keys ignored), `Livery.is_identity` = nothing to paint, `Livery.cache_key(aircraft_id, colors)` is the texture cache key (bump `KEY_VERSION` when masks or the rule change). Rule (sRGB as stored, Rec.709 luma): `out = lerp(orig, colour * clamp(luma(orig) / luma_base, 0, 1.3), mask)`, alpha kept, channels capped at 1, so baked occlusion, panel lines and dirt survive. Where regions meet the weights are added up and each takes the luminance left after the others' share (`Livery.recolor_multi`), so edges have no dark halo. A very bright colour on a bright paint saturates a channel; a region at factory colour still goes through the shader and can differ by about 1 %.
- **`LiveryPaint.compose(host, def, atlas_id, atlas, colors) -> Image`:** awaits one drawn frame and returns an RGBA8 image of the atlas size without mipmaps (the caller stamps the registration, then `generate_mipmaps()` and `ImageTexture.create_from_image`), or `null` = use the original (factory colours, no region on this atlas, mask missing or wrong size, no pixels on the dummy renderer / headless).
- **Setup:** `Session.setup.livery` = `{<aircraft id>: {colors: {region key: "#rrggbb"}}}`, saved in `last_flight.json`; a missing entry = factory. `Livery.repair_setup` drops what it cannot use (not a dictionary, unknown aircraft or region, bad hex), writes lowercase hex, never raises, keeps unknown keys of an entry. `Livery.entry(all, id)` is the safe read.
- **Command line:** `--livery=body=#c8101a,accent=#f2f2f2,stripe=#26262b,struts=#f2c200` (a bare `rrggbb` also works); per aircraft: `--livery=c172:body=#c8101a,a320:fin=#102030` (`Livery.parse_cli`; bad items and unknown regions skipped). It is a flight option: the start screen is skipped, nothing is saved, and a command-line flight starts from the factory livery.
- **One pass per atlas** (`aircraft/common/paint_pipeline.gd`, `PaintPipeline.apply`, called by `AircraftModel._build_glb`): base atlas → livery recolour (only if a region on that atlas differs from factory) → registration (wipe the old number, stamp the new one) → `generate_mipmaps` → cached `ImageTexture` → surface override on every exterior surface using the atlas. **The order is fixed:** number boxes are outside every mask and the wipe reads the recoloured rows, so the number sits on the new paint; mipmaps last. After an override a surface no longer shows its atlas path, so a second painter would find nothing.
- **Cache** key `aircraft | TEXT | atlas | livery key` (`factory` when all regions on that atlas are at factory colour): a new colour or call sign repaints, a setup seen before does not, a colour not on an atlas never repaints it. At most 9 textures are kept (about 22 MB each with mipmaps). Nothing is painted when the livery is factory and the registration is the number the atlas carries (`registration.baked`; the C172's default VT-LBR is not baked, so it is repainted).
- **While painting:** the exterior is hidden for the frames the GPU needs (a one-shot SubViewport per atlas and glyph style); a 12 s watchdog shows it again. A headless run does not paint; a renderer that returns no pixels keeps the factory atlas.
- **Tests and probes:** headless `tests/test_livery.gd`, `test_livery_struts.gd`, `test_paint_pipeline.gd` (GPU compose and glyph render replaced by `PaintPipeline.test_compose / test_glyphs`), `test_livery_session.gd`, `test_registration.gd`. Windowed (window in front; an occluded window is not drawn on macOS):

```bash
~/.local/bin/godot --path game --windowed --resolution 800x600 --audio-driver Dummy res://tests/debug_livery.tscn -- --out=<dir> [--aircraft=c172] [--liveries=red,navy] [--views=front] [--no-checks]
~/.local/bin/godot --path game --windowed --resolution 960x600 --audio-driver Dummy res://tests/debug_livery_flight.tscn -- --out=<dir> --livery=body=#c8101a,accent=#f2f2f2,stripe=#26262b,struts=#f2c200 --callsign=VT-LBR --airport=VAJJ --clean --quality=low [--air] [--factory]
```

The first prints `LIVERY PROBE PASS|FAIL` lines (factory returns null; mask-0 pixels identical; registration boxes untouched; GPU equals `Livery.recolor_multi` within 2 levels) and saves atlas crops and 3/4 renders. The second runs the real flight scene, checks the painted fuselage atlas against the original and the masks, saves front / rear / fuselage-side / wing-underside shots and prints `LIVERY FLIGHT PASS|FAIL`; with `--headless` it checks that the factory look stays and nothing hangs.

### Aircraft data: displays

Glass-cockpit aircraft (the A320-family one) draw their screens in code from Props, through the same panel pipeline as the steam gauges (SubViewport, 3D quads, click forwarding).

**panel.json schema** (new keys optional; the C172 file uses none and its rects are unchanged, asserted in `tests/test_displays.gd`):
- `size [w, h]`: natural size in px; without it the grid size is used, enlarged to hold every `rect`.
- Any item (`gauges[name]`, `strip`, `radios`, `switches`): `rect [x, y, w, h]` in px instead of `cell`; `span [cols, rows]` of grid cells (gauges; `strip` had it already).
- `gauges[name].kind: "display"`: the script is a full-rect `Display` (`ui/displays/display.gd`) that scales its own drawing (its `design` size) into the rect; otherwise a round `Gauge`. Item names (`pfd`, `nd`, `ewd`, `sd`, `fcu`, `mcdu`) are what `cockpit.spots` and the `overlay` layouts refer to.
- Example: `game/aircraft/a320/panel.json`. Preview and screenshots: `godot --path game res://tests/debug_displays.tscn --audio-driver Dummy` (PNGs to `$FREESIM_SHOTS`).

**Displays** (`ui/displays/`, Godot's default font, no copied code or fonts): `pfd.gd` + `pfd_tapes.gd` (attitude, pitch ladder, speed tape with Vls / Vsw / Vmax and trend, altitude tape and baro, V/S, heading arc, FD bars, ILS, radio altitude, 5-column FMA), `nd.gd` (ARC / ROSE, route, airports, VORs, wind, GS / TAS), `ewd.gd` (N1 / EGT / N2 / FF per engine, thrust limit, FOB, flaps, memo), `sd.gd` + `sd_pages.gd` (ENG, FUEL, WHEEL, F/CTL), `fcu.gd`, `mcdu.gd` (INIT, F-PLN, PERF; a lite unit, TODO list in its header). Clicks: FCU buttons / knobs (left / right half or wheel, right click x10, middle click toggles managed), ND mode and range labels, SD page keys, MCDU keys.

**Props read by the displays** (never the FDM directly): `instruments/pfd/{valid, ias_kt, mach, tas_kt, trend_kt, vls_kt, vsw_kt, vmax_kt, alt_ft, baro_hpa, baro_std, vs_fpm, ra_ft}` (`instruments/airliner_air_data.gd`), `instruments/adirs/{valid, pitch_rad, roll_rad, heading_deg, track_deg, slip}` (`adirs.gd`; failure flags `failures/adr`, `failures/adirs`), `instruments/engines/{count, <n>/{n1_pct, n2_pct, egt_c, ff_kgh, oil_psi, running}}` (`airliner_engines.gd`), `instruments/nd/{route, near, wind_dir_deg, wind_kt}` (`nd_feed.gd`, needs its `db` set to a NavDatabase), `controls/fcu/*`, `ap/{ap1, ap2, athr, fd, loc, appr, fd_pitch_rad, fd_roll_rad, thrust_limit, n1_target, fma/{thrust, vertical, lateral, approach, misc}}`, `fdm/{flap_lever, flap_deg, slat_deg, gear_pos, groundspeed_mps, position_enu, aileron_deg, elevator_deg, rudder_deg, stabilizer_deg, spoiler_deg, speedbrake}`, `fuel/{total_kg, tank_kg, tank_cap_kg}`, `avionics/{nav1,nav2,gps}/*`, `controls/{autobrake, parking_brake, baro/{hpa, std}}`, `ewd/{memo, warnings}`. Everything has a safe default. Air-data speed markers come from `instruments/airspeeds.gd` (`aircraft.json` `limits.speeds`: `ref_mass_kg, vs1g_kt [[slat+flap deg, kt]], vls_k, vsw_k, vmo_kt, mmo, vfe_kt, vle_kt`; defaults for a 64 t A320-class jet).

**Props written by the displays:** `controls/fcu/{ap1, ap2, athr, loc, appr}` (bool toggles), `controls/fcu/{spd_kt, hdg_deg, alt_ft, vs_fpm}` (pilot units), `controls/fcu/{spd, hdg, vs}_managed`, `controls/nd/{mode, range_nm}`, `sd/page`, `mcdu/{page, scratch, init/*, perf/*}` and, from the F-PLN page, `controls/gps/{target, route_next}`.

## 4b. Building and installing release packages

**Build** (repo root, after the data pipeline; needs the Godot export templates below; ~4 min):

```bash
tools/package/make_release.sh 0.1.0
```

Export templates (one time):

```bash
mkdir -p ~/.local/share/godot/export_templates && cd ~/.local/share/godot
curl -LO https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz
unzip Godot_v4.7.2-stable_export_templates.tpz -d tpl && mkdir -p export_templates/4.7.2.stable
mv tpl/templates/* export_templates/4.7.2.stable/ && rm -rf tpl *.tpz
```

**Outputs in `build/`:**

| File | Size | For |
|---|---|---|
| `libresim-<v>-linux-x86_64.tar.gz` | ~450 MB | Any 64-bit Linux: extract and run `libresim/libresim.sh` |
| `libresim-<v>-x86_64.AppImage` | ~440 MB | Any Linux, single file: `chmod +x` and run it |
| `libresim-<v>-macos-universal.zip` | ~480 MB | macOS 11+ (Intel and Apple Silicon): unzip, move `libresim.app` to Applications |
| `libresim-<v>-source.tar.gz` | ~65 MB | GPL corresponding source of that build |

**Flatpak** (wraps the Linux tar.gz):

```bash
flatpak install --user flathub org.freedesktop.Platform//25.08 org.freedesktop.Sdk//25.08 org.flatpak.Builder
flatpak run org.flatpak.Builder --user --install --force-clean build/flatpak packaging/flatpak/org.freesim.FreeSim.yml
flatpak run org.freesim.FreeSim
```

**macOS:** the build is ad-hoc signed with `rcodesign` (runs on Linux) and **not notarised**. On first launch right-click the app → Open, or run `xattr -dr com.apple.quarantine /Applications/libresim.app`. For public distribution, sign with an Apple Developer ID and notarise (`rcodesign` or Xcode; needs a paid Apple Developer account).

**Command-line options** work the same in every package: `./libresim.sh -- --airport=VABB --stand`; the AppImage takes them directly: `libresim.AppImage -- --stand`.

**Read-only installs** (AppImage, Flatpak): the F10 → Renderer toggle cannot write `override.cfg`. Start with `--rendering-method forward_plus` instead.

## 5. Aircraft models and 3D scenery

**The aircraft** is the FlightGear c172p model and cockpit (GPL-2.0-or-later, c172p team), converted by the Blender scripts in `tools/blender/`; the original sources are in `third_party/c172p/`. The live gauges are drawn onto the real panel at each instrument's true position. Without the `.glb` files the sim falls back to a box placeholder.

**3D buildings** (578k OSM footprints; heights from OSM tags or an estimate by footprint size; streamed within 9 km, hidden above 2500 ft AGL; scene `city_district`):
- **Geometry** (`tools/building_geom.py`, written by `10_buildings.py` as BLD2): flat roofs of 90 m² and more get a sloped parapet strip; small 4-corner footprints (under 150 m², up to 7.5 m) get a hip roof (30 % in the Mumbai-Pune grid, 75 % in the Konkan-Kerala corridor); big flat roofs get a stairwell box (from 250 m²) and a hexagonal water tank (from 400 m²). A BLD2 vertex carries wall height (cm, 16 bit), a parapet / rooftop-kind byte and the height fraction, besides roof colour and a style byte (`pid << 2 | roof type`). `Buildings` still reads old BLD1 tiles.
- **Shader** (`world/building.gdshader`): a hash of the building seeds wall colour, window rhythm, floors (3.1 m), slab edges, sills, balconies, shopfronts on the ground floor of medium buildings, glass curtain-wall towers above 32 m, dirt, soot and rain streaks; roofs: bare concrete, white coating, brick, tarpaulin or the satellite colour. Pattern detail fades to the average colour with distance. Windows light up at night. Buildings cast and receive the cascaded sun shadows. Researched terminals without a landmark model (roof type 2, `tools/terminal_ref.py` `facade_look`) use `world/building_terminal.gdshaderinc` (reference cladding, glazing share, roof colour, evenly lit hall at night; `docs/TERMINALS.md`).

**Water:** the Arabian Sea, creeks, rivers and lakes (elevation data and OSM water polygons) use an animated surface with wind waves, sun glints and Fresnel sky reflection; shallow creeks keep the satellite tint.

**Clouds:** a raymarched volumetric cumulus layer at the configured base and cover. It reads scene depth, so you can fly under, through (fog inside) and above it. It drifts with the wind aloft and is lit by the sun (darker bases, warm tints at sunset).

**Graphics presets** (F10, Options or `--quality=`):

| Preset | Renderer | FPS on a Radeon 780M | Render scale | Shadows | Buildings / trees range | Cloud steps (light samples) |
|---|---|---|---|---|---|---|
| Low | Mobile | ~69 | 70 % + FSR | off | 4 km / 1.2 km | 10 (1) |
| Medium | Mobile | ~62 | 85 % + FSR | 700 m, 2 cascades, atlas 4096 | 6 km / 1.8 km | 16 (1) |
| High | Forward+ | ~51 (Mobile) | 100 % + MSAA 2×, SSAO | 1.8 km, 4 cascades, atlas 4096 | 9 km / 2.2 km | 24 (2) |
| Ultra | Forward+ | ~45 (Mobile) | 100 % + MSAA 4×, SSAO, SSR, TAA | 4 km, 4 cascades, atlas 8192 | 12 km / 3 km (LOD0 tree meshes: 150 m; High 120, Medium 90, Low none) | 40 (3) |
| Max | Forward+ | not measured | 125 % supersampling + MSAA 4×, SSAO, SSIL, SSR, TAA | 6 km, 4 cascades, atlas 8192 | 16 km / 4 km (tree meshes 250 m) | 64 (4) |

(FPS figures are from before the cascaded shadows and Forward+ and have not been re-measured.)
- Each preset names its renderer (`core/graphics_settings.gd`, `renderer` key). Low and Medium run on Mobile (fastest on integrated GPUs); High, Ultra, Max on Forward+, the project default. Picking a preset on the other renderer writes `override.cfg` (git-ignored), and Options and F10 show "Restart libresim to apply". The F10 Renderer toggle overrides this until the next preset change. On the first start without `override.cfg`, a saved Low / Medium preset writes Mobile.
- Forward+ adds SSAO (High+), SSR on water and wet runways plus TAA (Ultra+), SSIL (Max), FSR2 instead of FSR1 below render scale 1, and more real apron floodlight lamps (2 / 4 on Low / Medium (Mobile: never more than 4), 10 / 16 / 24 on High / Ultra / Max).
- Every preset sets the sun shadow atlas size and the soft-shadow filter quality at run time. Anisotropic filtering is 16× (project setting). Clouds take `cloud_light` light samples per step (`CloudLayer.light_steps`).

**Ground detail and sun glare:** `world/terrain.gdshader` adds tonal variation at field and hill scale, plus fine grain and a micro-relief normal within about a kilometre, over the 10 m imagery (water excluded). `world/sun_glare.gd` / `sun_glare.gdshader` draw a veil, faint starburst and lens ghosts when the sun is in view (not on Low); terrain, cockpit frame and clouds cut it off (depth buffer), and looking toward the sun lowers exposure by up to 20 % (`SkyTime._update_glare`). Tone mapping is AgX (`docs/GRAPHICS-PLAN.md` G1).

**Ground materials and airport pavement** (`tools/26_terrain_textures.py`, `tools/27_pavement.py`; GRAPHICS-PLAN G6): within ~1.2 km the terrain gets tiling CC0 ground materials per WorldCover class (soil on crops, grass, dry scrub, laterite on bare ground, forest floor, gritty built-up ground, sand near the sea, mud in wetlands / mangroves, rock on steep Ghats slopes) at three scales, multiplied under the satellite colour. Aprons, stands and runway / taxiway shoulders are pavement (`world/terrain_pavement.gdshaderinc`): concrete slabs with sealed joints aligned to the runway, asphalt where OSM says so, tyre marks along stand lead-in lines, oil stains where aircraft park, rubber and grime streaks. The pavement tile loads with the road tile (within ~3.6 km). Credits: `CREDITS.md`, `game/world/textures/terrain/SOURCES.md`.

**Roads, rivers and shores** (`tools/20_roads_rivers.py`, `tools/21_shore.py`): the 10-20 m imagery smears roads and creeks, so OSM lines are rasterised into 4 m signed-distance tiles (`terrain/ro/0/`) that `world/terrain.gdshader` draws crisply: asphalt with tyre tracks and white edge / yellow centre lines on primary to tertiary roads (lane lines on motorways and trunks, within ~600 m), plain grey minor roads, tan tracks with ruts, rivers / canals / streams as thin water ribbons with a wet bank. Everything fades out by ~3.3 km; nothing is drawn over runways, aprons or water (bridges stay). Only the level-0 tiles within 3.6 km of the camera are resident (`world/terrain_roads.gd`, `terrain_quadtree.gd`). Narrow roads draw at least ~4.4 m wide; centre lines are solid. Water uses the shore tiles (`terrain/sd/`): shoals fade from turquoise to deep grey-blue over ~100 m, swash lines and wave fronts run toward open coasts (none on rivers, ponds, sheltered water). Not done: mud near river mouths, bathymetry (the DEM is flat at sea level), road dashes, bridges as geometry.

**More sky and surface effects:**
- **Cloud shadows** (`CloudLayer._publish_shadow` publishes coverage noise, wind phase, sun direction and strength as global shader parameters; `terrain.gdshader` darkens ground under a cloud; none under a thick deck, in clear air or at night), a **cirrus layer** (`sky_clouds.gdshader`), **forest floor** darkening under dense tree cover, darker tree crowns underneath, and a **Fresnel cockpit glass** (`aircraft/c172/glass.gdshader`).
- **Aircraft reflection probe** (`aircraft/c172/reflection_rig.gd`, `reflection_policy.gd`; off on Low): a ReflectionProbe above the aircraft captures the real surroundings so glass and paint reflect more than the sky (airframe layer only; box projection off). It re-captures when the picture changed (sun ±2°, 300 m travel, 150 m altitude, cloud / rain / visibility, preset change, 5 s after start) plus periodically (Medium 30 s, High 12 s, Ultra 5 s, Max 3 s; never faster than every 2 s), seeing 2.5 / 4 / 6 / 8 km on Medium / High / Ultra / Max. Resolution is the engine default (128 on Mobile, 256 on Forward+); it cannot be set per preset at run time.
- **Banding:** debanding is on (`project.godot`, `Viewport.use_debanding` in `Graphics.apply_to_scene`) and the sky shader adds about 4 % dither noise.
- **Atmosphere:** `world/atmosphere.gd` is a single-scattering Rayleigh + Mie + ozone sky on a spherical planet, with a twin in `sky_clouds.gdshader` (`atmo_sky`; keep them in step). Overcast, night, rain flashes and city glow still come from `SkyTime`, which also samples it for the fog / haze colour and the sun colour (`Atmosphere.sun_color`: white high, orange at 8°, red-orange at the horizon). After sunset the model keeps the sun on the horizon and fades (`Atmosphere.twilight_gain`); aerosol follows visibility.
- **Auto exposure** (`world/auto_exposure.gd`): Godot's camera auto exposure is Forward+ only, so this is a CPU estimate (sunlit or shaded ground, sky, camera pitch; gentle power law 0.3, clamped 0.8 to 1.5, at most 1.2 at night; smoothed 2.4 s toward darker, 0.9 s toward brighter). Published as `environment/exposure_mult`; off on Low (`ae` in the preset table).

**Trees:**
- Forests are placed from the satellite vegetation index, excluding buildings, roads, runways and water, generated deterministically within the preset's range (1.2 to 3 km) in streamed chunks. Hidden above 1500 m AGL.
- **Species** (`world/tree_species.gd`, one rule for drawing, LOD0 meshes and collisions): broadleaf (mango, neem, banyan), coconut palm, umbrella acacia, slim casuarina / eucalyptus. Palms follow region and elevation (a tenth in the Mumbai lowlands, up to 40 % on the Konkan coast, 45 % in Kerala, almost none above 160 m); acacias are common on the dry plateau above 400 m; slim trees stay near the sea. Palms have a thinner collision disc.
- **Impostors** (`world/tree_atlas.gd` + `tree_atlas.gdshader`, `tree.gdshader`): two SubViewports draw a procedural atlas once at startup (4 species x 4 variants of 128x256 px; albedo with baked occlusion, and a normal). Alpha-tested (`ALPHA_SCISSOR_THRESHOLD` 0.5, alpha to coverage under MSAA) so they take the volumetric fog composite. They cast no shadows (impostor shadows measured +9-10 ms at Ultra). Headless runs skip the baking.
- **LOD0** (`world/tree_lod.gd`, `tree_meshes.gd`, `tree_mesh.gdshader`): within the preset's LOD radius (Ultra 150 m, High 120, Medium 90, Low none) trees are real low-poly meshes (tapered trunk, 5 to 7 icosphere crown lumps, or palm fronds; 300 to 600 triangles) in 80 m cells, instanced per species, casting and receiving shadows. The impostor dithers away over 8 m where the mesh dithers in (`TreeLod.covered`). Off above 450 m AGL.

### Replacing the models with your own Blender models

1. Model in Blender in metres, **−Z forward, +Y up, origin at the C172's CG** (about 1.0 m aft of the JSBSim datum; see `mass.empty_cg_m` in `config.json`). Export glTF (`.glb`).
2. Name animated parts `elevator`, `rudder`, `aileron_L`, `aileron_R`, `flap_L`, `flap_R`, `prop`, with pivots on their hinge lines.
3. In the cockpit model, leave a flat panel face with UVs covering 0–1 and a material whose albedo is the panel SubViewport texture (see `Cockpit.build`), so the gauges and clickable knobs keep working.
4. Put the `.glb` files in `models/` of the aircraft folder (`exterior.glb`, `interior.glb`). `AircraftModel` uses them when present (see "Aircraft data: model, cockpit, lights, audio"), else a placeholder airframe sized from `config.json`.

The FlightGear c172p model (GPL) is fine as a private, local stand-in, but do not redistribute it.

## 5b. FlightGear assets and licences

See `docs/FLIGHTGEAR_NOTES.md`. The FlightGear c172p model and cockpit (GPL-2.0-or-later) can be converted with the Blender AC3D add-on and used locally. Distributing them requires GPL compliance; details and credit text are in `CREDITS.md`. The satellite imagery is CC BY-NC-SA: non-commercial use only.

## 6. Project layout

```
tools/        offline Python pipeline (section 3); common.py holds region/grid constants
data/raw      downloaded sources (gitignored)
data/processed generated tiles/JSON (gitignored)
game/         Godot project
  core/       floating_origin + props (autoloads), geo (lat/lon <-> ENU), units, paths
  world/      flight scene (main), weather, sky_time, clouds, runway_lights, terrain quadtree/cache/shader, airport_builder + runway shader, terrain_viewer scene
  input/      free_camera, keyboard_controls
  fdm/        flight model: aero (JSBSim tables), engine, propeller, gear, atmosphere
  tests/      headless test runner + suites
  ui/         hud, camera_rig, perf_overlay, instrument_panel + gauges/, panel_overlay
  systems/    pitot_static, vacuum, electrical, fuel
  instruments/ air-data, gyro, compass, engine gauge models (publish instruments/* props)
  aircraft/<id>/ one aircraft: aircraft.json, config.json + aero.json (from JSBSim; edit to tune), panel.json, models/, sounds/
  aircraft/common/ code shared by all aircraft (cockpit, lights, audio, reflections); aircraft_def.gd reads an aircraft folder
docs/USAGE.md this file
```

### UI font (Fira Sans)

Menus and in-game panels that use `MenuTheme.make()` (start screen, pause, saves, controls overlay) use **Fira Sans** (SIL OFL 1.1), unmodified, as four TTFs in `game/ui/fonts/` with `OFL.txt` and `FONT-NOTICE.txt` (copy and checksums in `third_party/fira-sans/`). `MenuTheme.font("regular" | "medium" | "semibold" | "bold")` returns the cached `FontFile`; `MenuTheme.use_font(control, "semibold", 28)` sets weight and size; `Theme.default_font` is Regular. Design tokens (`ACCENT` `#59BFFF`, `ACCENT_INK`, `DIM`, `PANEL`, `OK` / `WARN` / `BAD`, the `SIZE_*` scale, the 3 px focus ring `MenuTheme.focus_box()`) are in `ui/menu/menu_theme.gd`. The F12 credits and `CREDITS.md` credit the font; `tools/package/make_release.sh` copies `packaging/licenses/fira-sans-OFL.txt` into the release `licenses/` folder. Replace a font file only with the identical upstream file (never rename or edit it: Reserved Font Name "Fira"). The in-flight HUD and gauges use Godot's fallback font. Tests: `tests/test_menu_theme.gd`, `tests/test_attribution.gd`.

**Symbols.** Fira Sans has no triangles, circles, stars, check marks or cog, which the menus use as text (`▶ ◀ ▲ ▼ ● ○ ★ ☆ ✓ ✕ ✗ ⚙`). All four Fira weights list `game/ui/fonts/LibresimSymbols.ttf` as explicit fallback (`MenuTheme.symbols()`): 12 glyphs cut out of DejaVu Sans (about 12 KB, renamed "libresim Symbols" as the Bitstream Vera licence asks; `tools/make_symbols_font.py` rebuilds it; licence and notes in `third_party/dejavu-symbols/`, licence text in the release `licenses/` folder, credited in `CREDITS.md` and on F12). `tests/test_font_glyphs.gd` fails when a character in a start-screen, pause, credits or training script is in neither font. To use a new symbol, add it to `SYMBOLS` in the tool, rebuild and re-run the test. Not covered: two in-flight characters (the radio stack's `⇄`, the attitude gauge's `∩`) use the engine's default font.

## 6b. Knowledge graph of the repository (optional, graphify)

`/graphify .` (the graphify skill for Claude Code) builds `graphify-out/` (git-ignored: `graph.html`, `GRAPH_REPORT.md`, `graph.json`) from the Python tools and docs, but has no GDScript parser. `tools/gd_graph.py` adds the game without model calls:

```
$(cat graphify-out/.graphify_python) tools/gd_graph.py          # from the repo root, after /graphify .
$(cat graphify-out/.graphify_python) tools/gd_graph.py --dry    # only print the counts
```

It reads `game/**/*.gd`, `*.gdshader`, `*.tscn` and adds scripts, funcs, signals, scenes, resource json and one node per property-tree path used with a literal (`Props.get_f("fdm/ias_mps")`), with edges `contains`, `inherits`, `references`, `uses`, `calls` and `reads_property` / `writes_property`. Not resolved: calls through instance variables, dynamic `load()` paths, run-time property paths, signal connections. Run it again after code changes (its earlier nodes are replaced, the rest is kept). Above 5000 nodes `graph.html` shows one node per community; use `graphify query` / `explain` / `path` for node-level questions.

## 7. Troubleshooting

| Symptom | Fix |
|---|---|
| `godot: command not found` | Use `~/.local/bin/godot` or add `~/.local/bin` to PATH (section 1) |
| `missing data file: .../terrain/meta.json` | Run the pipeline (section 3) |
| Terrain is a flat green-grey colour | Imagery tiles are missing: run `01b_fetch_imagery.sh`, then `03_imagery_tiles.py` |
| `01b_fetch_imagery.sh` fails partway with HTTP errors | Re-run it; GDAL retries each tile 5 times. The EOX server sometimes rate-limits |
| Aircraft spawns in the wrong place / no runway | Run `tools/09_runways.py` (writes `data/processed/runways.json`) |
| No joystick found on macOS | See "macOS: joysticks and the Thrustmaster pads" |
| No sound | Godot uses PulseAudio/PipeWire; check the system output device |
| Low FPS | Check the F3 overlay. Lower `lod_k` on the Terrain node in `world/flight.tscn` (default 1.6), or turn off `shadow_enabled` on the Sun |

Developer probes (all in `game/tests/`; most need `data/processed`):

| Question | Command |
|---|---|
| Where does the frame time go? | `godot --path game res://tests/debug_perf.tscn -- --airport=VABB --runway=27 --air=1000 --quality=high --log=/tmp/f.csv --dur=60` logs every frame (GPU, physics, pipeline compiles, per-node `_process` time) and prints the worst frames and top consumers |
| Jump at the 5 km origin shift? | `res://tests/debug_origin.tscn -- --airport=VABB --runway=27 --air=1500 --dur=150` prints the largest per-frame world-space move of camera, aircraft and static scenery, split into normal and shift frames (static must be 0) |
| Does a stand look right? | `godot --path game res://tests/debug_stand.tscn -- --airport=VOCI --stand=B7 --tod=12 --weather=clear --shots=/tmp/s` saves `stand_chase`, `stand_orbit`, `stand_overview` PNGs (needs a display); `--cam=e,n,height_agl,yaw_deg,pitch_deg` puts the free camera anywhere instead and saves `cam.png` |
| Flicker / scenery check at a fixed spot | `res://tests/debug_view.tscn -- --eye=e,n,alt --at=e,n,alt --wait=12 --out=/tmp/v.png` (free camera, world metres); `--to=e,n,alt --frames=N` saves a fly-through frame by frame. `debug_perf.tscn ... --burst=/dir@20x10 --freeze` saves 10 frames with sim time stopped (any change = instability) |
| Does a crash register? (trees, buildings, terminals, jetways, vehicles) | `godot --headless --path game res://tests/obstacle_probe.tscn -- --only=mirror,forest,city,taxi,airport,corridor,fast,scan,ops` runs scripted flights and taxis in the real world and prints one `ROW` per case. `--only=scan --icao=VABB [--rules]` puts the aircraft at every stand, pushback path, taxiway and runway and reports overlaps with a solid (`--rules`: after the forgiveness rules; normal ops must give 0). `--only=ops` takes off from and lands on 10 runways; `--only=perf` times the collision check |
| Can a student-like pilot still land? Does the PAPI show the right colours? | `godot --headless --fixed-fps 120 --path game res://tests/play_landing.tscn -- --lesson=landing,off [--seed=N --wind=220/12G18 --turb=0.15 --nm=4.5 --ft=1700 --papi-need=WWWW\|RRRR]` flies the landing lesson's runway in the real flight scene with the real keyboard handling (a bot holds and releases keys, deciding every 0.1 s from what a pilot sees; `--seed` is the airspeed-needle noise) and checks the PAPI (4 units on the left, abeam the glide-slope point, 3.5 / 3.17 / 2.83 / 2.5°; the view at 4.5 / 3 / 2 / 1 / 0.5 nm must equal the reading from the elevation angle; `--ft=1300 --papi-need=WWWW` and `--ft=700 --papi-need=RRRR` start high / low). It writes none of your files. Last line: `PLAY RESULT PASS\|FAIL reason=.. touchdown_ias=.. vs_fpm=.. along_m=.. cross_m=.. bounces=.. papi=OK\|FAIL ..`, exit code 0 / 1; the sweep loop is in the header of `game/tests/play_landing.gd` |