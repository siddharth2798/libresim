# "libresim": Plan for a Lightweight, Realistic Flight Simulator (Mumbai–Pune, Cessna 172)

## Platform: runs locally, not in a browser
- **Primary target: a native desktop app on Pop!_OS (Linux).** Godot exports a single Linux executable plus a `.pck` data file. You launch it like any app: no browser, no internet, no server. This gives the best performance on an integrated GPU, full Vulkan, joystick support, and fast disk streaming of the ~600 MB of map data.
- **Why not the browser**: Godot's web export uses WebGL 2, which is slower and has no Vulkan Mobile renderer. The page would have to load hundreds of MB of terrain on every launch, and browser memory limits (especially Safari on iOS, ~1–1.5 GB) would make large-map streaming unreliable. It's possible later as a "lite" demo, but it's not the main path.
- **iPhone/iPad (optional, later)**: Godot can export to iOS, and the free tools allow it. However, it **requires a Mac with Xcode** to build and sign. With a free Apple ID, sideloaded apps expire after 7 days; a paid developer account ($99/yr) removes that limit. It would also need touch controls (virtual yoke and tilt steering like RFS) and a trimmed map/texture set for phone storage and RAM. Because the Godot project is cross-platform, the same codebase can be ported later with no rewrite. Plan this as a post-M8 phase.
- **Also possible for free**: Windows and macOS desktop exports from the same project, if needed.

## Context
Goal: a realistic desktop flight simulator in the style of MSFS and Real Flight Simulator (RFS), with these constraints:
- **Free tools only**, runs **locally**, no online services.
- **Light**: runs on a laptop with integrated GPU and keyboard now; dedicated GPU + joystick/gamepad in the next iteration.
- **Small map**: Mumbai–Pune region only (~140 × 110 km), total install **< 1 GB**.
- **Main aircraft**: Cessna 172 (C172S), built as realistically as the budget allows.
- **Low Claude-credit use**: most heavy work (data processing, 3D art) runs as local scripts or in free GUI tools, not inside Claude conversations.

The project started as a greenfield build (no existing code) in a `libresim/` directory.

---

## 1. What we take from RFS / MSFS (and what we skip)

| Feature (RFS/MSFS) | Our version | Phase |
|---|---|---|
| Satellite-imagery terrain with real elevation | Sentinel-2 10 m imagery + Copernicus 30 m DEM, with procedural detail up close | 1 |
| 3D airports | Runways, taxiways, aprons and lights generated from OSM; hand-made hero buildings only at Juhu (VAJJ) | 1–2 |
| Interactive 3D cockpit | Clickable C172 cockpit: switches, knobs, levers, six-pack gauges | 2 |
| Realistic flight model | Table-driven 6-DOF model using JSBSim's validated C172 aerodynamic data | 1 |
| Systems & failures | Engine, electrical, fuel, vacuum and pitot-static systems, with a failures menu | 2–3 |
| Navigation & flight plans | VOR/DME/ILS/NDB from OurAirports data, a simple GPS, a moving map | 3 |
| Weather | Offline METAR-style settings: wind layers, turbulence, visibility, cloud layers, QNH | 2 |
| ATC | Offline rule-based ATC with local TTS (Piper). Text-only first | 4 |
| Replay, save/load, cameras | Yes | 2 |
| Multiplayer, live traffic, live weather, global map | **Skip**: they need online services and big storage | — |

---

## 2. Tech stack (all free)

