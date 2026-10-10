# free-sim — Claude guide
Local desktop C172 flight sim, Mumbai–Pune region, Godot 4 (Mobile renderer), GDScript. Full plan: PLAN.md.

## Conventions
- Files < 300 lines, one responsibility each. snake_case files/functions, PascalCase class_name.
- SI units internally (m, s, kg, rad, Pa). Convert only at instruments/UI (units.gd).
- World frame: local ENU metres, origin 18.75N 73.40E. Data projection = local TM centred there (tools/common.py WORLD_PROJ), so projected metres == ENU. Render = Vector3(e-ox, up, -(n-oy)) via FloatingOrigin autoload (shifts every 5 km).
- FDM at fixed 120 Hz in _physics_process; rendering interpolates. All sim state lives in the property tree (e.g. /fdm/ias_mps, /systems/electrical/bus_volts); modules talk only via properties.
- Aircraft behaviour is data (game/aircraft/c172/*.json), not code.
- Heavy data work = Python in tools/, run locally. Never read files in data/ into context.

## Layout
tools/ offline pipeline · data/raw, data/processed (gitignored) · game/{core,fdm,systems,avionics,instruments,world,aircraft,input,ui,atc,tests}

## Status
M0, M1 done (pipeline: tools/0*.py, run order in docs/USAGE.md). M2 terrain viewer done (game/world, tests/run_tests.gd). M3 FDM done (game/fdm, tests/test_fdm_cards.gd all pass). M4 first flight, M5 instruments+placeholder cockpit done. Tests: godot --headless --path game res://tests/run_tests.tscn. M6 done. Real c172p model+cockpit (tools/blender), 8 cameras, credits/GPL done, 3D OSM buildings (tools/10). G done (clouds/water/trees/presets/panel layouts). Damage model done (tests/test_landing.gd). Outer ring (tools/12). Phase A done (stands, taxi + follow-me, pushback, vehicles, jetways, ATC text, checklists). P packaging done (tools/package/make_release.sh, packaging/). M7 radios done (game/avionics: VOR/ILS/DME/ADF, GPS, moving map N; tools/14_ils.py simulated ILS). M7b start screen (ui/menu, core/session.gd autoload) + failures (systems/failure_*.gd, F9) done. Next: session recording, realistic terminals, M8 polish, R (Mumbai-Kochi). Standing reqs: PLAN.md §8b.
Godot 4.7.2 at ~/.local/bin/godot (not on PATH). Python: tools/.venv. Keep docs/USAGE.md updated each milestone.
