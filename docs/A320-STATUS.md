# A320-family twin-jet: current state

Last updated 2026-10-29. Everything described here is committed. The plan and the phase table are in `docs/A320-PLAN.md`; contracts (aircraft.json sections, props, display schema, FBW parameters) are in `docs/USAGE.md` and are not repeated here.

**One line:** the A320 is selectable on the start screen and flyable from a gate, a runway or the air, with fly-by-wire, FADEC turbofans, airliner systems, glass displays, a real model and cockpit, sounds, jetway docking and icing. It is the newer and cruder of the two aircraft: no managed route, a lite MCDU, sounds not tuned by ear. It is not validated against real-aircraft data, only against the JSBSim A320 data it was converted from.

## 1. What works

| Area | State |
|---|---|
| Selection | `game/aircraft/a320/aircraft.json` (UI name "A320-family twin-jet airliner" plus non-affiliation note). Start screen aircraft page: specs, kg payload sliders (total fuel, cabin, cargo), W&B chart (kg and % MAC, approximate), stand and runway suitability (gate stands, 1,800 m). `--aircraft=a320` on the command line. Training lessons are C172 only (a lesson started with the A320 selected switches to the C172). |
| Start modes | Runway: engines running. Stand: cold and dark (batteries on, engines off). Air: stabilised-approach start from the aircraft's own `start.air` (3,500 ft above the field, 11 nm out, 205 KIAS, gear up, flaps 0; `--air=<ft>` keeps the distance and speed; the pilot's own numbers are kept and clamped, `Session.apply_air_defaults`). Payload defaults per aircraft (`Session.apply_payload_defaults`). |
| FDM | JSBSim A320-200 CFM56-5B4 data converted to JSON (`aero.json`, `config.json`): 3-D aero tables, retractable gear with bogies, nose steering (tiller and pedals), brakes with anti-skid and autobrake, slats and flaps with detents, 5+5 spoiler panels, speedbrake, trimmable stabiliser, FADEC turbofans (thrust, N1, N2, EGT, fuel flow, reverse, start sequence), APU model. Cold start from the gate: `controls/engine_mode` = 2 plus `controls/engine_master_<n>`; light-off at about 25 s, idle N1 19 % / N2 59 % at about 45 s (starter air from the batteries; no bleed or APU air). |
| Fly-by-wire | Hand-written `FbwLaw` (`fdm/fbw_*.gd`): normal, alternate and direct laws with reversion from failures, load-factor pitch law with auto-trim, roll-rate law with bank hold, yaw damper, flare mode, and the alpha, high-speed, bank, pitch and load-factor protections. Autopilot interface: with `ap/cmd/active` the law takes `ap/cmd/nz_g` and `ap/cmd/roll_rate_dps`; a sidestick push takes over. 22 FBW tests. |
| Systems | `AircraftSystems` factory with the `airliner` profile: electrical, hydraulics, fuel (kg, transfer), lights, warnings, cabin, APU. Failures list for the airliner. Wing and engine anti-ice from engine bleed (costs thrust), automatic probe heat. |
| Autoflight | `Autoflight` with FCU modes (HDG, ALT, V/S, SPD/MACH, LOC, APPR with the existing ILS), AP1/2, A/THR, FD, alpha floor. |
| Displays | PFD, ND (ARC and ROSE), E/WD, SD (ENG, FUEL, WHEEL, F/CTL), FCU and a lite MCDU, drawn in code from Props on the 3D panel and as HUD cards in the chase view; clickable. Own drawing with Godot's default font. |
| Model | Exterior and flight-deck glb converted from the upstream models with Blender (`tools/blender/`): 71.9k and 94.6k triangles. White livery, deep-blue fin, light-grey radome, registration painted on both sides from the call sign (VT-ZZA by default, `--callsign=`). Moving gear (leg pivots lowered by spring compression so tyres stand on the ground, within +-1.5 cm at VABB and VAPO), doors, slats, flaps, spoilers, reversers, stabiliser, nose steering, wheel spin, fans from N1. Lights: nav, beacons, strobes, landing and taxi lamps. Cameras: chase, orbit, wing, tail, cockpit. |
| Cockpit levers | In the cockpit view 39 pivots of `interior.glb` move (`cockpit.levers`, `CockpitLevers`): thrust levers with reverser flaps, both sidesticks and boots, speedbrake, flaps, gear, parking brake, engine masters and mode, rudder trim, pitch trim wheel, tillers, four pedals. Lever positions are the commanded ones, not the A/THR ones. |
| Sounds | `game/aircraft/a320/sounds/`: CC0 and CC-BY recordings only (engine idle / power / whine / start / shutdown, reverse, packs, hydraulic pump, gear motion, chime), driven by the data layer engine (`common/audio_layers.gd`), plus C172-pack files listed by path. Sources and licences: `sounds/SOURCES.md`, audited by `tools/25_a320_sounds.py`. |
| Ground ops | Pushback tug (scaled), follow-me, taxi route with taxi width and 30 kt limit, hold-short and gap values, service vehicles at the door and bays, stand class and `min_runway_m` filtering (VABB, VAPO, VOCI qualify). Airline ATC profile (phraseology, fictional telephony "Skyline", no SID/STAR). Checklists (cockpit prep to parking), callouts (V1, rotate, 100 kt, retard, minimums). |
| Jetway docking | `world/jetway_docks.gd` picks the jetway whose cab end is nearest the L1 door (`GroundParams.door_tip`), `world/jetway_rig.gd` stretches the tunnel, turns the cab to face the fuselage and tilts the bridge so the cab floor meets the sill; docks in 6 s when parked within 3 m of the gate, retracts when the aircraft leaves, not solid while extended. Without an aircraft (or a C172, which has no `door_height_m`) every jetway keeps its legacy layout (`JetwayPose.rest`). Measured against the L1 door at VOCI gate 2, VABB V17 and V27, VAPO 1, VOML 5: 0.08-0.17 m longitudinal, 0.11-0.17 m lateral error (target 0.15 m outside the skin). |
| Weather | Cloud physics, turbulence, thermals and storm cells act on the A320 like on the C172. Icing: the airframe, pitot, static and inlets accrete ice in cloud between about +2 and -20 C (in the tropics roughly FL150-FL250); effects and protection are data (`aircraft.json` `icing`); see USAGE "Icing and rain". |
| Replay and saves | Generic replay channels and situation saves include the A320's engines, FCS, gear, APU, hydraulics and autoflight (`save_key / save_state / load_state` rule). |

