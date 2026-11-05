class_name VfogRules
extends RefCounted
## Volumetric fog (world/volumetric_fog.gd): pure maps from weather / time of day to the near-field fog, the
## froxel settings per quality level and the composite's slice spacing. No scene access (tests/test_volumetric_fog.gd).
## Godot's froxel fog skips every material with render_mode fog_disabled (terrain, buildings, trees, clouds); those
## draw their own haze, and VfogComposite puts the froxel fog back onto them (vfog_composite.gdshader). So the fog holds
## only what the custom haze does not: light shafts, rain curtains, mist, structure in cloud, glow round lights.

## Quality level ("vfog" key of the graphics presets): 0 off, 1 High, 2 Ultra, 3 Max.
##   size / depth: froxel grid (x, y / slices), length: m the froxel volume reaches, slices: composite planes,
##   reproject: temporal reprojection amount (more = smoother, slower to react).
const QUALITY := {
	1: {"size": 64, "depth": 64, "length": 5000.0, "slices": 16, "reproject": 0.9},
	2: {"size": 96, "depth": 96, "length": 10000.0, "slices": 24, "reproject": 0.9},
	3: {"size": 128, "depth": 128, "length": 14000.0, "slices": 32, "reproject": 0.85},
}
const SPREAD := 2.0  # froxel / composite slice spacing exponent (Godot's volumetric_fog_detail_spread)
## The composite's last plane stops where the Environment fog reaches 1 - e^-1.4 (75 %). Its inversion multiplies any
## mismatch with the engine's fog by 1 / (1 - f), which shows as un-hazed far terrain, so f stays <= 0.75.
const ENV_FOG_LIMIT := 1.4
const ANISOTROPY := 0.6  # forward scattering: shafts and mist glow towards the sun
const STORM_REACH := 16000.0  # m: storm cells (CloudStorm) within this get a rain curtain
const MAX_CURTAINS := 4


static func quality(level: int) -> Dictionary:
	return QUALITY.get(level, {})


## View depth (m) of composite plane i of n between z0 and z1, spaced like the froxel slices.
static func slice_depth(i: float, n: float, z0: float, z1: float) -> float:
	var t := clampf(i / n, 0.0, 1.0)
	return z0 + (z1 - z0) * pow(t, SPREAD)


## Fractional plane index of view depth z (inverse of slice_depth, clamped to 0..n).
static func slice_index(z: float, n: float, z0: float, z1: float) -> float:
	return n * pow(clampf((z - z0) / maxf(z1 - z0, 1e-3), 0.0, 1.0), 1.0 / SPREAD)


## The composite's last plane: the froxel length, or nearer where the Environment fog (haze, 1/m) gets thick.
static func composite_far(length: float, haze: float) -> float:
	return clampf(ENV_FOG_LIMIT / maxf(haze, 1e-7), 50.0, length)


## Dawn mist is off by default: with it on, a hard straight edge shows a few km out and lit canopy tops speckle
## pale. The mist profile / range needs fixing first (docs/GRAPHICS-PLAN.md G5).
const MIST_ENABLED := false


## Morning mist 0..1: forms on calm, humid mornings under a clear sky and burns off as the sun climbs.
## time_h: local hours, sun_el: degrees, vis: visibility (m), wet: ground wetness 0..1, wind_kt: surface wind,
## cover: cloud cover 0..1. Humidity is read from the visibility (hazy = humid) and wet ground.
static func mist(time_h: float, sun_el: float, vis: float, wet: float, wind_kt: float, cover: float) -> float:
	var morning := smoothstep(3.5, 5.0, time_h) * (1.0 - smoothstep(9.0, 10.5, time_h))
	var low_sun := 1.0 - smoothstep(4.0, 14.0, sun_el)  # burns off within ~2 h of sunrise
	var humid := clampf(maxf(1.0 - smoothstep(4000.0, 16000.0, vis), wet * 0.8), 0.0, 1.0)
	var calm := 1.0 - smoothstep(6.0, 14.0, wind_kt)
	var clear_night := 1.0 - 0.7 * smoothstep(0.6, 0.95, cover)  # an overcast night does not cool the ground
	return clampf(morning * low_sun * humid * calm * clear_night, 0.0, 1.0)


## Mist layer {top (m AMSL), density (1/m at the floor)} over ground whose low points are at floor_m.
static func mist_layer(strength: float, floor_m: float) -> Dictionary:
	var s := clampf(strength, 0.0, 1.0)
	return {"top": floor_m + lerpf(30.0, 160.0, s), "density": 3.0 / lerpf(2500.0, 350.0, s) * s}


