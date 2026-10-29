# FlightGear fgdata: corresponding source (GPL-2.0)

These are the **unmodified original files** from FlightGear's base data package, converted by libresim into `game/world/models/vehicles/jetway.glb`.

- **Upstream:** https://gitlab.com/flightgear/fgdata, branch `release/2024.1`
- **Licence:** GPL-2.0 (see `COPYING`). © FlightGear contributors.

## Files and their converted forms

| Original | Converted to | Object |
|---|---|---|
| `Airport/Jetway/generic.ac` and `.png` | `jetway.glb` | Generic jetway |

The aircraft sounds taken from fgdata (wind, rumble, squeal, rain, avionics fan) are listed in `game/aircraft/c172/sounds/SOURCES.md`; the original WAV files are the shipped files themselves.

## Conversion
Each model is converted by `blender -b --factory-startup --python tools/blender/convert_ac.py -- <file.ac> <out.glb>`, which imports the model, flattens the hierarchy and exports glTF.

**Modification (2026-10-29, GPL-2.0 notice):** `jetway.glb` was then post-processed with `tools/.venv/bin/python tools/blender/separate_coplanar_glb.py game/world/models/vehicles/jetway.glb --eps 0.02`. The cab's back wall and its door (`Entrance` mesh) lie in one plane, back to back, and the model's material is double sided, so both surfaces were drawn at the same depth and flickered (z-fighting) as the view changed. The tool moves 37 triangles by 2 cm (or a multiple of it) along their own normals so that no two faces coincide; nothing else is changed. Run it again after any re-conversion; it is idempotent. `tests/test_vehicles.gd` fails if coincident faces come back.

The pushback tug, fire truck and bus originals were removed (2026-10-28): libresim now builds every ground vehicle in code.

**Runtime use (2026-10-29):** the game moves the model's named parts at run time (`world/jetway_rig.gd`: the `Tunnel1-4` and `Scissors` meshes are stretched along x, `Rotunda2`, `Support`, `SupportGirder` and the cab meshes `Hood`, `Entrance`, `GateSign` are translated or turned) so that the cab meets an aircraft's door; the glb file itself is not modified by this.
