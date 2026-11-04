# Graphics to the maximum: plan

Goal: push the look as far as Godot 4.7 allows on a strong GPU (dedicated card or Apple M-series Pro/Max)
without making Low / Medium worse on integrated GPUs (PLAN.md §8b).

Status: analysis done 2026-11-03 from the code and `docs/screenshots/`; nothing implemented yet.
Steps are ordered by **least time, risk and complexity first**. Each step ships on its own and is
checked before the next one starts.

## 1. Where things stand (facts)

- **Renderer**: Mobile by default (`project.godot`). Forward+ can be picked in the settings menu
  (`ui/settings_menu.gd`, written to `override.cfg`, needs a restart), but no preset selects it. On Mobile,
  Ultra's `ssao` and `taa` flags do nothing (`core/graphics_settings.gd`), so Ultra today mostly means longer
  draw distances, not better rendering.
- **Environment** (`world/flight.tscn`): Filmic tonemap, glow on, no SSAO / SSIL / SSR / volumetric fog.
  The sun uses 4 shadow cascades, max 4 km on Ultra. The shadow atlas size and anisotropic filtering are left at their defaults.
- **Sky**: physical single-scattering sky (`world/atmosphere.gd`, `sky_clouds.gdshader`). This is good already.
- **Clouds** (`world/volumetric_clouds.gdshader`): full-screen raymarch, 10–40 steps, one light sample per
  step, jitter but no averaging over frames, which makes the clouds look grainy. They end at 25 km (`max_dist`), leaving a hard band at the horizon.
- **Terrain**: Sentinel-2 imagery at 10 m per pixel (20 m in the corridor, 80 m in the outer ring), 30 m DEM, 64×64 cells per
  quadtree node. Close-up detail is all procedural noise (`terrain.gdshader`). Haze is a per-vertex
  exponential to one fog colour. 10 m is the limit for imagery that is free to use (docs/LICENSING.md; Google / Bing not allowed).
- **Water**: fresnel blend towards a flat sky colour, waves from gradient noise. Nothing real is reflected.
- **Buildings** (`world/building.gdshader`): already procedural windows, balconies, roofs, weathering
  and night windows. The detail fades with distance, so from the air the city still reads as pale blocks.
- **Trees**: crossed-quad impostors from a startup atlas, plus real meshes within 90–150 m.
- **Aircraft**: reflection probe captured once (`aircraft/common/reflection_rig.gd`), and the textures have AO baked into them.

## 2. Steps (cheapest and safest first)

Each step lists the time, risk, the main files it touches, and how it is checked. "Max" is the new
top preset added in G1.

### G0. Baseline first (½ day, no risk)
- Add an fps / GPU-frame-time capture to `tools/make_screenshots.sh` (or a `--bench` user arg): three fixed
  views (VABB final, Ghats cruise, cloud deck), each preset, each renderer.
- Output: a table in this file. Every later step is judged against it (no step may drop Low / Medium fps).

### G1. Settings-only wins + a "Max" preset (1 day, very low risk)
No new shaders; works on both renderers.
- New `max` preset in `graphics_settings.gd` (+ settings menu, `tests/test_graphics_presets.gd`):
  render scale 1.25–1.5 (supersampling), MSAA 4×, shadow distance 6 km, cloud steps 64,
  `lod_k` 2.4, building radius 16 km, trees 4 km, density 1.4, tree LOD radius 250 m.
- Project settings: anisotropic filtering 16×, directional shadow atlas 8192 for High+ and soft shadow quality Ultra.
- Tonemapper Filmic → **AgX** (better highlights at sunset and in bright cloud); re-tune exposure / glow
  once against the G0 screenshots.
- Check: preset test passes, screenshots side by side, fps table.

### G2. Forward+ for High / Ultra / Max (1–2 days, low risk)
- Each preset carries a renderer: Low / Medium → Mobile, High+ → Forward+. Changing to a preset on the
  other renderer writes `override.cfg` and shows "restart to apply" (the existing mechanism).
