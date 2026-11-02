# Credits and thanks

libresim stands on the shoulders of many open-source projects and open-data providers. Thank you to all of them. This page is also shown in the sim (press **F12**).

libresim itself is licensed under **GPL-2.0-or-later** (see `LICENSE`). Licence details and release obligations are in `docs/LICENSING.md`.

---

## Included in libresim

### Aircraft
- **Cessna 172P 3D model, cockpit interior, yoke, pedals and textures:**
  - Source: the FlightGear c172p project, https://github.com/c172p-team/c172p (tag `version/2024.1.3`). Licence: GPL-2.0-or-later.
  - Authors: originally by David Megginson; maintained by the c172p team: Gilberto Agostinho, Wayne Bragg, Juan Vera del Campo, onox, Fernando Barbosa, Daniel Dubreuil, Jonathan Redpath, Jonathan Schellhase, Tuomas Kuosmanen, Anders Gidenstam, Waldo Kitty, algefaen, Horacio, D-ECHO, Jarl Arntzen, Benedikt Hallinger, Sascha Reißner, Josh Davidson and others.
  - libresim converted these to glTF and modified them; the unmodified source is in `third_party/c172p/`.
- **Airbus A320 flight-model, engine and systems data (A320 pack, in development):**
  - Source: the FlightGear A320-family project, https://github.com/legoboyvdlp/A320-family (branch `dev`, commit `fec1ecba767c8fffd145337b27012e89c01e3ade`). Licence: **GPL-2.0 only** (the combined A320 pack is therefore GPL-2.0).
  - Copyright (c) 2025 Josh Davidson, Jonathan Redpath, merspieler, Matthew Maring, Thorsten Herrmann, Semir Gebran. Authors named in the project: Josh Davidson (Octal450), Jonathan Redpath (legoboyvdlp), Nia, Matthew Maring (mattmaring), Thorsten Herrmann (TH-555), Semir Gebran (CaptB) and Andrea Vezzali (vezza). The aircraft the project is based on is credited upstream to Immersive Design Group.
  - libresim converts the JSBSim flight-dynamics and engine files to JSON (`tools/06_jsbsim_to_json.py`) and modifies them; notices and change log in `third_party/a320-family/SOURCE.md`. No sounds, fonts, Nasal code, airline liveries or FlyByWire material from that project are used. "Airbus" and "A320" are trademarks of Airbus; libresim is not affiliated with or endorsed by Airbus, an airline or an engine maker, and uses a generic livery.
