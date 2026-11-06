extends RefCounted
## The numeric checks in docs/LIVE-WEATHER-PLAN.md section 4. Headless. No network.


func teardown() -> void:
	Props.set_v("weather/precip", 0.0)
	Props.set_v("weather/wind_table", [])
	Props.set_v("weather/use_humidity", false)


func test_isa_offset_density_altitude_and_qnh() -> String:
	var a := AtmosphereISA.new()
	a.delta_t = 20.0
	a.update(5000.0 * 0.3048)
	var extra := Units.m_to_ft(AtmosphereISA.density_altitude(a.density) - AtmosphereISA.pressure_altitude(a.pressure))
	if absf(extra - 2400.0) > 150.0:
		return "ISA+20 at 5000 ft density altitude %+0.f ft, want about +2400" % extra
	var sea := 31.1 + 0.0065 * 590.0
	var freeze_m := sea / 0.0065
	if absf(freeze_m - 5210.0) > 400.0:
		return "freezing level %.0f m from a 31.1 C field at 590 m" % freeze_m
	var p := 101325.0
	var dft := absf(Units.m_to_ft(AtmosphereISA.indicated_altitude(p, 100325.0) - AtmosphereISA.indicated_altitude(p, 101325.0)))
	if dft < 270.0 or dft > 300.0:
		return "10 hPa moved the altimeter %.0f ft" % dft
	return ""


func test_humidity_adds_density_altitude_and_not_temperature() -> String:
	var extra := AtmosphereISA.virtual_extra_k(36.0, 19.0, 1013.0)
	if extra < 2.2 or extra > 2.9:
		return "36/19 C virtual temperature +%.2f K, want about +2.5" % extra
	var a := AtmosphereISA.new()
	a.delta_t = 21.0
	a.update(0.0)
	var t := a.temperature
	var dry := AtmosphereISA.density_altitude(a.density)
	a.humidity_k = extra
	a.update(0.0)
	var rise := Units.m_to_ft(AtmosphereISA.density_altitude(a.density) - dry)
	if absf(a.temperature - t) > 0.01:
		return "humidity changed the temperature icing reads"
	if rise < 220.0 or rise > 400.0:
		return "humidity density altitude %+0.f ft, want about +300" % rise
	return ""


func test_live_values_clamp_and_fog_under_800_m_is_not_drawn() -> String:
	var w := LiveApply.for_sim({"temp_c": 50.0, "qnh_hpa": 980.0, "visibility_m": 100.0, "cloud_base_ft": 200.0})
	if float(w.temp_c) != 45.0 or float(w.qnh_hpa) != 990.0 or float(w.visibility_m) != 200.0 or float(w.cloud_base_ft) != 800.0:
		return "clamp %s" % w
	if WeatherVisuals.drawn_visibility(200.0, 0.0, true) != 800.0:
		return "200 m was drawn as fog"
	if WeatherVisuals.drawn_visibility(1500.0, 0.0, true) != 1500.0:
		return "1500 m was changed"
	var under := WeatherVisuals.light_scales(WeatherVisuals.sun_occlusion(1.0, 1.0), 0.0)
	var above := WeatherVisuals.sun_occlusion(1.0, 0.0)
	if float(under.sun) > 0.15 or above > 0.01:
		return "OVC sun under %.2f above occlusion %.2f" % [float(under.sun), above]
	return ""


func test_wet_stop_is_longer_than_dry() -> String:
	var g := GearGround.new({"gear": [{
		"name": "left", "type": "BOGEY", "pos_m": [0.0, 1.0, 1.0],
		"spring_n_per_m": 20000.0, "damping_n_s_per_m": 2000.0,
		"static_friction": 0.8, "dynamic_friction": 0.5, "rolling_friction": 0.02,
		"max_steer_deg": 0.0, "brake_group": "LEFT"}]})
	Props.set_v("weather/precip", 0.0)
	var dry := g._mu_braked(g.contacts[0], 1.0, 20.0)
	Props.set_v("weather/precip", 1.0)
	var wet := g._mu_braked(g.contacts[0], 1.0, 20.0)
	var v := 50.0 * Units.KT
	var ratio := (v * v / (2.0 * wet * 9.80665)) / (v * v / (2.0 * dry * 9.80665))
	return "" if ratio >= 1.4 else "wet/dry stop %.2f" % ratio