Keys: the A320 control set (J shows it); F1 help card. Icing switches: Ctrl+W wing, Alt+E / Alt+D engine 1 / 2 anti-ice.

## 2. Crude or missing

- **Avionics:** no FMGC route or managed profile, no ND VOR / ILS / PLAN modes, schematic F/CTL page, MCDU is INIT / F-PLN / PERF only, default font on the displays. No bleed or pack model, no APU start sequence on the overhead panel (the APU model exists: `controls/apu_master`, `controls/apu_start`). `controls/seatbelt_sign` is not published.
- **Sounds:** the engine layers are cuts of a Saab Draken turbojet recording standing in for a turbofan; the APU layers reuse them pitched up; the takeoff roar is the Draken power cut. No stall, autopilot-disconnect or GPWS sounds. Nobody has tuned the curves by ear. Better Freesound recordings (listed in `sounds/SOURCES.md` with licences) need a Freesound API key to download.
- **Model and cockpit:** flat shading, cabin interior not modelled, the autobrake buttons and lights, overhead and glareshield switches and knobs, the A/THR disconnect button, the cockpit door switch and the pull-to-adjust motion of the parking-brake and cut-off levers are static. Upstream's `Support` pole sticks 3 m above the jetway tunnel. The fly-by camera is the shared one (250 m ahead, 25 m off): small for an airliner.
- **Jetway docking:** the cab is a rigid glb, so its hood edges stand about 0.5 m off the curved skin. 20 VABB jetway ways are longer than 70 m (beyond the tunnel range) and gates whose OSM way is on the aircraft's right side do not dock (about 12 at VABB): they keep the jetway at rest. No docking at stands with no jetway within 26 m.
- **FDM:**
  - The upstream FDE puts the engine thrust points at y +-2.8775 m, while the model fans are at +-5.63 m. Kept as is to match JSBSim (the oracle); the thrust line is correct, the visual is not.
  - The takeoff roll is consistent with JSBSim (70 t, TOGA, flaps 1+F: liftoff after 1,125 m at 153 kt, 35 ft at 1,393 m) but about 30 % shorter than the public 1,800-2,200 m figure.
  - JSBSim stall speed is about 10-12 % above the FMGC table (aerodynamic 1 g speed at alpha-max 173.7 kt clean / 119.7 kt FULL at 64 t, against table Vs1g 155.4 / 109.2 kt); Vref (1.23 x table Vs1g) is 134.3 kt, close to the public ~135 kt.
  - FBW pitch is faster than the reference (63 % of a load-factor step in about 1 s against 1.9 s: the reference g-law PI is a stand-in). Landing, flare and the protections are tested but little hand-flown. The protections keep their clean alpha limits when the airframe is iced.
  - Engine feed from the pipe tanks, bleed, oil and fire systems are not modelled (`fuel.gd` feeds all main tanks equally).
