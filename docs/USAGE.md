# libresim: setup, running and usage

This guide covers how to install, build the map data, and run libresim, a local Cessna 172 flight simulator for the Mumbai–Pune region. Design and roadmap are in `PLAN.md`; the coding conventions are in `CLAUDE.md`.

## Quick start: double-click, or `./run.sh`

**Without a terminal.** Open the project folder in your file manager and double-click:

- **Linux:** `Start libresim.desktop`. Ready to play: the game just opens (output goes to `data/run.log`). First time or data missing: a terminal window opens, runs `./run.sh` (asks before installing anything with `sudo`) and starts the game when done. GNOME: right-click the file once and choose **Allow Launching**; COSMIC and KDE: just double-click (if your file manager asks, mark it trusted).
- **macOS:** `Start libresim.command` (opens Terminal for the setup, then the game; if macOS blocks it the first time, right-click, Open).
- Each launch also adds **libresim** to your applications menu (`~/.local/share/applications/libresim.desktop`, with the logo), so afterwards you can start it from the menu or app launcher like any other program. `./launch.sh --register-only` adds just the menu entry.
- The launcher finds the game folder from its own location, falling back to `~/.config/libresim/root` (written on every launch), so it still works if your file manager starts it from another directory.

**From a terminal:** one command installs what is missing, downloads the raw data, builds the game data and opens the game:

```bash
./run.sh                              # set up everything (first run: ~1-2 h, mostly downloads), then fly
./run.sh --airport=VABB --stand       # game options pass straight through (section 4)
./run.sh --dry-run                    # show what would run or be skipped, and why
```

Each step runs only when needed (outputs missing, or older than their scripts/inputs; stamps in `data/.stamps/`), so later runs start the game in seconds. Options: `--setup-only`, `--skip-data` (launch without touching data), `--region=mumbai_pune|all` (default `all` also fetches the Konkan-Kerala corridor), `--a320` (optional: also fetch the A320 data and regenerate its json, see "A320 data"), `--force-step=NN` (re-run one pipeline step), `--yes` (answer yes to prompts), `--help`. Missing system packages (GDAL, python3-venv, curl, git, unzip) are detected for apt, dnf, pacman and Homebrew; the install command is printed and only run with `sudo` after you say yes. If Godot 4.7.2 is missing it offers to download it into `~/.local/bin`. Blender is not needed. Everything is logged to `data/run.log`.

**macOS:** the script needs bash 4+ and Homebrew GDAL: `brew install bash gdal python`. It re-runs itself under Homebrew's bash (`/opt/homebrew/bin/bash` on Apple Silicon, `/usr/local/bin/bash` on Intel) and builds the venv from Homebrew's `python3`, whose site-packages contain GDAL's Python bindings.

The sections below describe the individual steps that `run.sh` automates.

---

> **Current state:** M1 (data pipeline) and M2 (terrain viewer) are complete: you can fly a free camera over the real Mumbai–Pune terrain with satellite imagery (~350 FPS on the Radeon 780M). M3 (flight model), M4 (first flight), M5 (cockpit & instruments, code side) and M6 (systems, weather, time of day, night lighting) are complete: you can take off from Juhu, Mumbai, Pune or Navi Mumbai and fly the C172 over the whole region on a working steam-gauge panel. The 3D aircraft and cockpit are still placeholder geometry until a Blender model replaces them (see section 5). Each section below says which milestone it belongs to.

---

## 1. Requirements (Pop!_OS / Ubuntu 24.04)

| What | How | Notes |
|---|---|---|
| GDAL + Python bindings | `sudo apt install gdal-bin python3-gdal` | already installed on this machine (GDAL 3.8) |
| QGIS (optional) | `sudo apt install qgis` | only for inspecting data |
| Godot 4.7.2 (standard build) | already installed at `~/.local/share/godot/`, with a symlink at `~/.local/bin/godot` | see below |
| Python venv | `python3 -m venv --system-site-packages tools/.venv && tools/.venv/bin/pip install osmium jsbsim mapbox_earcut shapely` | `--system-site-packages` lets it use the apt GDAL bindings |
| Blender 4.x + AC3D add-on | `sudo apt install blender`; add-on: download https://github.com/NikolaiVChr/Blender-AC3D (branch `4.0`) into `data/raw/fg/addon/` | only to regenerate the aircraft models |
| Disk | ~1.5 GB raw data + ~0.4 GB processed (+ 0.18 GB raw / 0.08 GB processed for WorldCover, + 0.37 GB processed for road / river tiles, 0.06 GB for shore tiles) | |

`~/.local/bin` is **not on your PATH** in this shell. Either run Godot by its full path (`~/.local/bin/godot`) or add this to `~/.bashrc`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

To install Godot on a fresh machine:

```bash
mkdir -p ~/.local/share/godot ~/.local/bin && cd ~/.local/share/godot
curl -LO https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip
unzip Godot_v4.7.2-stable_linux.x86_64.zip && rm Godot_v4.7.2-stable_linux.x86_64.zip
ln -sf ~/.local/share/godot/Godot_v4.7.2-stable_linux.x86_64 ~/.local/bin/godot
```

---

## 2. Getting the raw data (M0, one time)

Everything goes in `data/raw/`, which git ignores. `tools/01_fetch_notes.md` has the sources. The commands below are the scripted version. Run them from the repo root.

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

# Satellite imagery: Sentinel-2 cloudless 2024 (EOX), downloaded and reprojected to the world frame.
# This takes about 20-40 minutes and produces ~0.5 GB.
tools/01b_fetch_imagery.sh      # set LAYER=s2cloudless-2023_3857 to use a different year
tools/01c_fetch_outer_imagery.sh   # outer ring at 80 m (~490 x 490 km), ~15 min; re-run if it reports download errors (it resumes)

# Outer-ring elevation: Copernicus GLO-90 tiles 16-21 N, 70-76 E
mkdir -p data/raw/dem90 && cd data/raw/dem90
for lat in 16 17 18 19 20 21; do for lon in 70 71 72 73 74 75 76; do t=N${lat}_00_E0${lon}_00
  curl -fsLO https://copernicus-dem-90m.s3.amazonaws.com/Copernicus_DSM_COG_30_${t}_DEM/Copernicus_DSM_COG_30_${t}_DEM.tif || true  # open-sea tiles don't exist
done; done; cd -
```

---

### Phase R corridor (Mumbai → Kochi)

```bash
tools/.venv/bin/python tools/01d_fetch_corridor.py all   # GLO-30 + GLO-90 + 20 m / 80 m imagery + southern-zone OSM; ~40 min, resumable
```

- Downloads about 1.1 GB of DEM tiles, 163 MB of corridor imagery, 20 MB of outer-south imagery and 558 MB of OSM.
- Missing GLO-30 cells are open sea, listed in `data/raw/dem/missing_sea.txt`.

## 3. Building the game data (M1)

Run from the repo root, **in this order** (later steps read earlier outputs):

```bash
PY=tools/.venv/bin/python
$PY tools/05_airports_navaids.py   # -> data/processed/airports.json, navaids.json (Mumbai-Pune + Konkan-Kerala corridor)
$PY tools/04_osm_extract.py        # -> data/processed/osm/ (runways, roads, water, buildings) both regions, western+southern pbf ~6.5 min ([--thin] corridor density policy)
$PY tools/02_dem_tiles.py          # -> data/processed/terrain/h/  (heightmaps, runways flattened); corridor ~2 min
$PY tools/03_imagery_tiles.py      # -> data/processed/terrain/img/ BC1 .dds tiles (needs s2.tif; corridor: s2_corridor.vrt) ~15 s + 2 min
$PY tools/06_jsbsim_to_json.py     # [aircraft id, default c172] -> game/aircraft/<id>/aero.json, config.json (committed)
$PY tools/09_runways.py            # -> data/processed/runways.json (merged runways + taxiways; after 02 & 04)
$PY tools/10_buildings.py          # -> data/processed/buildings/ 3D building meshes in the BLD2 layout (after 02, 04; roofs from s2.tif / corridor s2_corridor.vrt; skips tiles without heights; parapets, hip roofs and rooftop boxes come from `tools/building_geom.py`) ~2.5 min on 8 processes, 364 MB + 79 MB collision, 33.7M vertices
$PY tools/11_landclass.py          # -> data/processed/terrain/lc/ land-class masks: water + tree density (after 02-04) ~30 s + 2 min
$PY tools/12_outer.py              # -> terrain levels 3-6 over OUTER_TOTAL ~980 x 1475 km to Kochi (real 90 m data + filled beyond) ~7 min
$PY tools/19_worldcover.py        # -> data/processed/terrain/wc/ ESA WorldCover 2021 v200 class tiles (CC BY 4.0), one per lc tile (after 11 and 12; ./run.sh orders it
                                   #   there). Needs network on the first run: GDAL /vsicurl/ windowed reads of the public COG tiles (no account):
                                   #   the 80 m overview of 17 three-degree tiles (30 MB) and 90 half-degree cells at 10 m over the level-0/1 tiles
                                   #   (122 MB) into data/raw/worldcover/ (resumable, existing files kept; --download-only fetches without building).
                                   #   Codes 0 nodata, 1 tree, 2 shrub, 3 grass, 4 crop, 5 built-up, 6 bare, 7 snow, 8 water, 9 wetland, 10 mangrove,
                                   #   11 moss. 1758 tiles, 76 MB, ~1 min on 10 cores (+ ~4 min the first download). Re-run with --force to rebuild.
                                   #   The terrain shader varies the ground per class (parcels, built-up speckle, bare soil, scrub); without wc/ the
                                   #   ground looks as before. Credit (CC BY 4.0): CREDITS.md, F12 screen, attribution line.
$PY tools/13_airport_ops.py        # -> data/processed/airport_ops.json: stands, gates, jetbridges, hold points, taxi graph ~35 s
                                   #   (stand_geom/stand_links/stand_remote/airport_stands.py derive airliner stands where OSM maps
                                   #   jet bridges but no stands: Kochi, Kannur. ./run.sh re-runs 13 when 13_airport_ops.py changes;
                                   #   after editing a stand_*.py / airport_stands.py run 13 by hand or --force-step=13)
$PY tools/14_ils.py                # -> data/processed/ils.json: SIMULATED ILS for runways >= 2000 m (after 09)
$PY tools/15_terminals.py          # -> data/processed/terminals/<ICAO>.json: terminal footprints (VABB, VAPO; VOCI via Overpass, cached) ~70 s
$PY tools/16_terminal_models.py    # -> terminals/<ICAO>.glb landmark terminal models + landmarks.json (follows the terrain: after 17); then re-run 10_buildings.py
$PY tools/20_roads_rivers.py       # -> data/processed/terrain/ro/0/ crisp road and river masks (after 04, 11, 12, 17; ./run.sh orders it after 17). OSM highway lines (motorway ...
                                   #   residential, service, track) and waterway lines (river, canal, stream, drain) of both regions, from one pass over the
                                   #   Geofabrik extracts the first time (~5 min, cached in osm/ways.npz by tools/ways_extract.py), then one PNG per level-0
                                   #   tile: 1920 x 1920, 4 m texels, two channels = signed distance to the nearest ribbon edge (0.16 m steps within 4 m) and the
                                   #   ribbon class. Roads stop at water (bridges stay), at aprons / runways / taxiways, and minor roads / waterways at
                                   #   aerodrome fences. 2213 tiles, 373 MB, ~7-11 min on 10 cores (resumable; --force rebuilds, --only tx_ty,...).
$PY tools/21_shore.py              # -> data/processed/terrain/sd/ shore distance (signed metres, +127 m deep side) and openness (how far open water reaches) per
                                   #   land-class tile with water, 1564 tiles, 58 MB, ~2 min. Drives shore foam, shoal colour and calmer backwaters.
$PY tools/17_airport_fixups.py     # patches terrain h/lc levels 0-2 in place, both regions (after 02, 09, 11, 12, 13, 15): levelled
                                   #   sites (VANM 8 m, VOKN, VOSR) without water/trees, taxiway ground smoothed, APRON GROUND
                                   #   levelled (tools/apron_flatten.py: stands, gates, apron polygons, taxilanes and a margin round
                                   #   terminals/hangars lose the DSM's roofs, walls and parked aircraft; harmonic fill from the
                                   #   ground around, 30 m blend, all three LODs), no water on paving, no trees inside airports.
                                   #   Re-runnable (starts again from the saved originals), tiles replaced atomically (~3 min).
                                   #   Then re-run 09, 14, 16 (terminal base heights follow the ground) and 10.
                                   #   (./run.sh orders this: ... 11 12 13 15 17 09 14 16 10).
$PY tools/apron_roughness.py       # optional QA: stand-area relief, apron polygon std, ring around terminals, terminal base height
                                   #   per airport from the tiles on disk (VABB before the apron fix: 54 % of the stands had a mound
                                   #   > 1.5 m within 45 m, median 2.0 m, p90 12.4 m; after: 5 %, 0.3 m, 1.0 m)

# Aircraft 3D models (FlightGear c172p, GPL), already committed as .glb; only needed to regenerate:
blender -b --factory-startup --python tools/blender/convert_c172p.py            # exterior.glb
blender -b --factory-startup --python tools/blender/convert_c172p_interior.py   # interior.glb
# fgdata jetway: blender -b --factory-startup --python tools/blender/convert_ac.py -- <in.ac> <out.glb>
$PY tools/07_preview.py 1          # -> data/processed/preview_L1.png  (sanity check)
$PY tools/08_jsbsim_reference.py   # optional: standalone JSBSim climb numbers for comparison
$PY tools/18_compare_fdm.py        # optional: fly 11 scripted manoeuvres in our FDM and JSBSim c172p,
                                   #   PNG plots + metrics.md in /tmp/fdm_compare (docs/FDM-VS-FLIGHTGEAR.md)
