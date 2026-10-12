# Landmark airport terminals

The generic city (`tools/10_buildings.py`) extrudes OSM footprints into plain boxes. That is
fine for houses, but the passenger terminals are what a pilot recognises an airport by. So
the terminals at Mumbai (VABB), Pune (VAPO) and Kochi (VOCI) are built as separate
landmark models. Each one starts from its real OSM footprint and adds a hand-written
"recipe" based on published photos and architects' descriptions.

## 1. Pipeline

| Step | File | In → out |
|---|---|---|
| Extract | `tools/15_terminals.py` | OSM → `data/processed/terminals/<ICAO>.json` |
| Model | `tools/16_terminal_models.py` | `<ICAO>.json` → `<ICAO>.glb`, `<ICAO>_model.json`, `landmarks.json` |
| Recipes | `tools/terminal_styles.py` | one function per airport (`RECIPES = {VABB, VAPO, VOCI}`) |
| Geometry | `tools/terminal_geom.py` | walls, caps, slabs, hip roofs with gablets, vaults, columns, boxes |
| Writer | `tools/glb_writer.py` | minimal glTF 2.0 binary: one mesh, one primitive per material |
| Game | `game/world/terminals.gd` + `terminal.gdshader` | loads the glb near the camera and swaps in the shader |
| Preview | `game/tests/debug_terminal.gd/.tscn` | renders PNGs of one airport on its own |

**Run order** (from `tools/`, using `tools/.venv`):

```sh
python 15_terminals.py [VABB VAPO VOCI]       # footprints; all three by default
python 16_terminal_models.py [VABB VAPO VOCI] # models + landmarks.json
python 10_buildings.py                        # re-run so the generic city drops the landmark footprints
```

**15_terminals.py** reads VABB and VAPO from the local Geofabrik PBF
(`data/raw/osm/western-zone-latest.osm.pbf`) with pyosmium. Kochi lies outside that
extract, so VOCI is fetched once from the Overpass API (`overpass-api.de`) and cached in
`data/raw/osm/overpass_VOCI.json`. Delete that file to fetch it again. For each airport it
searches a box of about ±3.3 km and sorts what it finds into these groups:

- `terminals`: `aeroway=terminal`, `building=terminal`, or buildings named "Terminal …".
  Cargo terminals and anything under 500 m² are dropped. Each must lie within 300 m of
  the aerodrome boundary.
- `parts`: buildings whose centroid is inside a terminal, plus `building:part` and
  `building=roof` canopies within 30 m of one.
- `jet_bridges`: `aeroway=jet_bridge` within 150 m.
- `car_parks`: multi-storey car parks within 300 m.
- `elevated_roads`: highways with `bridge=*` or `layer>=1` within 300 m.

Every feature keeps its OSM id, a subset of its tags, and its rings in world metres. It
also gets an area or length, a centroid and an oriented bounding box.

**16_terminal_models.py** puts the model origin at the mean centroid of the terminals
over 5,000 m² and runs the airport's recipe. The recipe returns two things: the landmark
footprints, and any signs. The script then writes three files:

- `<ICAO>.glb`: the model, in glTF axes (x = east, y = up, z = −north) relative to the origin.
- `<ICAO>_model.json`: `origin [east, north, ground h]`, `extent`, `signs` (text, position,
  height, heading, colour; drawn in game as `Label3D`) and `focus` (centre and size of each
  landmark, used by the preview).
- `landmarks.json`: the footprint rings of every airport, in world metres. 10_buildings.py
  uses this file to leave those buildings out of the generic extruded city.

The ground height comes from the DEM tiles where they exist. Otherwise (Kochi) it falls
back to the OurAirports field elevation.

**In game**, `Terminals` (`game/world/terminals.gd`) reads every `*_model.json`. Once a
second it checks the camera, loads an airport's glb with `GLTFDocument` when the camera
comes within 20 km, and frees it again beyond that. Each node is placed with
`FloatingOrigin.to_render(origin)` and placed again after every origin shift. The shader's
`night` parameter is driven from `/environment/sun_elev_deg`.

