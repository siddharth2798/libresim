# free-sim: setup, running and usage

This guide covers how to install, build the map data, and run free-sim, a local Cessna 172 flight simulator for the Mumbai–Pune region. Design and roadmap are in `PLAN.md`; the coding conventions are in `CLAUDE.md`.

> **Current state:** M1 (data pipeline) and M2 (terrain viewer) are complete: you can fly a free camera over the real Mumbai–Pune terrain with satellite imagery (~350 FPS on the Radeon 780M). M3 (flight model), M4 (first flight), M5 (cockpit & instruments, code side) and M6 (systems, weather, time of day, night lighting) are complete: you can take off from Juhu, Mumbai, Pune or Navi Mumbai and fly the C172 over the whole region on a working steam-gauge panel. The 3D aircraft and cockpit are still placeholder geometry until a Blender model replaces them (see section 5). Each section below says which milestone it belongs to.

---

## 1. Requirements (Pop!_OS / Ubuntu 24.04)

| What | How | Notes |
|---|---|---|
| GDAL + Python bindings | `sudo apt install gdal-bin python3-gdal` | already installed on this machine (GDAL 3.8) |
| QGIS (optional) | `sudo apt install qgis` | only for inspecting data |
| Godot 4.7.2 (standard build) | already installed at `~/.local/share/godot/`, with a symlink at `~/.local/bin/godot` | see below |
| Python venv | `python3 -m venv --system-site-packages tools/.venv && tools/.venv/bin/pip install osmium jsbsim mapbox_earcut` | `--system-site-packages` lets it use the apt GDAL bindings |
| Blender 4.x + AC3D add-on | `sudo apt install blender`; add-on: download https://github.com/NikolaiVChr/Blender-AC3D (branch `4.0`) into `data/raw/fg/addon/` | only to regenerate the aircraft models |
| Disk | ~1.5 GB raw data + ~0.4 GB processed | |

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
```

---

## 3. Building the game data (M1)

Run from the repo root, **in this order** (later steps read earlier outputs):

```bash
PY=tools/.venv/bin/python
$PY tools/05_airports_navaids.py   # -> data/processed/airports.json, navaids.json
$PY tools/04_osm_extract.py        # -> data/processed/osm/ (runways, roads, water, buildings) ~1 min
$PY tools/02_dem_tiles.py          # -> data/processed/terrain/h/  (heightmaps, runways flattened)
$PY tools/03_imagery_tiles.py      # -> data/processed/terrain/img/ BC1 .dds tiles (needs s2.tif) ~15 s
$PY tools/06_jsbsim_to_json.py     # -> game/aircraft/c172/c172_aero.json, c172_config.json (committed)
$PY tools/09_runways.py            # -> data/processed/runways.json (merged runways + taxiways; after 02 & 04)
$PY tools/10_buildings.py          # -> data/processed/buildings/ 3D building meshes (after 02, 03 source s2.tif, 04) ~15 s, 63 MB
$PY tools/11_landclass.py          # -> data/processed/terrain/lc/ land-class masks: water + tree density (after 02-04) ~30 s