```

Notes:
- **World frame:** a local Transverse Mercator centred at 18.75N 73.40E, so map metres are game ENU metres (x east, y north). Key positions: Juhu ≈ (-59540, 38628), VABB ≈ (-55997, 37576), VAPO ≈ (54856, -18505).
- **Regions (Phase R):** 02, 03 and 11 take `--region mumbai_pune|konkan_kerala|all` (default all) and `--workers N`.
  `mumbai_pune` writes `terrain/meta.json` (levels 0-4; 12_outer replaces 3+), `konkan_kerala` writes
  `terrain/meta_konkan_kerala.json` (levels 0-2, tiles `[min, max, flags]`, flags bit 0 = img, bit 1 = lc;
  level-0 corridor tiles have neither and borrow from their level-1 parent). Corridor tiles that border
  Mumbai-Pune tiles are stitched to their edges; Mumbai-Pune tiles are never written by the corridor run.
  Corridor flattening uses runways.json (09), then OSM runways, then OurAirports ends, so after a fresh 09 re-run 02/03/11 for the corridor.
  03 skips existing img tiles: delete `img/{1,2}/` corridor tiles to rebuild them after a re-fetch.
- `07_preview.py quicklook [level=2] [out.png]` mosaics every `meta*.json` at one level (imagery x hillshade + heights).
- `07_preview.py <level> x0 y0 x1 y1` zooms into a box, e.g. `07_preview.py 0 -62000 35000 -52000 41000` shows the Mumbai airports.
- To change the region or tile layout, edit `tools/common.py` and re-run steps 02–03. Re-run 03 after deleting `data/processed/terrain/img/`, because it skips tiles that already exist.
- Delete `data/processed/` at any time; it is fully regenerated by the scripts.

### A320 data (optional, `./run.sh --a320`)
The A320 flight model comes from the FlightGear "A320-family" JSBSim files (licence **GPL-2.0-only**: `third_party/a320-family/`, `docs/LICENSING.md`). `data/raw/fg/a320` is untrusted data: nothing in it is ever executed.
```bash
tools/22_a320_fetch.sh              # sparse checkout of FDE/ Engines/ Systems/ at the pinned commit (~2.5 MB); --force re-fetches
$PY tools/06_jsbsim_to_json.py a320 # -> game/aircraft/a320/{aero,config}.json (committed; c172 json untouched)
$PY tools/test_jsb_convert.py       # converter tests (c172 json must stay byte-identical)
$PY tools/23_a320_reference.py      # JSBSim oracle run -> tools/a320_reference.json + tools/ref/*.csv (a few minutes)
```
`./run.sh --a320` does the first two (fetch is skipped when the clone is at the pinned commit; json step 06a re-runs only when the converter or the clone changed). `23_a320_reference.py` flies the real A320 (FBW, FADEC, engines) headless in the JSBSim python package: trims, alpha limits, takeoff roll, climbs, FBW step responses, thrust formula check. The first run builds `data/raw/fg/a320_root` (symlinks to the clone plus a stub system for the ~700 FlightGear-side properties, ~3 min, cached). Use it as the tuning oracle for the hand-written control laws (`--only trim,stall,takeoff,climb,steps,thrust` selects parts). Details, the property bridge and what the files mean: `tools/A320_DATA_NOTES.md`.

---

### A320 model (exterior and flight deck, P8, optional)
The A320 exterior and flight deck are converted from the FlightGear A320-family models (GPL-2.0-only; credits and change log in `third_party/a320-family/SOURCE.md`). Needs Blender 5.x (tested 5.2.3 LTS, `/Applications/Blender.app/Contents/MacOS/Blender`; run headless, not on PATH). No Blender add-on is needed: AC3D files are read by `tools/blender/ac3d_parse.py` (Blender 5 has no AC3D importer).
```bash
tools/24_a320_models_fetch.sh                       # adds Models/ (~87 MB) to data/raw/fg/a320; run tools/22_a320_fetch.sh first
$PY -I tools/24_a320_textures.py                    # cleaned textures -> data/processed/a320/tex (white livery, no registration / logos)
B=/Applications/Blender.app/Contents/MacOS/Blender
$B -b --factory-startup --python tools/blender/convert_a320.py          # -> game/aircraft/a320/models/exterior.glb (+ exterior_pivots.json)
$B -b --factory-startup --python tools/blender/convert_a320_cockpit.py  # -> models/interior.glb (+ interior_info.json: eye, display rectangles)
$PY -I tools/24_a320_sections.py                    # -> game/aircraft/a320/model_sections.json (DRAFT model / cockpit / lights / registration / cameras for aircraft.json)
godot --path game res://tests/debug_a320_model.tscn --audio-driver Dummy -- --out=<dir> --pose=clean|down|spoil   # screenshots + pivot / triangle check
```
Budgets (reported by the scripts): exterior 71.9k triangles, 9 materials, 4096 px fuselage atlas (needed for the registration) and 2048 px rest; flight deck 94.6k triangles, 16 materials, <= 2048 px. Frame: glb origin = JSBSim structural origin (`model.origin_m` `[0,0,0]`). `model_sections.json` is a draft: the A320 has no `aircraft.json` until the FDM phases are done; its `_needs` list names the small `aircraft_model.gd` / `registration_paint.gd` extensions the pivots need (extra drives, piecewise `map`, `rotate`). The fetched data and the downloaded textures are untrusted: only decoded, never executed.

## 4. Running the simulator

```bash
cd game
~/.local/bin/godot --path .          # run the main scene
~/.local/bin/godot -e --path .       # open the Godot editor
```

On first run, Godot imports the project (a few seconds). The data is read from `../data/processed` relative to the project, so build it first (section 3).

### Start screen (flight setup)

Running the game opens the **start screen** (the libresim logo shows first as the splash). It first asks one question, **What would you like to do?**, with two large cards, and then shows only the path you chose:
- **Home screen:** **Free flight** (pick the airport, aircraft, weather and failures) or **Training** (guided lessons: take off, cruise, land). Click a card, or press **1** / **2** (or Left / Right) and **Enter**. The card you chose last time is focused when the game opens. Small buttons below open **Saved flights**, **Controls** and **Options**; **Handbook**, **Credits** and **Quit** stay in the top bar. Each of those pages has a **◀ Back** button (or **Esc**) to the home screen.
- **Free flight path:** a stepper shows Airport & start → Aircraft → Weather & time → Failures → Recording → Fly. The current step is highlighted, finished steps get a tick, and every pill is clickable. **Next: <step> ▶** moves on, **◀ Back** returns (on the first step, to the home screen), and on the last step the filled button is **FLY ▶**. Keys: **1**–**5** jump to a step, Page Up / Page Down step through, **Ctrl+Enter** flies. A summary line shows the whole setup. Your last setup is remembered (`user://last_flight.json`).
- **Training path:** the lesson list, "How much help?" and a fixed **START LESSON ▶** button in the bottom bar (it never scrolls out of sight), with **◀ Back** to the home screen. No free-flight stepper is shown. See "Training mode" below.

1. **Airport & start:**
   - Pick an airport from the searchable list. A north-up diagram shows its runways, taxiways and stands, with an arrow at your start point.
   - Start positions:
     - **Runway:** the chosen runway end, with the engine running. Tick "cold & dark" to start with everything off.
     - **Stand / gate:** a stand from OpenStreetMap (jetbridge gate, remote bay or GA parking). Stand starts are **always cold & dark with the parking brake set**, as in the real aircraft.
     - **In the air:** a height above the field and a distance on final to the chosen runway.
2. **Aircraft:**
   - Every `game/aircraft/<id>/aircraft.json` is listed (for now, the Cessna 172S) with its specifications.
   - Set fuel per tank and the front-seat, rear-seat and baggage loads. The takeoff weight is checked against MTOW. Payload changes the mass, CG and performance in the flight model.
3. **Weather & time:**
   - **Weather presets:** Clear, Fair, Scattered, Broken (passing showers), Overcast (drizzle), Winter haze, Monsoon (heavy rain under a low deck, occasional lightning).
   - **Custom sliders:** cloud cover, cloud base, visibility, rain, turbulence, QNH, temperature.
   - **Time of day:** presets or a slider, plus the clock rate and the month. **Dawn** and **Dusk** are the real sunrise and sunset for the chosen month (mid-February: 07:10 and 18:40 IST; June: about 06:00 and 19:15).
   - **Wind:** presets, direction, speed and gusts, plus a "90° crosswind" button. A live head/crosswind readout covers the chosen runway and turns red above the C172's 15 kt demonstrated crosswind or with a tailwind.
4. **Failures:**
   - Any of 26 failures can be scheduled with a trigger: **at start**, **after N min**, **climbing through N ft AGL** or **above N kt**.
   - Failures by area:

     | Area | Failures |
     |---|---|
     | Engine | total, partial power/rough running, left and right magneto |
     | Fuel | left and right tank leak |
     | Electrical | alternator, battery |
     | Vacuum & gyros | vacuum pump, attitude gyro, heading gyro, turn coordinator |
     | Pitot-static | pitot blocked, static blocked |
     | Flight controls | flaps jammed, trim jammed, left and right brake |
     | Avionics | COM1, COM2, NAV1, NAV2, ADF, DME, transponder, GPS |

   - **Random failures:** choose how many, a time window and which systems may fail. You are not told which failures are armed.
   - "Tell me when something fails" shows a notice. With it off, you diagnose the failure from the instruments and the aircraft's behaviour.

5. **Recording (optional):**
   - Tick "Record this flight" to record the whole session, **picture and sound**.
   - Files go to `recordings/` in the game folder by default, or to any folder you choose. Read-only installs (AppImage, .app) fall back to `~/.local/share/godot/app_userdata/libresim/recordings`.
   - Choose 720p, 1080p or native resolution, at 24, 30 or 60 fps.
   - **Format:** files are named `libresim_<date>_<time>.mkv` (MJPEG video plus 16-bit PCM sound), written by the game itself, so no extra software is needed. They play in VLC and mpv and import into video editors.
   - **Size:** about 5 MB/s at 720p30.
   - **MP4:** if `ffmpeg` is installed, the file is converted to a much smaller MP4 (H.264 + AAC) when the recording stops.
   - **Crash-safe:** the file is written as a stream, so it stays playable even if the game is killed.
   - **Cost:** frames are read back from the GPU asynchronously and encoded on worker threads, so frame rate is barely affected (42 FPS with or without recording on the dev machine).
   - **In flight:** F8 starts and stops recording, and a red ● REC shows the time and size. `--record` on the command line also turns it on.

6. **Controls** (home screen → Controls): joystick and gamepad bindings.
   - Connected devices are listed, and hot-plug works.
   - Each action has a **Bind** button: move an axis or press a button to capture it, or Esc to cancel. Each also has invert, a range (full, half for levers, trigger for toe brakes), deadzone, an expo curve and a live value bar.
   - "Reset: gamepad defaults" gives: left stick roll/pitch, right stick X yaw, triggers toe brakes, LB/RB flaps, A brakes, X parking brake, Y/B views, D-pad trim and magnetos.
   - "Reset: joystick defaults" gives: X/Y roll/pitch, twist yaw, throttle axis.
   - A bound axis takes over from the keyboard. Anything not bound stays on the keyboard.
   - Saved in `user://input_bindings.json`. Also available in flight with **J**.
   - **Keyboard keys are rebindable too.** Click a key slot (up to 3 keys per action, with Shift, Ctrl or Alt allowed), then press the new key. Esc cancels; Delete clears the slot. Conflicts with other actions or fixed hotkeys are shown in orange. Keys match by physical position. Keys are saved in `user://key_bindings.json`.
7. **Options** (home screen → Options):
   - Volume and mute for each sound bus: Master, Engine, Wind & environment, Cockpit, Radio, Menus.
   - Graphics preset.
   - Units preference (stored for later; the C172 panel stays in ft, kt and inHg).
   - Whether the HUD is shown at start.
   - **UI size** (Display): Auto (default) scales all text, HUD, panels and menus to the window, so they stay the same relative size at 1080p, 1440p, 4K, ultrawide (21:9, 32:9) and small windows; the 3D view always renders at the window's full resolution. Or pick 100 / 125 / 150 / 200 %, relative to your system display scale (100 % on a Retina screen is already 2x pixels). Takes effect at once; saved as `ui_scale` in `options.cfg`. Mechanism: `core/ui_scale.gd` (autoload `UiScale`) with the `canvas_items` / `expand` stretch mode in `project.godot`; UI code works in units of about 1280x720 at factor 1, and a wider window simply shows more of them.
   - **Radio / ATC:** call sign, **radio assist** (on by default: calls tune COM1 for you and the radio bar suggests the next call; off = tune COM1 yourself, nothing suggested) and the ATC voice.
   - **Voice (off by default):** "Speak them" (training callouts) and "ATC voice" use the operating system's text-to-speech. Nothing speech-related runs at start-up while both are off. Switching one on probes the system once (about half a second). If no voice is found, the checkbox stays saved but silent, a calm note appears under it and one line is printed to the console. **Linux:** install speech-dispatcher and a voice, e.g. `sudo apt install speech-dispatcher espeak-ng` (Fedora: `sudo dnf install speech-dispatcher espeak-ng`; Arch: `sudo pacman -S speech-dispatcher espeak-ng`), then restart the game. Windows and macOS use their built-in voices. Code: `core/speech_service.gd` (one door for callouts and ATC; tests in `tests/test_speech.gd`).

**On-screen messages:**
- **Notification cards** at the top-centre carry everything the sim tells you: failures, damage, and the landing debrief (grade, sink rate, g and centreline offset).
  - Colours: blue for info, amber for caution, red for warning.
  - Repeats merge into one card ("×3"), at most 3 cards show at once, and they fade after a few seconds.
- **Banners and hints:** STALL is a pulsing banner. A one-line hint at the bottom says when the engine has stopped.
- **Crash card:** after a crash, a centred card dims the scene. It gives the reason, the impact numbers and the damage, with buttons to Restart (F5), Watch replay (R) or start a New flight.
   - Saved in `user://audio.cfg` and `user://options.cfg`.
8. **Saved flights** (home screen → Saved flights): saved situations with a thumbnail, airport, altitude and IAS. "Fly from this save" resumes exactly there.

The **Aircraft** page also shows a **weight & balance chart**: the C172S normal and utility CG envelopes, with the takeoff and landing points (landing assumes 5 gal per tank). It turns red when overweight or out of CG limits. The flight model flies the CG you load: an aft CG makes the pitch light and less stable.

**Training mode** (home screen → Training, or `--lesson=takeoff|cruise|landing[,full|light|off]`):

Three short, separate lessons at Pune in calm, clear weather. Your free-flight setup is not changed.

| Lesson | You practise |
|---|---|
| **Takeoff** | Full power, staying on the centreline, rotating at 55 kt, climbing at Vy (74 kt), reaching 500 ft |
| **Cruise** | Level flight, cruise power, trim, a 90° turn, a 500 ft climb and descent |
| **Landing** | Slowing down, flaps, the 3° glide path and centreline, the threshold, the flare, touchdown and roll-out |

The landing lesson starts 3 nm out on final (1,000 ft, 80 kt, flaps up, on the 3° path), so there is time to set up. Its steps: **Slow down** (power about 1,700 RPM, 58 to 78 kt), **Flaps and trim** (flaps 20° with `]` or `F7` twice, about 65 kt; `End` trims nose-up, `Home` nose-down), **Fly the glide path** (within 1.5° of the path, stable by 0.8 nm out), **Cross the threshold** (about 60 kt), **Flare and touch down**, **Roll out** (brake with `B` to walking pace, 10 kt ground speed or less).

