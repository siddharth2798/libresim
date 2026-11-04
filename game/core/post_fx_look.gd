class_name PostFxLook
extends RefCounted
## How strong each atmospheric post effect is, from the time of day and the weather. Pure functions (tested in
## tests/test_post_fx.gd); world/postfx/post_fx_driver.gd feeds them from Props and the sun each frame.
## Everything here is deliberately subtle: these effects sit on top of a physically lit sky (world/atmosphere.gd)
## and the eye-like auto exposure (world/auto_exposure.gd), and must not fight either.


## Day factor like SkyTime's: 0 below civil twilight (-6 deg) .. 1 from +8 deg.
static func day_k(el_deg: float) -> float:
	return clampf((el_deg + 6.0) / 14.0, 0.0, 1.0)


## Sun shafts strength 0..1. el_deg: sun elevation; occl: WeatherVisuals.sun_occlusion (0 clear .. 1 overcast);
## cover: cloud cover 0..1; rain: local rain rate; vis_m: visibility; facing: 0..1 the camera looks towards the sun.
## Strongest with a low sun, some haze and broken cloud (gaps for the rays), nothing under a deck or in rain.
static func shafts_strength(el_deg: float, occl: float, cover: float, rain: float, vis_m: float, facing: float) -> float:
	var sun_up := clampf((el_deg + 1.0) / 6.0, 0.0, 1.0)  # same horizon fade as the sun glare (world/sky_time.gd)
	var low_sun := lerpf(0.45, 1.0, 1.0 - smoothstep(20.0, 55.0, el_deg))
	var gaps := 0.55 + 0.45 * smoothstep(0.15, 0.5, cover)  # broken cloud gives the best rays
	var haze := clampf(lerpf(1.0, 0.6, (vis_m - 5000.0) / 35000.0), 0.6, 1.0) * smoothstep(800.0, 2500.0, vis_m)
	var k := sun_up * low_sun * gaps * haze * (1.0 - smoothstep(0.4, 0.85, occl)) * (1.0 - clampf(rain * 2.0, 0.0, 1.0))
	return clampf(k * clampf(facing, 0.0, 1.0), 0.0, 1.0)


## Colour grade {contrast, saturation, warmth (-1 cool .. 1 warm)} for the sun elevation, cloud cover and rain.
## Brightness is never touched: exposure belongs to the auto exposure. Contrast pivots on mid grey, so the
## mean level does not move either. Ranges: contrast 0.96..1.06, saturation 0.85..1.1, warmth -0.35..0.4.
static func grade(el_deg: float, cover: float, rain: float) -> Dictionary:
	var day := day_k(el_deg)
	var golden := clampf(1.0 - absf(el_deg - 5.0) / 12.0, 0.0, 1.0) * (1.0 - 0.8 * smoothstep(0.5, 0.95, cover)) * (1.0 - clampf(rain * 1.5, 0.0, 1.0))
	var grey := clampf(smoothstep(0.55, 1.0, cover) * 0.6 + clampf(rain, 0.0, 1.0) * 0.7, 0.0, 1.0)  # monsoon: greyer, cooler
	var night := 1.0 - day
	var contrast := 1.0 + 0.04 * (1.0 - grey) * day + 0.02 * golden - 0.04 * grey
	var saturation := 1.0 + 0.06 * golden + 0.03 * (1.0 - grey) * day - 0.12 * grey - 0.08 * night
	var warmth := 0.4 * golden - 0.25 * grey - 0.15 * night * (1.0 - golden)
	return {"contrast": clampf(contrast, 0.96, 1.06), "saturation": clampf(saturation, 0.85, 1.1), "warmth": clampf(warmth, -0.35, 0.4)}


## Channel gains of a white-balance shift with Rec.709 luminance kept at 1 (warmth -1..1, about +-6 % red / blue).
static func warmth_gains(warmth: float) -> Vector3:
	var g := Vector3(1.0 + 0.06 * warmth, 1.0 + 0.012 * warmth, 1.0 - 0.09 * warmth)
	var lum := 0.2126 * g.x + 0.7152 * g.y + 0.0722 * g.z
	return g / lum


## Heat shimmer over sunlit ground 0..1: a sunny, dry day, the camera low (fades out from 500 to 1500 ft AGL),
## stronger when hot. Off at night, in rain and on wet ground.
static func ground_shimmer(el_deg: float, occl: float, rain: float, wetness: float, agl_m: float, temp_c: float) -> float:
	var sun := smoothstep(12.0, 35.0, el_deg) * (1.0 - smoothstep(0.3, 0.8, occl))
	var dry := (1.0 - clampf(rain * 4.0, 0.0, 1.0)) * (1.0 - clampf(wetness, 0.0, 1.0))
	var low := 1.0 - smoothstep(Units.ft_to_m(500.0), Units.ft_to_m(1500.0), agl_m)
	var hot := clampf((temp_c - 15.0) / 20.0, 0.2, 1.0)
	return clampf(sun * dry * low * hot, 0.0, 1.0)


## Exhaust shimmer 0..1 of one engine from the generic per-engine props (fdm/fdm_node.gd: engines/<n>/running,
## egt_k): hot gas, whatever the engine type. kind_k: the exhaust entry's strength (jet ~1, piston stub ~0.3).
static func exhaust_heat(running: bool, egt_k: float, kind_k: float) -> float:
	if not running:
		return 0.0
	return clampf(smoothstep(450.0, 900.0, egt_k) * kind_k, 0.0, 1.0)


## Lens rain target 0..1 (drops build up and dry off around it, see the driver). Outside views only.
static func lens_rain(view: int, rain: float, in_cloud: bool) -> float:
	if not PostFxRules.lens_rain_wanted(view):
		return 0.0
	return clampf(rain * 1.2 + (0.25 if in_cloud else 0.0), 0.0, 1.0)


## Depth of field around the aircraft at `focus_m` (camera distance): {near_end, near_len, far_start, far_len, amount}.
## extent_m: the aircraft's size (PostFxRules.aircraft_extent_m), so the whole airframe stays sharp.
static func dof(focus_m: float, extent_m: float) -> Dictionary:
	var f := maxf(focus_m, 1.0)
	var near_end := maxf(f - extent_m, 0.5) * 0.6
	return {"near_end": near_end, "near_len": near_end * 0.8, "far_start": f + extent_m * 1.5, "far_len": f * 3.0 + 50.0, "amount": 0.08}
