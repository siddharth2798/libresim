extends RefCounted
## Icing and rain: accretion conditions and rates, melting, protection (pitot heat, wing / engine anti-ice, alt air),
## the effects on drag, CLmax, stall speed, engine power and the pitot-static probes, saved state, the weather
## setting, notifications. Props are set directly (the cloud physics publishes environment/ac_*), and the shared
## Props tree is given back as it was.

const KT := 0.514444
const T_ICE := 263.15  # -10 C static


## Run f with Props snapshotted and a cold cloudy atmosphere set; returns f's error text.
static func _guard(f: Callable) -> String:
	var snap: Dictionary = Props._p.duplicate(true)
	for k in ["icing/airframe", "icing/pitot", "icing/pitot_blocked", "icing/static_blocked", "icing/engine_1", "icing/engine_2",
			"environment/precip", "environment/storm_intensity", "environment/ac_cloud_density", "weather/icing", "controls/anti_ice/wing",
			"controls/anti_ice/eng_1", "controls/anti_ice/eng_2", "controls/electrical/pitot_heat", "controls/alt_air", "engines/1/running",
			"engines/2/running", "systems/alternate_static", "failures/pitot_blocked", "failures/static_blocked"]:
		Props._p.erase(k)
	_cond(T_ICE, 1.0, "cumulus", 0.7, 60.0)
	var err: String = f.call()
	Props._p = snap
	return err


static func _cond(t_k: float, dens: float, kind: String, avail: float, tas: float) -> void:
	Props.set_v("atmosphere/temperature_k", t_k)
	Props.set_v("environment/ac_cloud_density", dens)
	Props.set_v("environment/cloud_kind", kind)
	Props.set_v("weather/icing", avail)
	Props.set_v("fdm/tas_mps", tas)


static func _icing(id := "c172") -> Icing:
	var ic := Icing.new()
	ic.def = AircraftDef.load_def(id)
	ic._ready()
	return ic


static func _run(n: Node, seconds: float, dt := 0.5) -> void:
	for i in int(seconds / dt):
		n._physics_process(dt)


static func _ice_after(seconds: float, id := "c172") -> float:
	var ic := _icing(id)
	_run(ic, seconds)
	var v := ic.airframe
	ic.free()
	return v


func test_icing_temperature_band_and_factors() -> String:
	var t := IcingRates.temp_factor
	if t.call(5.0) != 0.0 or t.call(-25.0) != 0.0 or t.call(-10.0) != 1.0 or not (t.call(1.0) > 0.0 and t.call(1.0) < 0.3) or not (t.call(-18.0) < 1.0 and t.call(-18.0) > 0.0):
		return "temperature factor: +5 %.2f, +1 %.2f, -10 %.2f, -18 %.2f, -25 %.2f" % [t.call(5.0), t.call(1.0), t.call(-10.0), t.call(-18.0), t.call(-25.0)]
	var base := IcingRates.cloud_rate(1.0, "cumulus", 1.0, -8.0, 80.0)
	if absf(base * IcingRates.AIRFRAME_S - 1.0) > 1e-6:
		return "dense cumulus at availability 1 and 80 m/s should fill in AIRFRAME_S: %.3f" % (base * IcingRates.AIRFRAME_S)
	var strat := IcingRates.cloud_rate(1.0, "stratiform", 1.0, -8.0, 80.0)
	var storm := IcingRates.cloud_rate(1.0, "storm", 1.0, -8.0, 80.0)
	if not (strat < base and base < storm):
		return "liquid water: stratiform %.5f, cumulus %.5f, storm %.5f" % [strat, base, storm]
	if IcingRates.cloud_rate(0.5, "cumulus", 1.0, -8.0, 80.0) >= base or IcingRates.cloud_rate(1.0, "cumulus", 1.0, -8.0, 160.0) <= base:
		return "rate should grow with cloud density and airspeed"
	if IcingRates.cloud_rate(0.04, "cumulus", 1.0, -8.0, 80.0) != 0.0 or IcingRates.cloud_rate(1.0, "cumulus", 0.0, -8.0, 80.0) != 0.0:
		return "no accretion out of cloud (density <= 0.05) or with no supercooled water"
	return ""


