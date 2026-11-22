class_name WeatherVisuals
extends RefCounted
## Pure mappings from the weather settings to what is drawn (used by SkyTime / WeatherFx,
## covered by tests/test_weather_visuals.gd). No scene access here.
##   cover: weather/cloud_cover 0..1, rain: local rain rate 0..1 (environment/precip),
##   vis: meteorological visibility (m).

## Contrast threshold for meteorological visibility (WMO: 5 %): exp(-sigma * V) = 0.05.
const CONTRAST := 0.05
## Reference colours for a thick grey deck (linear, before the daylight factor).
const OVERCAST_ZENITH := Color(0.42, 0.45, 0.5)
const OVERCAST_HORIZON := Color(0.6, 0.63, 0.66)


## Extinction coefficient (1/m) for a visibility: -ln(0.05) / V, i.e. about 3 / V.
static func fog_density(vis_m: float) -> float:
	return -log(CONTRAST) / maxf(vis_m, 50.0)


## Visibility in rain: heavy rain (1.0) cuts the between-showers visibility to about 55 %.
static func rain_visibility(vis_m: float, rain: float) -> float:
	return vis_m / (1.0 + 0.8 * clampf(rain, 0.0, 1.0))


## What the sky should fade to. A hand-set visibility is the value between showers, so rain
## cuts it. A METAR or model visibility already includes the rain (includes_precip).
static func drawn_visibility(vis_m: float, rain: float, includes_precip: bool) -> float:
	var v := maxf(vis_m, 200.0)
	v = v if includes_precip else rain_visibility(v, rain)
	return maxf(v, 800.0)  # fog denser than 800 m is not drawn; ATC still reads weather/visibility_m


## How much of the sun's disc and direct light the cloud deck blocks (0 clear .. 1 overcast).
## below: 1 under the layer, 0 above its top (sun is out above the deck).
static func sun_occlusion(cover: float, below := 1.0) -> float:
	return smoothstep(0.55, 0.97, cover) * clampf(below, 0.0, 1.0)


## Light scales for occlusion `occl` (sun_occlusion) and rain rate.
## sun: directional light energy factor, shadow: shadow opacity, ambient: ambient energy
## factor, grey: how far the sky moves toward the overcast grey, dark: overall dimming.
static func light_scales(occl: float, rain: float) -> Dictionary:
	var r := clampf(rain, 0.0, 1.0)
	var dark := lerpf(1.0, 0.75, occl) * (1.0 - 0.15 * r)
	return {
		"sun": lerpf(1.0, 0.04, occl) * (1.0 - 0.5 * r),
		"shadow": clampf(1.0 - occl * 1.15, 0.0, 1.0),
		"ambient": lerpf(1.0, 1.45, occl) * (1.0 - 0.15 * r),
		"grey": occl,
		"dark": dark,
	}


## Sky colours under the deck: blend the clear-sky colours toward a flat grey, dimmed.
static func overcast_sky(top: Color, hor: Color, day: float, occl: float, dark: float) -> Array:
	var g_top := OVERCAST_ZENITH * day * dark
	var g_hor := OVERCAST_HORIZON * day * dark
	var night := Color(0.02, 0.025, 0.035)
	g_top = g_top.lerp(night, 1.0 - day) if day < 1.0 else g_top
	g_hor = g_hor.lerp(night, 1.0 - day) if day < 1.0 else g_hor
	return [top.lerp(g_top, occl), hor.lerp(g_hor, occl)]


## Rain rate 0..1 under the cloud field at ground position p2 (ENU east, north m; cover, drift as CloudField): rain
## falls where the cloud is thick and drifts with it. A light setting (< 0.3) rains only as showers under the thickest
## clouds; heavier rain is steady, heavier under the thick parts. Same field for the drawn rain and the physics.
static func rain_rate(precip: float, p2: Vector2, cover: float, drift: Vector2) -> float:
	if precip <= 0.0:
		return 0.0
	var field := CloudField.lo((p2 + drift) / CloudField.TILE_M) - (1.0 - cover) * 0.82  # as CloudField.density's coverage
	var thick := smoothstep(0.1, 0.35, field)
	var shower := precip * 3.0 * thick
	var steady := precip * (0.75 + 0.25 * thick)
	return clampf(lerpf(shower, steady, smoothstep(0.2, 0.4, precip)), 0.0, 1.0)


## Surface wetness target for a rain rate (the actual value lags in WeatherFx).
static func wetness_target(rain: float) -> float:
	return clampf(rain * 4.0, 0.0, 1.0)


## Rain-streak particle count for a graphics preset and rain rate.
static func rain_particles(preset_max: int, rain: float) -> int:
	return int(round(preset_max * clampf(rain, 0.0, 1.0)))


## Local sunrise / sunset (IST hours) for day_of_year: the sun's upper limb at the
## horizon with standard refraction (-0.833 deg). Returns Vector2(sunrise, sunset).
static func sun_rise_set(day: float) -> Vector2:
	var rise := _cross(day, 5.0, 8.0, true)
	var set_h := _cross(day, 16.5, 20.0, false)
	return Vector2(rise, set_h)


static func _cross(day: float, a: float, b: float, rising: bool) -> float:
	var h0 := deg_to_rad(-0.833)
	for i in 40:  # bisection on the elevation
		var m := (a + b) * 0.5
		var above := SkyTime.sun_position(m, day).x > h0
		if above == rising:
			b = m
		else:
			a = m
	return (a + b) * 0.5