- Turn on, Forward+ only: **SSAO**, **SSIL** (Max), **SSR** (water and wet runways get real reflections
  for free, since their roughness is already low), **TAA** (or FSR2 when render scale < 1).
- Forward+ also lifts Mobile's limit on lights per mesh, so raise `REAL_LIGHTS` in `runway_lights.gd` and the apron floodlights on Max.
- Risks: shaders with `fog_disabled` and their own haze (terrain, buildings) must still match; TAA ghosting
  on the propeller disc and instruments. Run the full test suite and the e2e sweep on both renderers.

### G3. Small per-feature upgrades (1–2 days, low risk, each independent)
- Reflection probe: update every few seconds / after 300 m travel on Max (the policy file already has the rules).
- Cloud lighting, shader only: two-lobe Henyey–Greenstein phase (bright silver lining), "powder"
  darkening at cloud edges, 2–3 multiple-scattering octaves, 2–4 light samples per step on Max.
- Water: sun glint (sharp specular streak), a second layer of finer wave normals, slightly deeper colour
  away from the shore. All in `terrain_water.gdshaderinc`.
- Contact shadows / brighter AO under aircraft and vehicles on Forward+.

### G4. Horizon fix (2–3 days, medium-low risk)
- Fade clouds out with haze before `max_dist` instead of cutting them; extend `max_dist` on Max.
- Bend far terrain down with the Earth's curvature in the vertex shader (visual only; the FDM's terrain
  height queries are untouched), so the horizon dips and the haze band stops looking like a wall.
- Colour the far haze from the sky model along the view direction (sun side warmer), not one fog colour.

Status G4: done 2026-11-04.
- Curvature: `world/curvature.gdshaderinc` (`curve_drop()` = d²/2R from `terrain_eye`, the real camera also in
  shadow passes; `curve_local()` maps it into the mesh's local space), CPU twin `world/curvature.gd`. Used by
  terrain, buildings, terminals, both tree shaders, runway / taxiway / lead-on ribbons (`strip.gdshaderinc`),
  stand paint and light points; `tests/test_horizon.gd` checks every far shader includes it. Within ~700 m of
  the aircraft the ground stays flat while the camera is < 4–8 km away (tower / fly-by views; the aircraft
  itself is not bent). Not bent: vehicles, jetways, props, apron light pools (StandardMaterial or near only;
  < 1 px off beyond 5 km). The cloud layer follows the same curvature (quadratic slab intersection).
  The sky's horizon dips by the altitude (`horizon_dip`, `HazeLut.horizon_dip_sin`), so the bent ground's edge
  meets it; the terrain reaches the horizon (outer ring to ±490 km, camera far 160 km; at FL250 the edge at
  160 km is below the dipped horizon and fully hazed).
- Haze: `world/haze_lut.gd` fills a 32×8 RGBAH table (angle to the sun's azimuth × elevation above the dipped
  horizon) from `Atmosphere.sky()` + the sky shader's sun glow; `world/haze_sky.gdshaderinc` `haze_color(dir)` =
  fog_color + clear × (table − model colour of fog_color), the way the sky blends its analytic part, so
  overcast / night / lightning stay in fog_color. Refilled when the sun moves 0.25° or the aerosol changes,
  one row (32 sky samples, ~1 ms) per frame; nothing per frame otherwise. Globals haze_lut / haze_sun / haze_ref.
- Clouds: over the last 45 % of `max_dist` the density blends into the layer's mean density (CloudLayer
  `mean_density`, from the CPU twin at 3 heights), and beyond `max_dist` the layer goes on as a uniform veil to
  where the ray leaves the curved slab, so near-horizontal rays from in / near a layer pile up optical depth
  smoothly (no cut, no step at the horizon). Haze: clear-air extinction (`air_haze`, not the in-cloud fog
  density) to the seen part of the cloud, colour from `haze_color()`; alpha only thins with the haze in front of
  the layer's entry (none from inside it). `max_dist` 60 km on Max (preset key `cloud_dist`), 25 km below.