func test_wind_shear_of_12_kt_reaches_the_airspeed() -> String:
	Props.set_v("weather/wind_dir_deg", 360.0)
	Props.set_v("weather/wind_kt", 10.0)
	Props.set_v("weather/wind_table", [[30.48, 360.0, 10.0], [91.44, 360.0, 22.0]])
	var weather := Weather.new()
	var low := weather.wind_at(30.48).length() / Units.KT
	var high := weather.wind_at(91.44).length() / Units.KT
	weather.free()
	if absf((high - low) - 12.0) > 0.5:
		return "table shear %.1f kt" % (high - low)
	var f := FDM.new()
	f.wind_ned = Weather._from_dir_to_ned(360.0, high * Units.KT)
	f.set_airborne(0.0, 0.0, 91.44, 0.0, 90.0 * Units.KT)
	f.wind_ned = Weather._from_dir_to_ned(360.0, low * Units.KT)
	f.step(0.05)
	var drop := 90.0 - f.vt / Units.KT
	return "" if absf(drop - 12.0) < 2.0 else "airspeed dropped %.1f kt" % drop


func test_turbulence_sigma_matches_the_mapped_target() -> String:
	var err := _sigma(10.0)
	if err != "":
		return err
	return _sigma(20.0)


func _sigma(kt: float) -> String:
	Props.set_v("weather/wind_dir_deg", 270.0)
	Props.set_v("weather/wind_kt", kt)
	Props.set_v("weather/gust_kt", kt)
	Props.set_v("weather/turbulence", LiveMap.turbulence_of(kt, kt))
	Props.set_v("weather/cloud_cover", 0.0)
	Props.set_v("weather/convection", 0.0)
	Props.set_v("weather/storms", 0.0)
	Props.set_v("weather/precip", 0.0)
	Props.set_v("weather/wind_table", [])
	Props.set_v("fdm/position_enu", Vector3.ZERO)
	Props.set_v("fdm/agl_m", 10.0)
	Props.set_v("fdm/tas_mps", 50.0)
	var w := Weather.new()
	w._ready()
	w._rng.seed = 7
	var sum := 0.0
	var sum2 := 0.0
	var n := 0
	for i in 12000:  # dt 0.05 s: the filter's variance matches the continuous target only when dt is well under tau
		w._physics_process(0.05)
		if i < 2000:
			continue
		var z := w._turb.z
		sum += z
		sum2 += z * z
		n += 1
	w.free()
	var mean := sum / n
	var std := sqrt(maxf(sum2 / n - mean * mean, 0.0))
	var target := 0.1 * kt * Units.KT
	if absf(std - target) > 0.25 * target:
		return "at %d kt vertical sigma %.3f, target %.3f" % [int(kt), std, target]
	return ""


func test_atis_dewpoint_and_metar_history() -> String:
	var phr := AtcPhraseology.new()
	var c := AtcController.new("VT-FSM")
	var w := AtcWorld.blank()
	var plain := phr.fill(phr.template("controller", "atis", "*"), AtcSlots.build(c, w))
	w["dew"] = 19.0
	var with := phr.fill(phr.template("controller", "atis", "*"), AtcSlots.build(c, w))
	if plain.contains("dew") or not with.contains("dew point 19"):
		return "ATIS dew:\n%s\n%s" % [plain, with]
	Props.set_v("weather/live_metar", "METAR VABB 051200Z 09006KT 3000")
	var seen := AtcSession.note_metar(c, 1.0, "")
	if c.log.is_empty() or not str(c.log[0].text).contains("VABB"):
		return "METAR was not added to the radio history"
	if AtcSession.note_metar(c, 2.0, seen) != seen or c.log.size() != 1:
		return "the same METAR was logged twice"
	Props.set_v("weather/live_metar", "")
	return ""
