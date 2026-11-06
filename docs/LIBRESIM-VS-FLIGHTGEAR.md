# libresim compared with FlightGear

A factual comparison, not a ranking. FlightGear is a mature, general-purpose open-source simulator developed since 1997 by a large community. libresim is a small project for one region and two aircraft, and it **reuses FlightGear work** (the c172p model, cockpit and sounds, the A320-family model and data, JSBSim data). See [CREDITS.md](../CREDITS.md).

**Sources**
- FlightGear facts were checked on 2026-10-10 against its own sources: the 2024.1.7 source tags on GitLab (flightgear, simgear, fgdata `release/2024.1`), flightgear.org release and download pages, SourceForge release files, the official aircraft catalog and Flathub.
- wiki.flightgear.org could not be fetched (HTTP 403). Items that rely only on wiki search snippets are marked *(partly verified)*.
- libresim rows describe the code in this repository.

## At a glance

| | FlightGear (stable 2024.1.7) | libresim (this repo) |
|---|---|---|
| Latest release | 2024.1.7, released 14 Aug 2026 ([release notes](https://www.flightgear.org/blog/release-2024-1-7/)) | No public release yet. `tools/package/make_release.sh` builds a Linux AppImage and a macOS app |
| Licence | Core GPL-2.0-or-later; **SimGear** library LGPL-2.0-or-later; fgdata GPL-2.0 | GPL-2.0-or-later; third-party assets keep their own licences ([docs/LICENSING.md](LICENSING.md)) |
| Language / engine | C++ on OpenSceneGraph (≥ 3.6; FlightGear also hosts an OSG fork on GitLab); Nasal scripting | GDScript on the Godot 4.7 engine |
| User interface | Legacy PUI, a Qt launcher (Qt5/Qt6), Canvas | Godot start screen (free flight setup, training, saved flights, options, controls), in-sim HUD, F10 settings, F12 credits |
| Official platforms | Windows 10/11 x86_64, macOS 11+ (universal), Linux x86_64 AppImage; also on Flathub | Developed on Linux and macOS (Apple silicon). The Linux AppImage and the macOS app come from `make_release.sh`; the macOS app is untested end to end |
| Mobile | No iOS or Android builds offered | None yet (a mobile/tablet port is an optional later phase) |
| Download size | Data package 1.9 GB compressed; AppImage 329 MB (2024.1.7) | No published package; the generated regional data is about 2.6 GB |

## World and scenery

| | FlightGear | libresim |
|---|---|---|
| Coverage | Worldwide, downloaded on demand with TerraSync | Two regions: Mumbai to Pune (about 145 × 115 km) and the Konkan to Kerala corridor down to Kochi, with a coarser outer ring around them |
| Terrain | World Scenery 2.0 by default; a World Scenery 3.0 preview exists in 2024.1, **off by default** | Copernicus GLO-30 (30 m) heightmap tiles with runway and apron flattening, streamed chunked LOD |
| Ground imagery | Photoscenery support is built in but **disabled by default** | Sentinel-2 cloudless 10 m satellite imagery on all terrain, by default |
| Buildings and roads | OSM2City buildings, roads and pylons as optional TerraSync layers, **off by default** *(delivery partly verified)* | 3D buildings from OpenStreetMap footprints, on by default within ~9 km; roads and rivers drawn crisply on the terrain from OpenStreetMap |
| Water and trees | Part of FlightGear's scenery and shaders | Water and trees from a land-class mask built from the imagery, OSM and the DEM |

## Aircraft and flight model

| | FlightGear | libresim |
|---|---|---|
| Aircraft | 680 aircraft packages (plus 606 variants) in the official 2024 hangar catalog | Two: Cessna 172 (C172S performance targets) and an A320-family airliner with a fly-by-wire law and cockpit systems |
| Flight-dynamics models | JSBSim and YASim, plus UIUC and LaRCsim (both removed in the `next` branch) and special-purpose models | One 6-DOF model in GDScript that evaluates JSBSim's c172p aero tables, with its own engine, propeller and gear code |
| C172 model | c172p = "Cessna 172P Skyhawk (1982)" on JSBSim | The c172p airframe data and 3D model, retuned to C172S POH figures (IO-360 180 hp) and checked by automated POH test cards (`game/tests/`) |
| Damage | (not compared; outside this check) | Gear collapse by touchdown sink rate or load, prop strike, wingtip and tail strikes, ditching, tree strikes, Vne/Vd failure, flap overspeed, flight-load-factor limits |

## Systems, instruments, environment

| | FlightGear | libresim |
|---|---|---|
| Property tree | Yes (SimGear props); generic, telnet and built-in web-server interfaces; Phi web UI | Yes (a flat `Props` autoload); no external network interface |
| Instrument errors (c172p) | Compass northerly-turning and acceleration errors; vacuum gyros with spin-up/down and drift; pitot, static and vacuum failures; alternate static | Similar set: pendulous compass, vacuum gyros with erection and drift, VSI lag, ASI position error, pitot/static/vacuum failures, alternate static |
| Weather | Basic Weather (METAR) and Advanced Weather; live METAR fetch; 3D clouds on by default; voxel volumetric clouds only in `next` | Offline presets, plus an opt-in live weather switch (NOAA METAR and Open-Meteo, off by default, lessons stay offline): wind profile, gusts, turbulence, ridge lift, visibility, volumetric clouds and storms, rain, icing, QNH, temperature |
| Rendering | Compositor (always built in since 2024.1); dynamic shadows and lights available but off by default; HDR/PBR pipeline only in `next` | Godot Mobile renderer by default; Forward+ from the High preset; presets from Low to Max |
| VR | Preliminary OpenXR support (osgXR) in 2024.1, on by default in Windows and Linux builds | None |

## People and connectivity

| | FlightGear | libresim |
|---|---|---|
| Multiplayer | Built-in multiplayer on fgms servers; VATSIM through the swift module | None (offline by design) |
| AI traffic and ATC | Scheduled AI airline traffic with ATC controllers; ATIS spoken by built-in TTS; FGCom voice built in. ATC-pie and OpenRadar are separate programs *(partly verified)* | A rule-based text ATC controller (optional system voice) and checklists; no AI airline traffic yet (ground vehicles and ramp crew at airports) |

## In one sentence
FlightGear is a worldwide, multi-aircraft, multiplayer simulator with decades of community work. libresim is a two-aircraft, single-region, offline simulator that puts satellite terrain, 3D OSM buildings and a damage model on by default, built on FlightGear's aircraft assets and JSBSim's data.