### G5. Volumetric fog (2–3 days, medium risk, Forward+ only)
- Godot volumetric fog for light shafts under broken cloud, rain curtains under storms (`cloud_storm.gd`),
  mist in valleys at dawn, and the inside of cloud.
- Risk: how it combines with the custom haze, and its range (it is a froxel volume, good to a few km only).
  Kept to near-field effects; the far haze stays the custom one.

Status G5: done 2026-11-04 (details in docs/USAGE.md "Volumetric fog").
- `world/volumetric_fog.gd` (node, driven by the weather Props each frame), `vfog_rules.gd` (pure maps + quality
  table), `vfog_composite.gd/.gdshader`, `vfog_air.gdshader`, `vfog_rain.gdshader`; preset key `vfog` 0 / 0 / 1 / 2 / 3
  (Low .. Max); option `volumetric_fog` (on, High+, Forward+, PostFxRules); tests `tests/test_volumetric_fog.gd`;
  scenes `fog_shafts`, `fog_storm_curtain`, `fog_dawn_mist` (`tests/showcase_fog_scenes.gd`), `--no-vfog` for "before".
- Findings (Godot 4.7.2, Metal): (1) `render_mode fog_disabled` skips the volumetric fog as well as the
  Environment fog, so terrain / buildings / trees / water / the cloud pass never see it; a composite pass (n + 1
  full-screen planes in one draw, at the froxel slice depths, the Environment fog pre-inverted) puts it back on them,
  the aircraft keeps the engine's own (pixels nearer than the aircraft + its size are skipped), the cloud pass /
  rain / light points draw after it. Only plain exponential Environment fog can be inverted (checked every frame).
  (2) FogVolume density is accumulated in fixed point (~1/1024 per m; 0.001 vanishes, 0.0015 shows): the thin
  air goes into the Environment's float `volumetric_fog_density`, FogVolumes carry only dense things (mist, rain
  curtains, in-cloud puffs) or cut the thin air away (negative density, clamped at 0) in cloud shadows (shafts) and
  above the haze top. (3) Global shader uniforms read wrong values in fog shaders (passed as material parameters).
  (4) A `Color` set on a `vec3` uniform arrives linearised (pass a `Vector3`).
- The inversion multiplies any mismatch with the engine's fog by 1 / (1 - f): the last plane stops where the
  Environment fog reaches 75 % (`VfogRules.ENV_FOG_LIMIT`), i.e. the froxel fog reaches about half the visibility
  in haze, the full 5 / 10 / 14 km only in clear air.
- Cost (M5 Max, 1080p, `fog_shafts`, machine shared with other runs, so noisy): High 25.0 ms vs 28.7 off (noise),
  Ultra 33.5 vs 28.5 ms, Max 44.2 vs 40.3 ms: roughly +0-5 ms. Re-measure on a quiet machine (tools/bench.sh, `--no-vfog`).
- Follow-up (same day): the froxel air now glows with the haze colour (`volumetric_fog_emission` = fog colour x 1.1,
  measured neutral at ~1.2; ambient inject off), so it no longer darkens / re-tints the custom haze; the sun adds
  on top (energy 0.8 after the shaft renders). Shaft air under broken cloud: haze x (0.1 + 0.3 x broken x sun); more
  (tried 1.3 / 0.9 / 0.6 with anisotropy 0.6-0.7) gave no clearer columns, only a bright white layer under the base
  with a hard edge at the horizon (the cloud pass covers the sky pixels) and darker unfogged tree speckles: light
  shafts are NOT achieved; they need cloud-shadowed in-scatter that the trees and the cloud pass also receive. Night air is held in a 400 m ground layer and scales with humidity / low visibility.