- **Other:** training lessons are C172 only; ATC has no SID/STAR, speed instructions or wake separation; no neo or IAE variants.
- **P10 (packaging as a separate, withdrawable A320 pack) is not started.** `tools/package/make_release.sh` packages the whole game.

## 3. Licence decisions and exclusions

Details: `docs/LICENSING.md`, `third_party/a320-family/SOURCE.md`, `CREDITS.md`.

- Source: FlightGear "A320-family" (legoboyvdlp/A320-family, branch `dev`), pinned commit `fec1ecba767c8fffd145337b27012e89c01e3ade`. The licence is **GPL-2.0 only** (no "or later"). The A320 data, converted files and models live in `third_party/a320-family/` and `game/aircraft/a320/` with the upstream notices, licence text and a dated change log; a distribution that includes them is GPL-2.0 as a whole (libresim's own code is GPL-2.0-or-later, which can be combined).
- **Used:** the JSBSim FDE, engine and system XML (as data); the 3D models and textures, recoloured and converted (white livery, no logos).
- **Not used, not fetched, not shipped:** all upstream sounds, all fonts (the ECAM font comes from FlyByWire), the Nasal / Canvas / WebPanel code (the displays and autoflight are written from public behaviour, not ported), FlyByWire A32NX material, real airline liveries and logos, navdata. Our sounds are CC0 / CC-BY only, per file in `sounds/SOURCES.md`.
- **Provenance:** the project owner decided not to ask upstream about the origin of the models (the base aircraft is Immersive Design Group's A32X, whose own repository has no licence statement). We rely on the published GPL-2.0 and comply with it fully. **Residual risk:** that model provenance. Blender edits were for quality, polygon budget and trademark reasons, never to disguise the source.
- **Mitigation:** everything about the A320 is `aircraft.json` data, so the pack can be separated and withdrawn and the model replaced by an own generic twin-jet without code changes (plan: P10, plus P8 path B). A separate pack does not remove the GPL-2.0 obligation, it only isolates it.
- **Trademarks:** "Airbus" and "A320" are Airbus trademarks; the UI says "A320-family twin-jet airliner" with a non-affiliation disclaimer.

## 4. How to test by hand

Godot is `~/.local/bin/godot` (`G` below). Always add `--audio-driver Dummy` to a windowed run. Command-line flights, `--shot` and probe scenes never write the player's `last_flight.json`, `training.json`, `ui.cfg`, `options.cfg`, `graphics.cfg` or `audio.cfg` (`Session.interactive()`, `core/save_guard.gd`; `FREESIM_NO_SAVE=1` forces it).

```
G=~/.local/bin/godot
./run.sh --a320                                   # also fetch the A320 data (step 06a), then launch the game
$G --path game --audio-driver Dummy -- --aircraft=a320 --airport=VABB --stand       # gate, cold and dark
$G --path game --audio-driver Dummy -- --aircraft=a320 --airport=VABB               # runway, engines running
$G --path game --audio-driver Dummy -- --aircraft=a320 --airport=VABB --air         # the A320's own air start (--air=8000 for another height)
$G --path game --audio-driver Dummy -- --aircraft=a320 --menu                       # start screen with the A320 chosen
$G --headless --path game res://tests/run_tests.tscn -- --suite=a320_integration    # also --suite=fbw, --suite=a320, --suite=jetway
```

Run test suites in the background with the output in a file (a script parse error makes `run_tests.gd` hang; run `$G --headless --path game --import 2>&1 | grep -i error` first; macOS has no `timeout`).

Probes (scenes in `game/tests/`, usage in each header and in USAGE "Aircraft data: model, cockpit, lights, audio"):

| Probe | What it does |
|---|---|
| `debug_a320_look.tscn` | Screenshots from camera modes or free points (`--views`, `--lights`, `--jetway` prints the DOCK lines: gap of the hood face and cab floor to the L1 door). Needs `--shots=<absolute dir>`, windowed. |
| `debug_levers.tscn` | Cockpit levers: sets props, saves a screenshot per view (`--views="name\|prop=value\|eye\|target"`). |
| `debug_air_start.tscn` | The default air start, hands off: height, distance, speed, gear, flaps at the start and after 30 s (headless OK: `-- --airport=VABB --runway=27 --air --aircraft=a320`). |
| `debug_jetway.tscn` | Cab end of the nearest jetway and frame-to-frame flicker (`-- --airport=VABB --stand --shots=<dir>`). |
| `debug_displays.tscn` | Renders PFD, ND, E/WD, SD pages and MCDU for fixed states to `$FREESIM_SHOTS`. |
| `debug_a320_takeoff.tscn` | Scripted takeoff or cold start through the Props (roll, liftoff speed, climb). |
| `debug_tyres.tscn` | Gap of each tyre to the terrain (`--stand --at=60 --shots=<dir>`, windowed). |
| `debug_a320_model.tscn` | Model screenshots and pivot / triangle check (`--out=<dir> --pose=clean\|down\|spoil`). |

Reference runs: `tools/.venv/bin/python tools/23_a320_reference.py` (JSBSim oracle, a few minutes; the first run builds `data/raw/fg/a320_root`), `--only trim,stall,takeoff,climb,steps,thrust` selects parts. Output `tools/a320_reference.json` and `tools/ref/a320_*.csv`.

Measured in the real scene (VABB, 64 t, FBW normal law): hands-off from an air start (250 KIAS, 4,000 ft) 60 s with roll within 0.05 deg, heading +-0.2 deg, altitude +6 ft, speed 249-251 kt; scripted takeoff (TOGA, flaps 1+F, trim 0.15, rotate at 142 kt to 12 deg): liftoff after 36 s, roll 1,018 m at 155 kt, 5,000 ft/min initial climb.

## 5. Reference numbers (JSBSim A320-200 CFM, `tools/a320_reference.json`)

- Wing 122.6 m2, span 35.74 m, chord 7.68 m; empty 43.28 t; ground footprint 37.6 x 34.1 x 11.8 m; engine thrust 120.1 kN (JSBSim milthrust; static TOGA at sea level 113.6-116.8 kN); idle N1 18.9 %, N2 59.4 %.
- Approach, CONF FULL, 64 t, 3 deg glide: 135 KCAS, alpha 7.0 deg, pitch 4.1 deg, N1 52.8 %, 2,247 kg/h per engine. FMGC table at 64 t: Vs1g 155.4 clean / 109.2 FULL, Vls 123.5 and Vsw 120.1 FULL.
- Cruise fuel flow M0.78 FL350 64 t: 1,188 kg/h per engine (public 1,200-1,300). Initial climb 70 t, TOGA, CONF 1: 3,207 fpm; one engine out 584 fpm (3.67 %).
- Rejected takeoff from 140 kt, brakes only, no reversers: 923 m after the reject.
- Flaps: 0 0/0, 1 18/0, 1+F 18/10, 2 22/15, 3 22/20, FULL 27/35 (slat / flap deg); stabiliser clip -13.5..+4 deg at 0.25 deg/s; spoilers 50 deg.
- FBW tuning (`tests/test_fbw_a320*.gd`): roll rate 7.4 / 15.3 deg/s for half / full stick (reference 7.35 / 15.0), alpha limits from the JSBSim tables (alpha-prot 8.6, alpha-max 11.56 clean), pitch loop faster than the reference.
- Ground values (`aircraft.json` `ground`): `cg_to_door_m` 11.3 (door L1 centre x -13.78, y -1.95, sill z -0.58 vs CG x -2.5), `door_height_m` 3.65, `nose_gear_m` 11.1, `tow_ahead_m` 16.3, `taxi_half_m` 22, `min_runway_m` 1,800. Static gear deflection 0.30 m mains / 0.13 m nose at 64 t; tyre radii 0.40 / 0.57 m; the glb wheels are at y +-3.87 m, the FDE gear contacts at +-4.326 m (upstream data, kept).

## 6. Data pipeline

Run order and options: USAGE section 3 ("A320 data", "A320 model"). Untrusted fetched data is only decoded, never executed; nothing in `data/` is read into context.

| Tool | Produces |
|---|---|
| `tools/22_a320_fetch.sh` | Sparse clone of `FDE/ Engines/ Systems/` and top-level files at the pinned commit into `data/raw/fg/a320` (about 2.5 MB; `--force` re-fetches). Run by `./run.sh --a320`. |
| `tools/06_jsbsim_to_json.py a320` (with `jsb_a320.py`, `jsb_turbine.py`, `jsb_expr.py`; tests `tools/test_jsb_convert.py`) | `game/aircraft/a320/{config,aero}.json` (committed; the C172 json stays byte-identical). Format notes: `tools/A320_DATA_NOTES.md`. |
| `tools/23_a320_reference.py` (with `jsb_a320_root.py`, `jsb_a320_sim.py`, `a320_ref_*.py`) | JSBSim oracle run headless: `tools/a320_reference.json`, `tools/ref/*.csv`. `tools/a320_spike/` holds the early spike scripts. |
| `tools/24_a320_models_fetch.sh` | Adds `Models/` (about 87 MB) to the clone. |
| `tools/24_a320_textures.py` | Cleaned textures (white livery, no registration or logos) into `data/processed/a320/tex`. |
| `tools/blender/convert_a320.py`, `convert_a320_cockpit.py` (Blender 5, headless, `/Applications/Blender.app`) | `models/exterior.glb`, `interior.glb` and the pivot / info json. |
| `tools/24_a320_sections.py` | Draft `model_sections.json` (model, cockpit, lights, registration, cameras) that was pasted into `aircraft.json`. |
| `tools/25_a320_sounds.py` (`--fetch`, `--build`, default audit) | The files in `game/aircraft/a320/sounds/` and `manifest.json`; the audit checks hashes, loop seams and `SOURCES.md`. |

## 7. Where the docs are

- `docs/USAGE.md`: section 3 "A320 data" and "A320 model" (pipeline); "Adding an aircraft" and "Aircraft data: limits, systems, payload / FDM props / flight control law / replay / saved flights / model, cockpit, lights, audio / displays" (all contracts and props); "Icing and rain"; "Airport operations" (jetway docking); "Automated tests".
- `docs/A320-PLAN.md`: scope, phases, licence verdict, risks. `tools/A320_DATA_NOTES.md`: what the converter takes and what the JSBSim systems do.
- `docs/LICENSING.md`, `third_party/a320-family/SOURCE.md`, `CREDITS.md`, `game/aircraft/a320/sounds/SOURCES.md`: licences and credits.
- `docs/ATC.md`: the airline ATC profile.