## Air under the cloud base that the sun's shafts light up (1/m): a share of the clear-air haze, more in
## broken cloud and when it is humid. cover 0..1, haze: clear-air extinction (1/m), sun_el: degrees.
static func shaft_density(cover: float, haze: float, sun_el: float, rain: float) -> float:
	var broken := smoothstep(0.2, 0.45, cover) * (1.0 - smoothstep(0.85, 0.98, cover))
	var sun := smoothstep(1.0, 6.0, sun_el)
	return haze * (0.1 + 0.3 * broken * sun) * (1.0 + 0.5 * rain)  # more makes a bright band under the base, no clearer shafts


## Heavy rain near the camera: streak density (1/m, FogVolume: >= the fixed-point step) on top of the rain's haze.
static func rain_density(rain: float) -> float:
	return 0.003 * smoothstep(0.25, 1.0, rain)


## Smallest FogVolume density Godot keeps (its density buffer is fixed point, ~1/1024 per m); the shaft cut uses
## twice this so it always removes the whole thin air.
const VOLUME_STEP := 0.001


## Thin air of the Environment's volumetric density (1/m, a float: no fixed-point step): shaft air + night air.
static func thin_air(shaft: float, night: float) -> float:
	return maxf(shaft, 0.0) + maxf(night, 0.0)


## Density the air volume removes in cloud shadows and above the haze top: at least the thin air, never below two
## fixed-point steps; 0 without thin air.
static func shadow_cut(shaft: float, thin: float) -> float:
	return maxf(thin + VOLUME_STEP, 2.0 * VOLUME_STEP) if shaft > 0.0 else 0.0


## Top of the thin air (m AMSL): the cloud base, else the mixed layer ~2 km over the low ground.
## At night the glow air is a shallow ground layer (a nocturnal inversion, 400 m): light_level from SkyTime.
static func haze_top(cover: float, base_m: float, floor_m: float, light_level := 1.0) -> float:
	var top := base_m if cover > 0.05 else floor_m + 2000.0
	return minf(top, floor_m + 400.0) if light_level < 0.3 else top


## Night glow round lights (1/m): a little humid air, only once it is dark.
static func night_density(light_level: float, haze: float, vis: float) -> float:
	var dark := 1.0 - smoothstep(0.15, 0.45, light_level)
	var humid := 1.0 - smoothstep(5000.0, 30000.0, vis)
	return dark * (0.0002 + 0.0016 * humid + 0.5 * haze)  # held near the ground (haze_top), so the sky stays clear


## In-cloud structure: the near-field puffs that add to CloudInside's fog (1/m), small so the look stays CloudLook's.
static func cloud_density(in_cloud_k: float, sigma: float) -> float:
	return clampf(in_cloud_k, 0.0, 1.0) * minf(sigma * 0.35, 0.02)


## Rain curtains: storm cells (CloudStorm) whose centre is within reach of the camera (cam_en: world east / north).
## Returns up to MAX_CURTAINS {center (world EN), radius, strength}, nearest first.
static func storm_cells(cam_en: Vector2, t_s: float, wind_en: Vector2, storms: float, seed := 7) -> Array:
	var out := []
	if storms <= 0.0:
		return out
	var q := cam_en - wind_en * (CloudStorm.DRIFT_K * t_s)  # into the cells' frame
	var ci := floori(q.x / CloudStorm.CELL_M)
	var cj := floori(q.y / CloudStorm.CELL_M)
	var reach := int(ceil(STORM_REACH / CloudStorm.CELL_M))
	for di in range(-reach, reach + 1):
		for dj in range(-reach, reach + 1):
			var cl := CloudStorm.cell(ci + di, cj + dj, storms, seed)
			if not cl.on:
				continue
			var c := CloudStorm.center_at(cl, t_s, wind_en)
			var d := c.distance_to(cam_en)
			if d < STORM_REACH + float(cl.radius):
				out.append({"center": c, "radius": float(cl.radius), "strength": float(cl.strength), "dist": d})
	out.sort_custom(func(a, b): return a.dist < b.dist)
	return out.slice(0, MAX_CURTAINS)


## Density (1/m) inside a curtain of strength s (0..1) in rain rate `precip` (setting).
static func curtain_density(s: float, precip: float) -> float:
	return 0.0035 * clampf(s, 0.0, 1.0) * (0.5 + 0.5 * clampf(precip, 0.0, 1.0))
