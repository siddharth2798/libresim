# free-sim — Claude guide
Local desktop C172 flight sim, Mumbai–Pune region, Godot 4 (Mobile renderer), GDScript. Full plan: PLAN.md.

## Conventions
- Files < 300 lines, one responsibility each. snake_case files/functions, PascalCase class_name.
- SI units internally (m, s, kg, rad, Pa). Convert only at instruments/UI (units.gd).
- World frame: local ENU metres, origin 18.75N 73.40E; data projection EPSG:32643. Floating origin shifts every 5 km.
- FDM at fixed 120 Hz in _physics_process; rendering interpolates. All sim state lives in the property tree (e.g. /fdm/ias_mps, /systems/electrical/bus_volts); modules talk only via properties.
- Aircraft behaviour is data (game/aircraft/c172/*.json), not code.
- Heavy data work = Python in tools/, run locally. Never read files in data/ into context.

## Layout
tools/ offline pipeline · data/raw, data/processed (gitignored) · game/{core,fdm,systems,avionics,instruments,world,aircraft,input,ui,atc,tests}

## Status
M0 setup done. Next: M1 data pipeline (tools/02–06).
