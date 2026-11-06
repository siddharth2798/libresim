extends RefCounted
## Offline live-weather mapping (world/live/). Fixtures: tests/fixtures/live_weather/.


func _load(name: String) -> Dictionary:
	var raw := FileAccess.get_file_as_string("res://tests/fixtures/live_weather/%s.json" % name)
	var parsed = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}


func _near(a: float, b: float, tol: float, what: String) -> String:
	return "" if absf(a - b) <= tol else "%s %.2f, want %.2f" % [what, a, b]


func teardown() -> void:
	Props.set_v("weather/wind_table", [])
	Props.set_v("weather/visibility_includes_precip", false)


func test_vabb_uses_the_raw_metar_not_the_statute_mile_field() -> String:
	var w := LiveMap.map(LiveMetar.parse(_load("vabb")), {})
	if w.visibility_m != 3000.0:
		return "3000 m in the METAR became %.0f (the JSON visib is statute miles)" % w.visibility_m
	if not w.visibility_includes_precip:
		return "a METAR visibility already includes the rain"
	var err := _near(w.wind_dir_deg, 90.0, 0.1, "wind")
	if err != "":
		return err
	err = _near(w.wind_kt, 6.0, 0.1, "speed")
	if err != "" or w.cloud_cover != 0.0 or w.qnh_hpa != 1013.0:
		return err if err != "" else "NSC cover %.2f QNH %.0f" % [w.cloud_cover, w.qnh_hpa]
	err = _near(w.temp_c, 36.0 + 0.0065 * 11.0, 0.02, "sea-level temp")
	if err != "" or w.dewpoint_c != 19.0 or w.precip != 0.0:
		return err if err != "" else "dew %.1f precip %.2f" % [w.dewpoint_c, w.precip]
	if not str(w.live_metar).contains("3000"):
		return "raw METAR not kept"
	var ist := Time.get_datetime_dict_from_unix_time(1762339200 + 19800)
	var hour := float(ist.hour) + float(ist.minute) / 60.0
	return _near(w.time_h, hour, 0.02, "IST")


func test_voci_ceiling_is_the_lowest_layer_amsl() -> String:
	var metar := LiveMetar.parse(_load("voci"))
	var w := LiveMap.map(metar, LiveModel.parse(_load("kochi")))
	if absf(w.wind_kt - 4.0) > 0.1 or absf(w.wind_dir_deg - 270.0) > 0.1:
		return "model surface wind replaced the METAR: %.0f at %.0f" % [w.wind_kt, w.wind_dir_deg]
	if absf(w.cloud_cover - 0.2) > 0.01:
		return "lowest layer is FEW, cover %.2f" % w.cloud_cover
	var base := 1500.0 + Units.m_to_ft(8.0)
	var err := _near(w.cloud_base_ft, base, 1.0, "base AMSL")
	if err != "" or w.visibility_m != 4500.0 or w.qnh_hpa != 1011.0:
		return err if err != "" else "vis %.0f QNH %.0f" % [w.visibility_m, w.qnh_hpa]
	if w.storms != 0.0 or w.icing != 0.7:
		return "CB without CAPE: storms %.1f icing %.1f" % [w.storms, w.icing]
	if (w.wind_table as Array).is_empty():
		return "the model should still supply the wind table"
	return ""


func test_storm_needs_cape_over_1000() -> String:
	var metar := LiveMetar.parse(_load("ts"))
	var calm := LiveMap.map(metar, {"cape": 50})
	var hot := LiveMap.map(metar, {"cape": 1500})
	if calm.storms != 0.0 or hot.storms != 0.7:
		return "storms %.1f at CAPE 50, %.1f at 1500" % [calm.storms, hot.storms]
	if absf(hot.cloud_cover - 0.75) > 0.01 or hot.visibility_m != 2000.0:
		return "ceiling %.2f vis %.0f" % [hot.cloud_cover, hot.visibility_m]
	if absf(hot.precip - 0.85) > 0.01 or absf(hot.gust_kt - 25.0) > 0.1 or hot.icing != 0.7:
		return "precip %.2f gust %.0f icing %.1f" % [hot.precip, hot.gust_kt, hot.icing]
	return _near(hot.cloud_base_ft, 1500.0 + Units.m_to_ft(14.0), 1.0, "TS base")


