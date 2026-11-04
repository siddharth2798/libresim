class_name DayMath
extends RefCounted
## Pure maths of the day strip (ui/menu/day_strip.gd): sunrise and sunset, which part of the day
## (night / twilight / day) an hour belongs to, and the pixel <-> time mapping. The sun comes from
## the game's own code (SkyTime.sun_position for the region, WeatherVisuals.sun_rise_set), so the
## strip shows the same sun the flight will have. The game has one sky for the whole map (lat 18.75 N,
## lon 73.4 E, SkyTime.LAT / LON): every airport shares these times, they depend on the date only.

enum Phase { NIGHT, TWILIGHT, DAY }

const TWILIGHT_DEG := -6.0  # civil twilight: sun between -6 degrees and the horizon (sunrise / sunset)
const STEP_H := 0.25  # the time slider's step; the strip sets times in quarter hours
const MAX_H := 24.0 - 0.25
const SAMPLE_H := 1.0 / 12.0  # band resolution (5 min)


## Vector2(sunrise, sunset) in IST hours for the day of the year (WeatherVisuals.sun_rise_set).
static func sun_times(day: float) -> Vector2:
	return WeatherVisuals.sun_rise_set(day)


## Sun elevation in degrees at an IST hour on a day of the year.
static func elevation_deg(h: float, day: float) -> float:
	return rad_to_deg(SkyTime.sun_position(h, day).x)


static func phase_at(h: float, day: float) -> Phase:
	var el := elevation_deg(h, day)
	if el > -0.833:  # the same horizon the sunrise / sunset times use
		return Phase.DAY
	return Phase.TWILIGHT if el > TWILIGHT_DEG else Phase.NIGHT


## The day as consecutive bands [[from_h, to_h, Phase], ...] covering 0..24, at 5 min resolution.
static func bands(day: float) -> Array:
	var out := []
	var n := int(round(24.0 / SAMPLE_H))
	var start := 0.0
	var cur := phase_at(0.5 * SAMPLE_H, day)
	for i in range(1, n):
		var p := phase_at((i + 0.5) * SAMPLE_H, day)
		if p != cur:
			out.append([start, i * SAMPLE_H, cur])
			start = i * SAMPLE_H
			cur = p
	out.append([start, 24.0, cur])
	return out


## "07:10" for an IST hour (the time slider's text; 24.0 reads 24:00).
static func clock(h: float) -> String:
	return "%02d:%02d" % [int(h), int(fmod(h, 1.0) * 60.0)]


## Hour for a pixel x in a strip of `width` px with `pad` px at each end, snapped to `step`, 0..MAX_H.
static func time_from_x(x: float, width: float, pad := 0.0, step := STEP_H) -> float:
	var span := maxf(width - 2.0 * pad, 1.0)
	var h := clampf((x - pad) / span, 0.0, 1.0) * 24.0
	return clampf(snappedf(h, step), 0.0, MAX_H)


## Pixel x of an IST hour (the inverse of time_from_x before snapping).
static func x_from_time(h: float, width: float, pad := 0.0) -> float:
	return pad + clampf(h, 0.0, 24.0) / 24.0 * maxf(width - 2.0 * pad, 1.0)
