class_name LiveModel
extends RefCounted
## An Open-Meteo forecast JSON object, winds in m/s (ask wind_speed_unit=ms).
## Hourly columns contribute the hour matching current.time (else the first hour).
## Pressure-level heights are metres AMSL.
## No network.


static func parse(j: Dictionary) -> Dictionary:
	var cur: Dictionary = j.get("current", {})
	var hour: Dictionary = j.get("hourly", {})
	var idx := _hour_index(hour, str(cur.get("time", "")))
	var out := {"levels": _levels(hour, idx)}
	if j.has("elevation") and j.elevation != null:
		out["elevation_m"] = float(j.elevation)
	_put(out, "temp_c", _num(cur, "temperature_2m", hour, "temperature_2m", idx))
	_put(out, "dew_c", _num(cur, "dew_point_2m", hour, "dew_point_2m", idx))
	_put(out, "surface_hpa", _num(cur, "surface_pressure", hour, "surface_pressure", idx))
	_put(out, "wind_ms", _num(cur, "wind_speed_10m", hour, "wind_speed_10m", idx))
	_put(out, "wind_deg", _num(cur, "wind_direction_10m", hour, "wind_direction_10m", idx))
	_put(out, "gust_ms", _num(cur, "wind_gusts_10m", hour, "wind_gusts_10m", idx))
	_put(out, "vis_m", _num(cur, "visibility", hour, "visibility", idx))
	_put(out, "rain_mm_h", _num(cur, "rain", hour, "rain", idx))
	_put(out, "weather_code", _num(cur, "weather_code", hour, "weather_code", idx))
	_put(out, "cape", _num(cur, "cape", hour, "cape", idx))
	_put(out, "boundary_m", _num(cur, "boundary_layer_height", hour, "boundary_layer_height", idx))
	for name in ["low", "mid", "high"]:
		_put(out, "cloud_" + name, _num(cur, "cloud_cover_" + name, hour, "cloud_cover_" + name, idx))
	return out


## Index in hourly.time of the same clock hour as current.time. Midnight is index 0 when nothing matches.
static func _hour_index(hour: Dictionary, current_time: String) -> int:
	var times = hour.get("time", [])
	if typeof(times) != TYPE_ARRAY or current_time.length() < 13:
		return 0
	var want := current_time.substr(0, 13)
	for i in (times as Array).size():
		if str(times[i]).substr(0, 13) == want:
			return i
	return 0


static func _put(out: Dictionary, key: String, v: float) -> void:
	if not is_nan(v):
		out[key] = v


static func _num(cur: Dictionary, key: String, hour: Dictionary, hour_key: String, idx: int) -> float:
	if cur.has(key) and cur[key] != null:
		return float(cur[key])
	return _first(hour, hour_key, idx)


static func _first(hour: Dictionary, key: String, idx: int) -> float:
	if not hour.has(key) or typeof(hour[key]) != TYPE_ARRAY or (hour[key] as Array).is_empty():
		return NAN
	var col: Array = hour[key]
	var v = col[clampi(idx, 0, col.size() - 1)]
	return NAN if v == null else float(v)


static func _levels(hour: Dictionary, idx: int) -> Array:
	var out: Array = []
	for key in hour:
		var k := str(key)
		if k.begins_with("wind_speed_") and k.ends_with("m"):
			var n := k.trim_prefix("wind_speed_").trim_suffix("m")
			if not n.is_valid_int() or int(n) <= 10:
				continue
			var spd := _first(hour, k, idx)
			var dire := _first(hour, "wind_direction_%sm" % n, idx)
			if not is_nan(spd) and not is_nan(dire):
				out.append({"agl_m": float(n), "ms": spd, "from_deg": dire})
		elif k.begins_with("wind_speed_") and k.ends_with("hPa"):
			var lvl := k.trim_prefix("wind_speed_").trim_suffix("hPa")
			var h := _first(hour, "geopotential_height_%shPa" % lvl, idx)
			var spd := _first(hour, k, idx)
			var dire := _first(hour, "wind_direction_%shPa" % lvl, idx)
			if is_nan(h) or is_nan(spd) or is_nan(dire):
				continue
			var row := {"h_amsl_m": h, "ms": spd, "from_deg": dire}
			var tc := _first(hour, "temperature_%shPa" % lvl, idx)
			var rh := _first(hour, "relative_humidity_%shPa" % lvl, idx)
			if not is_nan(tc):
				row["temp_c"] = tc
			if not is_nan(rh):
				row["rh"] = rh
			out.append(row)
	return out
