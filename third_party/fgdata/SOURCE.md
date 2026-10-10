# FlightGear fgdata: corresponding source (GPL-2.0)

These are the **unmodified original files** from FlightGear's base data package, converted by free-sim into `game/world/models/vehicles/*.glb`.

- **Upstream:** https://gitlab.com/flightgear/fgdata, branch `release/2024.1`
- **Licence:** GPL-2.0 (see `COPYING`). © FlightGear contributors.

## Files and their converted forms

| Original | Converted to | Object |
|---|---|---|
| `Airport/Pushback/Goldhofert.ac` and `.png` | `pushback_tug.glb` | Goldhofer towbarless pushback tug |
| `Airport/Vehicle/hoskosh-ti-1500.ac` and `.png` | `fire_truck.glb` | Oshkosh TI-1500 airport fire truck |
| `Airport/Jetway/generic.ac` and `.png` | `jetway.glb` | Generic jetway |
| `Transport/110Bus.ac` and `.png` | `apron_bus.glb` | Bus, used as an apron bus |

The aircraft sounds taken from fgdata (wind, rumble, squeal, rain, avionics fan) are listed in `game/aircraft/c172/sounds/SOURCES.md`; the original WAV files are the shipped files themselves.

## Conversion
Each model is converted by `blender -b --factory-startup --python tools/blender/convert_ac.py -- <file.ac> <out.glb>`, which imports the model, flattens the hierarchy and exports glTF. No geometry is changed.
