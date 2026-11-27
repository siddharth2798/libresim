# Graphics to the maximum: plan

Goal: push the look as far as Godot 4.7 allows on a strong GPU (dedicated card or Apple M-series Pro/Max) without making Low / Medium worse on integrated GPUs (PLAN.md §8b).

Steps run least time, risk and complexity first. Each ships on its own and is checked before the next starts. G0–G6 are done; G7–G10 are open.

## 1. Facts that shape the plan

- Renderer: Mobile on Low / Medium, Forward+ on High and above (a preset change writes `override.cfg` and asks for a restart). `ssao` and `taa` do nothing on Mobile (`core/graphics_settings.gd`).
- Anti-aliasing: SMAA 1x on every preset when neither TAA (Ultra, Max) nor FSR2 (Forward+ below scale 1) runs (`core/screen_aa.gd`, preset key `post_aa`, option Edge smoothing); it replaced FXAA on Low / Medium. Export presets bake shaders (`shader_baker/enabled`; USAGE 4b).
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
- Done so far: half resolution on every preset up to Ultra and quarter resolution on Max (`world/cloud_upscale.gd`, `cloud_temporal.gd`), with the depth copy as a CompositorEffect (`cloud_depth_copy.gd`). On Mobile (Low, Medium) the copy runs after the transparent pass. Godot 4.7.2's Mobile renderer rejects POST_OPAQUE, and until that fix the copy never ran and Low and Medium fell back to the full-resolution march. The march and history viewports are float (`use_hdr_2d`); 8-bit targets clipped lit cloud above 1.0 and flattened the deck. Compatibility stays full resolution (no CompositorEffect). Mobile features must be checked on the running renderer, not taken from the Godot docs.

### G8. Trees and buildings up close (1–2 weeks, medium-high risk)
- Trees (done, details in USAGE "Trees"; tests `tests/test_tree_look.gd`, `tests/test_ground_cover.gd`; shots `review_screenshots/trees/before|after`):
  - Species by region, height and ESA WorldCover (`world/tree_species.gd`): forest broadleaf (teak, semi-evergreen Ghats), coconut palm (Konkan / Kerala villages and paddies), acacia scrub (Deccan, shrubland, laterite), casuarina / eucalyptus, and wide village trees (mango, banyan, peepal). Positions unchanged; heights in families (broadleaf and village trees keep the old height exactly). Runway ribbons from `runways.json` are kept clear in every tree path (`world/tree_clear.gd`).
  - Near meshes built at startup (`tree_meshes.gd`, `tree_parts.gd`): dark grey-brown trunk and limbs, 6–9 clumps of alpha-tested leaf cards with gaps and backlight (own leaf texture, `tools/tree_leaf_cards.py`, 4 × 2 cells), palms with a slender curving ringed trunk, 20 narrow feathery V-folded fronds, dead brown fronds hanging below and a coconut cluster, casuarina with hanging needle strands. LOD0 324–642 triangles with detail that shrinks away by 0.4 × the near radius, LOD1 80–226; the cell mesh swap happens where nothing is left to pop.
  - Hemi-octahedral impostors (`tree_atlas.gd`, `tree_octa.gd` / `.gdshaderinc`, `tree_bake.gdshader`, `tree.gdshader`): 8 × 8 frames per species baked from LOD1 at startup in one orthographic render per pass (albedo + cover RGBA8, normal RG8, block-compressed at bake time where available), one camera-facing quad per tree cut to the species' box seen along the view, three frames blended with per-frame plane projection on High and up, nearest frame and a single projection on Low / Medium. Frame 64 px (Low), 72 (Medium), 96 (High+): 3.3 / 4.2 / 7.5 MB compressed, at most 10.5 / 13.3 / 23.6 MB uncompressed (was 11 MB). Mesh-to-impostor handover stays a per-pixel dither (works on Mobile and Compatibility; visibility-range fades would act per 480 m chunk).
  - Far shadows: shadow-only 28-triangle opaque proxies per impostor chunk within 500 / 800 / 1200 m on High / Ultra / Max (`tree_shadows.gd`, `tree_shadow.gdshader`); beyond that and on Low / Medium the terrain canopy shade (`terrain_canopy.gdshaderinc`: edge shadows away from the sun, crown relief on High+, leaf litter near the camera).
  - Ground cover (`ground_cover*.gd`, `ground_roads.gd`, `ground_cover.gdshader`): ferns and bushes under canopy, grass on grassland and farmland, dry grass on the plateau and laterite, by WorldCover class; off water, roads, rivers, runways, taxiways and aprons; 24 m camera cells placed in world terms, seed-phased sway. Radius Low 0, Medium 18 m, High 40, Ultra 50, Max 65.
  - Season tint from the date (`TreeLook.dryness`), sway phase from the tree's seed (no jump at an origin shift).
  - Not done: depth-based parallax in the impostors; shadows from ground cover; per-instance palm lean variants.
  - Cost, measured on Apple M4 only (MacBook Air, Vulkan through MoltenVK, 1920 × 1080, auto resolution settled at 70 %, 8 s per run). First pass (G8 trees without grass or proxy shadows, back-to-back runs): Low runway 17.5 → 20.1 ms, Medium Ghats 23.5 → 27.2 ms, the rest within noise. Second pass: tighter impostor quad, no 4 × 4 inverse, one projection on Low / Medium, smaller block-compressed atlas, relief and litter noise only where the preset pays for it. Final, before → after in interleaved runs (the same scene alternating old and new build, because this fanless Mac drifts by up to 25 % over a session; frame ms, two runway views averaged): Low runway 18.9 → 19.1 (two rounds), Ghats 21.2 → 20.9, palms 18.7 → 18.5; Medium runway 26.7 → 23.9, Ghats 24.6 → 25.3, palms 24.7 → 22.4; High runway 50.2 → 53.2, Ghats 58.7 → 57.9, palms 48.8 → 48.7; Ultra runway 72.0 → 65.8, Ghats 76.6 → 74.4, palms 60.2 → 60.0. High and Ultra now include the ground cover (2000–3000 plants in view) and 9000–15000 shadow proxies, so far shadows cost far less than the old +9–10 ms. Atlas GPU memory: 3.3 / 4.2 / 7.5 MB (Low / Medium / High+) compressed, at most 10.5 / 13.3 / 23.6 MB where no compressor is available (was 11 MB). Other GPUs: impostors cost 2 texture fetches (Low / Medium) or 6 (High+) per covered pixel and cover a quarter to a half of the old quad area; BC3/BC5 sampling halves to quarters the bandwidth on every desktop GPU (all support S3TC/BC); ETC2 is used where S3TC is not reported; near meshes are fewer triangles but more alpha-tested fill, which costs most on tile-based GPUs (Apple, Mali) and older integrated parts; ground cover is 40–90 extra draws on High+ only; proxy shadows add 28 triangles per tree to the shadow passes within 500–1200 m; nothing depends on the vendor or API.
