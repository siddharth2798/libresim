class_name WxRadar
extends RefCounted
## Plan-view weather radar: the cloud field, area rain and the storm cells the aircraft
## actually meets (CloudField, CloudStorm). Each return is {e, n, r (m), level} with
## level 1 green, 2 amber, 3 red. Reads weather/* and environment/storm_clock_s only.


const COLOUR := [
	Color(0.15, 0.82, 0.28, 0.42),
	Color(1.0, 0.72, 0.05, 0.62),
	Color(0.92, 0.12, 0.08, 0.78),
]


static func colour(level: int) -> Color:
	return COLOUR[clampi(level, 1, 3) - 1]


## Returns inside `radius_m` of `origin` (east, north, metres). Empty in clear air.
static func blobs(origin: Vector2, radius_m: float) -> Array:
	var cover := Props.get_f("weather/cloud_cover")
	var precip := Props.get_f("weather/precip")
	var storms := Props.get_f("weather/storms")
	if cover < 0.08 and precip < 0.05 and storms < 0.02:
		return []
	var out: Array = []
	if precip >= 0.2:
		out.append({"e": origin.x, "n": origin.y, "r": radius_m, "level": 1 if precip < 0.5 else 2 if precip < 0.75 else 3})
	elif cover >= 0.12:
		_clouds(out, origin, radius_m, cover)
	if storms >= 0.02:
		_cells(out, origin, radius_m, storms)
	return out


static func _clouds(out: Array, origin: Vector2, radius_m: float, cover: float) -> void:
	var base := Units.ft_to_m(Props.get_f("weather/cloud_base_ft", 4500.0))
	var z := base + CloudField.THICK * 0.45
	var drift: Vector2 = Props.get_v("environment/cloud_drift", Vector2.ZERO)
	var step := maxf(radius_m / 14.0, 1800.0)
	var n := int(ceil(radius_m / step))
	for j in range(-n, n + 1):
		for i in range(-n, n + 1):
			var p := origin + Vector2(float(i), float(j)) * step
			if p.distance_to(origin) > radius_m:
				continue
			var d := CloudField.density(Vector3(p.x, p.y, z), base, cover, drift)
			if d < 0.22:
				continue
			out.append({"e": p.x, "n": p.y, "r": step * 0.62, "level": 2 if d > 0.7 else 1})


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
			var world: Vector2 = (cl.center as Vector2) + shift
			if world.distance_to(origin) > radius_m + float(cl.radius):
				continue
			var s: float = cl.strength
			out.append({"e": world.x, "n": world.y, "r": float(cl.radius) * 0.85, "level": 3 if s >= 0.62 else 2 if s >= 0.38 else 1})


static func _wind_en() -> Vector2:
	var aloft := Weather._from_dir_to_ned(Props.get_f("weather/aloft_dir_deg"), Props.get_f("weather/aloft_kt") * Units.KT)
	return Vector2(aloft.y, aloft.x)
