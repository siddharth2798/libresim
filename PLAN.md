# libresim plan

## Goal
A realistic, lightweight desktop flight simulator in the style of MSFS and Real Flight Simulator, for the Mumbai–Pune region (later a corridor to Kochi).

- Free tools only. Runs locally and offline. The one exception is an opt-in live weather switch, off by default (`docs/LIVE-WEATHER-PLAN.md`).
- Light: integrated GPU and keyboard first; dedicated GPU and joystick next.
- Small map: Mumbai–Pune only (~140 × 110 km), install under 1 GB.
- Main aircraft: Cessna 172S, as realistic as possible.
- Heavy data and art work runs as local scripts or in free GUI tools, not inside Claude chats.

## Platform
- Native desktop app (Linux first; Windows and macOS export from the same project). No browser: WebGL 2 is slower, has no Vulkan Mobile renderer, and the browser cannot hold hundreds of MB of terrain.
- iPhone/iPad is optional and later. It needs a Mac with Xcode (free Apple ID apps expire after 7 days; a paid account is $99/yr), touch controls and a smaller map and texture set. Same codebase, no rewrite.

## Scope
| Feature (RFS/MSFS) | Our version |
|---|---|
| Satellite terrain with real elevation | Sentinel-2 10 m imagery + Copernicus 30 m DEM, procedural detail up close |
| 3D airports | Runways, taxiways, aprons and lights from OSM; hand-made hero buildings only at Juhu (VAJJ) |
| Interactive cockpit | Clickable C172 cockpit, six-pack and engine gauges |
| Flight model | Table-driven 6-DOF model from JSBSim's C172 aero data |
| Systems and failures | Engine, electrical, fuel, vacuum, pitot-static; failures menu |
| Navigation | VOR/DME/ILS/NDB from OurAirports data, simple GPS, moving map |
| Weather | Offline METAR-style settings: wind layers, turbulence, visibility, clouds, QNH |
| ATC | Offline rule-based ATC, local TTS (Piper); text first |
| Replay, save/load, cameras | Yes |
| Multiplayer, live traffic, live weather, global map | Skipped: need online services and big storage |

## Tech stack
| Purpose | Tool |
|---|---|
| Engine | Godot 4 (MIT), Mobile renderer; Forward+ on High and above |
| Language | GDScript. Move the flight model to a C++ GDExtension only if profiling needs it |
| Flight data | JSBSim `c172p` files (LGPL), as data only; standalone JSBSim is the reference for tests |
| GIS | GDAL, QGIS, Python (`rasterio`, `numpy`, `osmium`) |
| Elevation | Copernicus GLO-30 DEM (30 m) |
| Imagery | Sentinel-2 cloudless (EOX s2cloudless, 10 m) |
| Vector data | OpenStreetMap, Geofabrik Western India extract |
| Airports, navaids | OurAirports CSV (public domain) |
| 3D | Blender |
| Textures | GIMP / Krita; CC0 sets from ambientCG / Poly Haven |
| Audio | Audacity; CC0 sounds from Freesound |
| ATC voice | Piper TTS (local) |

## Region
- Bounding box: 18.30°N–19.30°N, 72.75°E–74.10°E (Mumbai, Thane creek, Navi Mumbai, Western Ghats, Pune).
- Airports: VAJJ Juhu (home base, hero airport), VABB Mumbai (crossing runways, ILS), VAPO Pune (ILS), VANM Navi Mumbai, plus OSM airstrips.
- Why: coast, city, a 600–1,400 m escarpment and a flat plateau, all within one C172 fuel load (~110 nm).
- Projection: local TM centred at 18.75N 73.40E (near Lonavala), so projected metres equal world ENU metres. Earth curvature is a vertex-shader bend, not geometry.
- Size budget: DEM ~35 MB, imagery 250–400 MB, airport overlays ~50 MB, OSM meshes and data ~50 MB, aircraft/cockpit/audio ~150 MB. Total about 0.6–0.7 GB.

## Architecture
Code layout: see [CLAUDE.md](CLAUDE.md). Offline pipeline order: [docs/USAGE.md](docs/USAGE.md).

Decisions:
1. **FDM decoupled from rendering.** Fixed 120 Hz in `_physics_process`, 2 sub-steps if needed, 64-bit GDScript floats. Rendering reads and interpolates.
2. **Floating origin.** The world shifts every ~5 km. No double-precision Godot build, no 32-bit jitter far from the origin.
3. **Terrain = quadtree of chunked tiles.** 64×64-vertex meshes displaced in a vertex shader from a heightmap, LOD by screen-space error, skirts between LODs, tiles streamed on a background thread.
4. **Detail without big textures.** 10 m satellite colour blended with tiling CC0 detail textures chosen by a land-class mask; far terrain uses satellite colour only.
5. **Data-driven aircraft.** Aero, engine, mass, gear, V-speeds live in `config.json` / `aero.json`; limits, systems, lights, model and cockpit wiring in `aircraft.json`; `AircraftDef` reads them. A new aircraft needs no code, and tuning needs no Claude.
6. **Property tree.** Everything simulated is a property (e.g. `/systems/electrical/bus_volts`). Instruments, sounds, UI and failures read and write properties, so modules stay small and independent.