| Purpose | Tool | Why |
|---|---|---|
| Game engine | **Godot 4.x** (MIT), **Mobile renderer** (Vulkan) | ~100 MB, native on Linux, good on integrated GPUs, small projects, text-based scene files that Claude can edit cheaply |
| Language | **GDScript**. Move only the flight model to a C++ GDExtension if profiling shows it's needed | Fast iteration and short code, so fewer tokens |
| Flight-model data and reference | **JSBSim** (LGPL), the `c172p` aircraft files | Validated aero tables for lift, drag, moments and propeller; standalone JSBSim is also the "truth" we test against |
| GIS processing | **GDAL**, **QGIS**, Python (`rasterio`, `numpy`, `osmium`) | Crop, reproject and tile the DEM and imagery, extract OSM features |
| Elevation | **Copernicus GLO-30 DEM** (30 m, free) | Better than SRTM in built-up areas |
| Imagery | **Sentinel-2 cloudless mosaic** (EOX s2cloudless, 10 m; free for personal use) | Cloud-free and seamless |
| Vector data | **OpenStreetMap** extract from Geofabrik (Western India) | Runways, taxiways, roads, coastline, water, building footprints |
| Airports & navaids | **OurAirports** CSV (public domain) | Runway ends and headings, frequencies, VOR/NDB/ILS |
| 3D models | **Blender** | C172 exterior and cockpit, airport buildings |
| Textures | **GIMP / Krita**, CC0 textures from ambientCG / Poly Haven | Cockpit panels, ground detail textures |
| Audio | **Audacity**, CC0 sounds from Freesound | Engine loop layers, stall horn, wind, gear rumble |
| Voice (ATC) | **Piper TTS** (local, offline) | Pre-generated or runtime ATC voice |
| Version control | git | Snapshot every milestone |

---

## 3. Region definition

- **Bounding box** (approx.): 18.30°N–19.30°N, 72.75°E–74.10°E, covering Mumbai, the Thane creek, Navi Mumbai, the Western Ghats (Lonavala/Khandala, Sinhagad) and Pune.
- **Airports**:
  - **VAJJ Juhu**: small general-aviation field, the home base for the C172. This is the detailed "hero" airport.
  - **VABB Mumbai CSMIA**: two crossing runways, ILS.
  - **VAPO Pune**: ILS.
  - **VANM Navi Mumbai**.
  - Plus a few OSM airstrips if present.
- **Why this region**: it has coast, city, a 600–1,400 m escarpment (real mountain flying with ridge winds) and a flat plateau, all within one C172 fuel load (~110 nm apart).
- **Projection**: all data goes to **UTM zone 43N** (EPSG:32643). In-game world axes are local East-North-Up (ENU) metres, with the origin near Lonavala (~18.75N, 73.40E). Earth curvature over ±70 km is ≤ ~400 m of drop. We skip it in v1 and add an optional vertex-shader curvature bend later.

### Storage budget

| Asset | Size |
|---|---|
| DEM, 30 m, 16-bit, tiled (~4,700 × 3,700 samples) | ~35 MB |
| Imagery, 10 m, GPU-compressed tiles plus mip pyramid | ~250–400 MB |
| High-res overlay around the airports (optional, 2–5 m from free sources if any exist; otherwise procedural) | ~50 MB |
| OSM-derived meshes and data (buildings as extruded footprints, roads as decals) | ~50 MB |
| Aircraft, cockpit, audio, engine | ~150 MB |
| **Total** | **≈ 0.6–0.7 GB** |

---

## 4. Architecture

```
libresim/
  CLAUDE.md                 # conventions + module map (keeps Claude sessions cheap)
  tools/                    # offline Python/GDAL pipeline (run locally, never in Godot)
    01_fetch_notes.md       # manual download links/steps
    02_dem_tiles.py         # crop → reproject → 16-bit heightmap tiles + quadtree
    03_imagery_tiles.py     # crop → reproject → tile → mipmaps → compress
    04_osm_extract.py       # runways/taxiways/roads/buildings/water → compact JSON/bin
    05_airports_navaids.py  # OurAirports CSV → airports.json, navaids.json
    06_jsbsim_to_json.py    # c172p XML aero tables → c172_aero.json
  game/                     # Godot project
    core/        sim_clock.gd, floating_origin.gd, units.gd, geo.gd (lat/lon↔ENU)
    fdm/         fdm.gd (6-DOF integrator), aero.gd, engine_piston.gd, propeller.gd,
                 gear_ground.gd, atmosphere_isa.gd, wind_turbulence.gd (Dryden), mass_balance.gd
    systems/     electrical.gd, fuel.gd, vacuum.gd, pitot_static.gd, flaps.gd, lights.gd, failures.gd
    avionics/    nav_radio.gd (VOR/ILS/DME), adf.gd, com.gd, transponder.gd, gps_simple.gd, autopilot_kap140.gd
    instruments/ asi, attitude, altimeter, turn_coordinator, heading_indicator, vsi, tach, fuel/oil/egt gauges
    world/       terrain_quadtree.gd, terrain_tile.gd, terrain.gdshader, airport_builder.gd,
                 runway_lights.gd, water.gdshader, sky_time_of_day.gd, clouds_impostor.gd
    aircraft/c172/  exterior.glb, cockpit.glb, c172_config.json, sounds/
    input/       input_map, axis_filters.gd (rate, curves, deadzone), joystick_calibration.gd
    ui/          main_menu, flight_setup (airport/time/weather), map_view, failures_menu, checklist, replay
    atc/         (phase 4) atc_rules.gd, phraseology.json, piper voice clips
    tests/       headless FDM test cards (see Verification)
```

