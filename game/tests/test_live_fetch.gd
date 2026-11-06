extends RefCounted
## Live weather with no network: fallback order, cache age, and the in-flight blend.
## Fixtures: tests/fixtures/live_weather/.


func _load(name: String) -> String:
	return FileAccess.get_file_as_string("res://tests/fixtures/live_weather/%s.json" % name)


func _body(name: String) -> String:
	var d: Dictionary = JSON.parse_string(_load(name))
	d["lat"] = 19.09
	d["lon"] = 72.87
	return JSON.stringify([d])


func _place() -> Dictionary:
	return {"lat": 19.09, "lon": 72.87, "elev_m": 11.0, "name": "Mumbai", "icao": "VABB"}


func _now() -> int:
	return 1762339200 + 28 * 60


func teardown() -> void:
	LiveCache.path = LiveCache.PATH
	Props.set_v("weather/precip", 0.0)
	Props.set_v("instruments/altimeter/kollsman_inhg", 29.92)


func test_metar_wins_and_a_far_station_falls_through_to_the_model() -> String:
	var place := _place()
	var both := LiveFetch.decide({"noaa": {"code": 200, "body": _body("vabb")}, "meteo": {"code": 200, "body": _load("pune")}}, place, {}, _now(), 270.0, true, "Fair")
	if both.tier != "metar+model" or absf(float(both.weather.wind_dir_deg) - 90.0) > 0.1:
		return "METAR should win the wind: %s at %s" % [both.tier, both.weather.get("wind_dir_deg", "?")]
	if not str(both.status).contains("VABB") or not str(both.status).contains("28 min ago"):
		return both.status
	var far: Dictionary = JSON.parse_string(_load("vabb"))
	far["lat"] = 0.0
	far["lon"] = 0.0
	var model := LiveFetch.decide({"noaa": {"code": 200, "body": JSON.stringify([far])}, "meteo": {"code": 200, "body": _load("pune")}}, place, {}, _now(), 270.0, true, "Fair")
	if model.tier != "model" or absf(float(model.weather.wind_dir_deg) - 270.0) > 0.1:
		return "a station past 50 km should leave the model: %s" % model.tier
	return "" if str(model.status).contains("Mumbai") else model.status


func test_timeout_429_and_bad_json_fall_back_in_order() -> String:
	var place := _place()
	var limited := LiveFetch.decide({"noaa": {"code": 429, "body": ""}, "meteo": {"code": 200, "body": _load("pune")}}, place, {}, _now(), 270.0, true, "Fair")
	if limited.tier != "model":
		return "429 should skip NOAA, got %s" % limited.tier
	var cached := {"fetched_unix": _now() - 3 * 3600, "weather": {"wind_kt": 4.0, "qnh_hpa": 1010.0}}
	var stale := LiveFetch.decide({"noaa": {"code": 0, "body": ""}, "meteo": {"code": 0, "body": ""}}, place, cached, _now(), 270.0, true, "Fair")
	if stale.tier != "cache" or not str(stale.status).contains("3 h old"):
		return "timeout should use the cache: %s %s" % [stale.tier, stale.status]
	var none := LiveFetch.decide({"noaa": {"code": 200, "body": "[]"}, "meteo": {"code": 200, "body": "{\"error\":true}"}}, place, {}, _now(), 270.0, true, "Fair")
	if none.tier != "preset" or none.status != "Using the Fair preset.":
		return "bad JSON should keep the preset: %s %s" % [none.tier, none.status]
	return ""


func test_cache_round_trip() -> String:
	LiveCache.path = "user://live_weather_test.json"
	LiveCache.write({"fetched_unix": 10, "weather": {"wind_kt": 6.0}})
	var back := LiveCache.read()
	LiveCache.clear()
	LiveCache.path = LiveCache.PATH
	return "" if absf(float(back.weather.wind_kt) - 6.0) < 0.01 else "cache read %s" % back


func test_blend_respects_the_rate_limits_and_the_short_way_round() -> String:
	var origin := {"qnh_hpa": 1010.0, "cloud_base_ft": 2000.0, "wind_kt": 10.0, "wind_dir_deg": 350.0}
	var target := {"qnh_hpa": 1020.0, "cloud_base_ft": 4000.0, "wind_kt": 20.0, "wind_dir_deg": 10.0}
	var min1 := LiveBlend.at(origin, target, 60.0)
	if absf(float(min1.qnh_hpa) - 1011.0) > 0.05:
		return "QNH moved %.2f in one minute (limit 1 hPa)" % float(min1.qnh_hpa)
	if absf(float(min1.cloud_base_ft) - 2300.0) > 1.0:
		return "cloud base %.0f ft after one minute (limit 300 ft)" % float(min1.cloud_base_ft)
	if absf(float(min1.wind_kt) - 12.0) > 0.05:
		return "wind %.2f kt after one minute of a 5 min blend" % float(min1.wind_kt)
	var dir := float(min1.wind_dir_deg)
	if dir < 350.0 and dir > 20.0:
		return "direction took the long way: %.1f" % dir
	var done := LiveBlend.at(origin, target, 700.0)
	if not LiveBlend.arrived(done, target):
		return "not home after the slow QNH: %s" % done.qnh_hpa
	Props.set_v("instruments/altimeter/kollsman_inhg", 29.92)
	Props.set_v("instruments/pfd/baro_hpa", 1011.0)
	LiveBlend.write_props(done)
	if absf(Props.get_f("instruments/altimeter/kollsman_inhg") - 29.92) > 0.001 or absf(Props.get_f("instruments/pfd/baro_hpa") - 1011.0) > 0.001:
		return "the blend wrote the pilot's altimeter setting"
	return "" if absf(Props.get_f("weather/qnh_hpa") - float(done.qnh_hpa)) < 0.01 else "QNH was not published"


func test_model_uses_the_current_hour_not_midnight() -> String:
	var body := JSON.stringify({
		"current": {"time": "2026-11-06T09:00", "temperature_2m": 30.0},
		"hourly": {"time": ["2026-11-06T00:00", "2026-11-06T09:00"], "cape": [10, 1800], "boundary_layer_height": [80, 1600]},
	})
	var m := LiveOpenMeteo.parse_body(body)
	if absf(float(m.get("cape", -1)) - 1800.0) > 0.1 or absf(float(m.get("boundary_m", -1)) - 1600.0) > 0.1:
		return "midnight hour was used: cape %s boundary %s" % [m.get("cape", "?"), m.get("boundary_m", "?")]
	return ""


func test_lesson_and_live_weather_flag() -> String:
	var prev: Dictionary = Session.setup.duplicate(true)
	var skip := Session.skip_menu
	Session._parse_args(PackedStringArray(["--live-weather", "--airport=VAPO", "--lesson=takeoff"]))
	var on := bool(Session.setup.live_weather)
	var id := str(Session.training)
	Session.end_lesson()
	Session.setup = prev
	Session.skip_menu = skip
	Session.training = ""
	if on:
		return "a lesson kept live weather on"
	return "" if id == "takeoff" else "lesson did not start (%s)" % id
