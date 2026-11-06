class_name LiveBlend
extends RefCounted
## Moves the weather the aircraft is in toward a new fetch. Most values take about 5 minutes.
## Cloud base is limited to 300 ft/min and QNH to 1 hPa/min, so a large change takes longer.
## Wind direction takes the short way around. Nothing here writes the altimeter setting.


const WINDOW := 300.0
const BASE_FPM := 300.0
const QNH_PER_MIN := 1.0
const LINEAR := ["wind_kt", "gust_kt", "turbulence", "visibility_m", "cloud_cover", "temp_c", "precip", "icing", "convection", "storms", "cirrus", "dewpoint_c", "aloft_kt"]
const SKIP := ["time_h", "day_of_year", "time_rate"]


## The blended weather at `elapsed` seconds after `origin` started moving toward `target`.
static func at(origin: Dictionary, target: Dictionary, elapsed: float) -> Dictionary:
	var u := clampf(elapsed / WINDOW, 0.0, 1.0)
	var out := origin.duplicate(true)
	for k in LINEAR:
		if target.has(k) and origin.has(k):
			out[k] = lerpf(float(origin[k]), float(target[k]), u)
		elif target.has(k):
			out[k] = target[k]
	if target.has("wind_dir_deg"):
		out["wind_dir_deg"] = _angle(float(origin.get("wind_dir_deg", target.wind_dir_deg)), float(target.wind_dir_deg), u)
	if target.has("aloft_dir_deg"):
		out["aloft_dir_deg"] = _angle(float(origin.get("aloft_dir_deg", target.aloft_dir_deg)), float(target.aloft_dir_deg), u)
	if target.has("cloud_base_ft"):
		out["cloud_base_ft"] = _capped(float(origin.get("cloud_base_ft", target.cloud_base_ft)), float(target.cloud_base_ft), u, BASE_FPM * elapsed / 60.0)
	if target.has("qnh_hpa"):
		out["qnh_hpa"] = _capped(float(origin.get("qnh_hpa", target.qnh_hpa)), float(target.qnh_hpa), u, QNH_PER_MIN * elapsed / 60.0)
	out["wind_table"] = _table(origin.get("wind_table", []), target.get("wind_table", []), u)
	for k in ["visibility_includes_precip", "live_metar", "use_humidity"]:
		if target.has(k):
			out[k] = target[k]
	return out


static func arrived(now: Dictionary, target: Dictionary) -> bool:
	for k in ["qnh_hpa", "wind_kt", "cloud_base_ft", "temp_c", "visibility_m"]:
		if target.has(k) and now.has(k) and absf(float(now[k]) - float(target[k])) > (1.0 if k == "cloud_base_ft" else 0.15):
			return false
	if target.has("wind_dir_deg") and now.has("wind_dir_deg"):
		var d := absf(rad_to_deg(wrapf(deg_to_rad(float(target.wind_dir_deg) - float(now.wind_dir_deg)), -PI, PI)))
		if d > 1.0:
			return false
	return true


## Weather keys only. instruments/altimeter and the airliner baro setting are left alone.
static func write_props(d: Dictionary) -> void:
	for k in d:
		if str(k) in SKIP:
			continue
		Props.set_v("weather/" + str(k), d[k])


static func read_props() -> Dictionary:
	var out := {}
	for k in LINEAR + ["wind_dir_deg", "aloft_dir_deg", "cloud_base_ft", "qnh_hpa"]:
		if Props.has("weather/" + k):
			out[k] = Props.get_v("weather/" + k)
	out["wind_table"] = Props.get_v("weather/wind_table", [])
	out["visibility_includes_precip"] = bool(Props.get_v("weather/visibility_includes_precip", false))
	out["use_humidity"] = bool(Props.get_v("weather/use_humidity", false))
	out["live_metar"] = str(Props.get_v("weather/live_metar", ""))
	return out


static func _angle(a: float, b: float, u: float) -> float:
	return fposmod(rad_to_deg(lerp_angle(deg_to_rad(a), deg_to_rad(b), u)), 360.0)


static func _capped(a: float, b: float, u: float, cap: float) -> float:
	var lin := lerpf(a, b, u)
	var limited := a + clampf(b - a, -cap, cap)
	return limited if absf(limited - a) < absf(lin - a) else lin


static func _table(a, b, u: float) -> Array:
	if typeof(b) != TYPE_ARRAY:
		return a if a is Array else []
	if u >= 1.0 or typeof(a) != TYPE_ARRAY or (a as Array).size() != (b as Array).size():
		if u >= 1.0:
			return (b as Array).duplicate(true)
		return a if a is Array else []
	var out: Array = []
	for i in (a as Array).size():
		var ra: Array = a[i]
		var rb: Array = b[i]
		out.append([lerpf(float(ra[0]), float(rb[0]), u), _angle(float(ra[1]), float(rb[1]), u), lerpf(float(ra[2]), float(rb[2]), u)])
	return out
