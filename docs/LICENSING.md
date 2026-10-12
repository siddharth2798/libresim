# Licensing and compliance

libresim's code is **GPL-2.0-or-later** (`LICENSE`). The project also contains or produces material under other licences. This page lists every component and what we do to comply. Thanks and attributions are in `CREDITS.md`.

## Component by component

| Component | Where | Licence | What we do to comply |
|---|---|---|---|
| libresim code, scripts, shaders, docs | everywhere | GPL-2.0-or-later | Licence text in `LICENSE`; source is this repo |
| FlightGear c172p model, interior, textures | `game/aircraft/c172/models/*.glb` (converted), `third_party/c172p/` (original) | GPL-2.0-or-later | Unmodified source shipped in `third_party/c172p/` with upstream `LICENSE` and `Thanks`; modifications documented in `third_party/c172p/SOURCE.md` and reproducible by the `tools/blender/` scripts; authors credited |
| JSBSim c172p / IO-360 / prop data | `game/aircraft/c172/*.json` (derived) | LGPL-2.1 | LGPL-2.1 allows relicensing as GPL-2.0+ (§3), which is our combined licence; credited; the derivation script is `tools/06_jsbsim_to_json.py` |
| fgdata airport models (tug, fire truck, jetway, bus) | `game/world/models/vehicles/` (converted), `third_party/fgdata/` (original) | GPL-2.0 | Originals and `COPYING` vendored in `third_party/fgdata/`; conversion documented in `SOURCE.md`; credited |
| libresim's own vehicle models | `game/world/models/vehicles/` | GPL-2.0-or-later | Generated from source by `tools/blender/make_ground_vehicles.py` |
| Aircraft sounds | `game/aircraft/c172/sounds/` | CC0 / CC-BY (Morsule, algefaen) / GPL-2.0+ (c172p, fgdata) | Per-file sources in `sounds/SOURCES.md`; CC-BY authors credited in CREDITS.md and the F12 screen |
| Godot Engine (in exported builds) | binary | MIT plus bundled third-party licences | Copyright and licence notices are shown on the in-game credits screen (F12), taken from `Engine.get_license_text()` and `Engine.get_copyright_info()`; a `licenses/` folder is added to release archives |
| Sentinel-2 cloudless 2024 imagery | `data/processed/terrain/img` (generated, **not in git**) | CC BY-NC-SA 4.0 | Attribution always visible in the sim (bottom-right line) and in credits; derived tiles stay under CC BY-NC-SA; **no commercial use** of any package containing them |
| Copernicus GLO-30 DEM | `data/processed/terrain/h` (generated, not in git) | Copernicus licence (free, attribution) | Attribution visible in the sim and in credits |
| OpenStreetMap data | `data/processed/osm`, `runways.json` (generated, not in git) | ODbL 1.0 | "© OpenStreetMap contributors" visible in the sim and in credits. A shipped data pack is a derivative database, so it must be offered under ODbL (see below) |
| OurAirports | `data/processed/airports.json` | Public domain | Credited (courtesy) |
| Trademarks (Cessna, Skyhawk, MSFS, RFS, FlightGear) | docs only | n/a | Named only factually, with a non-affiliation statement |

## Before publishing the git repository
- [x] `LICENSE` (GPL-2.0) at the repo root, and `CREDITS.md`.
- [x] Original c172p source, `LICENSE` and `Thanks` in `third_party/c172p/`.
- [x] No generated map data in git (`data/` is gitignored), so no imagery (BY-NC-SA) or OSM (ODbL) data is redistributed through the repo.
- [x] No proprietary assets (no MSFS/RFS/Google/Bing content).

## Before shipping a binary or data pack (packaging phase)
`tools/package/make_release.sh` already does steps 1–3. Every package contains `LICENSE`, `CREDITS.md`, `README.md`, `docs/`, `third_party/` (c172p source), `licenses/` (Godot's LICENSE and COPYRIGHT) and `data/DATA-LICENSES.txt`. A `-source.tar.gz` of the exact commit is built alongside.

1. Include the libresim source, or a written offer valid for 3 years (GPL-2.0 §3b). The simplest option is to link the exact git tag *and* attach a source archive to the release.
2. Include `LICENSE`, `CREDITS.md`, `third_party/c172p/` and Godot's licence texts (`licenses/`).
3. Data pack: put a `DATA-LICENSES.txt` inside it covering:
   - imagery under CC BY-NC-SA 4.0
   - OSM-derived files under ODbL 1.0, offering the derived database (`osm/`, `runways.json`) under ODbL (shipping them inside the pack counts)
   - the Copernicus DEM notice
4. **Do not sell, or ship in paid or ad-supported stores, while the 2018+ s2cloudless imagery is included** (NC clause). Alternatives: the 2016 s2cloudless layer (CC BY 4.0) or raw Copernicus Sentinel-2 data (free, including commercial use).
5. Any new sound or asset must be added to CREDITS.md (and `sounds/SOURCES.md`) at the moment it is added.