**Preview** (renders without terrain, so it works for Kochi too). It takes two oblique
shots and one apron-level shot per landmark, saves `term_<ICAO>_<view>[_night].png`
to the output folder, and quits:

```sh
~/.local/bin/godot --path game res://tests/debug_terminal.tscn -- --icao=VOCI --out=/tmp [--night]
```

## 2. Material names and shader kinds

The glb materials carry only a **name** and a base colour, so Blender and other glTF
viewers still show sensible colours. `terminals.gd` swaps each surface for a
`ShaderMaterial` on `terminal.gdshader`. It picks the `kind` from the start of the
material name and keeps the base colour. `glb_writer.py` writes one primitive per
(material, colour) pair and appends the colour to the name, e.g. `panel#e6dbbf` or
`glass@2.0#545e66`, so the same material can be used in several colours.

| Material name | Kind | Look |
|---|---|---|
| `glass@<m>` | 0 glass curtain wall | mullion grid every `<m>` metres (`mullion` uniform), transoms and floor-slab bands every 4.5 m, Fresnel sky/fog reflection, interior lit in random warm panels at night |
| `panel` | 1 solid cladding | panel joints on a 3 m × 1.5 m grid (also used for fascias, jali bands and car-park decks) |
| `gable` | 1 solid cladding | white Kerala gablet triangles (written by `hip_roof`) |
| `roof_metal` (also `roof_white`) | 2 metal roof | faint standing seams, slightly metallic |
| `roof_tile` | 3 clay-tile roof | tile courses 0.28 m apart with staggered 0.32 m joints and per-tile shading |
| `concrete`, `column` | 4 plain | base colour only (slabs, parapets, piers, columns) |
| `soffit` | 5 coffered soffit | 6 m coffer ribs on the canopy underside, downlights at night |

Any name it does not recognise falls back to kind 1. Every kind fades its fine detail
out between 600 and 2,200 m and blends into the global haze (`fog_color`,
`haze_density`). `terminal_geom.vault()` writes plain `glass` end walls (default mullion
1.6 m). No recipe uses `vault()` at the moment.

## 3. Per airport

OSM has no `height`, `building:levels` beyond VABB T2's `levels=3`, or `roof:*` tags at
any of the three airports. So all heights below are set by hand from published figures.

### VABB Mumbai, Chhatrapati Shivaji Maharaj International

**Terminal 2** (`way/315613914`, 136,599 m² in OSM). The real building is by SOM and
opened in 2014. It is X-shaped: a central headhouse with piers, 450,000 m² over 4 levels.
One long-span roof of about 70,000 m² sits on 30 mushroom "mega-columns" on a
64 m × 34 m grid, over 30 m tall. The roof cantilevers about 40 m over the departures kerb.
Its underside has about 4,000 white GFRG coffers with coloured glass discs (the "peacock"
motif). Check-in sits behind a 15 m cable-stayed glass wall. The piers combine glazing
with white/silver jali screens. Sources disagree on the roof height: 36 m (SOM), about
42 m (Wikipedia) and about 45 m (airport-technology). The six-lane Sahar Elevated Access
Road reaches the level-4 kerb, and there is a multi-level car park for about 5,000 cars.

How it is modelled: a morphological opening (r = 70 m) splits the footprint into the
headhouse and the piers.
- **Piers:** glass to 14 m, then a white jali/panel band to 20 m, under a flat grey roof at 21.5 m.
- **Headhouse:** glass to 26 m and panels to 30 m.
- **Roof:** one canopy at 31–34 m, with a lit coffered soffit underneath and a silver
  fascia. It overhangs the headhouse by 6 m and reaches 40 m out on the landside. The
  landside is found as the direction away from the jet bridges.
- **Kerb:** tapered white columns about every 34 m along the 40 m kerb band.
- **Roof top:** seven glazed skylight ribs.
- **Around it:** the elevated approach roads (deck height from `layer`, columns every
  32 m), and the car park (`way/436222501`) as 5 open decks.

The roof is placed at 34 m, the low end of the published range.