### Key design decisions
1. **Flight model is decoupled from rendering.** The FDM runs at a fixed **120 Hz** in `_physics_process`, with 2 sub-steps if needed. It keeps its own state in double-precision-style ECEF/ENU variables (GDScript floats are 64-bit). Rendering only reads the state and interpolates it.
2. **Floating origin.** Keep the camera near (0,0,0) by shifting the world every ~5 km. This avoids a custom double-precision Godot build and the jitter that 32-bit floats cause at 70 km from the origin.
3. **Terrain = quadtree of chunked tiles.** Each node is a 64×64-vertex grid mesh displaced in a vertex shader from a heightmap texture. Screen-space error picks the LOD; neighbouring LODs are stitched with skirts. Tiles stream from disk on a background thread (`WorkerThreadPool`). Before writing our own, evaluate the **Terrain3D** plugin (MIT) with large vertex spacing. If it covers 140 km cleanly, use it and save a lot of work.
4. **Up-close detail without big textures.** Blend the 10 m satellite colour with tiling CC0 detail textures (grass, dirt, urban, forest), picked by a small land-class mask derived from OSM and imagery colour. Distant terrain uses satellite colour only.
5. **Data-driven aircraft.** Aero tables, engine and propeller curves, mass, CG, gear positions and V-speeds all live in `c172_config.json` and `c172_aero.json`. That lets an airliner be added later without code changes, and lets you tune the aircraft without Claude.
6. **Everything simulated is a node in a "property tree"**, similar to JSBSim/FlightGear (e.g. `/systems/electrical/bus_volts`). Instruments, sounds, UI and failures read and write properties. This keeps modules independent and small, which keeps Claude context small.

---

## 5. Realism specification (C172S)

**Flight dynamics (6-DOF rigid body):**
- Forces and moments come from JSBSim C172 coefficient tables:
  - Lift: CL(α, flaps, ground effect).
  - Drag: CD(α, flaps, β).
  - Side force and moments: Cm, Cl, Cn with damping derivatives (p, q, r) and control derivatives.
- **Stall behaviour**: CL break past α≈16°, reduced aileron effectiveness, wing-drop tendency, buffet shake, stall horn at ~5–10 kt above stall.
- **Propeller effects**: torque, P-factor, slipstream over the tail (rudder and elevator authority at low speed), gyroscopic precession.
- **Ground handling**: spring-damper gear, nosewheel steering tied to the rudder pedals, differential toe brakes, tyre friction, weathervaning, crosswind side-load.
- **Atmosphere**: ISA plus temperature offset, QNH, density altitude (hot Pune afternoons really matter), wind by altitude layers, Dryden turbulence, windshear, ridge lift and mechanical turbulence off the Ghats (simple slope-wind model).
- **Mass & balance**: fuel burn changes weight and CG; set pilot, passengers and baggage before flight.

**Engine (Lycoming IO-360, 180 hp):**
- RPM from a propeller torque balance.
- Manifold pressure, mixture (leaning, with EGT peak), fuel flow.
- Oil temperature and pressure lag, cylinder head temperature (CHT).
- Magnetos (L/R/BOTH): RPM drop on a mag check.
- Primer and starter; flooding and failed starts.
- Carb heat is omitted because the C172S is fuel-injected. Choose one: C172S (fuel injection) or C172N (carburettor with carb ice). **Recommendation: C172S**, because it matches the JSBSim data.