- Buildings (done in `world/building.gdshader`): the window pattern fades with the pixel footprint and the average glass tone stays out to the draw distance, so a 3° final still reads as a city rather than plain blocks. A dark band at the base seats each wall on the ground within about 1.6 km. Wall colours, curtain-wall towers, parapets, stair boxes and water tanks were already there.

### G9. Terrain geometry (1–2 weeks, high risk)
- 128×128 cells per node on Max and fractal height detail within ~2 km.
- Risk: the visible ground no longer matches the FDM terrain (wheels sinking or floating, trees and buildings at the wrong height). The detail must be zero on runways, aprons and roads and stay within a few metres. `tests/test_landing.gd` and the e2e sweep must pass.

### G10. Art (ongoing, the owner's Blender work)
Higher-resolution cockpit and exterior textures, separate AO / roughness / metal maps, baked AO for the cockpit interior (`tools/blender`). Optional: lens flare, a colour-grading LUT per weather.

### Phase 2. Draw distances, stand-ins and occlusion culling (done)
Code: `world/vis_ranges.gd` (size-on-screen ranges, preset and zoom scaling, pinning), `vis_chunks.gd` (lamp masts per 400 m cell), `jetway_standin.gd` (one-box HLOD per jetway, `visibility_parent`), `occluder_build.gd` + `occluder_rings.gd` (occluders from a model's walls, 1 m inside), `occluder_jobs.gd` (worker threads), `occlusion_rules.gd` + `hlod_director.gd` (when culling runs; camera zoom). Tests: `tests/test_hlod.gd`, `tests/test_occlusion.gd`. Views: `tests/showcase_hlod_scenes.gd`; `tests/debug_hlod_census.tscn` lists what is in view. Details: USAGE "Draw distances and stand-ins", "Occlusion culling".

Rules (the same on every machine): an object is drawn while it covers 3 px of a 1080p frame at 60° (High), scaled by the preset's `lod_k` / 1.6 and stretched by camera zoom; nothing is tuned to a measured frame time. Jetways become one box at 16 px. Occlusion culling runs within 150 m of the ground (off above 250 m) and only while an occluder is loaded.

Findings (Godot 4.7.2):
1. The Mobile renderer draws no visibility-range fades (checked in a bare scene: Forward+ blends over begin ± margin and end ± margin; Mobile cuts). On Low / Medium a far object switches off at the pixel limit.
2. A `visibility_parent` child shows again while its parent fades out at the parent's far end (Forward+). The stand-in box therefore has no far margin; the near cross-fade (fade mode DEPENDENCIES) works.
3. Forward+ already merges repeated meshes (vehicles, jetway parts) into instanced draws, so removing them cuts objects but hardly draw calls; a fading object is drawn unbatched in the transparent pass, so the fade band costs draw calls (±12 %: +96 draws at the VABB stand, ±5 %: +31, none: −2). The band is ±5 %.
4. Occluders built from the terminal walls cull 26 to 34 objects at a VABB stand, 2 or 3 in the taxi view, and none in the air (`--occlusion-always` on the 3 nm final: the same objects). City buildings are 7.7 km tile meshes and cannot be culled whole, so they get no occluders.

Measured on Apple M4 only (MacBook Air, Metal, 1920×1080, vsync off, 10 s per run, two interleaved runs each). Objects / draw calls are exact; frame times varied up to ±25 % between identical runs on this fanless machine, so no frame-time change below that can be claimed.

| View | Preset (renderer) | Before (objects / draws) | Draw distances | + occlusion | Frame ms before → after |
|---|---|---|---|---|---|
| VABB stand | Low (Mobile) | 1325 / 1325 | 914 / 914 | 888 / 888 | 33 → 33 |
| taxi past the terminal | Low (Mobile) | 1506 / 1506 | 935 / 935 | 932 / 932 | 30 → 27 |
| 3 nm final, 1000 ft | Low (Mobile) | 1861 / 1861 | 732 / 732 | (off) | 29 → 29 |
| VABB stand | Medium (Mobile) | 1347 / 1347 | 1019 / 1019 | 984 / 984 | 18-34 → 15-33 |
| taxi | Medium (Mobile) | 1527 / 1527 | 1050 / 1050 | 1048 / 1048 | 36 → 32 |
| final | Medium (Mobile) | 1884 / 1884 | 758 / 758 | (off) | 35 → 35 |
| VABB stand | High (Forward+) | 1513 / 921 | 1177 / 950 (±5 % fade) | — | 74 → 78 |
| taxi | High (Forward+) | 1697 / 955 | 1264 / 995 (±5 % fade) | — | 71 → 73 |
| final | High (Forward+) | 2114 / 1195 | 988 / 988 | (off) | 71 → 71 |

(The Forward+ ground rows are a later back-to-back set than the Mobile ones; the earlier set with a ±12 % fade had more objects in view but the same pattern.) On this Mac the Mobile runs are CPU-bound (17-28 ms of main-thread and render-setup time) and the Forward+ High runs GPU-bound, and neither is limited by draw calls, which is why the frame times do not move. What carries over to other hardware, from the counts and Godot's design:
- Draw calls and per-object CPU work fall 31-61 % on Mobile (no auto-instancing there): that is what helps integrated GPUs and draw-call-limited drivers (D3D12 / Vulkan on weaker CPUs, older Intel and AMD iGPUs) most.
- On Forward+ the object count falls 22-53 % but draw calls stay level, so the gain is in culling and shadow-caster work, not in submission.
- Occlusion culling is CPU ray casting (Embree) every frame; it removes ~2 % of objects at a stand. On a weak CPU it can cost more than it saves, which is why it is limited to the ground near loaded terminals; from the air it is off.

Not done: occluders for hangars and big city buildings (they would have to be split out of the tile meshes); a fade on Mobile (needs per-material dithering); stand-ins for the A320's own 300+ parts.

### Phase 3. Particles that meet the ground (done)
Code and rules: docs/USAGE.md "Ground particles". Choices: no GPU collision (a heightfield that follows the camera re-renders the scene depth every frame it moves, and collision is missing on Compatibility); splashes are born on a flat square tilted to the terrain plane (statistically the same as collisions for evenly falling rain); rings are a shader normal on the pavement with a uniform branch on `precip`. Paved or not comes from the runway ribbons and the `terrain/pv` mask.

Measured on Apple M4 only (MacBook Air, MoltenVK, 1920×1080, vsync off, 6 s from 8 m/s of a C172 wet takeoff roll in rain at VABB, chase view, render scale fixed at the preset's, two interleaved runs each). GPU ms with the effects off → on:

| Preset (renderer) | Off | On | Change |
|---|---|---|---|
| Low (Mobile, 70 %) | 12.4 / 12.9 | 12.6 / 13.0 | +0.2 (rings only) |
| Medium (Mobile, 85 %) | 17.1 / 18.2 | 17.7 / 18.2 | +0.3 |
| High (Forward+) | 39.6 / 40.2 | 40.0 / 41.9 | +1.1 |
| Ultra (Forward+) | 57.2 / 56.9 | 62.7 / 57.2 | +2.9 |
| Max (Forward+, 100 %) | 70.2 / 71.1 | 74.4 / 75.5 | +4.3 (first counts: +11) |

After the look pass (noise-shaped wisps instead of round puffs, more but smaller spray sprites, a streak fan for the rooster tail, no splashes under the aircraft) High measured 39.2 / 43.4 off → 42.2 / 43.5 on, about +1.5 ms. The A320 runs were CPU-bound on this Mac (about 5 fps with or without the effects), so they show nothing. The cost is overdraw of soft transparent sprites near the camera: it scales with fill rate, so a discrete GPU pays proportionally less and an older integrated GPU (Intel UHD, small AMD APUs) about the same share at the same resolution; the per-frame CPU work is a few property reads per wheel.

## 3. Rough totals

| Steps | Time | Risk |
|---|---|---|
| G0–G2 | ~4 days | low |
| G3–G5 | ~1.5 weeks | low–medium |
| G6–G7 | ~2.5 weeks | medium–high |
| G8–G9 | ~3–4 weeks | high |