## Realism target (C172S)
- **Flight dynamics:** 6-DOF from JSBSim tables (lift, drag, side force, moments with damping and control derivatives). Stall: CL break past alpha ~16 deg, reduced aileron effect, wing drop, buffet, horn 5–10 kt above stall. Prop torque, P-factor, slipstream, gyro precession.
- **Ground:** spring-damper gear, nosewheel steering from the rudder, differential brakes, tyre friction, weathervaning, crosswind.
- **Atmosphere:** ISA plus offset, QNH, density altitude, wind layers, Dryden turbulence, windshear, ridge lift and mechanical turbulence off the Ghats.
- **Mass and balance:** fuel burn moves weight and CG; set pilot, passengers and baggage before flight.
- **Engine (Lycoming IO-360, 180 hp):** RPM from a prop torque balance, manifold pressure, mixture with EGT peak, fuel flow, oil temperature/pressure lag, CHT, magnetos, primer, starter, flooding. No carb heat: the C172S is fuel-injected (chosen because it matches the JSBSim data).
- **Systems:** electrical (battery, alternator, split master, avionics master, breakers), fuel (L/R, selector, shutoff, unusable fuel, starvation), vacuum (gyros spin down on failure), pitot-static (blocked ports give wrong readings), electric flaps 0/10/20/30, lights.
- **Instrument errors:** ASI position error; altimeter Kollsman and lag; VSI lag ~6 s; attitude precession; heading drift; compass turning/acceleration errors; slip ball.
- **Avionics:** dual NAV/COM, VOR CDI, ILS with real ranges and terrain line-of-sight, DME, ADF, transponder, GPS direct-to with moving map. The KAP 140 autopilot is planned, not built.
- **Procedures:** cold-and-dark start; checklists that tick themselves. POH V-speeds (KIAS): Vs0 40, Vs1 48, Vr 55, Vx 62, Vy 74, Vfe 85–110, Vno 129, Vne 163.

## Performance target
60 FPS at 720p–1080p on an integrated GPU (Low preset, worst case a low pass over Mumbai).
- Mobile renderer: no SDFGI/SSR; one shadow cascade to ~2 km; FXAA.
- Terrain: up to ~250 visible tiles, ≤ ~400 draw calls, compressed textures, ~512 MB texture budget.
- Buildings: extruded OSM footprints within ~5 km, merged per tile; a flat city texture beyond.
- Clouds: impostor clusters plus fog layer on Low; volumetric on dedicated GPUs.
- Cockpit: baked mesh, needles dynamic, gauge faces in a `SubViewport` at 15–30 Hz.
- Presets Low / Medium / High / Ultra / Max only raise limits.
- Frame budget: FDM < 0.5 ms, terrain < 4 ms, total < 16 ms.

## Input
- Keyboard: rate-based controls that self-centre; throttle, mixture, trim, flaps, brakes keys; optional mouse-yoke mode.
- Joystick/gamepad: SDL mappings, binding UI with calibration, deadzone and curves, one profile per device, throttle quadrant and pedals.
- All input goes through `axis_filters.gd`, so the FDM always gets -1..1 or 0..1.

## Milestones
Done:
- M0 setup · M1 data pipeline · M2 terrain viewer · M3 core FDM (test cards pass) · M4 first flight · M5 cockpit and instruments · M6 systems and weather · M7 navigation (radios, GPS, moving map) · M7b start screen, failures, session recording · M8 polish (checklists, W&B, presets, joystick UI, audio/options, save/load, replay).
- **G** graphics toward MSFS quality: see [docs/GRAPHICS-PLAN.md](docs/GRAPHICS-PLAN.md) (G0–G6 done).
- **A** airport operations: start from a gate or stand, OSM terminals, taxi routing and follow-me, pushback, ground vehicles, jetways, ATC text, checklists.
- **P** packaging for Linux and macOS (`tools/package/make_release.sh`, `packaging/`).
- **R** region expansion to Kochi: ~1100 km × ~150 km corridor, imagery ~20 m/px (10 m would exceed 6 GB), region packs, 13 new airfields.
- Realistic terminals (VABB, VAPO, VOCI and more): [docs/TERMINALS.md](docs/TERMINALS.md).
- Start screen rebuilt (U0–U8): [docs/UI-IMPLEMENTATION-PLAN.md](docs/UI-IMPLEMENTATION-PLAN.md). Training mode.