**Systems:**
- **Electrical**: battery, alternator, master (split), avionics master, bus voltage/ammeter, circuit breakers.
- **Fuel**: L/R tanks, selector (L/R/BOTH), shutoff valve, unusable fuel, fuel starvation.
- **Vacuum**: pump drives the attitude and heading indicators. On failure they spin down and tumble slowly.
- **Pitot-static**: blocked pitot or static ports give realistic wrong readings.
- **Flaps**: electric, 0/10/20/30°, with real travel time and pitch change.
- **Lights**: nav, beacon, strobe, taxi, landing, panel dimmers.

**Instruments (with real errors):**
- Airspeed indicator: IAS from dynamic pressure, with position error.
- Altimeter: Kollsman setting, lag.
- VSI: ~6 s lag.
- Attitude indicator: precession during long turns.
- Heading indicator: drifts and needs resetting to the compass.
- Magnetic compass: turning and acceleration errors, local magnetic variation (~0°W, near zero in Mumbai).
- Turn coordinator and slip ball.
- Tach, fuel quantity, oil, EGT, suction, ammeter.

**Avionics:**
- Dual NAV/COM (KX-155 style) with standby frequencies.
- VOR CDI, ILS localizer and glideslope with real ranges and line-of-sight blocking by terrain.
- DME, ADF with NDB.
- Transponder.
- A simple GPS direct-to with a moving map.
- KAP 140 autopilot (ROL/HDG/NAV/APR/ALT/VS), phase 3.

**Procedures:**
- Cold-and-dark start.
- Interactive checklists that auto-tick when a state is met.
- POH V-speeds: Vs0 40, Vs1 48, Vr 55, Vx 62, Vy 74, Vfe 85–110, Vno 129, Vne 163 KIAS.

---

## 6. Performance plan (integrated GPU, 60 FPS at 720p–1080p)
- **Mobile renderer**: no SDFGI, no SSR, no volumetric fog. Use SSAO off/low, one directional shadow cascade limited to ~2 km, and FXAA.
- **Terrain**: ≤ ~250 visible tiles, one draw call each (≤ ~400 total draw calls per frame), compressed textures (VRAM-compressed / Basis Universal), and a texture memory budget of ~512 MB.
- **Buildings**: extruded OSM footprints only within ~5 km, merged per tile into one mesh, simple shading, rendered as a flat "city" texture beyond that. Mumbai has a huge number of footprints, so the pipeline must merge and decimate them per tile.
- **Clouds**: billboard/impostor clusters plus a fog layer, not volumetric (volumetric is an option for dedicated GPUs later).
- **Cockpit**: one baked-lighting mesh plus dynamic needles. Draw gauge faces into a `SubViewport` at ~15–30 Hz, not every frame.
- **Graphics presets** (Low / Medium / High) so the dedicated-GPU iteration only raises limits and adds nothing new.
- **Profiling**: Godot's built-in profiler and monitors. Frame-time budget: FDM < 0.5 ms, terrain < 4 ms, total < 16 ms.

---

## 7. Input
- **Keyboard (v1)**:
  - Rate-based controls: holding a key moves the elevator or aileron gradually, and it self-centres with a spring when released.
  - Throttle, mixture, trim, flaps and brakes keys.
  - Optional mouse-yoke mode, where the mouse position drives pitch and roll. RFS-like and very usable on a laptop.
- **Joystick/gamepad (next iteration)**:
  - Godot's Input API with SDL mappings.
  - An axis-binding UI with calibration, deadzone and response curves; a profile saved per device.
  - Support for a throttle quadrant and rudder pedals.
- All input goes through `axis_filters.gd`, so the FDM always receives normalized −1..1 or 0..1 values from any device.

---

## 8. Milestones (each is small, testable and committed)

