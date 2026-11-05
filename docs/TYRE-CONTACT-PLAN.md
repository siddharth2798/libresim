# Tyres that never sink into the ground

Goal: for every aircraft (all of `AircraftDef.list_ids()`, now and future), on every surface (runway, taxiway, apron, stand, grass, slope) and at every camera distance, the tyres touch the surface you see. No visible sinking, no floating.

Status: done (§4).

## 1. Causes

1. **Pavement was drawn 12 cm above the FDM ground.** `world/airport_builder.gd` (`LIFT := 0.12`) built ribbons at `terrain.height_at() + 0.12` against z-fighting, while the FDM ground (`fdm/fdm_node.gd`) is `terrain.height_at()`. Measured (`tests/test_ground_contact.gd`): median +0.120 m, max 0.16 m on runways and 0.22 m on taxiways (VABB). The strip shader added `lod_lift` × camera distance on top (2 cm at 30 m, 0.7 m at 1 km, 3 m at 4.5 km), so far views sank the wheels completely. This was the main cause.
2. **Ribbons were flat across their width** (two vertices across), while the FDM reads the DEM at the wheel. Small.
3. **FDM and terrain mesh interpolated the DEM differently.** The FDM used bilinear, the mesh uses two triangles per cell. Difference up to 0.13 m (VABB aprons), 0.04–0.06 m on grass.
4. **Coarse LODs and geomorphing** moved the visible ground away from the full-resolution surface when the camera was far. Finest nodes (30 m) only within ~3 km, geomorph from 3.7 km.
5. **No leg compression in the model for fixed gear.** The C172 nose floated +0.032 m (model 9.9 cm above the contact, static compression 6.6 cm). The A320 mains sat −0.032 m (its `lift_m` −0.04 / 0.0 were wrong; the main contact is under the outer wheel, 0.45 m from the bogie axle centre).
6. **Other lifted overlays:** the stand lead-in line and stop bar (+0.18 m), stand number (+0.20 m), green taxi-route line (+0.25 m). Terminal solids, jetways and touchdown decals have no offset.

## 2. Fixes

- **G1. Pavement at true height.** `world/ground_drape.gd` (GroundDrape) cuts every overlay triangle along the terrain lattice (x, y and the TerrainMesh diagonal x + y, 30 m) and takes `TerrainTileCache.height_at` at each vertex, so ribbons are coplanar with the finest terrain and the FDM ground. `airport_builder.gd` has no LIFT and no densify step. The cutting (~230 k vertices, ~1 s for all airports) runs on a worker thread with its own height cache (`build(t, true)` builds synchronously for tests). Z-fighting is solved by the view-space pull in the shader (runway 0.9985, taxiway 0.999, lead-on 0.998). The distance lift stays for the far field only: `world/ground_lift.gdshaderinc` fades it to 0 within 220–380 m of `ground_focus` (a shader global, the aircraft). Stand lead-in line, stop bar and the taxi-route line are draped the same way (`world/ground_paint.gd` + `ground_paint.gdshader`, pulls 0.998 / 0.9975). The stand number Label3D sits at +0.04 m (no depth pull possible).
- **G2. One height function.** `TerrainTileCache.height_at` interpolates the two TerrainMesh triangles (diagonal (i+1, j)–(i, j+1)) instead of bilinear. Max |FDM − drawn terrain| is 0.000 m.
- **G3. Finest LOD under the aircraft.** `TerrainQuadtree.focus` (set to the aircraft model by `flight.gd`): nodes within `FOCUS_KEEP_M` = 400 m always split to the finest level and never geomorph. It also sets `ground_focus`.
- **G4 / G5. Generic leg compression and contact check.** `aircraft/common/tyre_contact.gd` (TyreContact, replaces `AircraftModel._legs`). Per wheel contact it raises the leg pivot (`compress`) or, for fixed gear, the glb meshes named like wheel / tyre / fairing / brake / strut nearest the contact (or `model.wheels` {contact: [nodes]}), every frame. The lowest tyre point (axle − radius, measured from the meshes in the rest pose) lands on the FDM ground under its axle (compression + `FDM.ground_height`), so slopes and static attitude do not matter. If nothing is found, the whole model moves (no tyre sinks). The placeholder airframe names its wheels too. A320 `lift_m` was removed (measured now); `lift_m` stays an optional override. In the air the C172 nose wheel hangs 9.9 cm lower and the mains 3.9 cm (full extension, as the FDM contact points).

## 3. Tests (all in `tests/run_tests.gd`)

- `test_ground_contact.gd`: FDM ground equals the drawn terrain triangles (independent re-implementation reading the TerrainMesh index buffer) and the ribbon geometry within 1 cm at runway / taxiway / apron / grass samples at VABB, VAPO, VOCI. Max error 0.000 m.
- `test_tyre_contact.gd`: every aircraft of `AircraftDef.list_ids()` and a placeholder airframe, rested by the FDM on flat ground and on 2.5 % / 1.5 % slopes: tyre bottom − ground within 2 cm (now ≤ 2 mm).
- `test_a320_integration.gd`: parked-tyre test uses TyreContact.
- Render check: `tests/debug_tyres.gd` (any aircraft, `--place=grass|slope`, `--far` for 1.5 and 4.5 km zoomed views; see its header). The 4.5 km views are mostly blocked by trees or too small to judge G3; G3 is covered by its code path only.

## 4. Status: done

G1–G5 and the tests above are in. Tyres stand on the surface in every view (C172 and A320 on a VABB stand, on the VAPO / VOCI runway, on grass, on an 11 % slope).