**Terminal 1** (`way/61569813`). 1A closed in 2016 and has been demolished since
Nov 2025. T1 stops operating on 25 Oct 2026 for rebuilding, and demolition starts in
Jan 2027. It is modelled as low 1B/1C blocks:
- Grey glass with silver metal cladding and flat roofs.
- The core rises to 16–17.5 m and the arms to 12–13 m.
- The two OSM kerb canopies (`way/569614980`, `way/569614982`) are drawn at 8.5 m or
  13.5 m, depending on their `layer`.

The appearance is **unsure**: it is not based on detailed references.

### VAPO Pune

**New integrated terminal**, OSM "Terminal 2" (`way/1154418126`). It was inaugurated on
10 Mar 2024, has handled flights since 14 Jul 2024, covers about 52,000 m², and lies east
of the old terminal. Its signature is the 360–400 m **"Verandah"**, a canopy that ties the
old and new terminals together. The canopy has Maratha-style arches and decorated
columns faced in dark local stone, inspired by Shaniwar Wada. There is a multi-level
car park.

**Old terminal**, OSM "Terminal 1" (`way/69366490`).

How it is modelled:
- **New terminal:** grey glass to 9 m, cream cladding to 17 m, and a flat metal roof at
  18.5 m with a 4 m overhang.
- **Old terminal:** glass to 6 m, cladding to 12 m, and a roof at 13 m.
- **Verandah:** one 16 m deep canopy along the landside of both buildings, at 12–13.2 m
  with a deep cream fascia up to 15.5 m. It stands on dark basalt columns every 9 m.
- **Car parks:** 4 decks.

The roof form, glass tint and number of levels are **unsure**. The arches are not
modelled; the columns are plain cylinders.

OSM also has a large unnamed `aeroway=terminal` (`way/1178357638`) about 900 m NE,
among the hangars. The VAPO recipe does not model it, so it stays a generic building.

### VOCI Kochi (Cochin International)

**Terminal 3** (`way/452201953`, opened 2017). It covers about 150,000 m² on a
41,156 m² footprint, with floors at +0.15, +5.5, +10.5 and +15.5 m. It has long,
low-pitched terracotta hip roofs in sections, with small white Kerala gable dormers
(*mukhappu*). The cream facade has wide eaves, terracotta-red pylons and recessed grey
glazing. "COCHIN INTERNATIONAL AIRPORT" is written in white capitals on a red fascia
band, and "TERMINAL 3" on the pylons. A 725 m flyover leads to the departures kerb.
There is also a solar carport and 10 aerobridges.

How it is modelled:
- **Core walls:** grey glass and cream bands that follow the published floor levels:
  glass 0–5.5 m, cream 5.5–10.5 m, glass 10.5–15.5 m and a cream band to 17 m.
- **Core roofs:** the core is cut into strips about 75 m long. Each strip gets a 30°
  terracotta hip roof with gablets: eaves at 17 m, a 6 m overhang, a rise of up to 15 m,
  and a cream soffit.
- **Arms:** 60 m roof sections at 11 m.
- **Landside face:** a 120 m red fascia band at 11–15 m, two 20 m terracotta pylons
  ±140 m from the centre, and `Label3D` signs reading "COCHIN INTERNATIONAL AIRPORT" and
  "TERMINAL 3" (×2).
- **Approach:** the elevated approach roads within 300 m.

The roof pitch and section lengths are estimates taken from photos.

**Terminal 1** (`way/254109738`) has red clay-tile pitched roofs (the Ettukettu theme,
renovated in 2018). **Terminal 2** (`way/254109742`) is now the business-jet terminal.
Both are built in the same style but lower: glass to 5 m, cream to 9 m, and tile roofs at
9 m in 50 m sections. The solar carport and the aerobridges are not modelled.

## 4. Known gaps and improvements

- **No height tags in OSM.** Every height is hand-set from published floor levels or
  quoted roof heights. Add `height`/`roof:shape` tags to OSM where you can verify them,
  then read them in the recipes.