- **Propeller blade model:** Syd Adams and Heiko Schulz (c182s project), GPL-2.0, via the c172p team.
- **Flight-model data:** JSBSim `c172p` aircraft, `engIO360C` engine and `prop_75in2f` propeller, by the JSBSim Team and contributors (https://github.com/JSBSim-Team/jsbsim), LGPL-2.1. libresim converted them to JSON and retuned them (`tools/06_jsbsim_to_json.py`).
- **JSBSim authors:** the JSBSim project names Jon S. Berndt (primary architect), Agostino De Marco, Tony Peden and David Megginson among its principal authors (see its `AUTHORS` file). The header of the `c172p` aircraft file gives its author as unknown.
- **Flight-model code written from JSBSim's published design:** `game/fdm/aero.gd`, `game/fdm/table.gd` and `game/fdm/propeller.gd` re-implement how JSBSim evaluates aerodynamic function trees, lookup tables and propeller thrust, torque and P-factor. They are libresim's own GDScript; no JSBSim source code was copied. JSBSim is LGPL-2.1.
- **Tuning values from the c172p team's files:** the control actuator travel times (elevator 0.30 s, aileron and rudder 0.15 s) from `c172p.xml`, and the engine and wind sound volume and pitch curves in `game/aircraft/c172/aircraft_audio.gd` from `c172-sound.xml`. Numbers only, no code. Source and licence as for the c172p model above (GPL-2.0-or-later).

### Airport vehicles and jetways
- **From FlightGear fgdata** (https://gitlab.com/flightgear/fgdata, release/2024.1), FlightGear contributors, GPL-2.0. Converted to glTF; the original is in `third_party/fgdata/`:
  - generic jetway
- **Made for libresim** by the libresim contributors, GPL-2.0-or-later, built in code (`game/world/ground_vehicles.gd`, `vehicle_geo.gd`, `vehicle_parts.gd`, `veh_*.gd`, `follow_me_*.gd`; no imported models):
  - follow-me car (generic pickup)
  - pushback tug
  - fuel truck
  - ground power unit
  - baggage tug and carts
  - apron bus
  - rescue fire truck

### Sounds
All sounds are real recordings, listed file by file in `game/aircraft/c172/sounds/SOURCES.md`:
- **C172 engine** (start, crank, idle, run, cut): "small plane cessna engine start idle and takeoff" by **JLWSound** (freesound.org/s/322321), CC0, via the c172p team.
- **Stall horn:** from "Stalling and spinning with a Cessna 152" by **Morsule**, CC-BY.
- **Gyro spin:** from "Starting C172N" by **algefaen**, CC-BY.
- **Parking brake lever:** "Old Lever Pull" by **DrMinky**, CC0.
- **Trim wheel:** "rubber.wav" by **datasoundsample**, CC0.
- **Primer:** by **coltures**, CC0.
- **Flap motor, tyres, switches and doors:** c172p team, GPL-2.0-or-later.
- **Wind, rumble, squeal, rain, avionics fan:** FlightGear fgdata contributors (https://gitlab.com/flightgear/fgdata), GPL-2.0 (fgdata states no "or later").

**A320 pack sounds** (all CC0 / CC-BY, listed file by file in `game/aircraft/a320/sounds/SOURCES.md`; trimmed, filtered, resampled and normalised, changes made):
- **Turbojet start, idle, power, whine, shutdown:** "SaabJ35D Draken - start engine and taxiing" by **Work With Sounds / Torsten Nilsson** (provided to Wikimedia Commons in a project with Wikimedia Sverige), CC BY 4.0, https://commons.wikimedia.org/wiki/File:WWS_SaabJ35DDrakenstartengineandtaxiing.ogg
- **Reverse-thrust roar:** "LAX AIRPORT! LANDING SOUND LA CITY SOUNDS" by **freetousesounds** (Marcel), CC BY 4.0, https://opengameart.org/content/lax-airport-landing-sound-la-city-sounds
- **Cabin air conditioning:** "air conditioner hum 2" by **Gravity Sound**, CC BY 4.0, https://commons.wikimedia.org/wiki/File:Air_conditioner_hum_2_(Gravity_Sound).wav
- **Hydraulic pump:** "Pump" by **Work With Sounds / La Fonderie**, CC BY 4.0, https://commons.wikimedia.org/wiki/File:WWS_Pump.ogg
- **Landing-gear actuation:** "Hoist" by **Work With Sounds / Torsten Nilsson**, CC BY 4.0, https://commons.wikimedia.org/wiki/File:WWS_Hoist.ogg
- **Seat-belt chime:** "Airplane Chime Sound Effect" by **Sharelk**, CC0, https://commons.wikimedia.org/wiki/File:Airplane_Chime_Sound_Effect.ogg
- The A320 also reuses C172 sound files (wind, rain, tyres, flap motor, clicks, lever), credited above. No sound from the A320-family upstream project is used.

### Engine (runtime)
- **Godot Engine 4.7** (https://godotengine.org), MIT licence, © Juan Linietsky, Ariel Manzur and Godot Engine contributors. Godot bundles third-party components (FreeType, HarfBuzz, Vulkan loader, fonts and others); their licences are listed in full on the in-game credits screen (taken from the engine itself).

### Map data
- **Satellite imagery:** EOxCloudless (Sentinel-2 cloudless), https://cloudless.eox.at (also reachable as https://s2maps.eu), by EOX IT Services GmbH (Contains modified Copernicus Sentinel data 2024). Licence: **CC BY-NC-SA 4.0** (non-commercial; confirmed on EOX's own licence page on 2026-10-28, see `docs/LICENSING.md`). libresim's imagery tiles are derived from it and carry the same licence.
- **Elevation:** Copernicus GLO-30 DEM © DLR e.V. 2010–2014 and © Airbus Defence and Space GmbH 2014–2018, provided under COPERNICUS by the European Union and ESA. Free licence with attribution.
- **Land cover:** ESA WorldCover 2021 v200 © ESA WorldCover project / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium, https://esa-worldcover.org. Licence: **CC BY 4.0** (https://creativecommons.org/licenses/by/4.0/). libresim's land-class tiles (`terrain/wc/`) are a modified (resampled, re-coded) copy; the ground detail drawn per class is procedural.
- **Map features** (runways, taxiways, roads, buildings, water): © OpenStreetMap contributors, available under the Open Database Licence (ODbL 1.0), https://www.openstreetmap.org/copyright.
- **Airports, runways, frequencies and navaids:** OurAirports (https://ourairports.com), public domain.

### Branding
- **libresim logo, icon and boot splash:** original artwork by the libresim contributors (GPL-2.0-or-later), generated by `tools/branding/make_logo.py`.
- **Fira Sans** (Carrois Corporation / Mozilla; SIL Open Font License 1.1): the letter shapes of the "libresim" wordmark and the "09/27" runway designator, converted to outlines in `game/branding/*.svg`. Fira Sans itself is not shipped.

## Tools used to build libresim (not shipped in the game)
- **GDAL/OGR** (MIT) and **PROJ** (MIT): reprojection and tiling.
- **Python** (PSF): the data pipeline. Libraries:
  - NumPy (BSD-3)
  - pyosmium / libosmium (BSD-2 / BSL-1.0)
  - JSBSim Python bindings (LGPL-2.1), used for reference runs
  - Matplotlib (PSF-style), for previews
  - Pillow (MIT-CMU), for image checks
- **Blender 4.0** (GPL) and the **Blender AC3D importer** by Nikolai V. Chr. and contributors (https://github.com/NikolaiVChr/Blender-AC3D, GPL-2.0-or-later): model conversion.
- **Geofabrik** (https://download.geofabrik.de): OpenStreetMap extracts.
- **Overpass API** (https://overpass-api.de): one-off fetch of the OpenStreetMap data for Kochi (VOCI), outside the Geofabrik extract.
- **AWS Open Data** (Copernicus DEM bucket) and the **EOX WMTS** service: data hosting.

## Inspiration and references (the data and assets that were reused are credited above)
- **FlightGear** (https://www.flightgear.org), the open-source flight simulator. Its property tree, aircraft-as-data approach and c172p team's realism inspired our design. Research notes are in `docs/FLIGHTGEAR_NOTES.md`.
- **JSBSim**: its function and table format for aerodynamics is mirrored in `game/fdm/aero.gd`.
- **Real Flight Simulator (RORTOS)** and **Microsoft Flight Simulator (Asobo / Microsoft)**: feature and visual-quality benchmarks. Their names are trademarks of their owners. libresim is not affiliated with them and uses none of their content.
- **The Cessna 172S Pilot's Operating Handbook** (Textron Aviation): published performance figures used as test targets. "Cessna" and "Skyhawk" are trademarks of Textron Aviation Inc.; libresim is not affiliated with or endorsed by Textron.