func test_icing_accretes_only_in_cloud_and_band() -> String:
	return _guard(func():
		var out := ""
		var ice := _ice_after(300.0)
		if ice < 0.2 or ice > 0.9:
			out += "in cumulus at -10 C for 5 min: %.2f " % ice
		_cond(T_ICE, 0.0, "cumulus", 0.7, 60.0)
		if _ice_after(600.0) != 0.0:
			out += "ice out of cloud "
		for t_c in [10.0, -30.0]:
			_cond(273.15 + t_c, 1.0, "cumulus", 0.7, 60.0)
			if _ice_after(600.0) != 0.0:
				out += "ice at %.0f C " % t_c
		_cond(T_ICE, 1.0, "cumulus", 0.0, 60.0)
		if _ice_after(600.0) != 0.0:
			out += "ice with weather icing 0 "
		return out)


func test_icing_rates_by_cloud_kind_and_storm() -> String:
	return _guard(func():
		_cond(T_ICE, 1.0, "stratiform", 0.5, 60.0)
		var strat := _ice_after(240.0)
		_cond(T_ICE, 1.0, "cumulus", 0.5, 60.0)
		var cu := _ice_after(240.0)
		_cond(T_ICE, 1.0, "storm", 0.5, 60.0)
		var st := _ice_after(240.0)
		Props.set_v("environment/storm_intensity", 1.0)  # a storm cell adds availability even where the setting is 0
		Props.set_v("weather/icing", 0.0)
		var cell := _ice_after(240.0)
		if not (strat > 0.0 and strat < cu and cu < st and cell > 0.0):
			return "stratiform %.3f, cumulus %.3f, storm %.3f, storm cell at setting 0: %.3f" % [strat, cu, st, cell]
		return "")


func test_icing_freezing_rain_is_fast() -> String:
	return _guard(func():
		_cond(268.15, 0.0, "stratiform", 0.0, 60.0)  # -5 C, no cloud, no supercooled setting
		Props.set_v("environment/precip", 0.7)
		var fr := _ice_after(120.0)
		_cond(278.15, 0.0, "stratiform", 0.0, 60.0)  # +5 C: ordinary rain
		var warm := _ice_after(120.0)
		if fr < 0.3 or warm != 0.0:
			return "freezing rain 2 min at -5 C: %.2f (want > 0.3), +5 C: %.2f" % [fr, warm]
		return "")


func test_icing_melts_slowly_cold_fast_warm() -> String:
	return _guard(func():
		var ic := _icing()
		ic.airframe = 0.8
		_cond(T_ICE, 0.0, "cumulus", 0.7, 60.0)
		_run(ic, 600.0)
		var cold := ic.airframe
		ic.airframe = 0.8
		_cond(285.15, 0.0, "cumulus", 0.7, 60.0)  # +12 C
		_run(ic, 120.0)
		var warm := ic.airframe
		ic.free()
		if not (cold < 0.8 and cold > 0.35):
			return "clear cold air should sublimate it slowly: 0.80 -> %.2f in 10 min" % cold
		if warm > 0.01:
			return "+12 C should melt it within 2 min: %.2f" % warm
		return "")


func test_icing_saveable_round_trip() -> String:
	return _guard(func():
		var a := _icing("a320")
		a.airframe = 0.4
		a.pitot = 0.75
		a.engines = [0.2, 0.3]
		a._detect_t = 30.0
		a._pitot_blocked = true
		var d: Dictionary = JSON.parse_string(JSON.stringify(a.save_state()))
		var b := _icing("a320")
		b.load_state(d)
		b.load_state({})  # every key optional
		var ok := a.is_in_group(SituationSystems.GROUP) and a.save_key() == "icing" and b.airframe == 0.4 and b.pitot == 0.75 \
			and b.engines == [0.2, 0.3] and b._detect_t == 30.0 and b._pitot_blocked and Props.get_b("icing/pitot_blocked") \
			and Props.get_f("icing/engine_2") == 0.3
		a.free()
		b.free()
		return "" if ok else "state did not round-trip: %s" % [d])


