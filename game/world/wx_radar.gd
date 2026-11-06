class_name WxRadar
extends RefCounted
## Plan-view weather radar, the way an airborne set works: it paints precipitation,
## not cloud. Dry cumulus and a dry overcast stay black. Area rain is a few broad
## returns of one intensity. A storm is a green skirt with a hotter core.
## Each return is {e, n, r (m), level} with level 1 green, 2 amber, 3 red.
## Reads weather/* and environment/storm_clock_s only.


const COLOUR := [
	Color(0.0, 0.62, 0.16, 0.95),
	Color(0.98, 0.82, 0.0, 0.96),
	Color(0.86, 0.08, 0.05, 1.0),
]


static func colour(level: int) -> Color:
	return COLOUR[clampi(level, 1, 3) - 1]


## Returns inside `radius_m` of `origin` (east, north, metres). Empty without precip or storms.
static func blobs(origin: Vector2, radius_m: float) -> Array:
	var precip := Props.get_f("weather/precip")
	var storms := Props.get_f("weather/storms")
	if precip < 0.08 and storms < 0.02:
		return []
	var out: Array = []
	if precip >= 0.08:
		_rain(out, origin, radius_m, precip)
	if storms >= 0.02:
		_cells(out, origin, radius_m, storms)
	return out


## Area rain follows the thick parts of the cloud deck. Samples are far enough apart, and
## each return large enough, that neighbours merge into a sheet instead of a field of dots.
## One intensity for the whole area: red is reserved for a storm core.
static func _rain(out: Array, origin: Vector2, radius_m: float, precip: float) -> void:
	var level := 1 if precip < 0.5 else 2
	var drift: Vector2 = Props.get_v("environment/cloud_drift", Vector2.ZERO)
	var step := clampf(radius_m / 6.5, 7000.0, 22000.0)
	var n := int(ceil(radius_m / step))
	var wet := clampf(0.62 - precip * 0.45, 0.18, 0.62)
	for j in range(-n, n + 1):
		for i in range(-n, n + 1):
			var p := origin + Vector2(float(i), float(j)) * step
			if p.distance_to(origin) > radius_m * 0.9:
				continue
			var q := (p + drift) / CloudField.TILE_M
			var cov := CloudField.lo(q)
			if cov < wet:
				continue
			var jig := Vector2(CloudField.hi(q) - 0.5, CloudField.hi(q + Vector2(0.37, 0.13)) - 0.5)
			var c := p + jig * step * 0.5
			if c.distance_to(origin) > radius_m:
				continue
			out.append({"e": c.x, "n": c.y, "r": step * (0.72 + 0.22 * cov), "level": level})


## A cell's radar echo is the precip shaft, wider than the downdraft the flight model uses.
## Skirt first, then the core, so the core paints on top.
static func _cells(out: Array, origin: Vector2, radius_m: float, storms: float) -> void:
	var wind := _wind_en()
	var t := Props.get_f("environment/storm_clock_s")
	var shift := wind * (CloudStorm.DRIFT_K * t)
	var q := origin - shift
	var n := int(ceil(radius_m / CloudStorm.CELL_M)) + 1
	var ci := floori(q.x / CloudStorm.CELL_M)
	var cj := floori(q.y / CloudStorm.CELL_M)
	for dj in range(-n, n + 1):
		for di in range(-n, n + 1):
			var cl := CloudStorm.cell(ci + di, cj + dj, storms, 7)
			if not cl.on:
				continue
			var s: float = cl.strength
			if s < 0.34:
				continue
			var world: Vector2 = (cl.center as Vector2) + shift
			var echo := float(cl.radius) * 2.6
			if world.distance_to(origin) > radius_m + echo:
				continue
			out.append({"e": world.x, "n": world.y, "r": echo, "level": 1})
			out.append({"e": world.x, "n": world.y, "r": echo * 0.58, "level": 2})
			if s >= 0.6:
				out.append({"e": world.x, "n": world.y, "r": echo * 0.32, "level": 3})


static func _wind_en() -> Vector2:
	var aloft := Weather._from_dir_to_ned(Props.get_f("weather/aloft_dir_deg"), Props.get_f("weather/aloft_kt") * Units.KT)
	return Vector2(aloft.y, aloft.x)
