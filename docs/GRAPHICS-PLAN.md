# Graphics to the maximum: plan

Goal: push the look as far as Godot 4.7 allows on a strong GPU (dedicated card or Apple M-series Pro/Max) without making Low / Medium worse on integrated GPUs (PLAN.md §8b).

Steps run least time, risk and complexity first. Each ships on its own and is checked before the next starts. G0–G6 are done; G7–G10 are open.

## 1. Facts that shape the plan

- Renderer: Mobile on Low / Medium, Forward+ on High and above (a preset change writes `override.cfg` and asks for a restart). `ssao` and `taa` do nothing on Mobile (`core/graphics_settings.gd`).
- Sky: physical single-scattering (`world/atmosphere.gd`, `sky_clouds.gdshader`).
- Clouds: full-screen raymarch (`world/volumetric_clouds.gdshader`).
- Terrain: Sentinel-2 imagery at 10 m per pixel (20 m in the corridor, 80 m in the outer ring), 30 m DEM, 64×64 cells per quadtree node. 10 m is the limit for freely usable imagery (docs/LICENSING.md; Google / Bing not allowed).
- Buildings (`world/building.gdshader`): procedural windows, balconies, roofs, weathering, night windows. Detail fades with distance, so from the air the city reads as pale blocks.
- Trees: crossed-quad impostors from a startup atlas, real meshes within 90–150 m.
- Aircraft: reflection probe captured once (`aircraft/common/reflection_rig.gd`); AO baked into the textures.

## 2. Steps

### G0. Baseline (done)
`tools/bench.sh` runs fixed showcase scenes (`--bench=<s>`) on each preset and renderer with vsync off. Every later step is judged against it; no step may drop Low / Medium fps. See USAGE.

### G1. Settings-only wins and a Max preset (done)
- `max` preset in `graphics_settings.gd`: render scale 1.25–1.5, MSAA 4×, shadow distance 6 km, cloud steps 64, `lod_k` 2.4, building radius 16 km, trees 4 km, density 1.4, tree LOD radius 250 m. Test: `tests/test_graphics_presets.gd`.
- Anisotropic filtering 16×, shadow atlas 8192 on High+, soft shadows on Ultra.
- Tonemapper Filmic → AgX.

### G2. Forward+ for High / Ultra / Max (done)
- Each preset carries a renderer. On Forward+: SSAO, SSIL (Max), SSR (water and wet runways), TAA (FSR2 when render scale < 1).
- Forward+ lifts Mobile's per-mesh light limit, so `REAL_LIGHTS` in `runway_lights.gd` and the apron floodlights are higher on Max.
- Watch: shaders with `fog_disabled` and their own haze (terrain, buildings) must match; TAA ghosting on the propeller disc and instruments.

### G3. Per-feature upgrades (done)
Reflection probe refresh on Max; cloud lighting (two-lobe Henyey–Greenstein phase, powder darkening, multiple-scattering octaves, more light samples on Max); water sun glint, finer wave normals, deeper colour away from shore (`terrain_water.gdshaderinc`); contact shadows / AO under aircraft and vehicles on Forward+.

### G4. Horizon fix (done)
- **Curvature:** `world/curvature.gdshaderinc` (`curve_drop()` = d²/2R from `terrain_eye`; `curve_local()` maps it into mesh space), CPU twin `world/curvature.gd`. Used by terrain, buildings, terminals, both tree shaders, runway / taxiway ribbons (`strip.gdshaderinc`), stand paint and light points; `tests/test_horizon.gd` checks every far shader includes it. Visual only: FDM terrain queries are untouched. Ground within ~700 m of the aircraft stays flat while the camera is < 4–8 km away (tower / fly-by views); the aircraft itself is not bent. Not bent: vehicles, jetways, props, apron light pools. The cloud layer follows the same curvature. The sky horizon dips by altitude (`horizon_dip`, `HazeLut.horizon_dip_sin`). The terrain reaches the horizon (outer ring to ±490 km, camera far 160 km).
- **Haze:** `world/haze_lut.gd` fills a 32×8 RGBAH table (angle to the sun azimuth × elevation above the dipped horizon) from `Atmosphere.sky()` plus the sky shader's sun glow. `world/haze_sky.gdshaderinc` `haze_color(dir)` blends it over fog_color, so overcast, night and lightning stay in fog_color. Refilled when the sun moves 0.25° or the aerosol changes, one row (~1 ms) per frame. Globals: haze_lut, haze_sun, haze_ref.
- **Clouds:** over the last 45 % of `max_dist` density blends to the layer's mean density (CloudLayer `mean_density`); beyond it the layer continues as a uniform veil to where the ray leaves the curved slab, so there is no cut at the horizon. `max_dist` is 60 km on Max (preset key `cloud_dist`), 25 km below.