- (Superseded by follow-up 2 below for the trees.) Dawn mist is gated OFF (`VfogRules.MIST_ENABLED`): the tree impostors (`world/tree.gdshader` writes ALPHA without
  a scissor threshold) are transparent and draw after the composite, so they never get the froxel fog and every
  tree showed through the mist as a speckle. Mist itself is now low-frequency (blurred km-scale noise, soft vertical
  profile, density dither below the fixed-point step). Turning it on needs trees drawn before the composite
  (e.g. `ALPHA_SCISSOR_THRESHOLD` + alpha-to-coverage in tree.gdshader, not changed here). The same tree gap applies
  to shafts / curtains, but there the near-neutral air colour keeps it invisible.
- Follow-up 2 (2026-11-04): the tree impostors are alpha-tested now (`ALPHA_SCISSOR_THRESHOLD` 0.5 with the
  existing alpha_to_coverage_and_one; adding `ALPHA_ANTIALIASING_EDGE` turned distant impostors black at Ultra;
  the LOD dither swap, haze, curvature and night look unchanged), so they draw in the opaque pass, write depth and get the composite's froxel fog. Impostor
  shadows stay off: cut-out shadows from all chunks cost +9-10 ms at Ultra (trees_close 9.0 -> 18.8 ms,
  ghats_chase 11.6 -> 21.0 ms), +6 ms even for the chunks within 700 m. Dawn mist was re-tried with
  fogged trees and stays OFF: the mist pool shows a hard straight edge a few km out (darker inside,
  unchanged with MIST_GLOW 0.5 -> 1.0) and the lit canopy tops stand out of it as pale speckles, so the
  mist profile / range needs its own fix first. `fog_shafts`: unchanged (trees now fogged, but no visible
  shafts; clear-air haze untouched).
- Open: rain curtains are hard to judge in before / after pairs (showers randomly seeded per run); night glow
  only round real Omni/SpotLights (light points are sprites).

### G6. Terrain detail materials (1–1.5 weeks, medium risk)
- Tiling PBR sets (colour, normal, roughness) per WorldCover class (crops, grass, bare rock, laterite,
  forest floor, urban, sand), fading in within ~1 km and blended under the satellite colour so the
  imagery still sets the tone. Triplanar on steep slopes (Ghats cliffs).
- Assets: CC0 only (ambientCG, Poly Haven), listed in CREDITS.md. A small `tools/` script packs them into one texture array.
- Risk: texture memory and the number of samplers in `terrain.gdshader` (keep to one array + one atlas).

Status G6: done 2026-11-04 (with the apron fix below).
- Assets: `tools/26_terrain_textures.py` fetches 11 ambientCG 1K sets (CC0; `data/raw/textures/`) and packs two
  1024 px Texture2DArrays in `game/world/textures/terrain/` (lossy WebP in git, 5.5 + 13.8 MB; VRAM-compressed on
  import: BC1 7.7 MB + BC7 15.4 MB with mips): `detail_mod` = high-passed (wrap-around blur / 10 of the tile) and
  contrast-normalised albedo *modulation* (0.5 = unchanged), `detail_nrm` = normal xy, roughness offset, AO.
  Layers: soil, grass, scrub, laterite, rock, forest floor, urban, sand, mud, concrete, asphalt (`SOURCES.md`).
