# Landmark airport terminals

The generic city (`tools/10_buildings.py`) extrudes OSM footprints into plain boxes. That is
fine for houses, but the passenger terminals are what a pilot recognises an airport by. So
the terminals at Mumbai (VABB), Pune (VAPO), Kochi (VOCI) and Kannur (VOKN) are built as separate
landmark models. Each one starts from its real OSM footprint and adds a hand-written
"recipe" based on published photos and architects' descriptions. Every airport's real terminals are
recorded in a researched data set, `tools/ref/terminals_reference.json` (§6), which drives the
heights and colours of the reference-driven recipes and of the generic terminal boxes elsewhere.

## 1. Pipeline

| Step | File | In → out |
|---|---|---|
| Extract | `tools/15_terminals.py` | OSM → `data/processed/terminals/<ICAO>.json` |
| Model | `tools/16_terminal_models.py` | `<ICAO>.json` → `<ICAO>.glb`, `<ICAO>_model.json`, `landmarks.json` |
| Recipes | `tools/terminal_styles.py` | one function per airport (`RECIPES = {VABB, VAPO, VOCI}`) |
| Reference recipes | `tools/terminal_styles_ref.py` | recipes whose heights / colours come from the reference data (`VOKN`) |
| Reference data | `tools/ref/terminals_reference.json` + `tools/terminal_ref.py` | researched facts per ICAO / terminal (§6) |
| Geometry | `tools/terminal_geom.py` | walls, caps, slabs, hip roofs with gablets, vaults, columns, boxes |
| Writer | `tools/glb_writer.py` | minimal glTF 2.0 binary: one mesh, one primitive per material |
| Game | `game/world/terminals.gd` + `terminal.gdshader` | loads the glb near the camera and swaps in the shader |
| Preview | `game/tests/debug_terminal.gd/.tscn` | renders PNGs of one airport on its own |

**Run order** (from `tools/`, using `tools/.venv`):

```sh
python 15_terminals.py [ICAO ...]             # footprints; default: VABB VAPO VOCI + every reference airport
python 16_terminal_models.py [ICAO ...]       # models + landmarks.json (default: every recipe)
python 10_buildings.py                        # re-run: drops the landmark footprints, applies reference heights
```

**15_terminals.py** reads VABB, VAPO and every other ICAO given on the command line (reference point from
`data/processed/airports.json`) from the local Geofabrik extracts with pyosmium: the western extract for
airports north of 14.8° N, the southern one for those south of 18.6° N (objects in both are read once).
The polygon helpers live in `tools/osm_geom.py`. Kochi lies outside that
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

**Base height.** The ground under the terminals is the *levelled* apron ground that
`17_airport_fixups.py` leaves in the tiles (`tools/apron_flatten.py` replaces the DSM's roofs and
walls under and beside every terminal footprint with a smooth fill of the ground around it), so
run 16 after 17. `origin h` is the area-weighted terrain height under the landmark footprints,
and every vertex of the glb (and every sign) is raised by *terrain height under it minus origin h*
(`Glb.shift_y`, `GroundFn` in `16_terminal_models.py`). Each landmark therefore sits on its own
ground even when they are far apart: at VABB the terrain under T2, T1 and the GA terminal is 8.8,
6.5 and 10.2 m. Without DEM tiles under every landmark it falls back to the
OurAirports field elevation, with no per-vertex shift. `tests/test_apron_flat.gd` checks that the
origin height matches the terrain under the landmarks and is within 2 m of the stand ground beside them.

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
1.6 m). The VOKN hall and the generic curved roofs (VOGO) use `vault()`.

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

### VOKN Kannur International

**Integrated passenger terminal** (`way/392012106`, 28,266 m² footprint, 205 × 191 m; opened Dec 2018,
97,000 m² floor area by KIAL / Wikipedia, 56,000 m² by airport-technology). Three levels (basement,
arrivals, departures), six aerobridges on the north (airside) face, a 750 m flyover to departures.
Its signature is the city-side canopy: eight parallel gabled bays (OSM roof parts
`way/1178527723`–`730`, each about 53 × 19 m, `roof:shape=gabled`) with glazed triangular gable ends,
cantilevering about 30 m over the kerb, a dark soffit with "KANNUR INTERNATIONAL AIRPORT" on it, white
round columns and a laterite-red beam and piers along the frontage. From the apron the central hall roof
curves up from low airside eaves; the wings have flat roofs; glass and blue-grey metal cladding; white
metal (double-skin aluminium) roofs. The 30 m ATC tower is a separate building.

**Height:** OSM tags the terminal (and every roof part) `height=30`, the published height of the ATC tower, so it is ignored. No published terminal height exists; photos (jet bridges and vehicles for scale) give eaves of about 14 m and gable ridges of 24–28 m.