func test_pune_model_reduces_pressure_and_builds_a_wind_table() -> String:
	var w := LiveMap.map({}, LiveModel.parse(_load("pune")))
	var qnh := LiveMap.qnh_from_qfe(945.76, 592.0)
	var err := _near(w.qnh_hpa, qnh, 0.2, "QNH")
	if err != "" or absf(w.qnh_hpa - 945.76) < 1.0 or absf(w.qnh_hpa - 1019.0) < 1.0:
		return err if err != "" else "QNH fell through to station pressure or MSL"
	err = _near(w.temp_c, 31.1 + 0.0065 * 592.0, 0.05, "sea-level temp")
	if err != "":
		return err
	err = _near(w.wind_kt, 3.0 * LiveMap.MS_KT, 0.05, "10 m wind")
	if err != "" or absf(w.cloud_cover - 0.4) > 0.01 or absf(w.cirrus - 0.2) > 0.01:
		return err if err != "" else "cover %.2f cirrus %.2f" % [w.cloud_cover, w.cirrus]
	var base_m := 125.0 * (31.1 - 20.0) + 592.0
	err = _near(w.cloud_base_ft, Units.m_to_ft(base_m), 2.0, "spread base")
	if err != "":
		return err
	var table: Array = w.wind_table
	if table.size() != 3:
		return "%d wind levels, want 80 m, 180 m and 850 hPa" % table.size()
	err = _near(float(table[0][2]), 4.0 * LiveMap.MS_KT, 0.05, "80 m")
	if err != "":
		return err
	if w.storms != 0.0 or w.icing != 0.0 or not w.visibility_includes_precip:
		return "storms %.1f icing %.1f" % [w.storms, w.icing]
	return _near(w.convection, (1615.0 - 500.0) / 2000.0, 0.02, "thermals")


func test_vrb_9999_and_altimeter_inches() -> String:
	var vrb := LiveMap.map(LiveMetar.parse("METAR VABB 051200Z VRB05KT 9999 NSC 30/20 Q1012"), {}, 270.0)
	if absf(vrb.wind_dir_deg - 270.0) > 0.1 or vrb.wind_kt > 2.9 or vrb.visibility_m != 12000.0:
		return "VRB %.0f kt at %.0f, vis %.0f" % [vrb.wind_kt, vrb.wind_dir_deg, vrb.visibility_m]
	var calm := LiveMap.map(LiveMetar.parse("METAR VABB 051200Z 00000KT CAVOK 30/20 Q1013"), {}, 90.0)
	if absf(calm.wind_dir_deg - 90.0) > 0.1 or calm.wind_kt > 0.1 or calm.cloud_cover != 0.0:
		return "calm took direction %.0f" % calm.wind_dir_deg
	var inches := LiveMetar.parse("METAR KJFK 051200Z 18008KT 10SM FEW250 15/10 A2992")
	return _near(float(inches.qnh_hpa), 29.92 * Units.INHG / 100.0, 0.2, "A2992")


func test_moist_level_sets_the_base_and_light_icing() -> String:
	var model := {"levels": [{"h_amsl_m": 2500.0, "ms": 10.0, "from_deg": 270.0, "temp_c": -8.0, "rh": 95.0}]}
	var w := LiveMap.map({}, model)
	if absf(w.icing - 0.3) > 0.01:
		return "icing %.2f" % w.icing
	return _near(w.cloud_base_ft, Units.m_to_ft(2500.0), 2.0, "RH base")


func test_reported_visibility_is_not_cut_again_by_rain() -> String:
	if WeatherVisuals.drawn_visibility(3000.0, 0.85, true) != 3000.0:
		return "METAR visibility was reduced by the rain"
	if WeatherVisuals.drawn_visibility(5000.0, 1.0, false) > 3000.0:
		return "hand-set visibility should still fall in heavy rain"
	return ""


func test_wind_table_matches_at_the_sample_and_falls_back() -> String:
	Props.set_v("weather/wind_dir_deg", 90.0)
	Props.set_v("weather/wind_kt", 10.0)
	Props.set_v("weather/wind_table", [[80.0, 100.0, 14.0], [180.0, 110.0, 18.0], [1500.0, 140.0, 25.0]])
	var weather := Weather.new()
	var at10 := weather.wind_at(10.0).length() / Units.KT
	var at80 := weather.wind_at(80.0).length() / Units.KT
	var at180 := weather.wind_at(180.0).length() / Units.KT
	var at1500 := weather.wind_at(1500.0).length() / Units.KT
	Props.set_v("weather/wind_table", [])
	Props.set_v("weather/aloft_kt", 20.0)
	Props.set_v("weather/aloft_dir_deg", 100.0)
	var low := weather.wind_at(10.0).length()
	var high := weather.wind_at(300.0).length()
	weather.free()
	if absf(at10 - 10.0) > 0.5 or absf(at80 - 14.0) > 0.5 or absf(at180 - 18.0) > 0.5 or absf(at1500 - 25.0) > 0.5:
		return "table %.1f %.1f %.1f %.1f kt" % [at10, at80, at180, at1500]
	if high <= low:
		return "empty table should keep the surface-to-aloft blend"
	return ""
