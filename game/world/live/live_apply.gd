class_name LiveApply
extends RefCounted
## Copies a mapped forecast into Session.setup and the property tree. Values the sliders cannot
## show are clamped. Visibility may stay under 800 m (ATC says the real number); the drawing
## floors that in WeatherVisuals. The pilot's altimeter setting is never written here.


const CLAMP := {
	"temp_c": [5.0, 45.0], "qnh_hpa": [990.0, 1035.0], "wind_kt": [0.0, 40.0], "gust_kt": [0.0, 50.0],
	"cloud_base_ft": [800.0, 12000.0], "visibility_m": [200.0, 40000.0], "cloud_cover": [0.0, 1.0],
	"precip": [0.0, 1.0], "turbulence": [0.0, 1.0], "icing": [0.0, 1.0], "convection": [0.0, 1.0],
	"storms": [0.0, 1.0], "cirrus": [0.0, 1.0],
}


static func for_sim(weather: Dictionary) -> Dictionary:
	var out := weather.duplicate(true)
	for k in out.keys():
		if CLAMP.has(k) and (out[k] is float or out[k] is int):
			var r: Array = CLAMP[k]
			out[k] = clampf(float(out[k]), float(r[0]), float(r[1]))
	if out.has("time_h"):
		out["time_h"] = fposmod(float(out.time_h), 24.0)
	if out.has("day_of_year"):
		out["day_of_year"] = clampf(float(out.day_of_year), 1.0, 366.0)
	out["use_humidity"] = out.has("dewpoint_c")
	return out


static func into_setup(setup: Dictionary, weather: Dictionary) -> void:
	var w := for_sim(weather)
	for k in Session.WEATHER_KEYS:
		if w.has(k):
			setup[k] = w[k]
	setup["live_pack"] = w
	setup["weather"] = "Live"


## What a flight with the switch on publishes. A lesson, or a switch that is off, keeps today's preset rules.
static func push(setup: Dictionary) -> void:
	for k in Session.WEATHER_KEYS:
		Props.set_v("weather/" + k, float(setup[k]))
	if not _live(setup):
		Props.set_v("weather/aloft_dir_deg", float(setup.wind_dir_deg) + 10.0)
		Props.set_v("weather/aloft_kt", float(setup.wind_kt) * 1.6)
		Props.set_v("weather/wind_table", [])
		Props.set_v("weather/visibility_includes_precip", false)
		Props.set_v("weather/cirrus", 0.6)
		Props.set_v("weather/use_humidity", false)
		Props.set_v("weather/live_metar", "")
		return
	var p: Dictionary = setup.live_pack
	Props.set_v("weather/aloft_dir_deg", float(p.get("aloft_dir_deg", float(setup.wind_dir_deg) + 10.0)))
	Props.set_v("weather/aloft_kt", float(p.get("aloft_kt", float(setup.wind_kt) * 1.6)))
	Props.set_v("weather/wind_table", p.get("wind_table", []))
	Props.set_v("weather/visibility_includes_precip", bool(p.get("visibility_includes_precip", true)))
	Props.set_v("weather/cirrus", float(p.get("cirrus", 0.6)))
	Props.set_v("weather/dewpoint_c", float(p.get("dewpoint_c", 0.0)))
	Props.set_v("weather/use_humidity", bool(p.get("use_humidity", false)))
	Props.set_v("weather/live_metar", str(p.get("live_metar", "")))


static func _live(setup: Dictionary) -> bool:
	var pack = setup.get("live_pack", {})
	return bool(setup.get("live_weather", false)) and str(Session.training) == "" and pack is Dictionary and not (pack as Dictionary).is_empty()
