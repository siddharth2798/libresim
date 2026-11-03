# Tyres that never sink into the ground: plan

Goal: for every aircraft (all of `AircraftDef.list_ids()`, now and future), on every surface (runway,
taxiway, apron, stand, grass, sloped terrain), at every camera distance, the tyres touch the surface
you see: no visible sinking and no floating. Written 2026-11-03; **done 2026-11-04** (status in §4).

## 1. Causes found (facts, from the code)

1. **Pavement is drawn 12 cm above the ground the FDM stands on.** `world/airport_builder.gd`
   (`LIFT := 0.12`) builds runway / taxiway ribbons at `terrain.height_at() + 0.12` to stop z-fighting,
   while the FDM's ground is `terrain.height_at()` itself (`fdm/fdm_node.gd`). So on all pavement the
   tyres sit 12 cm into the visible surface. This is the most likely thing seen.
2. **Ribbons are flat across their width.** Each ribbon has two vertices across (the edges); the
   middle of a 45–60 m runway is a straight line between the edge heights, while the FDM reads the
   bilinear DEM at the wheel. Any crown or cross-slope makes them differ (mostly small, since tools/02
   flattens runways and aprons).
3. **The FDM and the terrain mesh interpolate the DEM differently.** The FDM uses bilinear
   interpolation of the 30 m heightmap (`TerrainTileCache.height_at`); the rendered terrain is two
   triangles per cell. On curved ground (grass strips, off-runway, rough fields) the difference is
   ¼·(h00 + h11 − h10 − h01), which reaches tens of cm.
4. **Coarser terrain LODs and geomorphing** move the visible ground away from the full-resolution
   surface when the camera is far (tower, fly-by, orbit zoomed out).
5. **Aircraft without leg compression in the model.** The A320 raises its legs by the gear compression
   (`"compress"` pivots, ±1.5 cm measured). The C172 has no such pivots, so its tyres sink by the
   static spring deflection of the FDM gear. Any future aircraft without `compress` data sinks too.
6. **Other surfaces** (apron and stand areas, terminal solids, `ops_solids.gd`) may have their own
   offsets; to be checked the same way.

## 2. Fix (one ground truth for physics and pictures)

- **G1. Pavement at true height (½ day).** Build ribbons at the FDM ground height and stop z-fighting
  in the shader instead: pull the vertices slightly towards the camera in view space (a depth bias that
  grows with distance), so the paint wins the depth test without being physically higher. Add
  cross-runway vertices every ~10 m so ribbons follow the DEM across their width. Same treatment for
  any other overlay mesh that is lifted for z-fighting.
- **G2. One height function (½ day).** Make the FDM read the ground exactly as the finest terrain mesh
  draws it: the same triangle split as `TerrainMesh` (same diagonal) instead of bilinear. Then the
  ground under the wheels and the drawn ground agree at the finest LOD by construction.
- **G3. Keep the finest LOD under the aircraft (½ day).** The terrain quadtree always keeps the node
  under the aircraft (and its neighbours within ~150 m) at the finest level with no geomorph, whatever
  the camera distance. Cheap: a few nodes.
- **G4. Generic leg compression (1 day).** Every aircraft's model raises each leg (or each wheel, for
  fixed gear like the C172) by its gear contact's compression. Fixed gear without leg pivots: move the
  wheel/fairing pivots, or failing that the whole model, so the lowest tyre point sits on the contact
  point. Data in `aircraft.json` (`compress` on pivots), with a fallback computed from the model's
  wheel positions so a new aircraft works without it.
- **G5. Check tyre radius and contact points per aircraft (½ day).** Measure the lowest tyre vertex of
  each wheel in each exterior glb against the FDM gear contact point plus static compression; fix
  config/model data where they differ.

## 3. Tests (stop it coming back)

- Unit test over every aircraft: lowest tyre vertex − contact point − static compression ≈ 0 (±2 cm).
- Ground test: for sample points on runways, taxiways, aprons and grass at VABB / VAPO / VOCI, the
  FDM ground height equals the rendered surface height (ribbon or terrain triangle) within 1 cm.
- Rendered check (tests/debug_tyres.gd exists): screenshots at the wheels of each aircraft parked on a
  stand, on a runway, on grass, on a slope, and from a far tower view.

Order: G1 → G2 → G5 → G4 → G3 (most visible first). About 3 days in total.

## 4. Status (2026-11-04): done

### Causes, measured before the fix
- **Pavement lift (cause 1): confirmed, the main one.** Ribbon height − FDM ground at sample points
  (tests/test_ground_contact.gd): median **+0.120 m** everywhere, max 0.16 m on runways and **0.22 m** on
  taxiways (VABB), 0.18 / 0.16 m (VAPO / VOCI taxiways). The strip shader added `lod_lift` × camera distance
  on top (2 cm at 30 m, 0.7 m at 1 km, 3 m at 4.5 km), so far / zoomed views sank the wheels completely.
- **Stand paint and route line, also lifted (cause 6): confirmed.** AirportOps' stand lead-in line and stop
  bar were 2 cm boxes at **+0.18 m** (top 0.19 m) on the nose-wheel track, the stand number at +0.20 m, and
  the green taxi-route line (RouteLine) at **+0.25 m**: the nose wheel rolled "through" them.
  Terminal / ops solids, jetways and touchdown marks (decals) have no ground offset.
