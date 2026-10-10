# Credits and thanks

free-sim stands on the shoulders of many open-source projects and open-data providers. Thank you to all of them. This page is also shown in the sim (press **F12**).

free-sim itself is licensed under **GPL-2.0-or-later** (see `LICENSE`). Licence details and release obligations are in `docs/LICENSING.md`.

---

## Included in free-sim

### Aircraft
- **Cessna 172P 3D model, cockpit interior, yoke, pedals and textures:**
  - Source: the FlightGear c172p project, https://github.com/c172p-team/c172p (tag `version/2024.1.3`). Licence: GPL-2.0-or-later.
  - Authors: originally by David Megginson; maintained by the c172p team: Gilberto Agostinho, Wayne Bragg, Juan Vera del Campo, onox, Fernando Barbosa, Daniel Dubreuil, Jonathan Redpath, Jonathan Schellhase, Tuomas Kuosmanen, Anders Gidenstam, Waldo Kitty, algefaen, Horacio, D-ECHO, Jarl Arntzen, Benedikt Hallinger, Sascha Reißner, Josh Davidson and others.
  - free-sim converted these to glTF and modified them; the unmodified source is in `third_party/c172p/`.
- **Propeller blade model:** Syd Adams and Heiko Schulz (c182s project), GPL-2.0, via the c172p team.
- **Flight-model data:** JSBSim `c172p` aircraft, `engIO360C` engine and `prop_75in2f` propeller, by the JSBSim Team and contributors (https://github.com/JSBSim-Team/jsbsim), LGPL-2.1. free-sim converted them to JSON and retuned them (`tools/06_jsbsim_to_json.py`).

### Sounds
All sounds are real recordings, listed file by file in `game/aircraft/c172/sounds/SOURCES.md`:
- **C172 engine** (start, crank, idle, run, cut): "small plane cessna engine start idle and takeoff" by **JLWSound** (freesound.org/s/322321), CC0, via the c172p team.
- **Stall horn:** from "Stalling and spinning with a Cessna 152" by **Morsule**, CC-BY.
- **Gyro spin:** from "Starting C172N" by **algefaen**, CC-BY.
- **Parking brake lever:** "Old Lever Pull" by **DrMinky**, CC0.
- **Trim wheel:** "rubber.wav" by **datasoundsample**, CC0.
- **Primer:** by **coltures**, CC0.
- **Flap motor, tyres, switches and doors:** c172p team, GPL-2.0-or-later.
- **Wind, rumble, squeal, rain, avionics fan:** FlightGear fgdata contributors (https://gitlab.com/flightgear/fgdata), GPL-2.0-or-later.

### Engine (runtime)
- **Godot Engine 4.7** (https://godotengine.org), MIT licence, © Juan Linietsky, Ariel Manzur and Godot Engine contributors. Godot bundles third-party components (FreeType, HarfBuzz, Vulkan loader, fonts and others); their licences are listed in full on the in-game credits screen (taken from the engine itself).

### Map data
- **Satellite imagery:** Sentinel-2 cloudless, https://s2maps.eu, by EOX IT Services GmbH (contains modified Copernicus Sentinel data 2024). Licence: **CC BY-NC-SA 4.0**. free-sim's imagery tiles are derived from it and carry the same licence.
- **Elevation:** Copernicus GLO-30 DEM © DLR e.V. 2010–2014 and © Airbus Defence and Space GmbH 2014–2018, provided under COPERNICUS by the European Union and ESA. Free licence with attribution.
- **Map features** (runways, taxiways, roads, buildings, water): © OpenStreetMap contributors, available under the Open Database Licence (ODbL 1.0), https://www.openstreetmap.org/copyright.
- **Airports, runways, frequencies and navaids:** OurAirports (https://ourairports.com), public domain.

## Tools used to build free-sim (not shipped in the game)
- **GDAL/OGR** (MIT) and **PROJ** (MIT): reprojection and tiling.
- **Python** (PSF): the data pipeline. Libraries:
  - NumPy (BSD-3)
  - pyosmium / libosmium (BSD-2 / BSL-1.0)
  - JSBSim Python bindings (LGPL-2.1), used for reference runs
  - Matplotlib (PSF-style), for previews
  - Pillow (MIT-CMU), for image checks
- **Blender 4.0** (GPL) and the **Blender AC3D importer** by Nikolai V. Chr. and contributors (https://github.com/NikolaiVChr/Blender-AC3D, GPL-2.0-or-later): model conversion.
- **Geofabrik** (https://download.geofabrik.de): OpenStreetMap extracts.
- **AWS Open Data** (Copernicus DEM bucket) and the **EOX WMTS** service: data hosting.

## Inspiration (ideas only; no code or assets taken)
- **FlightGear** (https://www.flightgear.org), the open-source flight simulator. Its property tree, aircraft-as-data approach and c172p team's realism inspired our design. Research notes are in `docs/FLIGHTGEAR_NOTES.md`.
- **JSBSim**: its function and table format for aerodynamics is mirrored in `game/fdm/aero.gd`.
- **Real Flight Simulator (RORTOS)** and **Microsoft Flight Simulator (Asobo / Microsoft)**: feature and visual-quality benchmarks. Their names are trademarks of their owners. free-sim is not affiliated with them and uses none of their content.
- **The Cessna 172S Pilot's Operating Handbook** (Textron Aviation): published performance figures used as test targets. "Cessna" and "Skyhawk" are trademarks of Textron Aviation Inc.; free-sim is not affiliated with or endorsed by Textron.