| # | Milestone | Deliverable | Rough effort |
|---|---|---|---|
| M0 | Setup | Godot project, git, CLAUDE.md, folder skeleton, download all data manually (`01_fetch_notes.md`) | 1–2 days |
| M1 | Data pipeline | DEM and imagery tiles plus airports/navaids JSON for the region; a quick preview in QGIS | 3–5 days |
| M2 | Terrain viewer | Fly a free camera over the streaming, LOD'd Mumbai–Pune terrain at 60 FPS on the laptop; floating origin | 1–2 weeks |
| M3 | Core FDM | C172 aero, engine and gear from JSON; take off from a flat test plane; headless test cards pass | 2–3 weeks |
| M4 | First real flight | FDM on the terrain, with VAJJ/VABB/VAPO runways from OSM/OurAirports; basic HUD, external and cockpit cameras, keyboard controls, engine sound | 1–2 weeks |
| M5 | Cockpit & instruments | Blender C172 cockpit, clickable controls, six-pack plus engine gauges driven by pitot-static and vacuum | 3–4 weeks (mostly Blender) |
| M6 | Systems & weather | Electrical, fuel, flaps, lights, failures menu, wind, turbulence, cloud impostors, time of day, runway and approach lights at night | 2–3 weeks |
| M7 | Navigation | NAV/COM, VOR/ILS/DME/ADF, GPS direct-to, moving map, flight-setup UI, save/load, replay | 2–3 weeks |
| M7b | Flight setup & failures | Start screen (airport/stand/runway/air, aircraft + payload, weather/time/wind), 26 failures with triggers, random failures, F9 panel, Esc pause menu; session recording (built-in MKV writer, video + sound, chosen folder, MP4 via ffmpeg if present) | done |
| M8 | Polish | Checklists, cold-and-dark start, mass & balance (CG envelope chart), graphics presets, joystick/gamepad binding UI, audio/options, save/load situations, instant replay | done |
| M9 (opt) | ATC & autopilot | KAP140 autopilot, rule-based ATC (Juhu tower, Mumbai approach) with Piper TTS | 3+ weeks |
| M9b (opt) | iPhone/iPad port | Touch controls (virtual yoke, tilt), phone graphics preset, reduced texture set; built on a Mac with Xcode | 2–3 weeks |
| **G** | **Graphics toward MSFS quality** (user priority) | Presets Low/Med/High/Ultra; High+ switch to Forward+ renderer, plus:<br>• rendering: TAA/FSR2<br>• sky and clouds: physical atmosphere scattering, raymarched volumetric clouds<br>• water: reflective with waves (coast, creeks, lakes, from OSM water polygons)<br>• scenery: OSM 3D buildings (578k footprints, merged per tile, PBR facades), tree/forest scatter from imagery classes, terrain detail textures + normal maps<br>• aircraft: PBR C172 (converted FlightGear c172p, GPL)<br>• weather effects: rain and wet-runway reflections | 3–5 weeks |
| **A** | **Airport operations & "start from terminal"** (user priority, RFS-style) | Start at gate / parking stand / remote bay (cold & dark or ready); airports built from OSM: terminals & concourses (3D, extruded with roofs), jetbridges at OSM `aeroway=gate`/`jet_bridge`, remote stands (`parking_position`), apron markings & stand numbers; full taxiway graph from OSM (`aeroway=taxiway` with refs) → A* taxi routing, progressive-taxi guidance (on-ground arrows/follow-me line, RFS-like), hold-short lines & stop bars; ground vehicles: pushback tug (driven by the sim, with steering), fuel truck, GPU, baggage carts & tugs, follow-me car, marshaller with signals; ground ops menu (request pushback, fuel, boarding, doors); interactive checklists (preflight → shutdown, auto-ticking from properties); ATIS/clearance/ground/tower text (voice in M9) | 4–6 weeks |
| **P** | **Packaging for Linux & macOS** (after the MVP) | Linux: AppImage (any distro) + Flatpak (Flathub) + .tar.gz; macOS: universal .app/.dmg exported from Godot (signing & notarisation need an Apple Developer ID; `rcodesign` can do it from Linux, or use a Mac); data pack beside the binary; licences per docs/LICENSING.md; CI builds | 1–2 weeks |
| **R** | **Region expansion: Mumbai → Kochi** (user request, after existing phases) | Coastal corridor ~1100 km × ~150 km (Konkan, Goa, Mangaluru, Kerala) incl. VAGO/VOGA (Goa), VOML (Mangaluru), VOCL (Kozhikode), VOCI (Kochi); imagery at ~20 m/px (10 m would be > 6 GB) + 30 m DEM; data packs per region downloaded on demand; world frame re-centred per pack or multiple TM zones with origin hand-off; same pipeline (tools/0x) parameterised by region | 3–5 weeks |
| M10 (opt) | Airliner | A320/737-class aircraft reusing the same FDM framework plus FMS-lite | large |