- **A lesson card** (left) lists the steps, shows the current instruction and a hint, and ticks steps off as you complete them.
- **Live gauges** show your value against the target and tolerance (green inside, amber near, red far).
- **3D markers:** a dashed line down the runway centreline, glide-path rings on the approach (cyan = ahead, yellow = next, green = flown, red = missed), an aim-point box on the runway, and a beacon to turn toward in the cruise lesson.
- **Coach messages** (and optional system-voice speech) warn you: "Drifting off the centreline", "Rotate now!", "High. Reduce power, lower the nose", and so on. Training callouts are always on during a lesson.
- **Help level:** *Full guidance* (all of the above), *Hints only* (card, hints, callouts) or *Minimal* (step list only, like a check ride).
- **Result:** 1–3 stars from the graded numbers (centreline error, rotation speed, climb speed, sink rate at touchdown, touchdown point, and so on), with **Try again**, **Next lesson**, **Keep flying** and **Menu**. Your best stars are remembered (`user://training.json`).
- **Steps are in order, but not strict:** if you already meet a later step's conditions (for example you are configured and stable on the glide path before you finished "Slow down"), the earlier steps are ticked off for you.
- **A lesson never leaves you stuck.** If you can no longer finish it (you touched down or left the runway before the lesson expected it, got far too low or too high on the approach, floated off the end of the runway, settled back onto the runway after rotating, flew into the ground, or crashed), it ends with a **"not completed"** card: what happened and in which step, which steps you did finish, what to work on, and **Try again** / **Keep flying** / **Menu**. After a crash the lesson card says so and **F5** (or the crash card's Restart) starts the lesson again. **Try again** and **F5** put the aircraft back at the lesson start, whatever state it was in (airborne, stopped on the runway or crashed).
- Lessons are data in `game/training/lessons.json`: steps (with `any_order` for the tolerant ones), conditions, gauges, grades and `abort` rules (`--air-kt=` sets the IAS of an airborne start; lessons use it).

**In flight:**
- **Esc** opens the full-screen pause screen (like Microsoft Flight Simulator). The flight stops and the frozen scene stays visible behind a blurred, dimmed backdrop; resuming is instant and nothing is reloaded. A big **PAUSED** title shows the aircraft, start airport and time; the left column lists **Resume flight**, **Options**, **Weather & time** (F10), **Controls & keys** (J), **Save / Load flight** (F11), **Failures** (F9), **Checklists** (F2), **Instant replay** (R), **Restart flight** (F5), **Quit to main menu** and **Quit game**. The page you pick is shown on the right, embedded (the same content as the start screen's Options and Controls pages and the F9 / F10 / F11 panels). The home page shows altitude, height, airspeed, heading, wind, visibility, time and flight time. In a lesson the context line names the lesson, and during a replay it says Replay.
  - **Keys:** **↑ ↓** move down the list (each page previews as you pass it), **← →** cross between the list and the page, **Enter** selects (and moves into the page), the mouse works everywhere. **Esc** backs out one level: a text field, then the page (back to the home page), then it resumes. Every other key is ignored while paused, so the flight hotkeys do nothing underneath. A gamepad or joystick pause button works like Esc. Restart flight, Quit to main menu and Quit game need a second click ("Click again to confirm", cancelled by Esc or after 3 s).
  - It scales with **UI size** and fits any window shape (16:9, ultrawide, small windows).
- **Saving and loading:** Esc → Save / Load flight, or **F11** to quick-save and **Shift+F11** to quick-load. A save keeps everything: position, motion, engine state, fuel, damage, switches, radios, failures, weather and time. Saves live in `user://saves/`.
- **Replay (R):** replays up to the last 10 minutes from any camera.
  - **Space** plays and pauses, **← / →** seek ±5 s, and **[ / ]** change speed (0.25x–4x). The timeline bar can be scrubbed.
  - **Take control** resumes flying from the replayed moment, with its exact speed and attitude. **Exit replay** returns to where you were.
- **F9** opens the failures panel. It shows every system as OK, FAILED or armed, lets you fail or repair any of them live, and shows how many random failures are still pending.

Command-line flight options (below) skip the start screen. Add `--menu` to open it pre-filled instead.

### Flying (M4): the main scene

```bash
cd game
~/.local/bin/godot --path .                                   # start screen
~/.local/bin/godot --path . -- --airport=VAJJ                 # skip it: Juhu, longest runway, engine idling
~/.local/bin/godot --path . -- --airport=VABB --runway=27     # Mumbai runway 27
~/.local/bin/godot --path . -- --airport=VAPO --air=2000      # airborne, 5 nm final to Pune at 2000 ft AGL
~/.local/bin/godot --path . -- --aircraft=a320 --airport=VABB --stand   # the A320 at a gate, cold (batteries on, engines off)
~/.local/bin/godot --path . -- --aircraft=a320 --airport=VABB --air=8000        # A320 airborne, clean, 250 KIAS
~/.local/bin/godot --path . -- --airport=VANM                 # Navi Mumbai
```

| Option (after `--`) | Meaning |
|---|---|
| `--airport=ICAO` | VAJJ (default), VABB, VAPO, VANM, VAAV (Aamby Valley), … any airport in `runways.json` |
| `--runway=NN` | runway end, e.g. `08`, `26`, `14`, `32`; default = the longest runway |
| `--air[=ft]` | start airborne on a 5 nm final at that height above the field (default 1500) |
| `--air-nm=N` | with `--air`: distance out on final in nm (default 5) |
| `--air-kt=N` | with `--air`: airspeed (KIAS) at the start (default 90) |
| `--lights-debug` | print aerodrome-light build times and what the nearest PAPI shows the camera (e.g. `WWRR`, eye angle) |
| `--stand[=REF]` | start parked at a stand (always cold & dark): e.g. `--airport=VABB --stand` (a jetbridge gate), `--stand="Bay 40"`, Juhu `--stand=GA3` |
| `--cold` | cold and dark: everything off, parking brake set (do the "Before Starting Engine" and "Starting Engine" checklists) |
| `--view=NAME` | initial camera: cockpit, chase, orbit, free, tower, wing, tail or flyby (default chase) |
| `--quality=low\|medium\|high\|ultra` | graphics preset (otherwise the one saved from F10) |
| `--tod=h` | local time (IST), e.g. `--tod=7.2` sunrise and `--tod=18.7` sunset in mid-February, `--tod=21` night (06:30 in February is still pre-dawn twilight) |
| `--day=N` | day of the year (default 45 = 14 Feb): sun times and moon phase (e.g. `--day=3` full moon) |
| `--wind=DDD/SS[GNN]` | surface wind, e.g. `--wind=270/15G25` (wind aloft is set a bit stronger and veered) |
| `--vis=m` | visibility in metres (between showers; rain lowers it further) |
| `--rain=R` | rain 0–1 (after `--weather` to override the preset); below 0.3 it comes and goes in showers |
| `--clouds=C@ft` | cloud cover 0–1 at a base in ft AMSL, e.g. `--clouds=0.6@3500` |
| `--weather=NAME` | weather preset: clear, fair, scattered, broken, overcast, monsoon |
| `--fail=ID[,ID…]` / `--fail=ID@min` | failures at start / after N minutes, e.g. `--fail=vacuum_pump,mag_left` (ids as in `game/systems/failure_catalog.gd`) |
| `--random-failures` | one random failure 2–30 min after start (any system) |
| `--menu` | open the start screen pre-filled with these options instead of flying straight away |
| `--record` | record the session (video + sound) |
| `--clean` | hide all UI (screenshots) |
| `--shot=file.png --time=s` | for testing: fly hands-off `s` seconds, save a screenshot and quit |

**Flight controls (keyboard):**

| Key | Action |
|---|---|
| ↑ / ↓ (or numpad 8 / 2) | Pitch: ↓ pulls back (nose up), ↑ pushes (nose down). Rate-based: hold to deflect, release to re-centre |
| ← / → (or numpad 4 / 6) | Roll (ailerons) |
| Z / X (or numpad 0 / Enter) | Rudder left / right; also nosewheel steering on the ground |
| Page Up / Page Down (or = / −) | Throttle up / down |
| ' / ; | Mixture richer / leaner |
| Home / End (or numpad 7 / 1) | Pitch trim: nose down / nose up |
| ] or F7 / [ or F6 | Flaps down / up one notch (0°, 10°, 20°, 30°; electric, takes a few seconds) |
| B (hold) | Both brakes |
| , / . (hold) | Left / right brake (differential steering) |
| Shift+B | Toggle parking brake |
| Ctrl+click (cockpit view) | Zoom in on the instrument / switch under the cursor; Ctrl+click again or V to return. The mouse wheel zooms toward the cursor |
| Shift+M / Shift+V | Master switch (BAT + ALT) / avionics master |
| Shift+F / Ctrl+F | Fuel selector cycle / fuel shutoff valve |
| Ctrl+B / N / S / L / T / H | Beacon / nav / strobes / landing / taxi light / pitot heat |
| M | Cycle magnetos OFF → L → R → BOTH |
| S (hold) | Starter |
| Y | Toggle mouse yoke (mouse position = control column) |
| L / Shift+L | PANEL light dimmer brighter / dimmer (instrument post lights + glareshield flood, 10 % steps; also the PANEL knob in the switch row) |
| C / Shift+C, or 1–8 | Camera: 1 cockpit, 2 chase, 3 orbit, 4 free camera (WASD to move, Q/E down/up, right-drag to look, Shift for speed, wheel to set speed), 5 tower, 6 wing, 7 tail, 8 fly-by |
| Tab / Shift+Tab | 2D panel layout in outside views: Full, Split (six-pack bottom-left, engine gauges right), Compact (small six-pack), Minimal (ASI, AI, ALT top-right), Off. Remembered between sessions |
| Right-mouse drag | Look around (cockpit, orbit, free, wing, tail). Mouse wheel: cockpit zoom (field of view), orbit distance, free-camera speed |
| V | Re-centre the view |
| T | Taxi guidance: route to the into-wind runway (green line on the ground, "Taxi via …, hold short"). T again clears it. The instruction is a compact card at the top of the screen for 8-12 s (12 s the first time after landing), then it fades; the route and the distance left stay as a tiny line in the radio bar |
| Backspace | Dismiss the taxi / pushback message at once (it also goes when you start taxiing, reach the stand or a newer instruction replaces it; it stays in the radio History) |
| P | Pushback (parking brake off): tug pushes you back and swings the tail toward the taxiway. P again stops |
| ` (backquote) | Open / close the radio (the bar top-left is always there in free flight; click it to open). Open: ↑ ↓ choose, Enter or 1–4 call, Esc close, A say again, H history, V voice |
| F2 | Checklists window (C172S POH, preflight → securing), see "Checklist window" below; Ctrl+PgUp/PgDn change list, Enter ticks the next item, Shift+Enter takes the last tick back, Shift+F2 collapses it; most items tick themselves |
| H / F1 / F3 | Flight-data bar (IAS, GS, ALT, AGL near the ground, VS, HDG; top-centre) / key-help card / developer performance overlay (off by default) |
| F12 | Credits and licences |
| F10 | Settings: graphics preset and renderer, time of day and time rate, wind and gusts, wind aloft, turbulence, visibility, clouds, QNH, temperature, failures |
| Esc | Pause screen (Esc again: back, then resume) |
| F5 | Reset to the start position |

**Control feel (start screen → Options → Flight controls):**
- *Yoke keys:* **Spring** (default): the arrow keys and Z/X re-centre when released. **Sticky**: they stay where you leave them, as in FlightGear; tap the opposite key to come back, and it stops at centre.
- *Input smoothing:* off / **light** (0.05 s, default) / strong (0.12 s). This is a low-pass on keyboard, joystick and mouse-yoke inputs at the physics rate. The aircraft's control actuators are also rate-limited, as in FlightGear's c172p: full elevator travel in 0.3 s, aileron and rudder in 0.15 s.
- *Auto-coordination:* the rudder follows the aileron (0.5 × aileron). Use it if you have no pedals.

**A first flight from Juhu:** Page Up to full throttle (about 2300 RPM static). Keep straight with Z/X. At 55 kt, hold ↓ gently to rotate. Climb at 74 kt (Vy). Trim with Home/End until hands-off level, then reduce to about 2400 RPM for cruise. The Ghats are 45 km east; Pune (VAPO) is about 120 km east-southeast.

### Airport operations (phase A)

**Start options:**
- Start at a stand: at **VABB** 114 stands (52 gates with jetbridges), **VANM** 87, **VAPO** 24 (11 gates), **Calicut** 36 (14 gates), **Manohar (Goa)** 16 (6 gates), **Mangaluru** 15 (6 gates), **Dabolim** 11, and generated GA parking at **Juhu** and other small fields. **Kochi (VOCI)** and **Kannur (VOKN)** have jet bridges in OpenStreetMap but no mapped stands, so their airliner stands are derived from the bridges: at Kochi 11 jetbridge gates (refs 2, 3, 4, B1 to B8: the C172 sits at the L1 door, nose to the terminal), a walk-out gate (1) and 26 remote bays (R1 to R26) along the apron lanes; at Kannur 3 gates. Every one is joined to the taxi graph, so T (taxi to the runway) and the ATC "taxi to the apron" route to it.
- Start **cold and dark** if you want: the C172 needs the real start procedure (master, mixture rich, throttle cracked, magnetos BOTH, starter).

**On the ground:**
- **Training callouts (optional, off by default):** a real C172 has none, but an instructor would call them. Turn them on with **K** in flight or on the Options page ("Speak them" uses your system's text-to-speech voice if it has one; on Linux that needs `speech-dispatcher` and a voice such as `espeak-ng`, see Options → Voice).
  - **Takeoff:** *Airspeed alive* (40 kt), *Rotate* (55 kt), *Positive rate*.
  - **Approach:** *Five hundred*, *One hundred*, *Fifty*, *Thirty*, *Twenty*, *Ten* (feet above ground, once each, only while descending).
  - **Cautions:** *Sink rate*, *Low airspeed* and *Bank angle* near the ground.
- **Touchdown effects:** a landing puffs tyre smoke from each main wheel (more at higher speed and sink rate) and leaves a rubber mark on the runway that follows how hard you landed: a butter landing (under ~80 fpm) leaves nothing, a smooth one a faint scuff, a firm one a clear dark mark, a hard one a long heavy streak. Each mark is irregular (dark spin-up smudge, patchy trail), and up to 40 are kept per session.
- **Pushback** with a tug.
- **Taxi guidance:** the route is computed over the real OSM taxiway network, and the instruction names the taxiways ("via A, B").

**Radio and checklists:**
- **ATC** (`): a controller with memory, in text (and optionally in the system voice). **The radio bar** sits at the top-left of the screen in free flight: `COM1 118.100 · Pune Tower` (green when a unit answers on that frequency, amber "no facility", red when COM1 is off or failed), the suggested next call ("Next: ask Ground for taxi") and, for 20 s, the latest controller message. Click the bar or press `` ` `` to open a short list of at most four plain calls with the suggested one first and highlighted ("Ask Ground for taxi", "Report ready for departure", "Report final"...): **↑ ↓** move, **Enter** or **1-4** call, **Esc** or `` ` `` close, and the list closes by itself after a call. While it is open the arrow keys do not pitch the aircraft and the number keys do not change the camera. Small row: **Say again** (A), **History** (H: the last 30 transmissions, scrollable) and **Voice** on/off (V). What you hear arrives as one calm card at the top-centre (like the other notification cards, gone after 6-8 s) with your own call and read-back as small muted lines. Departure: ATIS (the information letter changes when the weather does) → VFR clearance with squawk, runway and a readback → pushback and taxi (the green route line and follow-me car start with the call) → "contact Tower" at the holding point → ready for departure → line up and wait → cleared for takeoff with wind → "contact Approach" or "frequency change approved, squawk VFR". Arrival: inbound call (position, altitude) → join / straight-in and QNH → "report final" at about 5 nm → cleared to land → "vacate runway, contact Ground" → taxi to the apron → parked. **Radio assist (Options, on by default):** a call tunes COM1 to the right unit by itself ("COM1 tuned to 118.100 Pune Tower") and the bar suggests the next call. **Assist off** is the realistic radio: you tune COM1 yourself, nothing is suggested, the list offers **Tune COM1 to <unit>** first when needed, and a call on the wrong unit is redirected ("you are on the wrong frequency, contact Tower 118.1"). Airports with no published frequency are answered on any COM1 frequency (Juhu, Navi Mumbai); small fields and heliports have no ATC: your calls are blind transmissions that nobody answers. A dead or switched-off COM1 sends nothing. **Free flight only:** if you take off, land or enter a runway without a clearance you get one short note (once per flight), never a block. **In a training lesson ATC stays out of the way:** no unprompted calls or notes, the radio bar stays hidden (`` ` `` still opens the list), clearances count as given. The call sign defaults to VT-FSM (Options → Radio / ATC, or `callsign` in `options.cfg`). Details, phrase file and state machine: docs/ATC.md.
- **Checklists** (F2) that track what you've actually done.
- **Checklist window** (F2): a floating window, docked at the right edge and vertically centred the first time (it steps aside for the 2D instrument-panel pieces and the training card). Drag it by the title bar (it snaps to the screen edges and corners, keeping an 8 px margin, and can never leave the screen); resize it from any edge or corner (the cursor changes; minimum 250 x 130 UI units); **–** / Shift+F2 collapses it to the title and the current item, **×** / F2 closes it; the **Opacity** slider (or the wheel over the title bar) makes the background see-through while the text stays fully opaque; **‹ ›** or Ctrl+PgUp/PgDn switch lists. The current item is highlighted and scrolled into view; items the sim can detect tick themselves (green, locked), others tick on click or Enter. Only the window's own rectangle takes the mouse: everywhere else the mouse (and the mouse yoke) works as before, and the yoke holds still while the cursor is over the window. It is hidden during the pause screen. Position (as fractions of the free screen space, so it follows window and UI-size changes), size, opacity and collapsed state are saved in `options.cfg` (`checklist_*`); delete those keys to dock it again. Code: `ui/checklist_geom.gd` (clamp / snap / resize rules, tests in `tests/test_checklist_window.gd`), `ui/checklist_window.gd` (chrome, mouse), `ui/checklist_panel.gd` (the lists).

**Landmark terminals:** Mumbai (T2 and T1), Pune (the new integrated terminal and the old terminal) and Kochi (T3, T1 and T2) are drawn as dedicated models that look like the real buildings, not as generic blocks.
- **Mumbai T2:** SOM's glazed headhouse under one long roof on mushroom columns, with a 40 m kerb cantilever, a lit coffered soffit and glazed piers.
- **Pune:** the long "verandah" with a dark-basalt pointed arcade.
- **Kochi:** Kerala terracotta hip roofs with white gablets, cream walls, and a red fascia with "COCHIN INTERNATIONAL AIRPORT".
- Glass curtain walls reflect the sky and glow warm at night.
- Kochi is flyable (phase R corridor). To preview a terminal alone, use `godot --path game res://tests/debug_terminal.tscn -- --icao=VOCI --out=/tmp`.
- Details and sources are in [TERMINALS.md](TERMINALS.md).

**At the airport:** jetbridges, stand lead-in lines with stand numbers, yellow lead-on lines that carry on over the runway where a taxiway meets it, and windsocks that turn with the wind.

**Ground vehicles:**
- **At jetway gates:** a ground power unit at the nose, a baggage tug with carts aft, and a fuel truck on some stands. The jetways are the real FlightGear model, laid along the OSM jetbridge.
- **Elsewhere:** fuel trucks at some GA and remote stands, apron buses, and a fire truck by the tower.
- **Pushback:** a yellow towbarless-style tug.
- **Follow-me car:** when you request taxi (T), it drives ahead of you along the route, waits if you fall behind, and turns off at the hold-short point.
- **How they look:** every vehicle is built in code (`world/ground_vehicles.gd`, `vehicle_geo.gd`, `vehicle_parts.gd`, one `veh_*.gd` per type; no imported models; 2 to 5 thousand triangles each): fuel truck, GPU, baggage tractor and cart, apron bus, rescue and fire-fighting truck (red, roof turret) and pushback tug, with glossy clearcoat paint, rubber tyres with tread, glass, reflective bands and chevrons, a little dirt, and beacons that flash at night. The **follow-me car** (`follow_me_car.gd`) is a generic yellow double-cab pickup with a chequered FOLLOW ME board and amber light bar on the roof (the two sides flash in turn), headlamps, and brake lamps that light whenever it slows or waits. Its wheels turn with its speed and steer into corners, the body leans a little under acceleration and in turns, and it follows the ground slope. `tests/debug_vehicle_lineup.tscn` shows them all side by side (`-- --old` shows the previous models, `-- --night` the night look).

**Not yet:** moving service vehicles, AI traffic (ATC stage A2) and recorded radio voices with real radio effects (stage A3).

### Beyond the detailed region

- **Detailed area:** about 145 × 115 km, with 30 m terrain and 10 m imagery.
- **Outer ring:** coarser real data (90 m terrain, 80 m imagery) out to about 245 km, reaching Nashik, Ahmednagar, Satara, Kolhapur and the Konkan coast.
- **Beyond that,** to about 490 km, the terrain is filled from the nearest real data with generated relief and texture, so there is no edge.

### Landing, takeoff and damage (realism)

Mistakes end the flight the way they would in reality. The thresholds come from the C172S POH and FAR 23.

**Landing gear:**
- A touchdown sink rate above about 590 fpm at a main wheel is a **hard landing**: the airframe is damaged and needs inspection.
- Above about 900 fpm (about 510 fpm for the nose wheel) the **gear collapses** and the airframe drops onto it.
- Gear loads beyond the design limit also collapse the gear.

**Strikes and impacts:**
- **Prop strike:** the propeller tip touches the ground (for example, landing nose wheel first or porpoising). The engine is destroyed, and if you were moving faster than about 25 kt the aircraft noses over (crash).
- **Wingtip strike** above 10 kt (ground loop) is a crash. A **tail strike** damages the airframe.
- **Ditching** (touching water) is a crash. For trees, buildings, terminals, jetways and vehicles see **What counts as a crash** below.
- **Crosswind:** touching down while drifting sideways more than about 6 kt damages the gear; more than about 10 kt folds it (ground loop). Use a crab or wing-low correction.

**What counts as a crash (obstacles):** touching any solid ends the flight, in the air or on the ground, at any speed. The card names the part and the thing, for example "The right wingtip hit trees at 82 kt" or "The nose hit a parked vehicle (fuel truck) at 6 kt (taxiing)", and the replay (R) shows the same line.
- **The whole airframe counts**, not a few points: the propeller disc, nose, cowling, fuselage, both wings (leading and trailing edges, struts), tail fin and stabilizers, and the wheels. A 6 m house or a single tree between a wingtip and the nose is hit by the wing.
- **Solids:** trees (the same ones that are drawn, canopy and height), 3D OSM buildings (footprint and roof height), the landmark **terminal models** at Mumbai, Pune and Kochi (their real shape: you can taxi under an 8 m canopy but not into a wall), **jetways**, parked **ground vehicles** (fuel trucks, buses, baggage carts, GPUs), apron **floodlight masts** and windsock poles. Wheels count too: driving into a wall or a vehicle at 5 kt is a crash.
- **No gate on height:** a tall building beside a cliff is hit however far the ground is below you. Collision data for buildings loads around the aircraft (and where it is heading), not around the camera, and the tile under a freshly placed aircraft is read at once.
- **Normal ground operations never crash:** stands, the pushback swing, taxiways and runways are corridors where OSM buildings and trees (which are not survey-grade) are forgiven, ground vehicles and masts that would stand in them are left out, and an overlap that exists while you sit parked (a stand beside a tree) is forgiven until you drive away from it. Terminals, jetways and vehicles stay solid.
- Not solid: runway and approach lights, PAPIs, signs, the follow-me car and the pushback tug.

**In-flight limits:**
- More than 2 s above **Vne 163 KIAS** damages the airframe; at **185 KIAS** the structure fails.
- **Flaps above VFE** (110 kt at 10°, 85 kt beyond that) for 2 s damages and jams them.
- **Load factor** beyond +3.8 / −1.52 g overstresses the airframe; 1.5× those values breaks it. This counts flight loads only.

**After every landing** a debrief shows sink rate, g, airspeed, pitch, bank, centreline offset and distance past the threshold, with a grade: BUTTER (under 120 fpm), SMOOTH (under 300), FIRM (under 600), HARD (under 900), or DAMAGED.
**After a crash**, the cause and event log are shown; press F5 to restart.

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

**Not modelled yet:**
- tyre bursts
- engine damage from over-temperature or over-speed
- collisions with ground vehicles
- bird strikes

### Instruments and cockpit (M5)

The panel is a C172S steam-gauge layout:

- **Six-pack:** airspeed, attitude, altimeter, turn coordinator, heading indicator, VSI.
- **Tachometer.**
- **Engine/fuel cluster:** fuel L/R, oil temperature and pressure, EGT, fuel flow, vacuum, ammeter.
- **Wet compass strip.**

It shows on the 3D panel in the cockpit view (C) and as a 2D strip at the bottom of the screen in outside views (Tab).

**Clickable knobs**, in the cockpit or on the 2D panel:

| Gauge | Click left / right half, or mouse wheel | Other |
|---|---|---|
| Altimeter | Kollsman setting −/+ 0.01 inHg (hold Shift for 0.10) | |
| Heading indicator | Turn the card −/+ 1° (hold Shift for 10°) | Middle-click syncs it to the magnetic compass |

**What the instruments model:**
- **Airspeed:** C172S position error (reads about 6 kt low near the stall); pitot pressure falls off at high angle of attack.
- **Altimeter:** Kollsman setting and slight lag.
- **VSI:** about 6 s to settle after a pitch change.
- **Attitude indicator:** vacuum-driven gyro with a 3°/min erection mechanism, so it shows small turn and acceleration errors. It spins down and wanders after a vacuum failure, and shows a GYRO flag.
- **Heading indicator:** drifts about 4° per 15 min. Re-sync it to the compass regularly.
- **Compass:** pendulous card with real northerly turning and acceleration errors, and swing and overshoot.
- **Turn coordinator:** electric rate gyro canted 30°, with the slip ball.

### Navigation and radios (M7)

The panel now carries the right-hand column and radio stack of a real C172S:

- **VOR1** (KI-208 CDI) on NAV1 and **VOR2/ILS** (KI-209, with glideslope) on NAV2. The OBS knob works by clicking the left or right half, or by mouse wheel: ±1° per step, ±10° with Shift. Each shows TO/FROM and OFF flags.
- **ADF** (KI-227): the needle shows the NDB's relative bearing. The HDG knob turns the card (5° per step, 10° with Shift).
- **Radio stack:**
  - A GPS line.
  - Two KX-155 COM/NAV radios.
  - KR-87 ADF.
  - KT-76A transponder.
  - KI-266 DME, which follows NAV1.

  Tuning:
  - **Frequencies:** the mouse wheel over a standby frequency tunes it (COM 25 kHz, NAV 50 kHz, ADF 1 kHz; Shift for 1 MHz / 100 kHz steps), and clicking the ⇄ arrow swaps active and standby.
  - **Transponder:** the wheel over a digit changes it (0–7), and clicking the mode box cycles OFF/SBY/ON/ALT.
- **Reception:**
  - Navaids come from OurAirports.
  - Range depends on altitude, and terrain line of sight is checked every 0.5 s. Flying low behind the Western Ghats will lose Pune VOR.
  - The radios need avionics power.
- **ILS:** OurAirports has no ILS data, so `tools/14_ils.py` **generates simulated** localizers and glideslopes for the long runways. Geometry follows the real runway, and the glideslope is 3°. **The frequencies and idents are not real.** The map labels them "simulated".
- **GPS direct-to and route:** in the moving map, click any airport or navaid for direct-to; Shift+click adds it as a further leg. The GPS line on the stack shows bearing, distance and ETE of the active leg, and the GPS flies to the next leg by itself once you pass within 1 nm of the active waypoint (`avionics/route_plan.gd`; Props `controls/gps/target` is the active waypoint and `controls/gps/route_next` the ones after it).
- **Moving map (N):** a large overlay (the window minus a 28-unit margin, scaled with UI size) that opens centred on the aircraft, about 20 nm across, or wider if a route is set so that the whole route fits.
  - **Contents:** satellite imagery (loaded in the background, a coarser tile stands in while a fine one loads, so there are no holes), airports and runways, VOR / NDB, ILS feathers, your track, the aircraft symbol turned to its heading, a north arrow and a scale bar. Labels do not overlap: route names win, then airports, then navaids; heliports show below 15 nm across, navaid names below 140 nm.
  - **Zoom:** mouse wheel (around the cursor), `+` / `-` (also `=` and the number pad), or the on-screen buttons; 0.3 to 300 nm across, eased. While the map is open `=`, `-` and Num +/- zoom instead of moving the throttle (Page Up / Page Down still do), and the mouse yoke is ignored.
  - **Pan and follow:** drag with the left button (a click moves under 6 px, so a drag never sets a direct-to). Panning, or zooming at the cursor away from the middle, leaves follow mode; **Space** or the Follow button recentres on the aircraft. **O** (or the button) switches north up / heading up. **G** (Fit route) zooms to show the whole route.
  - **Route (magenta line):** from the aircraft to the active waypoint in bold, later legs thinner, with a dark outline, direction arrows, a label per leg (magnetic bearing, distance, ETE; ETE uses 90 kt when you are nearly stopped), a diamond with ident and distance along the route at each waypoint, and a ring on the active one. The line updates live as you fly. **Backspace** or the Clear route button cancels the direct-to and the route. The bottom of the map shows the whole route with total distance and ETE. There is no mini map in the cockpit panel.
  - **Keys:** N open/close, wheel or +/- zoom, Space follow, O orientation, G fit route, Backspace clear route. Tests: `tests/test_map.gd`; screenshots: showcase scenes `map_open`, `map_zoom_in`, `map_zoom_out`, `map_route`, `map_heading_up`.

Default frequencies are COM1 118.10/121.90, NAV1 116.60/113.90, NAV2 108.10/109.30, ADF 381 and squawk 7000. Panel layouts: the Full, Split and Compact layouts include the VORs, ADF and radio stack.

### Systems, weather and failures (M6)

**Switch panel** (the bottom row of the instrument panel; click to toggle):
- **Electrical:** BAT and ALT masters, AVN (avionics).
- **Lights:** BCN, LAND, TAXI, NAV, STRB, and the PANEL dimmer knob (click left/right half or wheel, or L / Shift+L).
- **Aircraft lights at night:** red/green/white nav lights, a flashing red fin beacon and white wingtip strobes (double flash) are drawn as glowing points with a minimum on-screen size, so the aircraft stays visible from the tower miles away; small shadowless lights tint the wingtips, fin and wings around them. Landing and taxi lights are spot lights with a faint visible beam and a lit pool on the runway ahead (fading out above ~80 m AGL). A soft fill keeps the airframe readable in outside views. All of this is off in daylight (the bulbs still glow).
- **Lights at start (night or dusk, sun below 5°):** nav + beacon always; strobes for air and runway starts; landing light for runway starts and air starts below 3000 ft AGL; taxi light for runway starts. Cold & dark and stand starts: everything off. By day: beacon only.
- **Cockpit at night:** the instruments are internally lit and follow the PANEL dimmer (default 70 %; unpowered = dark), the radio displays stay lit, and a warm glareshield flood lights the panel and yokes. Daytime look is unchanged.
- **Other switches:** PITOT HT; fuel SHUTOFF valve; ALT STAT (alternate static source).
- **Rotary selectors** (click left/right half, or mouse wheel):
  - MAGS: OFF/R/L/BOTH
  - FUEL selector: OFF/LEFT/RIGHT/BOTH

**What's modelled:**
- **Electrical:** 24 V battery (35 Ah) and 60 A alternator.
  - The alternator needs more than about 1000 RPM, so at idle the ammeter shows discharge.
  - The LOW VOLTS light comes on below 24.5 V.
  - The starter needs battery power, and the flaps and turn coordinator need bus power.
- **Fuel:**
  - Left and right tanks feed according to the selector.
  - The engine runs about 6 s on line fuel after starvation, and restarts while windmilling once fuel returns.
  - A left-tank leak failure is available.
- **Weather** (F10 or command line):
  - **Wind:** logarithmic surface profile blending into the wind aloft, plus gusts and turbulence.
  - **Terrain effects:** ridge lift on windward slopes (the Ghats give about 3 m/s in a 20 kt westerly) and sink plus mechanical turbulence on the lee side.
  - **Atmosphere:** QNH and temperature affect density altitude and the altimeter. The Kollsman window is preset to QNH at start.
- **Sky:** clouds are a cumulus layer that drifts with the wind aloft. Visibility drives haze and fog: everything fades to the horizon colour with an extinction of 3 / visibility (5 % contrast at the visibility distance), so low visibility merges terrain, cloud base and sky.
- **Cloud cover and rain** (`world/weather_visuals.gd`, `world/weather_fx.gd`):
  - Broken and thicker cover dims and diffuses the sun: under Overcast there are no hard shadows or sun disc, the light is flat and grey, the sky and cloud base turn grey and the undersides darken. Climb above the tops and the sun is back.
  - Rain falls only below the cloud tops: streaks around the camera lean with the wind and stretch with airspeed (count set by the graphics preset), drops bead on the windshield when parked and run back and streak with airspeed, terrain, roofs and trees get darker and glossier with standing water on flat ground (they dry slowly after rain), rain lowers visibility, and rain on the canopy is heard louder at speed. Monsoon storms have occasional lightning flashes.
- **Night:** a real moon (position and phase for the date, cool moonlight and a glitter path on water), stars, a warm city glow on the horizon and cloud undersides, and a night ambient level and exposure so terrain, coastlines and clouds stay readable.
- **Time of day:** real sun position for Mumbai/Pune (IST). Default 10:00 on 14 February. The F10 time rate can speed it up.
- **Night:** ICAO/FAA aerodrome lighting, built per airport within 25 km: runway edge lights (white, last 600 m yellow on instrument runways), green threshold / red end bars with wing bars, centreline lights (white, red/white alternating 900-300 m, red last 300 m) and touchdown-zone barrettes on ILS runways, ALSF-II-style approach lights with sequenced flashers ("the rabbit") on ILS ends and a 420 m simple system elsewhere, a PAPI on the left of each runway (2 red + 2 white on a 3 degree path, visible by day too), blue taxiway edge and green centreline lights with green/yellow lead-on lights, red stop bars and flashing runway guard lights at holding points (night and visibility under 5 km), rotating green/white aerodrome beacons, and apron floodlight masts. Lights are directional, fade in haze and dim by day. The aircraft has nav, beacon, strobe, taxi and landing lights.
- **Failures:** 26 failures with schedules and random failures. See "Start screen" above, and F9 in flight.

**Realism notes:**
- On runway and air starts the engine is running. Stand starts and `--cold` are cold & dark. To start the engine: BAT on (Shift+M), mixture rich (hold '), throttle cracked (Page Up), magnetos BOTH (M three times; a cold start has them off), then hold S. The engine fires after a fraction of a second of cranking and idles by itself when you let go; the e2e job `coldstart_keys_VAJJ` does exactly this with real key presses.
- With only the pilot aboard (the default load) the CG sits slightly left, and engine torque also rolls the aircraft left. Fixed aileron/rudder tabs (`controls.aileron_rigging` 0.033, `rudder_rigging` 0.004) cancel this at about 100 KIAS in level flight. Slower or at climb power it rolls gently left (hold a little right aileron and right rudder); faster it rolls slightly right. Hands off from trim, the bank after 60 s is about −10° at 90 KIAS, 0° at 100 KIAS and +10° at 110 KIAS. JSBSim's c172p behaves the same way: its spiral mode is nearly neutral. See `docs/FDM-VS-FLIGHTGEAR.md`.
- The aircraft turns left on the takeoff roll (P-factor and torque), so use right rudder (X).
- **Sound** uses real recordings throughout:
  - the C172 engine (start, crank, idle, run and cut, pitched by RPM)
  - stall horn, gyro spin-up, flap motor, trim wheel
  - tyre roll, touchdown squeal, wind by airspeed
  - switch clicks and levers
  - Switch clicks are cockpit-only. Sources and licences are in `game/aircraft/c172/sounds/SOURCES.md`.

### Terrain viewer (M2)

A free camera without an aircraft, for inspecting the scenery:

```bash
~/.local/bin/godot --path . res://world/terrain_viewer.tscn -- --at=-15000,-20000,1400 --heading=70 --pitch=-12
```

`--at=east,north,altitude` is in world metres (altitude above mean sea level). Keys: right-mouse look, W/A/S/D move, E/Q up/down, Shift ×10, Ctrl ×0.1, mouse wheel changes speed, G drops to 50 m AGL, R resets, F3 shows the overlay.

### Automated tests

```bash
cd game
~/.local/bin/godot --headless --path . res://tests/run_tests.tscn               # all tests
~/.local/bin/godot --headless --path . res://tests/run_tests.tscn -- --only=fdm  # tests named test_fdm*
~/.local/bin/godot --headless --path . res://tests/run_tests.tscn -- --suite=test_replay  # suite files whose name contains this
```

The runner prints PASS/FAIL per test and exits non-zero on failure. The run must end without "ObjectDB instances leaked" / "resources still in use at exit" messages (the e2e sweep's "no script errors" check fails on them): a test that builds a Node must free it, and a callback that captures `self` (or an object that holds it) makes a reference cycle. `-- --leaks` lists the tests that leave orphan nodes behind.

| Suite | Covers |
|---|---|
| `tests/test_core.gd` | Geo projection, floating origin, terrain heights and runway flatness |
| `tests/test_fdm_cards.gd` | POH performance test cards (M3) |
| `tests/test_flight.gd` | Takeoff from Juhu on the real terrain and runway (M4) |
| `tests/test_instruments.gd` | Altimeter and Kollsman, ASI, VSI lag, vacuum-failure gyro drift, compass northerly turning error (M5) |
| `tests/test_systems.gd` | Alternator failure and battery drain, fuel starvation and restart, wind profile, Ghats ridge lift (M6) |
| `tests/test_landing.gd` | Normal landing plus POH landing roll; hard landing, nose-first and prop strike, ditching, Vne failure, overstress, flap overspeed |
| `tests/test_engine_start.gd` | Cold start: the starter alone turns the engine above its firing speed, it fires and idles by itself at every throttle, nothing starts without mixture / magnetos / fuel, battery start with the alternator charging |
| `tests/test_apron_flat.gd` | Apron ground from the real terrain cache: stand-area relief at VABB and VANM (no DSM mounds), landmark terminal base height on the ground (step 17 + 16) |
| `tests/test_fdm_handsoff.gd` | Hands-off for 60 s at 3000 ft: neutral at 100 KIAS, bank about −10° and heading about −70° at 90 KIAS, pinned to JSBSim's c172p with the same rigging |

### README screenshots

`tools/make_screenshots.sh [scene ...]` regenerates the gallery in `docs/screenshots/` from the real game: each scene (list and camera settings in `game/tests/showcase_scenes.gd`, runner `game/tests/debug_showcase.gd`) is one game run at 1920x1080 on the Ultra preset that places the aircraft, hides the UI except what the scene shows, waits until the terrain, tree and building streamers are idle and saves a PNG (to `$FREESIM_SHOTS`, default `/tmp/libresim-shots`); the script then writes the 1600x900 progressive JPEGs (quality 85, Pillow from `tools/.venv`). It needs a display and the generated data, opens a window per scene, and backs up and restores your `*.cfg` / `*.json` settings and saves in the user data folder. To look at a new camera, add `"variants"` to a scene and run `godot --path game res://tests/debug_showcase.tscn -- --scene=<name> --quality=ultra`.

### Flight-model test cards (M3)

`tests/test_fdm_cards.gd` flies the C172 with a test autopilot (2550 lb, sea level, ISA) and checks it against the POH:

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

### Adding an aircraft

An aircraft is a folder `game/aircraft/<id>/`; nothing else in the game names an aircraft. Everything is read through `AircraftDef` (`game/aircraft/aircraft_def.gd`: `load_def(id)`, `current()`, `path(key)`, `config()`, `section(name)`, `section_or(name, defaults)`; an unknown id falls back to the c172). Generic code (cockpit, lights, audio, glass, reflections) is in `game/aircraft/common/`, the model loader is `game/aircraft/aircraft_model.gd`. Folder layout:

```
game/aircraft/<id>/
  aircraft.json    what the game shows and needs: name, specs, limits, systems, ... (sections below)
  config.json      flight model: mass, gear, tanks, engines, controls
  aero.json        aerodynamic tables (JSBSim form, tools/06_jsbsim_to_json.py)
  hull.json        collision outline (optional)   checklists.json   panel.json   (optional)
  models/exterior.glb, models/interior.glb, sounds/   (optional; a placeholder airframe is drawn without a glb)
```

Each file name can be overridden with a `files` map in `aircraft.json` (`{"config": "other.json"}`).

`aircraft.json` sections (`AircraftDef` header lists the same): `model` (glb pivots), `cockpit` (gauge spots, eye), `lights`, `audio`, `limits` (V-speeds, load limits), `damage` (touchdown thresholds, propeller hubs), `systems` (electrical, fuel, pitot-static), `ground` (below), `payload` (start-screen stations), `failures` (optional allow-list). Details of each are in the two "Aircraft data" sections above. `ground`: the footprint stands, taxi corridors and jetways are sized for, structural-frame metres about the CG: `ahead_m` (3.3, forward incl. margin), `behind_m` (7.4, to the tail), `across_m` (6.7, half span) and `height_m` (2.5, what a jetway or tunnel must clear). Defaults are the C172's. `ground` also takes `tow_ahead_m` (tug position ahead of the CG during pushback) and `min_runway_m` (the start screen marks shorter runways "too short for this aircraft"). Ground operations read more keys (all optional; the defaults are the C172's, so it needs none; they live in `world/ground_params.gd`): `cg_to_door_m` (0; L1 door ahead of the CG: at a jetbridge gate, whose stand point is the door, the CG is placed that far behind it), `door_height_m` (absent = `height_m`; what a jetway part must clear before it counts as solid in a corridor, so an airliner's own gate does not drop its jetway), `nose_gear_m` (0; nose wheel ahead of the CG, where the stand stop bar is drawn), `taxi_half_m` (8; half width of the taxiway corridor in which OSM obstacles are forgiven), `max_taxi_kt` (absent = no advice; a short note "Taxi speed N kt, keep it under M kt" while a taxi route is active), `follow_gap_m` (absent = max(35, `ahead_m` + 25); the follow-me car leads by that much, starts 5 m further ahead and peels off 10 m before it), `hold_short_m` (40; distance of the "Hold short" call), `min_runway_m` (0; shorter runways are marked on the start screen, never the default pick, and rank last for the wind-based runway choice of taxi guidance and ATC), `stand_class` (`"any"`, `"ga"`, `"gate"`; `"any"` = no preference, the first jetbridge gate is the default stand and taxi-to-apron prefers ramp stands; `"gate"` offers jetbridge gates and remote bays (no GA tie-downs), gates first, and taxi-to-apron prefers gates; `"ga"` lists tie-downs first; a stand is a gate if `jetbridge`, GA if its ref starts with GA or it is synthesised, else remote: `world/ground_choice.gd`), `tug_scale` (1; size of the pushback tug model, `tow_ahead_m` is its origin ahead of the CG, so for a scaled tug add its cradle, about 2.9 m x scale, to the nose gear position), and `service` (`{gpu, baggage, fuel, bus}`, each `[forward, right]` in metres from the L1 door; vehicles an aircraft does not list keep their legacy offsets from the stand point; without a `service` block all do). The top-level `pushback` section sets the path and speed: `{"straight_m": 30, "radius_m": 18, "speed_mps": 1.4}` (straight back, then a 90 degree swing around the CG's arc; the stand corridors for obstacles are sampled along it with the full footprint, so no separate nose-gear check). Not done: jetway docking animation, a taxiway width filter in the route search, a stand size class in `tools/airport_stands.py` (the class is derived at run time). Other top-level keys: `radio_type` (how the pilot calls the aircraft on the radio, e.g. "Cessna 172", used by the `{type}` slot in `atc/phraseology.json`), `atc` (`{profile: "ga" | "airline", wake: L|M|H|J}`; an airliner adds `telephony` (a fictional airline name), `flight_no` and `callsign_style: "airline"`, giving the radio call sign "Skyline 123"; the airline profile uses IFR phrases and no VFR circuit, see "Airline profile" in `docs/ATC.md`), `cameras` (`chase` [back, up], `wing`, `tail` [x, y, z], `orbit_m`; default: the C172's scaled by wingspan), `start` (`pitch_trim` of a parked start), and in `limits`: `vr_kias` (Rotate call) and `vs0_kias` (Airspeed-alive call). `registration` (a target takes `rotate: 180` for an upside-down atlas island) paints the tail number on the exterior texture at flight start (`aircraft/common/registration_paint.gd`): `source` `"callsign"` (the pilot's call sign from Options / the start screen, default VT-FSM) or `"fixed"` (+ `text`, e.g. an airliner's own registration), `texture` (the atlas, relative to the aircraft folder), and `targets` `[{erase [x,y,w,h] (pixels of the old number plus a margin), text [x,y,w,h] (box the new one is fitted into, aspect kept), align left|right|center, color [r,g,b], italic}]`. No section = the model keeps its own number. A changed call sign shows at the next flight start.

`config.json` engines. The older single-engine form `{"engine": {...}, "propeller": {...}}` is one piston engine. For any number of engines use a list (each engine carries its own `propeller` block, copy it per engine):

```json
"engines": [
  {"type": "piston", "pos_m": [-0.96, -1.6, 0.68], "maxhp": 180, "...": "as the c172 engine block", "propeller": {"diameter_m": 1.9, "...": "..."}},
  {"type": "turbine", "pos_m": [1.0, 1.6, 0.9], "thrust_n": 12000, "max_rpm": 100, "idle_n1": 0.22,
   "spool_up_s": 5, "spool_down_s": 3, "tsfc_kg_per_n_s": 1.6e-5, "alt_exponent": 0.8, "mach_lapse": 0.3, "windmill_drag_n": 36, "start_n1": 0.25}
]
```

`pos_m` is the thrust point in structural metres (x aft, y right, z up). `type` is `piston` (engine plus propeller, `fdm/engine_piston.gd`) or `turbine` (no propeller; `fdm/engine_turbine.gd`: N1 spool, thrust from N1 with density and Mach lapse, fuel flow = `tsfc * thrust`, windmilling drag when failed or out of fuel). Optional `cruise_rpm` / `start_rpm` set the thruster speed of an airborne / ground start. Engine 1 has the controls `controls/throttle`, `mixture`, `starter`; engines 2..N use `controls/throttle_2` ... (falling back to the engine-1 lever) and `failures/engine_2` ... `tanks` is any list (`pos_m`, `capacity_kg`, `contents_kg`); a tank's side (left / right / centre) comes from its y position, and the fuel system (`systems.fuel.feed`: `selector` or `all`) decides which tanks feed.

`gear` entries take an optional `role`: wheels `nose`, `main` or `tail`; structure points `wingtip`, `tail_skid` or `skid`. When it is missing it is derived: a steered wheel ahead of the fixed wheels is `nose`, behind them `tail` (a taildragger; it uses the weaker-leg limits of the nose wheel), structure points by name (`TIP`, `TAIL`). `brake_group` is `LEFT`, `RIGHT`, `BOTH` or `NONE` (which pedal brakes the wheel).

`config.json` and `aero.json` of a JSBSim-based aircraft come from `tools/06_jsbsim_to_json.py [id]`: add an entry to `SPECS` (JSBSim aircraft, engine and propeller file names, rigging, gear damping, V-speeds, ...) and run `$PY tools/06_jsbsim_to_json.py <id>` (default `c172`; the committed c172 files regenerate byte for byte). Aircraft built another way write the two JSON files by hand. Tests: `tests/test_generic_aircraft.gd` builds a twin piston, a taildragger and a twin turbine from the c172 data in code (`AircraftDef.make`), a good template for checking a new configuration.

### Tuning the aircraft

The aircraft's behaviour is data, so you can tune it without touching code:

- `game/aircraft/c172/config.json`: mass, inertia, gear springs and friction, surface limits, flap timing, engine and prop. `propeller.ct_factor_vs_j` (a thrust multiplier versus advance ratio) and `cp_factor` are the main performance knobs.
- `game/aircraft/c172/aero.json`: aerodynamic coefficient tables and constants, from JSBSim.
- Both files are regenerated by `tools/06_jsbsim_to_json.py`, so put permanent tuning changes in that script (or stop regenerating the files).
- `controls.full_travel_s`: the actuator rate limits (seconds for full −1..1 travel; pitch 0.3, roll and yaw 0.15, from FlightGear's c172p).
- Re-run the test cards and `tools/18_compare_fdm.py` after any change.

### Aircraft data: limits, systems, payload

Numbers that belong to one aircraft are in its `aircraft.json` (read through `AircraftDef`, `game/aircraft/aircraft_def.gd`); the scripts hold only defaults. Sections:

- `limits`: `vne_kias`, `vd_kias`, `vfe_kias` (`[[max flap deg, KIAS], ...]`), `g_pos`, `g_neg` (damage model), `vs0_kias`, `vs1_kias`, `vno_kias`, `asi_min_kias`, `asi_max_kias` (airspeed indicator arcs and scale; the white arc ends at the last `vfe_kias` speed), `tach` (`max_rpm`, `green` `[lo, hi]`, `red`) and `gauges` (`fuel_gal`, `oil_temp_f`, `oil_press_psi`, `egt_f`, `fuel_flow_gph`, `suction_inhg`, `ammeter_a`, each `{min, max, green: [lo, hi], red}`; `red` optional, a gauge left out is not shown on the engine strip).
- `damage`: touchdown and gear thresholds (`hard_landing_ms`, `collapse_ms`, `nose_collapse_ms`, `collapse_drop_m`, `side_damage_ms`, `side_collapse_ms`, `main_load_w`, `nose_load_w`) and `prop_hubs_m` (one `[x, y, z]` structural position per engine, for the prop-strike check).
- `systems.electrical`: `battery_ah`, `alt_max_a`, `alt_rpm_min`, `alt_rpm_ramp`, `bus_volts`, `bat_v_empty`, `bat_v_full`, `bat_ohm`, `charge_gain`, `charge_min_a`, `starter_a`, `flap_motor_a`, `low_volts`, `powered_volts`, `starter_min_volts`, `loads` (amps per consumer). Defaults are the C172's, in `systems/electrical.gd`.
- `systems.pitot_static`: `pos_err_kcas` and `pos_err_dkt` (airspeed position error table, kt; none = no error).
- `systems.fuel`: see `systems/fuel.gd`.
- `payload`: `fuel_kg_per_gal`, `cruise_gph` and `reserve_gal` (endurance estimate on the aircraft page), `fuel_slider` (`min`, `max`, `step`, `unit`; the fuel per tank) and `stations`, a list of `{key, label, max, step, masses}`. `key` is the `Session.setup` entry (kept in saved flights), `masses` the names of the `config.json` point masses the station's kg is split over. W&B, the start screen and the flight loading all read this list.
- `payload` extras for an airliner: `fuel_unit: "kg"` makes the fuel slider and `Session.setup.fuel_gal` the TOTAL fuel in kg (wing tanks first in proportion to capacity, then the centre tank, pipe tanks empty: `WeightBalance.fuel_per_tank`), `cruise_kgh` / `reserve_kg` (endurance line), `defaults` (`{fuel_gal, cabin_kg, cargo_kg, ...}` applied by `Session.apply_payload_defaults` when the aircraft is chosen on the start screen or with `--aircraft=`; an aircraft without it restores the plain defaults). `cg_envelope` for the A320: `mac {lemac_x_m, mac_m}` reports the CG in % MAC, `weight_unit "kg"` + `max_kg` + `landing_fuel_kg`, `cg_label` / `cg_unit` labels and `chart {x, y, x_step, y_step}` axis ranges (all optional; defaults = the C172's inches / lb chart). The A320 envelope is approximate (public shape, assumed LEMAC), say so wherever it is shown.
- `start.air_kt` (airborne start speed when no `--air-kt` is given; the A320 starts clean, gear up, at 250 KIAS), `fcs {"law": "airbus_fbw"}` (control law), `callouts {alive_kt, rotate_kt, v1_kt, low_kt, heights}` (training callouts of `ui/callouts.gd`; `v1_kt` adds a "V one" call, `heights` the radio-altitude calls).
- `failures`: optional `{"disabled": [ids]}` to remove failures from the catalogue (`systems/failure_catalog.gd`); engines 2..N get `engine_<n>` / `engine_partial_<n>` automatically.

### Aircraft data: FDM props (airliner parts of the FDM)
Aircraft whose `config.json` has the A320 shapes get extra FDM parts; absent keys = the C172's behaviour, which the tests assert unchanged. Selection: `controls.flaps` a Dictionary with `detents` -> `AirlinerControls` (`fdm/flight_controls_airliner.gd`: per-surface `SurfaceActuator`s from `controls.surfaces` (lag, rate, clip, final-deg conventions: aileron / elevator + = trailing edge down, rudder + = nose right, THS nose up = negative), flap + slat detents, 5+5 spoiler panels, speedbrake; the `law` seam: `FlightControls.law.update(dt, fdm)` writes `fcs.cmd` / `fcs.spoiler_cmd` and replaces the direct stick mapping); any `gear[].retractable` -> `RetractableGear` (`fdm/gear_retractable.gd`, built through `Gears.make(cfg)`: retract / extend over `controls.gear_transit`, locked down on the ground, nose wheel `gear[].steer {tiller_deg, pedal_deg, fade_mps}`, `gear[].brake_mu`, anti-skid, autobrake LO / MED / MAX); an engine with `thrust_table` -> `EngineTurbineFadec` (`fdm/engine_turbine_fadec.gd`, limits from top-level `fadec_limits` through `fdm/turbine_fadec.gd`: JSBSim thrust tables over Mach and density altitude, N1 spool-rate tables, N2, EGT, TSFC x sqrt(T/288.15), start sequence, reverse); `engines[].orient_deg` gives the thrust line; top-level `apu` adds `systems/apu.gd` (`fdm/apu_model.gd`). Expressions and 3-D tables: `fdm/expr.gd`, `fdm/table.gd`; `Aero.strict = true` makes an unknown property name an error (tests).
Props read (`fdm/fdm_airliner_props.gd`): `controls/gear` `speedbrake` `autobrake` `tiller` `engine_master_<n>` `engine_mode` (0 NORM, 1 CRANK, 2 IGN/START) `reverse_<n>` `flex_temp_c` `lights/landing`, `failures/engine_fire[_<n>]`, `systems/hydraulics/antiskid`; the lever of engine n is `controls/throttle_<n>` - `controls/reverse_<n>`. Props published: `engines/<n>/{n1,n2 (percent),egt_k,ff (kg/s),oil,thrust_n,running,reverser,lever}` (engine 1 also as `engine/*`), `fdm/{mach,slat_deg,spoiler (per panel deg),spoiler_left_deg,spoiler_right_deg,speedbrake,stabilizer_deg,flap_lever,flap_deg,gear_pos,gear_state,door_pos,autobrake_on,ground_speed_mps}`, `apu/{running,starting,n_pct,ff_kgs}`. FlightControls / gear fields saved and replayed: `slat_deg slat_cmd spoiler spoiler_cmd speedbrake speedbrake_cmd gear_pos gear_cmd thrust_lever`, gear `gear_pos gear_cmd gear_state door_pos`. Not modelled: engine feed from the pipe tanks (the three pipe tanks are excluded from the default feed; fuel.gd feeds all tanks equally), bleed air, oil / fire systems. The FBW law is described below.

### Aircraft data: flight control law (fly-by-wire)

`aircraft.json` `"fcs": {"law": "airbus_fbw", ...}` installs `FbwLaw` (`fdm/fbw_law.gd` + `fbw_{params,sense,pitch,roll,yaw,trim,protection,reversion}.gd`) as `FlightControls.law` of an `AirlinerControls`; absent = direct stick-to-surface control (the C172, and the A320 until its `aircraft.json` carries the section). Every other `fcs` key is optional and overrides the defaults in `FbwParams.DEFAULTS` (nested dictionaries merge): `nz_max / nz_max_flaps / nz_min*`, `pitch_limit_deg`, `vmo_kt / mmo` (default from `limits.speeds`), `ground_blend_s`, `ground_gain` (direct elevator vs CAS kt), `flare`, and the groups `pitch` (`kn ki kq kiq q_max_dps trim_k trim_dead_deg k_alpha alpha_lead_s k_theta`), `roll` (`rate_dps kp ki kff k_bank hold_deg limit_deg limit_prot_deg taper_deg level_deg spoiler_start spoiler_max_deg`), `yaw` (`k_r k_beta limit_deg travel_kt`), `alpha_deg.rows` (`[slat, flap, alpha_prot, alpha_max, alpha_stall]` deg per configuration), `speed_prot`.

- **Laws** (`FbwReversion`): NORMAL, ALTERNATE (load factor law and auto-trim, roll direct, no protections), DIRECT (stick to surface, trim wheel). Reversion from `failures/{adr, adirs, elac (or elac_1 + elac_2), sec, hyd_g, hyd_b, hyd_y, fac}`: ADR / ADIRS / ELAC lost or two hydraulic circuits -> ALTERNATE; ELAC + SEC or all three circuits -> DIRECT; ALTERNATE with the gear down -> DIRECT; `fcs/law_force` (0..2) forces at least that law. `fac` only removes the yaw damper and the rudder travel limit.
- **Pitch**: stick = load factor demand `cos(gamma) / cos(phi) + increment` (neutral = hold the flight path, also in a bank), rate loop with speed-scheduled gains (`q_ref / qbar`), THS auto-trim, ground mode = direct (scheduled gain) blended over `ground_blend_s`, flare mode (nose-down bias below 50 ft RA, gear down, levers back). **Roll**: stick = roll rate (15 deg/s), bank hold on release (wings level below 2.5 deg, back to 33 deg above it), limit 67 deg (45 deg in the alpha / speed protections), roll spoilers on panels 2-5. **Yaw**: pedals with a speed travel limit, yaw damper, turn coordination.
- **Protections** (normal law): high angle of attack (stick maps to alpha between `alpha_prot` and `alpha_max`, alpha floor latch), high speed (nose-up bias above VMO + 6 kt / MMO + 0.01), bank, pitch attitude (-15 / +30 deg), load factor (+2.5 / -1 g, +2 / 0 g with slats or flaps).
- **Props published**: `fcs/law` ("NORMAL" / "ALTERNATE" / "DIRECT"), `fcs/law_id` (0..2), `fcs/law_reason`, `fcs/ground_mode`, `fcs/flare`, `fcs/alpha_{prot,max,floor,stall}_deg`, `fcs/alpha_floor` (bool, for the A/THR), `fcs/stall_warning`, `fcs/prot/{alpha,speed,bank,pitch,nz}`, `ap/cmd/takeover`.
- **Autopilot interface**: with `ap/cmd/active` the law takes `ap/cmd/nz_g` (g increment) and `ap/cmd/roll_rate_dps` (+ right) instead of the stick; a sidestick deflection above 0.1 sets `ap/cmd/takeover` (the autoflight disengages on it) and gives the stick back immediately.
- Tuned against `tools/a320_reference.json` (JSBSim A320): roll rate 7.4 / 15.3 deg/s for half / full stick (ref 7.35 / 15.0), alpha limits from the JSBSim tables; pitch is faster than the reference (63 % of a load factor step in about 1 s vs 1.9 s, whose g-law PI is a stand-in). Tests: `tests/test_fbw_a320*.gd`.

### Aircraft data: replay

What instant replay (R) records is the C172 channel list (`systems/replay_layout.gd`, never changed, so C172 recordings keep their layout) plus the optional `replay` section of `aircraft.json`, all keys optional:

- `lerp`, `rad`, `deg`, `bool`, `int`: extra prop keys by kind (`rad` / `deg` are angles interpolated the short way, `bool` / `int` are held between frames).
- `enums`: `{"ap/fma/lateral": ["", "HDG", "NAV", "LOC"]}`: a string prop recorded as an index into its list (a value not in the list is not recorded).
- `units`: per-engine channels `engines/<n>/rpm | thrust_n | fuel_flow_kgs | egt_k | oil_press_pa | oil_temp_k | running` and `controls/throttle_<n>`, `mixture_<n>`, `starter_<n>`. Default: on when the aircraft has more than one engine. Aircraft with more than two tanks also record every tank as `fuel/tank_kg#<i>`.
- `fcs`: `true` (the list `ReplayChannels.EXTRA_FCS_FIELDS`: `slat_deg`, `spoiler`, `speedbrake`, `gear_pos`, `thrust_lever`) or a list of `FlightControls` field names; a field that the aircraft's `fcs` does not have is skipped, an array field gets a channel per element. These are state the model reads directly, so they play back like the elevator.

Taking control resumes every engine (rpm, running, EGT, oil, levers) and every tank from the replay frame. `tests/test_replay_generic.gd` pins the C172 channel list.

### Aircraft data: saved flights (the saveable rule)

A system node that keeps state between ticks (battery charge, APU, hydraulics, autoflight) joins the group `saveable` in `_ready` (`add_to_group(SituationSystems.GROUP)`) and implements `save_key() -> String` (stable name), `save_state() -> Dictionary` (JSON-safe) and `load_state(d)` (every key optional). `core/situation_systems.gd` then saves and loads it with a flight (`systems.<key>` in the file); nothing else needs to change. Props under `engines/`, `ap/`, `apu/`, `fcu/` and `hyd/` are saved too. Optional FCS / gear fields (slats, spoilers, speedbrake, gear position) are saved when the object has them: names in `SituationFdm.OPTIONAL_FCS_KEYS` / `OPTIONAL_GEAR_KEYS`. Saves from before the hook (flat `soc`, `suction`, `fuel_line`, ...) still load.

### Aircraft data: model, cockpit, lights, audio

The look and sound of an aircraft is data too. Files are found by `AircraftDef.path(key)`: `models/exterior.glb`, `models/interior.glb`, `sounds/`, `panel.json` in the aircraft's folder (override any of them with a `files` map in `aircraft.json`). Without an exterior glb a `PlaceholderAirframe` (`game/aircraft/placeholder_airframe.gd`) is drawn from `config.json` (wingspan, chord, tail arm, gear contacts, one propeller or nacelle per engine), with moving control surfaces. Generic code is in `game/aircraft/common/`, `aircraft_model.gd` and `ui/instrument_panel.gd`.

- `model`: `surfaces` is `{pivot: {drive, sign}}`: the glb node `pivot_<pivot>` turns about its X axis by `sign` times the control position (`drive` = `elevator`, `aileron`, `rudder` in radians, or `flap_deg`); `propellers` is a list of `{pivot, engine (0 = engine 1), sign, visual_rate}` (spin = `sign * rpm/60 * TAU * dt * visual_rate`); optional `origin_m` places the glb's origin (default `metrics.vrp_m`). The glb uses FlightGear's model frame (x aft, y right, z up from the origin). A missing pivot is skipped. Airliner drives (`aircraft/model_drives.gd`): `slat_deg`, `stabilizer_deg`, `spoiler_<l|r><n>_deg`, `gear_pos` / `reverser` (0..1, with a piecewise `map` `[[value, degrees], ...]`), `nose_steer_deg`, `wheel_nose_rad` / `wheel_main_l_rad` / `wheel_main_r_rad` (rolling angle from the ground speed). A leg pivot may carry `compress: "<gear contact name>"` and `lift_m`: the leg is raised by that contact's spring compression (+ `lift_m`, the metres the tyre bottom hangs below the contact point when extended), so tyres stand on the ground instead of sinking by the static deflection (0.14 m nose / 0.30 m mains on the A320; `lift_m` is calibrated from the glb: tyre bottom minus contact z, A320 nose -0.04, mains 0). Check with `godot --path game res://tests/debug_tyres.tscn --audio-driver Dummy -- --aircraft=a320 --airport=VABB --stand --at=60 --shots=<dir>` (prints each tyre's gap to the terrain, FDM contacts, glb wheel positions; PNGs side / front / rear / gear / nose; `--nolegs` shows the uncorrected state). Wheel spin ignores ground speeds below 0.05 m/s (a parked aircraft creeps by mm/s) and uses the measured tyre radii (`model_drives.gd`). A turbofan's `rpm` is N1 in percent: use `visual_rate` about 0.75 for a fan (0.13 for a propeller).
- `cockpit` `screens` (glass displays measured on the glb: `{name: {centre, width, height, u_dir, v_dir, normal}}`, model frame) with a spot's `screen` (default: the spot's own name) puts the display on a quad of exactly that size and tilt; a spot's `item` names the panel item it shows (the first officer's PFD shows `pfd`).
- `cockpit`: `eye` (model frame), `panel_mesh` (the panel's mesh node, so gauge quads clear its bezels) and `spots`, `{item: {pos, size, round}}`, where on the interior glb each panel item is shown (`pos` model frame, `size` = face width in m). Without an interior glb, or without spots, a flat placeholder panel is used.
- `panel.json` (extra keys `size`, `rect`, `span`, `kind` for glass displays: see "Aircraft data: displays"): the instrument panel layout: `cell`, `pad`, `switch_h` (px), `radio_w` (cells), `cols`, `rows`, `gauges` (`{name: {script, cell: [col, row], meta}}`, scripts in `ui/gauges/`) and the optional `strip` (`{script, cell, span}`), `switches` and `radios` items. The item names are what `cockpit.spots` and the 2D overlay layouts (`ui/panel_overlay.gd`) refer to.
- `lights`: `nav` (`{pos, side: left|right|tail, color: red|green|white, size, range, omni_off}`), `beacon` and `strobe` (same fields; several allowed), `lamps` (`{switch: landing|taxi, pos, energy, range, angle, beam, tilt}`). Positions are structural metres (x aft, y right, z up).
- `audio`: `engine` and `wind` mappings (volume / pitch against rpm and airspeed; keys and defaults at the top of `common/aircraft_audio.gd`). The wav files come from the `sounds/` folder; a file that is not there is just silent. An aircraft whose `audio` has a `layers` list (the A320 pack; draft in `game/aircraft/a320/audio_section.json`) uses the data-driven layer engine (`common/audio_layers.gd`, pure curve / gate / trigger functions in `common/audio_curves.gd`, schema in that file's header) instead: each layer is `{file, bus, loop, drive, volume, pitch, gain, view, muffle_hz, per_engine, gate, trigger}`; `drive` is a Props key (`engines/{n}/n1`) or `[op, ...]`, `volume` / `pitch` are `[[x, y], ...]` tables, `per_engine` makes one copy per engine panned left / right, `gate` conditions (view, ground, props, min / max, in-transit `between`, `moving`) and `trigger` edges (rising / falling / change) fire one-shots; the cockpit view low-passes layers with `muffle_hz` and applies the `view.cockpit` factor. `file` may be a `res://` path to reuse another aircraft's sound. Sources of the A320 files: `game/aircraft/a320/sounds/SOURCES.md`, rebuilt and audited by `tools/25_a320_sounds.py` (`--fetch`, `--build`, default audit).

### Aircraft data: displays

Glass-cockpit aircraft (the A320-family one) draw their screens in code from Props, through the same panel pipeline as the steam gauges (SubViewport, 3D quads, click forwarding).

**panel.json schema** (all new keys are optional; the C172 file uses none of them and its rects are unchanged, asserted in `tests/test_displays.gd`):
- `size [w, h]`: natural size in px; without it the grid size is used, enlarged to hold every `rect`.
- Any item (`gauges[name]`, `strip`, `radios`, `switches`): `rect [x, y, w, h]` in px instead of `cell`; `span [cols, rows]` of grid cells (gauges; `strip` had it already).
- `gauges[name].kind: "display"`: the script is a full-rect `Display` (`ui/displays/display.gd`) that scales its own drawing (its `design` size) into the rect; otherwise a round `Gauge` as before. Item names (`pfd`, `nd`, `ewd`, `sd`, `fcu`, `mcdu`) are what `cockpit.spots` and the `overlay` layouts refer to; `cockpit.gd` already maps non-square rects.
- Example: `game/aircraft/a320/panel.json`. Preview and screenshots: `godot --path game res://tests/debug_displays.tscn --audio-driver Dummy` (PNGs to `$FREESIM_SHOTS`).

**Displays** (`ui/displays/`, drawn with Godot's default font, no copied code or fonts): `pfd.gd` + `pfd_tapes.gd` (attitude, pitch ladder, speed tape with Vls / Vsw / Vmax and trend, altitude tape and baro, V/S, heading arc, FD bars, ILS, radio altitude, 5-column FMA), `nd.gd` (ARC / ROSE, route, airports, VORs, wind, GS / TAS), `ewd.gd` (N1 / EGT / N2 / FF per engine, thrust limit, FOB, flaps, memo), `sd.gd` + `sd_pages.gd` (ENG, FUEL, WHEEL, F/CTL), `fcu.gd`, `mcdu.gd` (INIT, F-PLN, PERF; a lite unit, TODO list in its header). Clicks: FCU buttons / knobs (left / right half or wheel, right click x10, middle click toggles managed), ND mode and range labels, SD page keys, MCDU keys.

**Props read by the displays** (never the FDM directly): `instruments/pfd/{valid, ias_kt, mach, tas_kt, trend_kt, vls_kt, vsw_kt, vmax_kt, alt_ft, baro_hpa, baro_std, vs_fpm, ra_ft}` (`instruments/airliner_air_data.gd`), `instruments/adirs/{valid, pitch_rad, roll_rad, heading_deg, track_deg, slip}` (`adirs.gd`, failure flags `failures/adr` and `failures/adirs`), `instruments/engines/{count, <n>/{n1_pct, n2_pct, egt_c, ff_kgh, oil_psi, running}}` (`airliner_engines.gd`, from `engines/<n>/{n1, n2 (fractions), egt_k, ff (kg/s), oil_press_pa, running}`), `instruments/nd/{route, near, wind_dir_deg, wind_kt}` (`nd_feed.gd`, needs its `db` set to a NavDatabase), `controls/fcu/*`, `ap/{ap1, ap2, athr, fd, loc, appr, fd_pitch_rad, fd_roll_rad, thrust_limit, n1_target, fma/{thrust, vertical, lateral, approach, misc}}`, `fdm/{flap_lever, flap_deg, slat_deg, gear_pos, groundspeed_mps, position_enu, aileron_deg, elevator_deg, rudder_deg, stabilizer_deg, spoiler_deg, speedbrake}`, `fuel/{total_kg, tank_kg, tank_cap_kg}`, `avionics/{nav1,nav2,gps}/*`, `controls/{autobrake, parking_brake, baro/{hpa, std}}`, `ewd/{memo, warnings}`. Everything has a safe default. The air-data speed markers come from `instruments/airspeeds.gd` (`aircraft.json` `limits.speeds`: `ref_mass_kg, vs1g_kt [[slat+flap deg, kt]], vls_k, vsw_k, vmo_kt, mmo, vfe_kt, vle_kt`, defaults for a 64 t A320-class jet).

**Props written by the displays**: `controls/fcu/{ap1, ap2, athr, loc, appr}` (bool toggles), `controls/fcu/{spd_kt, hdg_deg, alt_ft, vs_fpm}` (pilot units), `controls/fcu/{spd, hdg, vs}_managed`, `controls/nd/{mode, range_nm}`, `sd/page`, `mcdu/{page, scratch, init/*, perf/*}` and, from the F-PLN page, `controls/gps/{target, route_next}`.

---

## 4b. Building and installing release packages (phase P)

**Build** (from the repo root, after the data pipeline):

```bash
tools/package/make_release.sh 0.1.0      # needs Godot export templates (see below); ~4 min
```

Godot export templates (one time):

```bash
mkdir -p ~/.local/share/godot/export_templates && cd ~/.local/share/godot
curl -LO https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz
unzip Godot_v4.7.2-stable_export_templates.tpz -d tpl && mkdir -p export_templates/4.7.2.stable
mv tpl/templates/* export_templates/4.7.2.stable/ && rm -rf tpl *.tpz
```

**Outputs in `build/`:**

| File | Size | For |
|---|---|---|
| `libresim-<v>-linux-x86_64.tar.gz` | ~450 MB | Any 64-bit Linux distro: extract and run `libresim/libresim.sh` |
| `libresim-<v>-x86_64.AppImage` | ~440 MB | Any Linux distro, single file: `chmod +x` and run it |
| `libresim-<v>-macos-universal.zip` | ~480 MB | macOS 11+ (Intel and Apple Silicon): unzip, move `libresim.app` to Applications |
| `libresim-<v>-source.tar.gz` | ~65 MB | GPL corresponding source of that build |

**Flatpak** (wraps the Linux tar.gz):

```bash
flatpak install --user flathub org.freedesktop.Platform//25.08 org.freedesktop.Sdk//25.08 org.flatpak.Builder
flatpak run org.flatpak.Builder --user --install --force-clean build/flatpak packaging/flatpak/org.freesim.FreeSim.yml
flatpak run org.freesim.FreeSim
```

**macOS notes:**
- The build is ad-hoc signed with `rcodesign`, which runs on Linux, but **not notarised**.
- On the first launch, right-click the app → Open. Alternatively, run `xattr -dr com.apple.quarantine /Applications/libresim.app`.
- For public distribution, sign with an Apple Developer ID and notarise. Both `rcodesign` and Xcode can do this, with a paid Apple Developer account.
- The macOS build was produced and checked for structure on Linux (universal binary, data in `Contents/Resources`, valid signature). It hasn't been run on a Mac yet.

**Command-line options** work the same in every package: `./libresim.sh -- --airport=VABB --stand`. The AppImage takes them directly: `libresim.AppImage -- --stand`.

**Read-only installs** (AppImage, Flatpak): the F10 → Renderer toggle can't write `override.cfg`. Start with `--rendering-method forward_plus` instead.

## 5. Aircraft models and 3D scenery

**The aircraft** is the FlightGear c172p model and cockpit (GPL-2.0-or-later, c172p team), converted by the Blender scripts in `tools/blender/`. The original sources are vendored in `third_party/c172p/`. The live libresim gauges are drawn onto the real panel at each instrument's true position. If the `.glb` files are missing, the sim falls back to the box placeholder.

**3D buildings:**
- Built from 578k OSM footprints, with heights from OSM tags or a synthetic estimate by footprint size.
- **Geometry** (`tools/building_geom.py`, written by `10_buildings.py` as BLD2): flat roofs of footprints of 90 m² and more get a sloped parapet strip; small 4-corner footprints (under 150 m², up to 7.5 m) get a hip roof (30 % of them in the Mumbai-Pune grid, 75 % in the Konkan-Kerala corridor, where tiled roofs are common); big flat roofs get a stairwell box (from 250 m²) and a hexagonal water tank (from 400 m²). A BLD2 vertex carries the wall height (cm, 16 bit), a parapet / rooftop-kind byte and the height fraction, besides the roof colour and a style byte (`pid << 2 | roof type`). That is about 1.6x the vertices of the old two-ring layout (the dense Juhu tile: 364k to 595k). `Buildings` still reads old BLD1 tiles (the shader then falls back to world height).
- **Shader** (`world/building.gdshader`): a hash of the building seeds the wall colour (whitewash, cream, ochre, grey concrete, pastel blue / green / pink, weathered brown, terracotta), window width and rhythm, floors laid out from the ground (3.1 m, plain parapet wall above the last), slab edges with a shadow line, sills, a recess under the lintel, balconies on some apartment blocks, shopfronts with shutters and signboards on the ground floor of medium buildings, glass curtain-wall towers above 32 m (spandrels, mullions, sky tint, a little gloss), dirt toward the ground, soot under the roof edge and rain streaks. Roofs: bare concrete, white coating, brick, tarpaulin or the satellite colour with stains; courses of tiles on hip roofs; a light parapet cap with a shadow line inside it; concrete boxes and black plastic tanks. Pattern detail fades to the building's average colour with distance (no shimmer). Windows (and shop fronts, and glass towers) light up at night as before; haze is the terrain's. Buildings cast and receive the cascaded sun shadows.
- Streamed within 9 km and hidden above 2500 ft AGL. Showcase scene `city_district` (VAJJ, three cameras: overview, 35 m, street level).

**Water:**
- The Arabian Sea, creeks, rivers and lakes (from the elevation data and OSM water polygons) use an animated water surface.
- It has wind waves, sun glints and a Fresnel sky reflection, and keeps the satellite tint in shallow creeks.

**Clouds:**
- A raymarched volumetric cumulus layer at the configured base and cover.
- It reads the scene depth, so you can fly under it, through it (fog inside) and above it, looking down on the tops.
- It drifts with the wind aloft and is lit by the sun, with darker bases and warm tints at sunset.

**Graphics presets** (F10 or `--quality=`):

| Preset | FPS on a Radeon 780M | Render scale | Shadows | Buildings / trees range | Cloud steps |
|---|---|---|---|---|---|
| Low | ~69 | 70 % + FSR | off | 4 km / 1.2 km | 10 |
| Medium | ~62 | 85 % + FSR | 700 m, 2 cascades | 6 km / 1.8 km | 16 |
| High | ~51 | 100 % + MSAA 2× | 1.8 km, 4 cascades | 9 km / 2.2 km | 24 |
| Ultra | ~45 | 100 % + MSAA 4× | 4 km, 4 cascades | 12 km / 3 km (LOD0 tree meshes: 150 m; High 120, Medium 90, Low none) | 40 |

With the Forward+ renderer (F10 → Renderer, then restart; or launch with `--rendering-method forward_plus`), Ultra also enables SSAO and TAA. Mobile is the default renderer and the fastest on integrated GPUs. The FPS figures were measured before the cascaded shadows (sun shadows now reach 0.7 / 1.8 / 4 km instead of 150 / 300 / 600 m) and have not been re-measured.

**Ground detail and sun glare** (quick wins towards a more photographic look): `world/terrain.gdshader` adds tonal variation at field and hill scale with distance, and fine grain plus a soft micro-relief normal within about a kilometre, over the 10 m satellite imagery (water is left alone). `world/sun_glare.gd` / `sun_glare.gdshader` draw a veil, a faint starburst and lens ghosts when the sun is in view (not on Low); terrain, the cockpit frame and clouds cut it off because it samples the depth buffer, and looking towards the sun lowers the exposure by up to 20 % (`SkyTime._update_glare`). Filmic tone mapping was kept: AgX and ACES were tried on the same scenes and were not clearly better (AgX greyer, ACES a darker cockpit). New showcase scene `low_ground` (VAPO, 450 ft, low sun) shows the terrain detail.

**Roads, rivers and shores** (`tools/20_roads_rivers.py`, `tools/21_shore.py`): the 10-20 m imagery smears roads and creeks, so OSM lines are rasterised into 4 m signed-distance tiles (`terrain/ro/0/`, see the pipeline list) that `world/terrain.gdshader` draws crisply: asphalt with polished tyre tracks and white edge / yellow centre lines on primary to tertiary roads and lane lines on motorways and trunks (within ~600 m), plain grey minor roads, tan tracks with ruts, rivers / canals / streams as thin water ribbons with the water look and a wet bank. Everything fades out by ~3.3 km and nothing is drawn over runways, aprons or water (bridges stay). Only the few level-0 tiles within 3.6 km of the camera are resident (`world/terrain_roads.gd`, bound per node by `terrain_quadtree.gd`), and nodes further away skip the extra texture sample. Narrow roads are drawn at least ~4.4 m wide (a 4 m lattice cannot hold less); centre lines are solid, not dashed (a dash phase would need the arc length along the road). Water uses the shore tiles (`terrain/sd/`): shoals fade from turquoise (mixed with the imagery) to the deep grey-blue over ~100 m, soft swash lines and animated wave fronts run towards open coasts (none on rivers, ponds and sheltered water), and sheltered water gets smaller waves. Not done: mud near river mouths, bathymetry (the DEM is flat at sea level), road dashes, bridges as geometry. Showcase scenes `coast_juhu`, `coast_juhu_low`, `coast_kochi`, `roads_low`; tests in `tests/test_roads.gd`. OSM and WorldCover credits already cover the data.

More in the same spirit: **cloud shadows** (`CloudLayer._publish_shadow` publishes the cloud coverage noise, wind phase, sun direction and strength as global shader parameters; `terrain.gdshader` darkens ground whose sun ray crosses a cloud, so shadows drift with the wind and vanish under a thick deck, in clear air and at night), a **cirrus layer** in the sky shader (`sky_clouds.gdshader`, drifting with the wind aloft, thinner under cloud, warm at sunset), **forest floor** (dense tree cover from the land class darkens and greens the imagery under the canopy), crowns of the tree billboards that are darker underneath, and a **Fresnel cockpit glass** (`aircraft/c172/glass.gdshader`: clear head-on, reflecting the sky at grazing angles). Showcase scenes `chase_close` and `cloud_shadows` look at the glass and the cloud shadows. **Aircraft reflection probe** (`aircraft/c172/reflection_rig.gd`, rules in `reflection_policy.gd`): a ReflectionProbe above the aircraft captures the real surroundings (terrain, horizon, haze, volumetric clouds) so glass and paint reflect more than the sky radiance (Low: off). The airframe, interior and lights are on layers the capture does not draw, and only the airframe layer is reflected on (the cockpit interior is not touched). Box projection is off (far scenery has no parallax), so one cubemap serves a 1.2 km box and the probe stays put between captures. It is re-captured only when the picture changed: sun elevation +-2 deg, 300 m of travel, 150 m of altitude, cloud cover / base, rain or visibility, a graphics-preset change, a second capture 5 s after a start (terrain still streaming at the first), plus a periodic one (Medium 30 s, High 12 s, Ultra 5 s; never more often than every 2 s). Medium / High / Ultra differ in that period and in how far the capture sees (2.5 / 4 / 6 km). The capture resolution is the engine's mobile default (128, `rendering/reflections/reflection_atlas/reflection_size.mobile`); a per-preset resolution is not possible at run time (`reflection_probe_set_resolution` has no effect, the atlas is sized from the project setting). The effect is modest: close views show terrain in the glass and a little more light on paint and cowling, golden hour warms the cowling. The land-cover splat (ESA WorldCover) is done.

**Sky pass** (clouds, banding, atmosphere, exposure):
- **Cloud edges:** the grain along cloud edges was aliasing: the march took one point sample per step (up to hundreds of metres apart at grazing angles) on 6 m noise texels, with a white-noise start offset. `volumetric_clouds.gdshader` now samples the noise at the mip that matches the step length, offsets the start per pixel with interleaved gradient noise, and averages each 2x2 pixel quad (fine derivatives, on premultiplied colour, so empty pixels do not darken the edge). Same step count; the clouds are smoother and a little softer than before. Showcase scenes `cloud_inside` and `cloud_tops` check the compositing.
- **Banding:** dark sky gradients showed concentric 8-bit bands. Debanding is on (`project.godot`, `Viewport.use_debanding` in `Graphics.apply_to_scene`) and the sky shader adds about 4 % dither noise.
- **Atmosphere:** `world/atmosphere.gd` is a single-scattering Rayleigh + Mie + ozone sky on a spherical planet (8 view samples x 4 sun samples, exponential density), with a twin in `sky_clouds.gdshader` (`atmo_sky`; keep them in step). The sky shader shows it as the deviation from its own gradient, so overcast, night, rain flashes and the city glow still come from `SkyTime` unchanged and a clear day is exactly the model: deep blue zenith, pale horizon, orange-red band towards a low sun, purple twilight. After sunset the model keeps the sun on the horizon and fades (`Atmosphere.twilight_gain`). Aerosol follows the visibility. `SkyTime` samples the model for the fog / haze colour (horizon in the camera's heading, at least 35 deg of azimuth away from the sun, luminance capped) so terrain, trees and buildings fade into the sky's colour at every hour, and for the colour of the sun itself (`Atmosphere.sun_color`: white high up, orange at 8 deg, red-orange at the horizon). The sky costs about 45 exponentials per sky pixel (not in the ambient cubemap pass). New showcase scenes `sky_sunrise`, `sky_noon`, `sky_twilight`.
- **Auto exposure:** `world/auto_exposure.gd`. Godot's `CameraAttributes` auto exposure is Forward+ only (tested: a warning on Mobile and no effect), so it is a CPU estimate: sunlit or shaded ground (cloud shade from the CPU cloud density along the sun ray), sky and camera pitch give a luminance, a gentle power law (0.3, clamped 0.8 to 1.5, at most 1.2 at night) a multiplier, smoothed with an eye-like time constant (2.4 s towards a darker scene, 0.9 s towards a brighter one). It multiplies the exposure `NightSky` sets and sits before the sun-glare pull, published as `environment/exposure_mult`. Off on Low (`ae` in the preset table). Showcase scenes `exp_noon`, `exp_shade`, `exp_night` (same cockpit view). Cirrus is much dimmer at night.

**Trees:**
- Forests are placed from the satellite vegetation index, excluding buildings, roads, runways and water.
- They're generated deterministically within the preset's range (1.2 to 3 km) of the aircraft, in streamed chunks.
- **Species** (`world/tree_species.gd`, one rule shared by the drawing, the LOD0 meshes and the collisions, so what you see is what you hit): broadleaf (mango, neem, banyan), coconut palm, umbrella acacia and slim casuarina / eucalyptus. Coconut palms follow region and elevation (a tenth in the Mumbai lowlands, up to 40 % on the Konkan coast, 45 % in Kerala, almost none above 160 m); acacias are common on the dry plateau above 400 m; slim trees stay near the sea. Palms have a thinner collision disc than the other trees.
- **Impostors** (`world/tree_atlas.gd` + `tree_atlas.gdshader`): at startup two SubViewports draw a procedural atlas once (4 species x 4 variants of 128x256 px: crown lumps with ragged outlines and leaf mottling, trunks, palm fronds as combs along drooping curves; albedo with baked occlusion, and a normal), which is copied to mipmapped textures. `tree.gdshader` lights the sprite normal with the sun and sky (lit and shade side, backlit leaves), tints foliage per tree, and edges are soft with alpha to coverage (MSAA). Headless runs skip the baking.
- **LOD0** (`world/tree_lod.gd`, `tree_meshes.gd`, `tree_mesh.gdshader`): within the preset's LOD radius (Ultra 150 m, High 120, Medium 90, Low none) of the camera, trees are real low-poly meshes built in code (a tapered trunk, 5 to 7 icosphere crown lumps of 80 triangles, or palm fronds; 300 to 600 triangles per tree), in 80 m cells made one per frame, instanced per species. Each crown is displaced by noise per tree, with leaf-gap silhouettes, and they cast and receive sun shadows. The impostor dithers away over 8 m where the mesh dithers in (`TreeLod.covered` tells the impostors how far the meshes really reach). Off when the camera is above 450 m AGL.
- Hidden above 1500 m AGL. Showcase scenes `trees_close` (VAAV, three cameras), `konkan_palms` (VOCI) and `city_district`. Typical counts at Ultra: Kochi 149k impostors and about 1270 LOD0 meshes; the Aamby valley 216k impostors and 900 meshes. `tests/test_trees_buildings.gd` covers species mix, determinism, mesh size, the atlas, the shader uniforms, the BLD1 / BLD2 loader and the night uniform.

### Replacing the models with your own Blender models

To use your own models instead of the converted FlightGear ones:

1. Model in Blender in metres, with **−Z forward, +Y up, origin at the C172's CG**. The CG is about 1.0 m aft of the JSBSim datum; see `mass.empty_cg_m` in `config.json`. Export glTF (`.glb`) to `game/aircraft/c172/exterior.glb` and `cockpit.glb`.
2. Name animated parts `elevator`, `rudder`, `aileron_L`, `aileron_R`, `flap_L`, `flap_R` and `prop`, with pivots on their hinge lines.
3. In the cockpit model, leave a flat panel face with UVs covering 0–1. Assign it a material whose albedo is the panel SubViewport texture (see `Cockpit.build`), so the existing gauges and clickable knobs keep working.
4. Put the `.glb` files in `models/` of the aircraft folder; `AircraftModel` uses them when present (see "Aircraft data: model, cockpit, lights, audio"), else a generic placeholder airframe sized from `config.json`.

The FlightGear c172p model (GPL) is fine as a private, local stand-in while you build your own, but don't redistribute it.

---

## 5b. FlightGear assets and licences

See `docs/FLIGHTGEAR_NOTES.md`. In short, the FlightGear c172p model and cockpit (GPL-2.0-or-later) can be converted with the Blender AC3D add-on and used locally. Distributing them requires GPL compliance; the details and credit text are in `CREDITS.md`. The satellite imagery is CC BY-NC-SA, which means non-commercial use only.

---

## 6. Project layout

```
tools/        offline Python pipeline (section 3); common.py holds region/grid constants
data/raw      downloaded sources (gitignored)
data/processed generated tiles/JSON (gitignored)
game/         Godot project
  core/       floating_origin + props (autoloads), geo (lat/lon <-> ENU), units, paths
  world/      flight scene (main), weather, sky_time, clouds, runway_lights, terrain quadtree/cache/shader, airport_builder + runway shader, terrain_viewer scene
  input/      free_camera, keyboard_controls
  fdm/        flight model: aero (JSBSim tables), engine, propeller, gear, atmosphere (M3)
  tests/      headless test runner + suites
  ui/         hud, camera_rig, perf_overlay, instrument_panel + gauges/, panel_overlay
  systems/    pitot_static, vacuum, electrical, fuel
  instruments/ air-data, gyro, compass, engine gauge models (publish instruments/* props)
  aircraft/<id>/ one aircraft: aircraft.json, config.json + aero.json (from JSBSim; edit to tune), panel.json, models/, sounds/
  aircraft/common/ code shared by all aircraft (cockpit, lights, audio, reflections); aircraft_def.gd reads an aircraft folder
docs/USAGE.md this file
```

---

## 7. Troubleshooting

| Symptom | Fix |
|---|---|
| `godot: command not found` | Use `~/.local/bin/godot` or add `~/.local/bin` to PATH (section 1) |
| `missing data file: .../terrain/meta.json` | Run the pipeline (section 3) |
| Terrain is a flat green-grey colour | Imagery tiles are missing: run `01b_fetch_imagery.sh`, then `03_imagery_tiles.py` |
| `01b_fetch_imagery.sh` fails partway with HTTP errors | Re-run it; GDAL retries each tile 5 times. The EOX server sometimes rate-limits |
| Low FPS | Check the F3 overlay. Lower `lod_k` on the Terrain node in `world/flight.tscn` (default 1.6), or turn off `shadow_enabled` on the Sun |
| Stutter / where does the frame time go? | `godot --path game res://tests/debug_perf.tscn -- --airport=VABB --runway=27 --air=1000 --quality=high --log=/tmp/f.csv --dur=60` logs every frame (GPU, physics, pipeline compiles, per-node `_process` time) and prints the worst frames and top consumers |
| Jump at the 5 km origin shift? | `res://tests/debug_origin.tscn -- --airport=VABB --runway=27 --air=1500 --dur=150` prints the largest per-frame world-space move of the camera, aircraft and static scenery, split into normal and shift frames (static must be 0) |
| Does a stand look right? (markings, jetbridge, heading) | `godot --path game res://tests/debug_stand.tscn -- --airport=VOCI --stand=B7 --tod=12 --weather=clear --shots=/tmp/s` saves `stand_chase`, `stand_orbit` and `stand_overview` PNGs there (needs a display); `--cam=e,n,height_agl,yaw_deg,pitch_deg` puts the free camera anywhere instead (e.g. with `--runway=09` at a taxiway junction) and saves `cam.png` |
| Flicker / scenery check at a fixed spot | `res://tests/debug_view.tscn -- --eye=e,n,alt --at=e,n,alt --wait=12 --out=/tmp/v.png` (free camera, world metres); add `--to=e,n,alt --frames=N` to save a fly-through frame by frame. `debug_perf.tscn ... --burst=/dir@20x10 --freeze` saves 10 frames with sim time stopped (any change = instability) |
| Does a crash register? (trees, buildings, terminals, jetways, vehicles) | `godot --headless --path game res://tests/obstacle_probe.tscn -- --only=mirror,forest,city,taxi,airport,corridor,fast,scan,ops` flies and taxis scripted runs in the real loaded world (needs `data/processed`) and prints one `ROW` per case; `--only=scan --icao=VABB [--rules]` puts the aircraft at every stand, pushback path, taxiway and runway and reports overlaps with a solid (`--rules`: after the forgiveness rules; normal ops must give 0); `--only=ops` takes off from and lands on 10 runways; `--only=perf` times the collision check |
| Aircraft spawns in the wrong place / no runway | Run `tools/09_runways.py` (it writes `data/processed/runways.json`) |
| No sound | Godot uses PulseAudio/PipeWire; check the system output device |