# Aircraft 3D models (FlightGear c172p, GPL), already committed as .glb; only needed to regenerate:
blender -b --factory-startup --python tools/blender/convert_c172p.py            # exterior.glb
blender -b --factory-startup --python tools/blender/convert_c172p_interior.py   # interior.glb
$PY tools/07_preview.py 1          # -> data/processed/preview_L1.png  (sanity check)
$PY tools/08_jsbsim_reference.py   # optional: standalone JSBSim climb numbers for comparison
```

Notes:
- **World frame:** a local Transverse Mercator centred at 18.75N 73.40E, so map metres are game ENU metres (x east, y north). Key positions: Juhu ≈ (-59540, 38628), VABB ≈ (-55997, 37576), VAPO ≈ (54856, -18505).
- `07_preview.py <level> x0 y0 x1 y1` zooms into a box, e.g. `07_preview.py 0 -62000 35000 -52000 41000` shows the Mumbai airports.
- To change the region or tile layout, edit `tools/common.py` and re-run steps 02–03. Re-run 03 after deleting `data/processed/terrain/img/`, because it skips tiles that already exist.
- Delete `data/processed/` at any time; it is fully regenerated by the scripts.

---

## 4. Running the simulator

```bash
cd game
~/.local/bin/godot --path .          # run the main scene
~/.local/bin/godot -e --path .       # open the Godot editor
```

On first run, Godot imports the project (a few seconds). The data is read from `../data/processed` relative to the project, so build it first (section 3).

### Flying (M4): the main scene

```bash
cd game
~/.local/bin/godot --path .                                   # Juhu (VAJJ), longest runway, engine idling
~/.local/bin/godot --path . -- --airport=VABB --runway=27     # Mumbai runway 27
~/.local/bin/godot --path . -- --airport=VAPO --air=2000      # airborne, 5 nm final to Pune at 2000 ft AGL
~/.local/bin/godot --path . -- --airport=VANM                 # Navi Mumbai
```

| Option (after `--`) | Meaning |
|---|---|
| `--airport=ICAO` | VAJJ (default), VABB, VAPO, VANM, VAAV (Aamby Valley), … any airport in `runways.json` |
| `--runway=NN` | runway end, e.g. `08`, `26`, `14`, `32`; default = the longest runway |
| `--air[=ft]` | start airborne on a 5 nm final at that height above the field (default 1500) |
| `--view=NAME` | initial camera: cockpit, chase, orbit, free, tower, wing, tail or flyby (default chase) |
| `--quality=low\|medium\|high\|ultra` | graphics preset (otherwise the one saved from F10) |
| `--tod=h` | local time (IST), e.g. `--tod=6.5` sunrise, `--tod=18.6` sunset, `--tod=21` night |
| `--wind=DDD/SS[GNN]` | surface wind, e.g. `--wind=270/15G25` (wind aloft is set a bit stronger and veered) |
| `--vis=m` | visibility in metres |
| `--clouds=C@ft` | cloud cover 0–1 at a base in ft AMSL, e.g. `--clouds=0.6@3500` |
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
| M | Cycle magnetos OFF → L → R → BOTH |
| S (hold) | Starter |
| Y | Toggle mouse yoke (mouse position = control column) |
| C / Shift+C, or 1–8 | Camera: 1 cockpit, 2 chase, 3 orbit, 4 free camera (WASD to move, Q/E down/up, right-drag to look, Shift for speed, wheel to set speed), 5 tower, 6 wing, 7 tail, 8 fly-by |
| Tab / Shift+Tab | 2D panel layout in outside views: Full, Split (six-pack bottom-left, engine gauges right), Compact (small six-pack), Minimal (ASI, AI, ALT top-right), Off. Remembered between sessions |
| Right-mouse drag | Look around (cockpit, orbit, free, wing, tail). Mouse wheel: cockpit zoom (field of view), orbit distance, free-camera speed |
| V | Re-centre the view |
| H / F1 / F3 | Toggle HUD / key help / performance overlay |
| F12 | Credits and licences |
| F10 | Settings: graphics preset and renderer, time of day and time rate, wind and gusts, wind aloft, turbulence, visibility, clouds, QNH, temperature, failures |
| Esc | Pause |
| F5 | Reset to the start position |

**A first flight from Juhu:** Page Up to full throttle (about 2300 RPM static). Keep straight with Z/X. At 55 kt, hold ↓ gently to rotate. Climb at 74 kt (Vy). Trim with Home/End until hands-off level, then reduce to about 2400 RPM for cruise. The Ghats are 45 km east; Pune (VAPO) is about 120 km east-southeast.

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

### Systems, weather and failures (M6)

**Switch panel** (the bottom row of the instrument panel; click to toggle):
- **Electrical:** BAT and ALT masters, AVN (avionics).
- **Lights:** BCN, LAND, TAXI, NAV, STRB.
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
- **Sky:** clouds are a cumulus layer that drifts with the wind aloft. Visibility drives haze and fog.
- **Time of day:** real sun position for Mumbai/Pune (IST). Default 10:00 on 14 February. The F10 time rate can speed it up.
- **Night:** runway edge lights, threshold and end lights, and approach bars at every runway. The aircraft has nav, beacon, strobe, taxi and landing lights.
- **Failures (F10):**
  - engine
  - vacuum pump
  - pitot blocked, static blocked
  - alternator, battery
  - left tank leak

**Realism notes:**
- The engine is running at start (cold-and-dark start comes in M8). If it stops, set magnetos to BOTH (M) and hold S.
- With only the pilot aboard (the default load), the CG sits slightly left, so the aircraft rolls gently left hands-off, as the real C172 does. Hold a little right aileron.
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
```

