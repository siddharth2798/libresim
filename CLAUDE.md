# libresim — Claude guide
Local desktop C172 flight sim, Mumbai–Pune region, Godot 4 (Mobile renderer), GDScript. Full plan: PLAN.md.

## Conventions
- Files < 300 lines, one responsibility each. snake_case files/functions, PascalCase class_name.
- SI units internally (m, s, kg, rad, Pa). Convert only at instruments/UI (units.gd).
- World frame: local ENU metres, origin 18.75N 73.40E. Data projection = local TM centred there (tools/common.py WORLD_PROJ), so projected metres == ENU. Render = Vector3(e-ox, up, -(n-oy)) via FloatingOrigin autoload (shifts every 5 km).
- FDM at fixed 120 Hz in _physics_process; rendering interpolates. All sim state lives in the property tree (e.g. /fdm/ias_mps, /systems/electrical/bus_volts); modules talk only via properties.
- Aircraft behaviour is data (game/aircraft/<id>/*.json, read through AircraftDef), not code.
- Heavy data work = Python in tools/, run locally. Never read files in data/ into context.

## Layout
tools/ offline pipeline · data/raw, data/processed (gitignored) · game/{core,fdm,systems,avionics,instruments,world,aircraft,input,ui,atc,tests}
Aircraft are folders under game/aircraft/<id>/ (aircraft.json, config.json, aero.json, ...) read through AircraftDef; generic aircraft code is in game/aircraft/common/ (docs/USAGE.md, "Adding an aircraft").

## Status
Done (details in docs/USAGE.md, plans in docs/):
- Pipeline tools/0*.py (run order in docs/USAGE.md), region packs (tools/01d, regions.py, osm_regions.py, meta_*.json; Mumbai–Pune plus the konkan_kerala corridor), OSM roads/rivers (tools/20: 4 m SDF tiles; tools/21: shore foam, depth colour; 13 new airfields in the corridor), WorldCover land classes (tools/19, terrain/wc, per-class ground shader), 3D OSM buildings (tools/10), outer ring (tools/12), simulated ILS (tools/14_ils.py), terminals (tools/15-16, terminal_*.py, world/terminals.gd, docs/TERMINALS.md), terrain textures (tools/26-27), jetways (tools/jetway_net.py), branding (tools/branding/make_logo.py), packaging (tools/package/make_release.sh, packaging/), e2e sweep (tools/e2e.sh), `./run.sh`.
- Sim: terrain viewer (game/world), FDM (game/fdm, tests/test_fdm_cards.gd), c172p model and cockpit (tools/blender), 8 cameras, credits/GPL screen, instruments, systems, failures (systems/failure_*.gd, F9), radios (game/avionics: VOR/ILS/DME/ADF, GPS, moving map), damage model, weather/night/moon, save/load (core/situation*.gd), replay (systems/replay*.gd), session recording (ui/session_recorder.gd, core/mkv_writer.gd, F8), joystick/gamepad and keyboard rebinding, audio/options.
- World: airport stands, taxi and follow-me, pushback, vehicles and ramp crew (world/ramp_*.gd), jetways (world/jetway_*.gd), apron floodlights (world/apron_*.gd), airport lighting, tyre contact (docs/TYRE-CONTACT-PLAN.md), aircraft lights (aircraft_lights.gd, light_parts.gd).
- Graphics G0–G6 (docs/GRAPHICS-PLAN.md): bench (tools/bench.sh), Max preset, Forward+ on High+, AgX, post effects (core/post_fx*.gd, world/postfx/), clouds, water, horizon curvature and haze LUT, volumetric fog (world/vfog_*.gd).
- UI: home (Free flight | Training), start flow with rail and footer chips, Fly anyway confirm (core/setup_checks.gd), airport search and map, wind dial, Options/Controls tabs, UI scale 100-200 % (tests/debug_ui_walk.tscn), in-flight notifications, optional callouts (K), touchdown smoke/marks, fly-by placement (ui/flyby_placement.gd). Plan: docs/UI-IMPLEMENTATION-PLAN.md.
- Training mode (game/training: lessons.json, logic, markers, hud, session; ui/menu/training_page.gd). ATC A1 (game/atc: stateful controller, monitor, phraseology.json, panel; silent in lessons; docs/ATC.md). Stands, ATC text and checklists.
- A320: thrust at the fans, rudder x3 (docs/A320-STATUS.md).
- Game is named libresim; legacy user data is migrated (core/legacy_migrate.gd). Brand: runway "09/27" mark, Fira Sans wordmark (game/branding, one brand, no variants).
- Docs: FDM vs JSBSim in docs/FDM-VS-FLIGHTGEAR.md.

Next: finish the e2e re-run; ATC A2 (circuit traffic) and A3 (Piper voice, real radio sounds); radio UI = slim bar top-left + message card + short call list + History + radio assist option (docs/ATC.md "The radio on screen"); graphics G7–G10 (docs/GRAPHICS-PLAN.md); dawn mist and light shafts (G5 notes). A320 is paused (docs/A320-PLAN.md; cockpit buttons paused; body and flight-deck finish in docs/A320-FINISH-PLAN.md).

Standing reqs: PLAN.md §8b.

Tests: `godot --headless --path game res://tests/run_tests.tscn`.
Godot 4.7.2 at ~/.local/bin/godot (not on PATH). Python: tools/.venv. Keep docs/USAGE.md updated each milestone.