- **VABB T2 roof** is flat. The real roof is a long-span shell on mushroom columns with
  peacock coffers. The 30 interior mega-columns, the varying roof height, the coloured
  coffer discs and the 15 m cable-stayed check-in wall are all missing. Its height
  (34 m) is uncertain, somewhere between 36 and 45 m in the sources.
- **VABB T1** is generic. It also has a limited life: when it closes (Oct 2026) and is
  demolished (from 2027), it should be removed or replaced with the new building.
- **VAPO**: the roof form, glass tint and level count are unknown. The Verandah's
  Maratha arches and decorated stone columns are simplified to plain basalt cylinders.
- **VOCI coordinates**: Kochi is outside the mapped terrain until phase R (Mumbai–Kochi).
  Its model and `landmarks.json` entry are in the current **Mumbai-origin** world frame,
  more than 900 km from the origin. Re-run 15 and 16 (and 10) when phase R re-projects
  the world.
- **VOCI ground height** comes from the OurAirports field elevation, not a DEM.
- **Jet bridges** are only used to work out which side is landside. The in-game jetways
  come from the Phase A stand system.
- **Signs** are `Label3D` with the default font, not the real lettering.
- **Car parks** are modelled with a fixed number of decks (VABB 5, VAPO 4), not
  real counts.
- **Materials** are procedural only, with no textures. Glass reflects a sky colour, not
  the scene.

## 5. Licensing

- **Footprints:** © OpenStreetMap contributors, under the Open Database Licence (ODbL
  1.0). VABB and VAPO come from the Geofabrik extract. VOCI comes from a single query to
  the Overpass API (overpass-api.de), cached locally and not fetched again.
- **Generated models** (`.glb`, `_model.json`, `landmarks.json`) are derived from those
  footprints. They are produced databases under the ODbL and need the same attribution.
  They are **not committed**: `data/processed` is gitignored, and anyone can regenerate
  them with the commands in §1.
- The recipes, geometry code and shader are libresim code (GPL-2.0-or-later). No
  third-party models or textures are used.
- The architectural facts in §3 come from the public sources listed below. No images or
  drawings were copied.

## Sources

- SOM, CSMIA Terminal 2: https://www.som.com/project/chhatrapati-shivaji-international-airport-terminal-2
- Airport Technology, T2 Mumbai: https://www.airport-technology.com/projects/terminal-2-chhatrapati-shivaji-international-airport-mumbai/
- Dezeen, SOM Mumbai terminal (2014): https://www.dezeen.com/2014/02/20/chhatrapati-shivaji-airport-terminal-mumbai-som/
- Wikipedia, CSMIA: https://en.wikipedia.org/wiki/Chhatrapati_Shivaji_Maharaj_International_Airport
- Business Today, T1 closure (Oct 2026): https://www.businesstoday.in/india/story/mumbai-airport-terminal-1-to-shut-for-4-years-from-october-25-what-flyers-need-to-know-559256-2026-10-03
- Wikipedia, Pune Airport: https://en.wikipedia.org/wiki/Pune_Airport
- Punekar News, new terminal and heritage design: https://www.punekarnews.in/pune-airport-to-get-new-terminal-building-with-enhanced-capacity-and-reflection-of-cultural-heritage/
- Curly Tales, Pune terminal architecture: https://curlytales.com/pune-international-airport-architecture-facilities-cost-and-operation-all-you-need-to-know/
- CIAL, T3 details (PDF): https://www.cial.aero/UserFiles/CIAL/Terminals/T3-Details.pdf
- Wikipedia, Cochin International Airport: https://en.wikipedia.org/wiki/Cochin_International_Airport
- Onmanorama, T3 sneak peek: https://www.onmanorama.com/news/kerala/blockbuster-t3-terminal-checks-in-cial-sneak-peek.html
- The News Minute, renovated domestic terminal (T1): https://www.thenewsminute.com/kerala/kerala-cm-inaugurates-renovated-domestic-terminal-kochi-airport-93271
- OpenStreetMap ways cited above: https://www.openstreetmap.org/way/<id>