The runner prints PASS/FAIL per test and exits non-zero on failure. Ignore the "ObjectDB instances leaked" warnings at exit.

| Suite | Covers |
|---|---|
| `tests/test_core.gd` | Geo projection, floating origin, terrain heights and runway flatness |
| `tests/test_fdm_cards.gd` | POH performance test cards (M3) |
| `tests/test_flight.gd` | Takeoff from Juhu on the real terrain and runway (M4) |
| `tests/test_instruments.gd` | Altimeter and Kollsman, ASI, VSI lag, vacuum-failure gyro drift, compass northerly turning error (M5) |
| `tests/test_systems.gd` | Alternator failure and battery drain, fuel starvation and restart, wind profile, Ghats ridge lift (M6) |

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

### Tuning the aircraft

The aircraft's behaviour is data, so you can tune it without touching code:

- `game/aircraft/c172/c172_config.json`: mass, inertia, gear springs and friction, surface limits, flap timing, engine and prop. `propeller.ct_factor_vs_j` (a thrust multiplier versus advance ratio) and `cp_factor` are the main performance knobs.
- `game/aircraft/c172/c172_aero.json`: aerodynamic coefficient tables and constants, from JSBSim.
- Both files are regenerated by `tools/06_jsbsim_to_json.py`, so put permanent tuning changes in that script (or stop regenerating the files).
- Re-run the test cards after any change.

---

## 5. Aircraft models and 3D scenery

**The aircraft** is the FlightGear c172p model and cockpit (GPL-2.0-or-later, c172p team), converted by the Blender scripts in `tools/blender/`. The original sources are vendored in `third_party/c172p/`. The live free-sim gauges are drawn onto the real panel at each instrument's true position. If the `.glb` files are missing, the sim falls back to the box placeholder.

**3D buildings:**
- Built from 578k OSM footprints, with heights from OSM tags or a synthetic estimate by footprint size.
- Roofs take their colour from the satellite image; facades get procedural windows that light up at night.
- Streamed within 9 km and hidden above 2500 ft AGL.

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
| Medium | ~62 | 85 % + FSR | 150 m | 6 km / 1.8 km | 16 |
| High | ~51 | 100 % + MSAA 2× | 300 m | 9 km / 2.2 km | 24 |
| Ultra | ~45 | 100 % + MSAA 4× | 600 m | 12 km / 3 km | 40 |

With the Forward+ renderer (F10 → Renderer, then restart; or launch with `--rendering-method forward_plus`), Ultra also enables SSAO and TAA. Mobile is the default renderer and the fastest on integrated GPUs.

**Trees:**
- Forests are placed from the satellite vegetation index, excluding buildings, roads, runways and water.
- They're generated deterministically within about 2 km of the aircraft: crossed-quad canopies with colour variation and wind sway.
- Hidden above 1500 m AGL.

### Replacing the models with your own Blender models

To use your own models instead of the converted FlightGear ones:

1. Model in Blender in metres, with **−Z forward, +Y up, origin at the C172's CG**. The CG is about 1.0 m aft of the JSBSim datum; see `mass.empty_cg_m` in `c172_config.json`. Export glTF (`.glb`) to `game/aircraft/c172/exterior.glb` and `cockpit.glb`.
2. Name animated parts `elevator`, `rudder`, `aileron_L`, `aileron_R`, `flap_L`, `flap_R` and `prop`, with pivots on their hinge lines.
3. In the cockpit model, leave a flat panel face with UVs covering 0–1. Assign it a material whose albedo is the panel SubViewport texture (see `Cockpit.build`), so the existing gauges and clickable knobs keep working.
4. Instantiate the `.glb` files in `C172Model.build()` instead of the `_box()` calls (a few lines of code).

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
  aircraft/c172/  aero + config JSON (from JSBSim; edit to tune), placeholder model, procedural engine sound
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
| Aircraft spawns in the wrong place / no runway | Run `tools/09_runways.py` (it writes `data/processed/runways.json`) |
| No sound | Godot uses PulseAudio/PipeWire; check the system output device |