func test_icing_aircraft_data_and_defaults() -> String:
	var c := Icing.params(AircraftDef.load_def("c172"))
	var a := Icing.params(AircraftDef.load_def("a320"))
	var none := Icing.params(AircraftDef.make("x", {}, "res://aircraft/c172"))
	if c.protection != "pitot_only" or c.pitot_heat_prop != "controls/electrical/pitot_heat" or c.clmax_k <= 0.0:
		return "c172 icing section %s" % [c]
	if a.protection != "wing_and_engine" or a.wing_anti_ice_prop != "controls/anti_ice/wing" or a.engine_anti_ice_prop != "controls/anti_ice/eng_%d" or a.pitot_heat_prop != "controls/anti_ice/probe":
		return "a320 icing section %s" % [a]
	if none != Icing.DEFAULTS or Session.DEFAULT.icing != 0.0:
		return "an aircraft without the section should get the defaults; Session.DEFAULT.icing = %s" % Session.DEFAULT.icing
	return ""


func test_icing_weather_presets_and_old_setups() -> String:
	var want := {"Clear": 0.0, "Fair": 0.0, "Scattered": 0.2, "Broken": 0.4, "Overcast": 0.5, "Winter haze": 0.2, "Monsoon": 0.7}
	for n in want:
		if not Session.WEATHER.has(n) or absf(float(Session.WEATHER[n].get("icing", -1.0)) - want[n]) > 1e-6:
			return "preset %s icing %s" % [n, Session.WEATHER.get(n, {}).get("icing", "none")]
	if not "icing" in Session.WEATHER_KEYS:
		return "icing is not pushed to Props"
	# a setup from before the setting (no icing key / icing 0) still shows its preset
	var page = load("res://ui/menu/conditions_page.gd")
	var s: Dictionary = Session.DEFAULT.duplicate(true)
	for k in Session.WEATHER.Scattered:
		s[k] = Session.WEATHER.Scattered[k]
	s.icing = 0.0
	if page.weather_match(s) != "Scattered":
		return "old Scattered setup shows %s" % page.weather_match(s)
	return ""


func test_icing_notifications_once_per_episode() -> String:
	return _guard(func():
		var n := IcingNotices.new()
		Props.set_v("engine/count", 1)
		for k in ["icing/airframe", "icing/engine_1"]:
			Props.set_v(k, 0.0)
		Props.set_v("icing/pitot_blocked", false)
		var none := n.poll(false).size()
		Props.set_v("icing/airframe", 0.1)
		var first := n.poll(false)
		var again := n.poll(false).size()
		Props.set_v("icing/pitot_blocked", true)
		var pitot := n.poll(false)
		Props.set_v("icing/engine_1", 0.3)
		var eng := n.poll(true)
		Props.set_v("icing/airframe", 0.0)
		n.poll(false)
		Props.set_v("icing/airframe", 0.2)
		var second := n.poll(true)
		if none != 0 or first.size() != 1 or first[0][0] != "Ice accretion — leave icing conditions" or again != 0:
			return "airframe card: %s / %s / %s" % [none, first, again]
		if pitot.size() != 1 or pitot[0][0] != "Pitot icing — airspeed unreliable" or pitot[0][2] != Notifications.WARNING:
			return "pitot card %s" % [pitot]
		if eng.size() != 1 or eng[0][0] != "Engine icing":
			return "engine card %s" % [eng]
		if second.size() != 1 or not str(second[0][1]).contains("anti-ice"):
			return "second episode / airliner hint: %s" % [second]
		return "")


func test_icing_ewd_memo_ice_detected() -> String:
	return _guard(func():
		var w := AirlinerWarnings.new()
		w.def = AircraftDef.load_def("a320")
		w._ready()
		w.update()
		var quiet := str(Props.get_v("ewd/memo_text", "")).contains("ICE")
		Props.set_v("icing/ice_detected", true)
		w.update()
		var amber: Array = Props.get_v("ewd/memo").filter(func(l): return l[0] == "ICE DETECTED")
		Props.set_v("controls/anti_ice/wing", true)
		w.update()
		var memo: Array = Props.get_v("ewd/memo")
		w.free()
		var green := memo.any(func(l): return l[0] == "ICE DETECTED" and l[1] == "green") and memo.any(func(l): return l[0] == "ANTI ICE")
		if quiet or amber.size() != 1 or amber[0][1] != "amber" or not green:
			return "memo: quiet %s, detected %s, with anti-ice %s" % [not quiet, amber, memo]
		return "")