### G5. Volumetric fog (done; Forward+ only)
Code: `world/volumetric_fog.gd` (driven by the weather Props each frame), `vfog_rules.gd` (pure maps and quality table), `vfog_composite.gd/.gdshader`, `vfog_air.gdshader`, `vfog_rain.gdshader`. Preset key `vfog` 0 / 0 / 1 / 2 / 3 (Low .. Max); option `volumetric_fog` (on, High+, Forward+, PostFxRules). Tests: `tests/test_volumetric_fog.gd`. Scenes: `fog_shafts`, `fog_storm_curtain`, `fog_dawn_mist` (`tests/showcase_fog_scenes.gd`); `--no-vfog` gives the "before". Details: USAGE "Volumetric fog".

Findings (Godot 4.7.2, Metal):
1. `render_mode fog_disabled` skips volumetric fog as well as Environment fog. So terrain, buildings, trees, water and the cloud pass never see it. A composite pass (n + 1 full-screen planes in one draw at the froxel slice depths, the Environment fog pre-inverted) puts it back. The aircraft keeps the engine's own fog; the cloud pass, rain and light points draw after it. Only plain exponential Environment fog can be inverted (checked every frame).
2. FogVolume density is fixed point (~1/1024 per m; 0.001 vanishes, 0.0015 shows). Thin air goes into the Environment's float `volumetric_fog_density`. FogVolumes carry only dense things (mist, rain curtains, in-cloud puffs) or cut the thin air away (negative density, clamped at 0) in cloud shadows and above the haze top.
3. Global shader uniforms read wrong values in fog shaders; pass them as material parameters.
4. A `Color` set on a `vec3` uniform arrives linearised; pass a `Vector3`.

Limits:
- The inversion multiplies any mismatch with the engine's fog by 1 / (1 - f), so the last plane stops where Environment fog reaches 75 % (`VfogRules.ENV_FOG_LIMIT`). The froxel fog reaches about half the visibility in haze, the full 5 / 10 / 14 km only in clear air.
- The froxel air glows with the haze colour (`volumetric_fog_emission` = fog colour × 1.1; ambient inject off), so it does not tint the custom haze. Shaft air under broken cloud: haze × (0.1 + 0.3 × broken × sun).
- **Light shafts are not achieved.** Stronger air only gave a bright layer under the cloud base with a hard horizon edge. They need cloud-shadowed in-scatter that trees and the cloud pass also receive.
- **Dawn mist is off** (`VfogRules.MIST_ENABLED`). The mist pool shows a hard straight edge a few km out, and lit canopy tops stand out of it as pale speckles. The mist profile and range need a fix first.
- Tree impostors are alpha-tested (`ALPHA_SCISSOR_THRESHOLD` 0.5 with `alpha_to_coverage_and_one`), so they draw in the opaque pass, write depth and get the fog. `ALPHA_ANTIALIASING_EDGE` turned distant impostors black at Ultra. Impostor shadows stay off: +9-10 ms at Ultra.
- Night air sits in a 400 m ground layer and scales with humidity and low visibility.
- Cost (M5 Max, 1080p, `fog_shafts`, noisy): roughly +0–5 ms (High 25.0 vs 28.7 off, Ultra 33.5 vs 28.5, Max 44.2 vs 40.3). Re-measure on a quiet machine (`tools/bench.sh`, `--no-vfog`).
- Open: rain curtains are hard to judge (showers are seeded per run); night glow only works round real Omni/SpotLights (light points are sprites).