How it is modelled (`terminal_styles_ref.vokn`, values from the reference entry):
- **Body:** glass to 60 % of the 14 m eaves (`glass_share`), blue-grey cladding above, flat white roof.
- **Hall:** the band of the canopy bays, 60 % of the way back toward the apron, walls to 16 m and a
  vault rising to about 22 m.
- **Canopy:** the eight OSM roof parts as gable roofs, eaves 18 m, ridges 26 m (`roof_top_m`), glazed
  gable ends, a dark fascia from 15 to 18 m with a soffit under it, white columns every 19 m on the kerb,
  a laterite beam (11–13.5 m) and nine piers on the frontage, the sign, and the flyover (elevated roads).

Heights are **low confidence** (photo estimates); the plan and roof form are from OSM and photos.

## 4. Known gaps and improvements

- **Reference heights are mostly estimates.** No source publishes a roof height for any terminal except VABB T2
  (SOM 36 m); Kannur's come from photos. Most other heights are `model` values from storeys or guesses.
  Better numbers (architects' sections, AAI tender drawings, measured photos) go into the reference file.
- **Next promotions** (enough data to model, own shapes needed): VANM (Zaha Hadid lotus shell on 17
  mega-columns, 3 floors), VOGA (processor + pier roofs with linear skylights, azulejo panels), VOML
  (3 levels, curved roof), VOSH (lotus petal roof). VAKP and VARG need their OSM outlines checked first.

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
- **VOCI** is placed in the Mumbai-origin world frame, more than 900 km from the origin. Re-run 15, 16 and 10 if the world is re-projected.
- **VOCI ground height** comes from the OurAirports field elevation, not a DEM.
- **Jet bridges** are only used here to work out which side is landside. The in-game jetways
  come from the stand system: `tools/jetway_net.py` (step 13) splits each OSM jet-bridge network
  into movable bridges (one per cab end, hinged at its rotunda: a junction, a sharp bend, or 12-45 m back
  from the cab) and fixed links, which run 2 m into the wall; a rotunda at the wall is moved 3.5 m out
  of it. In game `world/jetway_build.gd` draws the bridges (`jetway_rig.gd`: the rotunda and its stub stay
  put, the wheel support stands upright on the apron) and the links (`jetway_links.gd`, plain corridors on
  columns at the bridges' 3.78 m floor). `tests/test_jetway_terminal.gd` / `debug_jetway_audit.tscn` measure
  every bridge's root against the terminal model's collision raster and the building footprints. Kochi's 16 bridges have no mapped stands in OSM, so
  `tools/airport_stands.py` (called from step 13) derives them: one gate stand per bridge
  gate (two bridges at one door count once), the aircraft's nose gear 2.4 m beside the cab
  tip, heading square to the main tunnel or along the line between two cabs, turned in 5
  degree steps until an A320-sized outline clears the terminal footprints. That gives
  11 gates (the three T1/T2 gate numbers 2, 3, 4 come from the OSM gate nodes), a walk-out
  gate 1 and 26 remote bays beside the apron lanes, each with a lead-in edge in the taxi
  graph.
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
- The architectural facts in §3 and §6 come from the public sources listed below and in the reference file
  (each with its access date). Photos were looked at, not copied: no images or drawings are stored.

## 6. Reference data set (`tools/ref/terminals_reference.json`)

A researched record of the real passenger terminals of every airport in `data/processed/airports.json`
(18 ICAOs; the heliports have none). Per ICAO: what the field really is (`icao_note`) and whether it has a
passenger terminal. Per terminal: `name`, `osm` (the OSM ids of its footprint, which link the entry to
`terminals/<ICAO>.json`), `status`, `opened` / `expanded`, `roof_top_m`, `eaves_m`, `storeys`, `plan_shape`,
`length_m` / `width_m` / `footprint_m2` / `floor_area_m2`, `roof_form`, roof / facade / glass colours as
approximate sRGB hex plus words and materials, `glass_share`, `jet_bridges`, `tower_attached`,
`kerb_canopy`, `notable`, `osm_reflects_current` + `osm_note`, a `confidence` (high / medium / low) per
field, `conflicts` between sources, and `sources` (URL, title, access date, which fields it supports).
Research values are **null when unknown**: nothing is invented. Colours are judged from photos or
Sentinel-2 roof pixels, not measured paint. Wikipedia was used only as a lead.

`model` holds what the pipeline builds with where the research is null, each with its `basis`
(estimates, e.g. "3 levels under a curved roof"), plus recipe switches (`recipe: "generic"`,
`roof: flat | curved | pitched`, `overhang_m`). `tools/terminal_ref.py` reads the file:
`value(t, key)` = research, else model; `ref_heights(t)` = (eaves, roof top), falling back to
storeys × 4.5 m + 1 m; `rgb(t, key, default)`.

**What uses it**
- **Landmark recipes** (`terminal_styles_ref.py`): `VOKN` takes its heights, glass share and colours
  from the entry; the `generic` recipe models any terminal whose `model.recipe` is `"generic"` (today
  **VOGO** Dabolim: a glazed block to the 18 m eaves with a curved metal roof to 24 m, slices following
  the footprint, 6 m overhang). The hand recipes VABB / VAPO / VOCI keep their own numbers; the
  reference records the same values (as `model`) with their sources.
- **Generic terminal boxes** (`10_buildings.py`): every other researched terminal with a linked OSM
  footprint is extruded to its reference box height (the eaves when the roof rises above them, else the
  roof top) with the reference roof colour, over any OSM `height` tag or the synthetic airfield rule. The
  same height goes into the collision `.col` (landmarks keep a collision box too).
- **Terminal look:** those boxes are not drawn as office blocks. `building_geom.py`
  marks them as roof type 2 and gives the walls their own vertex ring carrying the reference cladding colour
  (`facade_colour_hex`, else light grey), the glazing share (`glass_share`, else 0.5) and the glass tone
  (`glass_hex` luminance); the roof keeps `roof_colour_hex` (else the imagery colour as the city shades it)
  and gets no stairwell box or water tank (`terminal_ref.facade_look`). `world/building_terminal.gdshaderinc`
  draws a curtain wall: plinth, one tall glazed band with 1.5 m mullions and 4.5 m transoms, a fascia under
  the roof edge and piers every 18 m (less glass = deeper fascia, wider piers, spandrels per storey), a
  standing-seam roof; no storey windows, balconies or shopfronts. At night the glazed hall glows evenly
  (warm white, a little brighter low down) instead of random lit rooms. Scenes `term_<icao>_apron`, `term_voml_night`
  (VANM, VOML, VOGA, VOSH ...).

| ICAO | Terminal (OSM) | Was (OSM tag or synthetic) | Now | Source of the height |
|---|---|---|---|---|
| VOKN | Kannur (`way/392012106`) | 30 m box (OSM tag) | landmark: 14 m eaves, 26 m gables | photos (low) |
| VOGO | Dabolim (`way/889406836`) | 10.6 m (OSM tag) | landmark: 18 m eaves, curved roof 24 m | 4 storeys (medium) + model |
| VANM | Navi Mumbai T1 (`way/1413816601`) | 14.3 m synthetic | 22 m, white roof | model (3 floors + mezzanines) |
| VOML | Mangaluru (`relation/20984353`) | 18.8 m synthetic | 14 m | 3 levels (medium) + model |
| VOGA | Mopa (`way/1180144485`) | 17.9 m synthetic | 16 m | model |
| VOSH | Shivamogga (`way/1433698918`) | 11.3 m synthetic | 10 m, off-white roof | model |
| VOSR | Sindhudurg (`way/890926927`) | 18.3 m synthetic | 9 m | model |
| VOBM | Belagavi (`way/555353911`) | 13.9 m synthetic | 9 m | model |
| VOCL | Karipur (`way/254158852`, all blocks) | synthetic | 10 m | 2 storeys (medium) + model |

Not linked on purpose: VAKP (the OSM outline, 1,405 m², looks like the old terminal), VARG (new civil
terminal under construction; the OSM building is the small existing one), VOBM Terminal 2 (not built in
OSM), VAJJ (only the ONGC helicopter terminal is mapped). VAAV and VA1M are strips without a terminal;
VOCC (INS Garuda) has had no civil terminal since 1999.

**Extending it.** Add or correct a terminal entry (keep nulls for unknowns, a confidence per value, the
URL and access date of each source), link its footprint by putting the OSM id from
`data/processed/terminals/<ICAO>.json` (15_terminals.py prints them) in `osm`, put modelling guesses
in `model` with a `basis`, then re-run `16_terminal_models.py` (if it is a landmark) and `10_buildings.py`.
To promote an airport to a data-only landmark set `model.recipe = "generic"` and `model.roof`; a
building that needs its own shapes (like Kannur's gabled canopy) gets a function in
`terminal_styles_ref.py`. The showcase views are in `game/tests/showcase_terminal_scenes.gd`
(`term_<icao>_apron` / `_appr`, `term_vokn_gate`), generated from the terminal centroids, stands and runways.

## Sources

Per-terminal sources of the reference data set are in `tools/ref/terminals_reference.json`. Kannur:
- KIAL, passenger terminals: https://www.kannurairport.aero/corporate/passenger-terminals
- Wikipedia, Kannur International Airport (lead): https://en.wikipedia.org/wiki/Kannur_International_Airport
- Airport Technology, Kannur: https://www.airport-technology.com/projects/kannur-international-airport/
- JSW Steel, Kannur project: https://www.jswsteel.in/project/kannur-international-airport/
- Wikimedia Commons photos (viewed only): https://commons.wikimedia.org/w/index.php?search=Kannur+International+Airport+terminal

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
