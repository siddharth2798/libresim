# What `./run.sh` does

`./run.sh` is the one-shot setup and launch script. It is idempotent: every step runs only when it is needed, so the first run takes hours and later runs start the game in seconds. Option list: `./run.sh --help`. General usage: [USAGE.md](USAGE.md) section 1.

```
./run.sh [options] [--] [game args...]     e.g. ./run.sh --airport=VABB --stand
```

Options not listed below (and everything after `--`) go to the game.

| Option | Effect |
|---|---|
| `--setup-only` | do everything except launch the game |
| `--skip-data` | skip downloads and the pipeline; launch even if data is incomplete |
| `--region=mumbai_pune\|all` | default `all` also fetches the Konkan-Kerala corridor |
| `--a320` | also fetch the FlightGear A320-family data and regenerate `game/aircraft/a320/{aero,config}.json` (step 06a) |
| `--force-step=NN` | re-run pipeline step NN (repeatable) |
| `--dry-run` | print the plan and what would run or be skipped, and why; change nothing |
| `--yes`, `-y` | answer yes to every prompt |

## Before step 1

- **bash:** macOS ships bash 3.2; the script needs bash 4+ (associative arrays). It re-executes itself under Homebrew's bash (`/opt/homebrew/bin/bash` or `/usr/local/bin/bash`), or tells you to `brew install bash`.
- It changes into the repo root and starts logging: all output is also appended to `data/run.log`. A failure prints the step it was in and the log path.

## The 8 steps

1. **System tools and Godot.** Checks for python3, `gdalwarp`, the GDAL Python bindings, venv/ensurepip, curl or wget, git and unzip. Missing packages are found for apt, dnf, pacman or Homebrew; the install command is printed and run (with `sudo` where the manager needs it) only after you say yes. Then looks for Godot 4.7.2 at `~/.local/bin/godot` or on `PATH`; if missing it offers to download it into `~/.local/share/godot` and symlink it. On macOS, Homebrew auto-update is switched off for the run.
2. **Plan.** Prints the raw data still to download (size of each file, total in GB), the pipeline steps that will run with the reason and the usual time (from `data/run.log`, else a built-in table). Asks `Continue? [y/N]` when there is real work. With nothing stale it says "Everything is up to date".
3. **Python venv (`tools/.venv`).** Creates it (with system site-packages, for GDAL) and pip-installs whatever is not importable: osmium, jsbsim, mapbox_earcut, shapely, matplotlib, pillow, numpy.
4. **Raw data (`data/raw`).** Downloads what is missing: Copernicus DEM 30 m and 90 m tiles, the Geofabrik western-zone OSM extract, OurAirports CSVs, the JSBSim aircraft data, Sentinel-2 imagery (inner and outer), the corridor pack (`--region=all`), and the A320 data (`--a320`).
5. **Data pipeline (`tools/NN_*.py`).** Runs the stale steps in this order: `05 28 04 02 03 06 09 11 12 19 13 15 17 20 21 09 27 14 16 10` (airports and navaids, airways, OSM, terrain heights, imagery, c172 model json, runways, land class, outer ring, WorldCover, stands, terminals, airport fixups, roads and rivers, shore, runways again, pavement, ILS, terminal models, buildings). Each step is described in the next section.
6. **Godot first-run import.** Runs `godot --headless --path game --import` once, when `game/.godot/imported` does not exist.
7. **Summary.** Warns if `terrain/meta.json`, `runways.json` or `airports.json` is missing, and prints disk use and total time.
8. **Launch.** On macOS exports `SDL_JOYSTICK_MFI=0` and `SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1` (joystick detection, see USAGE.md). Registers the applications-menu entry via `launch.sh --register-only`, then `exec`s `godot --path game -- <game args>`. It refuses to launch if the data is incomplete (unless `--skip-data`).

## The pipeline steps, one by one

Run order (`PIPELINE` in `run.sh`): `05 28 04 02 03 06 09 11 12 19 13 15 17 20 21 09 27 14 16 10`. "Needs" lists the upstream steps that re-trigger a step when they run (`DEP` in `run.sh`). Ground tiles are indexed by level L (0 = finest) and tile x/y in the local ENU world frame.