- Shader: `world/terrain_detail.gdshaderinc` (two new texture uniforms, bound once as shader defaults by
  `world/terrain_detail.gd`). WorldCover class -> layer, the two strongest layers of the 4 class texels around
  the fragment (the third's weight is subtracted, so a change of rank is seamless); sand replaces open classes
  within ~25-70 m of the sea (shore tiles); rock projected on the vertical planes above ~35° (Ghats cliffs).
  Three scales per layer (~3 m, x4.37, x19.3, each rotated / offset; fine skipped beyond 160 m, coarse inside
  40 m), so nothing repeats from altitude; multiplied under the imagery colour, plus normal, roughness and AO;
  fades 650 -> 1200 m. The class-corner lookup moved from `terrain.gdshader` into `cls_corners()`.
- Apron fix: aprons are terrain, and the urban "block" patches, macro blotches and class tint made them pink /
  grey slabs. `tools/27_pavement.py` (+ `pavement_raster.py`) writes `terrain/pv/0/<tx>_<ty>.png` (RGBA, 4 m, the
  road tiles' lattice; 38 tiles): exact signed distance to the pavement edge, signed offset from the nearest stand
  lead-in, slab-joint direction, surface (concrete / asphalt from OSM `surface`) + stand wear. Pavement = OSM
  aeroway areas (incl. multipolygons, own osmium pass cached in `osm/aeroway_areas.json`), runway / taxiway
  shoulders (+7.5 / +4 m), a pad round every stand and a 38 m morphological closing near stands (OSM lacks
  e.g. the VABB T2 apron). `world/terrain_pavement.gdshaderinc` replaces the ground detail there: concrete slabs
  5 x 6.25 m along the airport's longest runway (OSM apron polygons along their own edges), per-slab tone,
  sealed joints fading by ~380 m, asphalt with patches, rubber / grime streaks, tyre marks along lead-ins (nose
  + main-gear tracks), oil stains where aircraft stand; the imagery only as a ~150 m blur tint. Loaded with the
  road tile (`terrain_roads.gd`) and bound by `terrain_quadtree.gd` (`pv_tex`, `pv_on`); fades 2-3.3 km.
- Tests: `tests/test_terrain_detail.gd` (shader compiles, arrays one layer per set, credits / licensing list every
  set, pipeline / shader encodings agree, >= 95 % of the stands of VABB / VAPO / VOCI / VOGO / VANM on pavement).
- Not done: per-slab normal tilt / edge spalling, painted apron markings beyond the stand lines, hex tiling
  (three scales were enough), detail on the outer ring (> 1.2 km anyway).

### G7. Clouds at full quality (1–1.5 weeks, medium-high risk)
- Raymarch at half (High) or quarter (Max) resolution into a buffer, reproject the previous frame and
  blend: kills the grain and makes 96–128 steps affordable. Upsample with depth so edges against
  terrain and the aircraft stay sharp.
- Implementation: `CompositorEffect` (compute) or a SubViewport pass; decide in a 1-day spike.
- Risk: ghosting when the camera turns fast or switches view; the reprojection must reset on camera cuts.

### G8. Trees and buildings up close (1–2 weeks, medium-high risk)
- Trees: octahedral impostors (8–16 baked angles with normals), colour variation per species and
  season, wind sway in the vertex shader, darker canopy undersides.
- Buildings: keep window detail at longer range (fade later on Max), darker band at the base (fake AO),
  more wall colour variety in dense Mumbai, roof clutter at distance.

### G9. Terrain geometry (1–2 weeks, high risk)
- 128×128 cells per node on Max and fractal height detail within ~2 km.
- Risk: the visible ground no longer matches the FDM's terrain (wheels sinking or floating, trees and
  buildings at the wrong height). The detail has to be zero on runways / aprons / roads and kept to a few metres;
  `tests/test_landing.gd` and the e2e sweep must pass.

### G10. Art (ongoing, the owner's work in Blender)
- Higher-resolution cockpit and exterior textures, separate AO / roughness / metal maps, a baked AO for
  the cockpit interior (tools/blender). Optional post: lens flare, colour-grading LUT per weather.

## 3. Rough total

| Steps | Time | Risk |
|---|---|---|
| G0–G2 | ~4 days | low |
| G3–G5 | ~1.5 weeks | low–medium |
| G6–G7 | ~2.5 weeks | medium–high |
| G8–G9 | ~3–4 weeks | high |

G0–G3 give most of the visible gain (AO, reflections, sharper and steadier image, better clouds and water)
for about a week of work.