### G6. Terrain detail materials (done)
- **Assets:** `tools/26_terrain_textures.py` fetches 11 ambientCG 1K sets (CC0, into `data/raw/textures/`) and packs two 1024 px Texture2DArrays in `game/world/textures/terrain/` (lossy WebP in git, 5.5 + 13.8 MB; VRAM-compressed on import). `detail_mod` is high-passed, contrast-normalised albedo modulation (0.5 = unchanged); `detail_nrm` is normal xy, roughness offset, AO. Layers: soil, grass, scrub, laterite, rock, forest floor, urban, sand, mud, concrete, asphalt (`SOURCES.md`).
- **Shader:** `world/terrain_detail.gdshaderinc`, bound once by `world/terrain_detail.gd`. WorldCover class picks a layer: the two strongest of the 4 class texels around the fragment (the third's weight is subtracted so a rank change is seamless). Sand replaces open classes within ~25-70 m of the sea. Rock is projected on vertical planes above ~35° (Ghats cliffs). Three scales per layer (~3 m, ×4.37, ×19.3, each rotated and offset; fine skipped beyond 160 m, coarse inside 40 m) so nothing repeats from altitude. Multiplied under the imagery colour, plus normal, roughness and AO; fades 650 -> 1200 m.
- **Aprons:** aprons are terrain, and the urban patches, macro blotches and class tint made them pink / grey slabs. `tools/27_pavement.py` (+ `pavement_raster.py`) writes `terrain/pv/0/<tx>_<ty>.png` (RGBA, 4 m, 38 tiles): signed distance to the pavement edge, offset from the nearest stand lead-in, slab-joint direction, surface (concrete / asphalt from OSM `surface`) and stand wear. Pavement = OSM aeroway areas (incl. multipolygons, cached in `osm/aeroway_areas.json`), runway / taxiway shoulders (+7.5 / +4 m), a pad round every stand and a 38 m closing near stands (OSM lacks e.g. the VABB T2 apron). `world/terrain_pavement.gdshaderinc` replaces the ground detail there: concrete slabs 5 × 6.25 m along the airport's longest runway, per-slab tone, joints fading by ~380 m, asphalt with patches, rubber / grime streaks, tyre marks along lead-ins, oil stains where aircraft stand. Loaded with the road tile (`terrain_roads.gd`), bound by `terrain_quadtree.gd` (`pv_tex`, `pv_on`); fades 2-3.3 km.
- **Tests:** `tests/test_terrain_detail.gd` (shader compiles, one layer per set, credits / licensing list every set, encodings agree, at least 95 % of the stands of VABB / VAPO / VOCI / VOGO / VANM on pavement).
- **Not done:** per-slab normal tilt and edge spalling, apron markings beyond stand lines, hex tiling, detail on the outer ring.

### G7. Clouds at full quality (1–1.5 weeks, medium-high risk)
- Raymarch at half (High) or quarter (Max) resolution into a buffer, reproject the previous frame and blend. This removes the grain and makes 96–128 steps affordable. Upsample with depth so edges against terrain and the aircraft stay sharp.
- `CompositorEffect` (compute) or a SubViewport pass: decide in a 1-day spike.
- Risk: ghosting on fast turns or view switches; reset the reprojection on camera cuts.

### G8. Trees and buildings up close (1–2 weeks, medium-high risk)
- Trees: octahedral impostors (8–16 baked angles with normals), colour variation per species and season, wind sway in the vertex shader, darker canopy undersides.
- Buildings (done in `world/building.gdshader`): the window pattern fades with the pixel footprint and the average glass tone stays out to the draw distance, so a 3° final still reads as a city rather than plain blocks. A dark band at the base seats each wall on the ground within about 1.6 km. Wall colours, curtain-wall towers, parapets, stair boxes and water tanks were already there.

### G9. Terrain geometry (1–2 weeks, high risk)
- 128×128 cells per node on Max and fractal height detail within ~2 km.
- Risk: the visible ground no longer matches the FDM terrain (wheels sinking or floating, trees and buildings at the wrong height). The detail must be zero on runways, aprons and roads and stay within a few metres. `tests/test_landing.gd` and the e2e sweep must pass.

### G10. Art (ongoing, the owner's Blender work)
Higher-resolution cockpit and exterior textures, separate AO / roughness / metal maps, baked AO for the cockpit interior (`tools/blender`). Optional: lens flare, a colour-grading LUT per weather.

## 3. Rough totals

| Steps | Time | Risk |
|---|---|---|
| G0–G2 | ~4 days | low |
| G3–G5 | ~1.5 weeks | low–medium |
| G6–G7 | ~2.5 weeks | medium–high |
| G8–G9 | ~3–4 weeks | high |
