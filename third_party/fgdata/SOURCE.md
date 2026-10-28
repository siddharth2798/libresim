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
Each model is converted by `blender -b --factory-startup --python tools/blender/convert_ac.py -- <file.ac> <out.glb>`, which imports the model, flattens the hierarchy and exports glTF. No geometry is changed.

The pushback tug, fire truck and bus originals were removed (2026-10-28): libresim now builds every ground vehicle in code.