---

## 8a. Later additions requested
- **Session recording**: option on the start screen; records the whole flight (video + sound) to a local folder (default: game folder, user-selectable).
- **Realistic terminals** (done for VABB, VAPO, VOCI): terminal buildings that look like the real ones (CSMIA T1/T2, Pune, Navi Mumbai): glass curtain walls, roof forms, piers.
- **Airbus A320** (final stages): find an open-licence model with accurate cockpit/systems mapping (e.g. FlightGear A320-family, GPL), convert and make it compatible (JSON aircraft data, FDM, panel, sounds), credit it. Detailed plan: docs/A320-PLAN.md.

## 8b. Standing requirements (apply to everything built now and later)
- **Real sounds for every moving/working part.** No synthesized placeholders in releases. Every engine, propeller, actuator, switch, lever, gear, flap motor, trim wheel, stall horn, gyro, wind, tyre/rumble, door, ground vehicle (pushback tug, fuel truck, GPU…), ATC radio and ambient airport sound must use real recordings, layered and pitch/volume-mapped to the simulated state (RPM, load, airspeed, position). Sources: the FlightGear c172p sound set (CC0/CC-BY, credited per its `Thanks` file), Freesound CC0/CC-BY, own field recordings. Every file is listed with its licence in CREDITS.md. The procedural engine sound in `aircraft/c172/engine_sound.gd` is a stand-in until then.
- **Credits & licence compliance before any push or release:** see CREDITS.md, docs/LICENSING.md, the in-game F12 credits screen and the always-visible map attribution line.
- **Graphics as close to MSFS as possible** (phase G), with Low/Med/High/Ultra presets so integrated GPUs stay smooth.

## 9. Keeping Claude credit usage low
1. **Claude writes code and scripts; your machine does the heavy work.** Never paste DEM, imagery, OSM data, large logs or `.tscn` dumps into chat. The Python tools run locally.
2. **Do the art yourself** in Blender, GIMP and Audacity. It needs almost no tokens, and it's where most of the "looks like MSFS" feel comes from.
3. **One milestone per session.** Start with plan mode for that milestone, then `/clear` when it's done. CLAUDE.md holds the module map and conventions so every new session starts oriented without re-reading the codebase.
4. **Small files** (< 300 lines each) and the property-tree design mean each task touches 1–3 files.
5. **Use Sonnet for routine work** (UI, gauges, JSON wiring). Save Opus for the FDM, terrain LOD and tricky bugs.
6. **Data-driven tuning.** Aircraft behaviour lives in JSON you can tweak yourself, not in code changes you ask for.
7. **Give precise bug reports**: expected vs. actual, the file, and a small log excerpt. Don't say "it's broken, look around".
8. **Reuse before writing.** Try Terrain3D before a custom terrain system, use JSBSim tables rather than invented aerodynamics, and use Godot's built-in sky, audio buses and navigation.

---

## 10. Challenges & mitigations

