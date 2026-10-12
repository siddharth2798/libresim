# libresim compared with FlightGear

This is a factual comparison, not a ranking. FlightGear is a mature, general-purpose open-source flight simulator developed since 1997 by a large community. libresim is a small project focused on one aircraft in one region, and it **reuses FlightGear work**: the c172p 3D model, cockpit and sounds, and JSBSim data. See [CREDITS.md](../CREDITS.md).

**How this was checked**
- **FlightGear facts** were checked on 2026-10-10 against FlightGear's own sources: the 2024.1.7 source tags on GitLab (flightgear, simgear, fgdata `release/2024.1`), flightgear.org release and download pages, SourceForge release files, the official aircraft catalog and Flathub.
- **Not checked directly:** wiki.flightgear.org could not be fetched (it returned HTTP 403). Items that rely only on wiki search snippets are marked *(partly verified)*.
- **libresim facts** describe the code in this repository as of the same date.

## At a glance

| | FlightGear (stable 2024.1.7) | libresim (this repo) |
|---|---|---|
| Latest release | 2024.1.7, released 14 Aug 2026 ([release notes](https://www.flightgear.org/blog/release-2024-1-7/)) | No release yet (pre-MVP, development builds only) |
| Licence | Core GPL-2.0-or-later; **SimGear** library LGPL-2.0-or-later; fgdata GPL-2.0 | GPL-2.0-or-later; third-party assets keep their own licences ([docs/LICENSING.md](LICENSING.md)) |
| Language / engine | C++ on OpenSceneGraph (≥ 3.6; FlightGear also hosts an OSG fork on GitLab); Nasal scripting | GDScript on the Godot 4.7 engine |
| User interface | Legacy PUI, a Qt launcher (Qt5/Qt6), Canvas | Godot UI: in-sim HUD, F10 settings, F12 credits; no launcher yet |
| Official platforms | Windows 10/11 x86_64, macOS 11+ (universal), Linux x86_64 AppImage; also on Flathub | Developed and tested on Linux only (Pop!_OS). Linux and macOS packages are planned (phase P) |
| Mobile | No iOS or Android builds offered | None yet (a mobile/tablet port is an optional later phase) |
| Download size | Data package 1.9 GB compressed; AppImage 329 MB (2024.1.7) | No package yet; generated regional data is about 0.4 GB |

## World and scenery

| | FlightGear | libresim |
|---|---|---|
| Coverage | Worldwide, downloaded on demand with TerraSync | One region only: Mumbai to Pune, about 145 × 115 km. The outer ring and procedural terrain beyond it are planned |
| Terrain | World Scenery 2.0 by default; a World Scenery 3.0 preview exists in 2024.1, **off by default** | Copernicus GLO-30 (30 m) heightmap tiles with runway and apron flattening, streamed chunked LOD |
| Ground imagery | Photoscenery support is built in but **disabled by default** | Sentinel-2 cloudless 10 m satellite imagery on all terrain, by default |
| Buildings and roads | OSM2City buildings, roads and pylons as optional TerraSync layers, **off by default** *(delivery partly verified)* | 3D buildings from OpenStreetMap footprints, on by default within ~9 km; roads only as imagery |
| Water and trees | Part of FlightGear's scenery and shaders | Water and trees from a land-class mask built from the imagery, OSM and the DEM |

## Aircraft and flight model

| | FlightGear | libresim |
|---|---|---|
| Aircraft | 680 aircraft packages (plus 606 variants) in the official 2024 hangar catalog | One aircraft: Cessna 172 (C172S performance targets) |
| Flight-dynamics models | JSBSim and YASim, plus UIUC and LaRCsim (both removed in the `next` branch) and special-purpose models | One 6-DOF model in GDScript that evaluates JSBSim's c172p aero tables, with its own engine, propeller and gear code |
| C172 model | c172p = "Cessna 172P Skyhawk (1982)" on JSBSim | The c172p airframe data and 3D model, retuned to C172S POH figures (IO-360 180 hp) and checked by automated POH test cards (`game/tests/`) |
| Damage | (not compared; outside this check) | Gear collapse by touchdown sink rate or load, prop strike, wingtip and tail strikes, ditching, tree strikes, Vne/Vd failure, flap overspeed, flight-load-factor limits |

## Systems, instruments, environment

| | FlightGear | libresim |
|---|---|---|
| Property tree | Yes (SimGear props); generic, telnet and built-in web-server interfaces; Phi web UI | Yes (a flat `Props` autoload); no external network interface |
| Instrument errors (c172p) | Compass northerly-turning and acceleration errors; vacuum gyros with spin-up/down and drift; pitot, static and vacuum failures; alternate static | Similar set: pendulous compass, vacuum gyros with erection and drift, VSI lag, ASI position error, pitot/static/vacuum failures, alternate static |
| Weather | Basic Weather (METAR) and Advanced Weather; live METAR fetch; 3D clouds on by default; voxel volumetric clouds only in `next` | Offline settings only (no live weather): wind profile, gusts, turbulence, ridge lift, visibility, one raymarched volumetric cumulus layer, QNH, temperature |
| Rendering | Compositor (always built in since 2024.1); dynamic shadows and lights available but off by default; HDR/PBR pipeline only in `next` | Godot Mobile renderer by default (Forward+ optional), presets from Low to Ultra |
| VR | Preliminary OpenXR support (osgXR) in 2024.1, on by default in Windows and Linux builds | None |

## People and connectivity

| | FlightGear | libresim |
|---|---|---|
| Multiplayer | Built-in multiplayer on fgms servers; VATSIM through the swift module | None (offline by design) |
| AI traffic and ATC | Scheduled AI airline traffic with ATC controllers; ATIS spoken by built-in TTS; FGCom voice built in. ATC-pie and OpenRadar are separate programs *(partly verified)* | None yet (ATC and checklists planned in phases A and M9) |

## In one sentence
FlightGear is a worldwide, multi-aircraft, multiplayer simulator with decades of community work. libresim is a single-aircraft, single-region, offline simulator that puts satellite terrain, 3D OSM buildings and a damage model on by default, built on FlightGear's C172 assets and JSBSim's data.