- **Flat ribbons across the width (cause 2): confirmed, small**: it is the part of the 0.12 → 0.22 m spread
  above the lift.
- **Bilinear vs triangles (cause 3): confirmed.** |FDM ground − drawn terrain triangles|: max 0.13 m on
  VABB aprons, 0.07 m on taxiways, 0.04–0.06 m on grass, 0.02 m on runways (median 0: mostly flattened).
- **Coarse LOD / geomorph (cause 4): confirmed in code.** Finest nodes (level −2, 30 m) only within ~3 km of
  the camera, geomorph from 3.7 km; level 0 deviates by metres (tools/17).
- **No compression on fixed gear (cause 5): confirmed, and the A320 data was off.** Lowest tyre vertex −
  ground, parked on flat ground (tests/test_tyre_contact.gd): C172 nose **+0.032 m** (floating: its model
  sits 9.9 cm above the contact, static compression 6.6 cm), mains −0.005 / −0.001 m; A320 mains
  **−0.032 m**, nose −0.020 m (its lift_m −0.04 / 0.0 were wrong; the main contact is under the outer
  wheel, 0.45 m from the bogie axle centre).

### Fixes
- **G1** world/ground_drape.gd (GroundDrape): every overlay triangle is cut along the terrain lattice
  (x, y and the TerrainMesh diagonal x + y, 30 m) and takes TerrainTileCache.height_at at each vertex, so
  ribbons are coplanar with the finest terrain and with the FDM ground. airport_builder.gd: no LIFT, no
  densify step; the cutting (≈230 k vertices, ~1 s for all airports) runs on a worker thread with its own
  height cache (`build(t, true)` builds synchronously for tests). Z-fighting: the existing view-space pull
  (runway 0.9985, taxiway 0.999, lead-on 0.998). The distance lift is kept for the far field only:
  world/ground_lift.gdshaderinc fades it to 0 within 220–380 m of `ground_focus` (new shader global, the
  aircraft). Stand lead-in line / stop bar and the taxi-route line are draped the same way
  (world/ground_paint.gd + ground_paint.gdshader, pulls 0.998 / 0.9975); the stand number Label3D is at
  +0.04 m (no depth pull possible).
- **G2** TerrainTileCache.height_at interpolates the two TerrainMesh triangles (diagonal (i+1, j)–(i, j+1))
  instead of bilinear; same signature. Max |FDM − drawn terrain| now 0.000 m at all samples.
- **G3** TerrainQuadtree.focus (set to the aircraft model by flight.gd): nodes within FOCUS_KEEP_M = 400 m
  of it always split to the finest level and never geomorph, whatever the camera distance; it also sets
  `ground_focus`.
- **G4/G5** aircraft/common/tyre_contact.gd (TyreContact, replaces AircraftModel._legs): per wheel contact,
  the leg pivot ("compress"), or for fixed gear the glb meshes named like wheel / tyre / fairing / brake /
  strut nearest the contact (or `model.wheels` {contact: [nodes]}), are raised every frame so that the
  lowest point of each tyre (axle − radius, measured from the meshes in the rest pose) is on the FDM ground
  under its axle (compression + FDM.ground_height, so slopes and the static attitude do not matter).
  Nothing found: the whole model moves (no tyre sinks). The placeholder airframe names its wheels so it
  works too. A320 `lift_m` removed (measured now); `lift_m` stays an optional override.
  In the air the C172 nose wheel hangs 9.9 cm lower, the mains 3.9 cm (gear at full extension, as the FDM
  contact points).

### Tests (all in tests/run_tests.gd)
- test_ground_contact.gd: FDM ground == drawn terrain triangles (independent re-implementation reading the
  TerrainMesh index buffer) and == ribbon geometry within 1 cm at runway / taxiway / apron / grass samples at
  VABB, VAPO, VOCI: max error 0.000 m.
- test_tyre_contact.gd: every aircraft of AircraftDef.list_ids() and a placeholder airframe, rested by the
  FDM on flat ground and on a 2.5 % / 1.5 % slope: tyre bottom − ground within 2 cm (now ≤ 2 mm).
- test_a320_integration.gd parked-tyre test updated to TyreContact.
- Render check: tests/debug_tyres.gd (generic now: any aircraft, `--place=grass|slope`, `--far` for 1.5 and
  4.5 km zoomed views), see its header.
- Before / after renders (2026-11-04, Ultra, 1920x1080; before = HEAD 8a00ded): PNGs in the session scratchpad
  `tyres/before`, `tyres/after`, side-by-side in `tyres/compare` (C172 and A320 on a VABB stand, on the
  VAPO / VOCI runway incl. 1.5 / 4.5 km zoomed views, beside the runway on grass, C172 on an 11 % slope).
  Before: C172 tyres hidden in the runway up close, both aircraft half sunk at 1.5 km; A320 tyres cut by the
  floating stand lead-in line. After: tyres on the surface in every view. The 4.5 km views are mostly
  blocked by trees / too small to judge G3 visually; G3 is covered by its code path only.