| Step | Script | What it does | Writes (under `data/processed/` unless noted) | Needs / notes |
|---|---|---|---|---|
| 05 | `05_airports_navaids.py` | Reads the OurAirports CSVs for the Mumbai-Pune box and the Konkan-Kerala corridor; converts to world metres plus lat/lon. | `airports.json`, `navaids.json` | none |
| 28 | `28_airways.py` | Reads ATS routes from the AAI eAIP HTML pages (designator, ordered points, coordinates) for routes crossing the regions. Not for navigation. | `airways.json` | network the first time (cached in `data/raw/aai`) |
| 04 | `04_osm_extract.py` | One pass over the OSM extracts: runways and taxiways, aprons, major roads, water polygons, building footprints per level-0 tile. Corridor building density follows `building_density.py`. | `osm/aeroways.json`, `osm/roads.json`, `osm/water.json`, `osm/buildings/` | raw OSM pbf |
| 02 | `02_dem_tiles.py` | Copernicus DEM to world-frame heightmap tiles (16-bit), flattening runways and aprons. Corridor tiles come from their own packs. | `terrain/meta.json`, `terrain/h/<L>/` | 04, 05 |
| 03 | `03_imagery_tiles.py` | Sentinel-2 mosaic to BC1/DXT1 DDS imagery tiles with mip chains, same tiling as the heights. Corridor tiles use the 20 m mosaic, flat sea/land colour where there is no imagery. | `terrain/img/<L>/` | 02 |
| 06 | `06_jsbsim_to_json.py` | Converts JSBSim aircraft, engine and propeller XML into the game's aero expression trees and config. Outputs are committed, so this runs only if they are missing. | `game/aircraft/c172/{aero,config}.json` | none (06a does the A320 with `--a320`) |
| 09 | `09_runways.py` | Merges OSM runways and taxiways into start positions and render geometry; heights are sampled from the flattened DEM. | `runways.json` | 02, 04, 05, 17. Runs twice: once early, once after 17 so heights match the levelled ground |
| 11 | `11_landclass.py` | Land-class mask per imagery tile: water (sea or OSM water), tree density from a vegetation index (minus buildings, roads, aeroways), other. Higher levels are downsampled. | `terrain/lc/<L>/` | 02, 03, 04 |
| 12 | `12_outer.py` | The outer ring: coarse heights (GLO-90/30 warped at 240 m, gaps filled), imagery and land class for levels 3-6, so the world never ends abruptly (reaches Kochi). Overwrites the clamped levels from 02/03/11. | `terrain/h/6`, `img/6`, `lc/6` (levels 3-6), extends `meta.json` | 02, 03, 11 |
| 19 | `19_worldcover.py` | ESA WorldCover 2021 (10 m, 11 classes) windowed reads into per-tile class masks for the per-class ground shader. | `terrain/wc/` (raw in `data/raw/worldcover/`) | 11, 12; network the first time |
| 13 | `13_airport_ops.py` | OSM airport ground infrastructure per airport (nearest OurAirports airport within 6 km): stands (gate or remote, jetbridge flag, heading), with `stand_aim.py` repositioning stands whose left door no bridge could reach. | `airport_ops.json` | 04, 05 |
| 15 | `15_terminals.py` | Passenger terminal complexes per airport: terminal areas, parts and canopies, jet bridges, car parks, elevated roads. | `terminals/<ICAO>.json` | 04, 05 |
| 17 | `17_airport_fixups.py` | Edits the terrain tiles (levels 0-2) in place: levels the cut-and-fill airports (VANM, VOKN, VOSR), makes ground follow taxiway profiles, apron and stand ground, no water or trees on airfields. | `terrain/fixups.json` (tiles patched in place) | 02, 04, 05, 11, 12, 13, 15. Must run after 02/11/12; 09 is not a dependency because it re-runs after |
| 20 | `20_roads_rivers.py` | OSM roads and waterways rasterised as 4 m signed-distance tiles (plus ribbon class) so thin roads and rivers stay crisp in the shader. Roads never cross water. | `terrain/ro/0/` (cache `osm/ways.npz`, first pass about 5 min) | 04, 11, 17 |
| 21 | `21_shore.py` | Shore distance and "openness" of water per land-class tile, for foam, depth colour and calm backwaters. | `terrain/sd/<L>/` | 11, 12, 17 |
| 09 | (second run) | Runways again, now with the levelled airport ground. | `runways.json` | see above |
| 27 | `27_pavement.py` | Airport pavement masks: aprons, stands, runway and taxiway shoulders as 4 m RGBA tiles (concrete or asphalt, tyre marks, oil stains). There is no apron mesh. | `terrain/pv/0/` | 04, 09, 13, 17. Always rebuilt (`--force`), about 1.5 min |
| 14 | `14_ils.py` | Generates a simulated ILS (localizer and 3 deg glideslope) for the long runways. Idents and frequencies are made up, flagged `"simulated": true`. | `ils.json` | 09 |
| 16 | `16_terminal_models.py` | Landmark terminal 3D models from the footprints plus per-airport recipes (`terminal_styles.py`), seated on the levelled ground. Lists their footprints so 10 skips those buildings. | `terminals/<ICAO>.glb`, `<ICAO>_model.json`, `terminals/landmarks.json` | 15, 17 |
| 10 | `10_buildings.py` | Extrudes OSM building footprints into per-tile meshes with roof colours from the imagery, heights from the DEM, leaving out the landmark terminals. | `buildings/<tx>_<ty>.bin` | 02, 04, 16, 17. Slowest step, about 20 min |

Ordering in one line: 17 patches what 02, 11 and 12 wrote, so it follows them (and 13 and 15); 20, 21 and 27 read the final water mask or stands, so follow 17; 16 needs 17's base heights; 10 goes last because it needs the landmark list from 16.

## When does a pipeline step re-run?

A step is stale when any of these hold (logic in `tools/run_stale.sh`):

- an output is missing (its stamp, `data/.stamps/<step>.done`, is the sentinel);
- an upstream step it depends on ran this session, or is newer than its stamp;
- an input changed. Python scripts are compared by **code hash** (`tools/code_hash.py`, recorded in `data/.stamps/<step>.hashes`), so editing a comment, docstring or formatting rebuilds nothing. Raw data and json inputs are compared by file time;
- you passed `--force-step=NN`.

Stamps from before the hash records are migrated without rebuilding. Step 27 (pavement) always rebuilds (about 1.5 min).

## Files involved

| File | Role |
|---|---|
| `run.sh` | the script; pipeline table (`OUT`, `IN`, `DEP`) and step functions |
| `tools/run_stale.sh` | staleness decisions and hash records |
| `tools/run_raw.sh` | raw download list, sizes and fetch |
| `tools/run_progress.sh` | plan printing, progress lines, 15 s heartbeat (`RUN_HEARTBEAT=secs`) |
| `launch.sh` | double-click launcher: starts the game if ready, else opens a terminal running `./run.sh` |
| `tools/test_run_sh.sh` | tests all of the above in a scratch copy |
| `data/run.log`, `data/.stamps/` | log; per-step stamps and hashes |

`RUN_OFFLINE=1` uses the built-in size estimates instead of asking servers.