Left:
- ATC A2 (circuit traffic) and A3 (Piper voice, real radio sounds): [docs/ATC.md](docs/ATC.md).
- Graphics G7–G10: [docs/GRAPHICS-PLAN.md](docs/GRAPHICS-PLAN.md).
- A320 airliner (M10): paused. [docs/A320-PLAN.md](docs/A320-PLAN.md), [docs/A320-STATUS.md](docs/A320-STATUS.md), [docs/A320-FINISH-PLAN.md](docs/A320-FINISH-PLAN.md).
- Liveries: [docs/LIVERY-PLAN.md](docs/LIVERY-PLAN.md).
- KAP 140 autopilot for the C172.
- iPhone/iPad port (M9b): touch controls, phone preset, reduced textures.
- Freeze scope: multiplayer stays out. Live weather is the one opt-in online feature, off by default (`docs/LIVE-WEATHER-PLAN.md`).

## 8b. Standing requirements
- **Real sounds for every moving or working part.** No synthesized placeholders in releases. Every engine, propeller, actuator, switch, lever, gear, flap motor, trim wheel, stall horn, gyro, wind, tyre rumble, door, ground vehicle (tug, fuel truck, GPU), ATC radio and airport ambience uses real recordings, layered and pitch/volume-mapped to the simulated state. Sources: FlightGear c172p sounds (CC0/CC-BY, credited per its `Thanks` file), Freesound CC0/CC-BY, own recordings. Every file is listed with its licence in CREDITS.md. The procedural engine sound in `aircraft/c172/engine_sound.gd` is a stand-in until then.
- **Credits and licence compliance before any push or release:** [CREDITS.md](CREDITS.md), [docs/LICENSING.md](docs/LICENSING.md), the F12 credits screen and the always-visible map attribution line.
- **Graphics as close to MSFS as possible**, with Low/Med/High/Ultra presets so integrated GPUs stay smooth.

## Working with Claude cheaply
1. Claude writes code and scripts; your machine does the heavy work. Never paste DEM, imagery, OSM data, big logs or `.tscn` dumps into chat.
2. Do the art yourself (Blender, GIMP, Audacity).
3. One milestone per session: plan mode first, `/clear` when done. CLAUDE.md orients each new session.
4. Files under 300 lines and the property tree mean each task touches 1–3 files.
5. Sonnet for routine work (UI, gauges, JSON wiring); Opus for the FDM, terrain LOD and hard bugs.
6. Tune aircraft in JSON, not through code requests.
7. Bug reports: expected vs actual, the file, a small log excerpt.
8. Reuse before writing: Terrain3D before a custom terrain, JSBSim tables before invented aerodynamics, Godot's sky, audio buses and navigation.

## Challenges and answers
| Challenge | Answer |
|---|---|
| Flight model fidelity (sign errors make the aircraft uncontrollable) | Reuse JSBSim C172 tables (data only, no code port); add one force term at a time; compare with standalone JSBSim and POH numbers in test cards |
| Ground handling (stiff springs bounce at a fixed step) | 120 Hz with sub-steps, critically damped gear, a static-friction stick state at low speed, tuned by test cards |
| Float precision | Floating origin; 64-bit FDM state |
| Terrain LOD seams and streaming hitches | Skirts or stitching, geomorphing, background loading, tile cache with prefetch along the velocity vector |
| 10 m imagery looks blurry at pattern altitude (Google/Bing tiles are not allowed) | Procedural detail, OSM land classes, hand-detailed airports, haze shader |
| Mumbai building density | Only within ~5 km, merged per tile, heights from OSM tags or by land class, far city as texture |
| Noisy DEM (±5–10 m) puts runways on bumps | Pipeline cuts a smoothed flat pad under each runway and taxiway |
| Faceted Ghats cliffs at 30 m | DEM normal maps, slope-based rock texture, slight bicubic upsampling |
| Instrument realism | Each instrument is a small model on the property tree with first-order lags and precession |
| Navaid realism | Line-of-sight ray-march on the DEM at ~2 Hz; simplified cone of confusion |
| Integrated-GPU performance | Strict presets, low-rate `SubViewport` gauges, impostor clouds, profile every milestone |
| 3D art workload | Start low-poly and iterate; the FlightGear c172p model (GPL) is now the real model |
| Licensing (ODbL, CC-BY, GPL, s2cloudless is non-commercial) | Keep CREDITS.md; see docs/LICENSING.md |

## Verification
Headless FDM test cards (`godot --headless --path game res://tests/run_tests.tscn`), each against the C172S POH or standalone JSBSim (±10%):
- Stall speed clean / full flaps: 48 / 40 KIAS.
- Takeoff roll at sea level, standard day, max weight: ~960 ft.
- Climb at Vy at sea level: ~730 fpm.
- Cruise at 75% power, 6,000 ft: ~120 KTAS.
- Trimmed level flight holds altitude ±50 ft over 60 s hands-off.
- Phugoid and short-period oscillations present and damped plausibly.
- Static RPM ~2,300 at full throttle; mag-check drop 50–125 RPM.

Manual flight tests each milestone: Juhu circuit; ILS 27 into Mumbai; VAJJ to VAPO over the Ghats on VOR; 15 kt crosswind landing; engine-out glide (best glide 68 KIAS, ~9:1); vacuum failure.

Data check: runway thresholds within ~10 m of OurAirports coordinates; ILS localizer lines up with the runway centreline.