| Challenge | Why it's hard | Mitigation |
|---|---|---|
| **Flight model fidelity** | Realism depends on correct aero coefficients, moments and damping; small sign errors make the aircraft uncontrollable | Port validated JSBSim C172 tables; build one force term at a time; compare against standalone JSBSim runs and POH numbers with automated test cards |
| **Ground handling** | Stiff springs plus a fixed timestep cause bouncing and jitter; ground friction is notoriously hard | 120 Hz with sub-steps, critically damped gear, a static-friction "stick" state at low speed, and tuning via test cards (takeoff roll, crosswind taxi) |
| **Floating-point precision** | 32-bit render transforms jitter at tens of km | Floating origin; keep FDM state in 64-bit GDScript floats |
| **Terrain LOD, seams & streaming** | Cracks between LODs, pop-in, hitches while loading | Skirts or edge stitching, geomorphing, background-thread loading, a tile cache with prefetch along the velocity vector |
| **Imagery resolution** | 10 m Sentinel looks blurry at pattern altitude; free sub-metre imagery is rare, and Google/Bing tiles are **not** allowed | Procedural detail textures, OSM-driven land classes, hand-detailed airport surroundings, haze/aerial-perspective shader to hide blur |
| **Mumbai city density** | Millions of OSM buildings mean a performance and storage blow-up | Only within ~5 km, merged per tile, height from OSM tags or random by land class, distant city as texture only |
| **Runway flattening** | The DEM is noisy (±5–10 m), so runways sit on bumps or float | Pipeline cuts a flattened, smoothed pad under each runway/taxiway polygon into the heightmap |
| **Ghats terrain** | Steep cliffs at 30 m resolution look faceted | Normal maps from the DEM, slope-based rock texture, slight bicubic upsampling |
| **Instrument realism** | Gyro, lag and pitot-static errors need proper models | Each instrument is a small model reading the property tree, with first-order lags and precession |
| **Navaid realism** | Line-of-sight, cone of confusion, ILS glideslope false lobes | Line-of-sight ray-march on the DEM at ~2 Hz, not every frame; simplified cone model |
| **Integrated-GPU performance** | Shadows, clouds, city and cockpit all compete | Strict presets, `SubViewport` gauges updated at a lower rate, impostor clouds, profile on every milestone |
| **3D art workload** | Cockpit modelling is the largest manual task | Start with a low-poly cockpit and textures, iterate. The FlightGear c172p model is GPL and OK for private local use as a reference or stand-in, but not for redistribution |
| **Licensing** | Mixed licences (ODbL, CC-BY, GPL, s2cloudless personal use) | Fine for local, personal use; keep `CREDITS.md` with attributions; revisit if you ever publish |
| **Scope creep** | Airliner, ATC and multiplayer can each double the project | Freeze the scope at M8; the rest is optional |

---

## 11. Verification (how we know it's realistic and working)

**Headless FDM test cards** (`godot --headless -s tests/run_fdm_tests.gd`), each comparing against the C172S POH or a standalone JSBSim run (±10%):
- Stall speed, clean and full flaps: 48 / 40 KIAS.
- Takeoff ground roll at sea level, standard day, max weight: ~960 ft.
- Rate of climb at Vy at sea level: ~730 fpm.
- Cruise speed at 75% power and 6,000 ft: ~120 KTAS.
- Trimmed straight and level holds altitude ±50 ft over 60 s hands-off.
- Phugoid and short-period oscillations are present and damped plausibly.
- Engine: static RPM ~2,300 at full throttle; mag-check drop 50–125 RPM.

**Performance check**: the in-game FPS/frame-time overlay must hold 60 FPS (Low preset, 720p) on the laptop during a low pass over Mumbai city, the worst case.

**Manual flight tests every milestone**:
- Juhu circuit.
- ILS 27 approach into Mumbai.
- VAJJ→VAPO cross-country over the Ghats on VOR navigation.
- Crosswind landing at 15 kt.
- Engine-out glide: best glide 68 KIAS, ~9:1 ratio.
- Vacuum failure on instruments.

**Data check**: runway thresholds sit within ~10 m of the OurAirports coordinates, and the ILS localizer lines up with the runway centreline.

---

## 12. Immediate next steps after approval
1. Create `libresim/` with the folder skeleton, `CLAUDE.md` and `tools/01_fetch_notes.md`. The fetch notes list exact download pages for Copernicus DEM, s2cloudless, Geofabrik, OurAirports and JSBSim c172p.
2. Install Godot 4 (latest stable), Blender, QGIS/GDAL, Python 3 plus rasterio/numpy/osmium, and JSBSim (pip `jsbsim`).
3. Start M1 (data pipeline) in a fresh session.
