extends RefCounted
## E2E scenarios: every failure in the catalogue shows its effect; nav receivers
## (VOR, ILS, ADF, DME, GPS); frame-time performance.


func _avg(r, prop: String, seconds: float) -> float:
	var s := 0.0
	var n := 0
	var t := 0.0
	while t < seconds:
		await r.wait(0.1)
		t += 0.1
		s += float(r.p(prop))
		n += 1
	return s / maxf(n, 1)


func _find_script(n: Node, file: String) -> Node:
	var sc: Script = n.get_script()
	if sc and sc.resource_path.ends_with(file):
		return n
	for c in n.get_children():
		var x := _find_script(c, file)
		if x:
			return x
	return null


func _nearest(r, list: Array) -> Dictionary:
	var p: Vector3 = Props.get_v("fdm/position_enu", Vector3.ZERO)
	var best := {}
	var bd := INF
	for s in list:
		var d := Vector2(p.x, p.y).distance_to(Vector2(s.x, s.y))
		if d < bd:
			bd = d
			best = s
	return best


func _tune(r) -> Dictionary:
	var db = r.f.get_node("Avionics/Nav").db
	var vor := _nearest(r, db.vors)
	var ndb := _nearest(r, db.ndbs)
	Props.set_v("controls/nav1/freq_mhz", float(vor.mhz))
	Props.set_v("controls/adf/freq_khz", float(ndb.khz))
	Props.set_v("controls/gps/target", r.f._apt)
	var ils := {}
	for s in db.ils:
		if s.airport == r.f._apt and s.runway == str(r.f._start.ident):
			ils = s
			Props.set_v("controls/nav2/freq_mhz", float(s.mhz))
	return {"vor": vor, "ndb": ndb, "ils": ils}


## Air start (--air=3000). Attitude held level by the test pilot between failures.
func failures(r) -> void:
	await r.wait(2.0)
	r.take_controls()
	r.pilot.pitch_tgt = rad_to_deg(Props.get_f("fdm/pitch_rad"))
	r.pilot.active = true
	_tune(r)
	await r.wait(2.0)
	var fm: Node = r.f.get_node("Systems/Failures")
	var gy: Node = r.f.get_node("Instruments/Gyros")
	var radios := _find_script(r.f, "radio_stack.gd")
	var order := FailureCatalog.all_ids()
	order.erase("engine")
	order.append("engine")  # last: it may not come back
	for id in order:
		var pre := {}
		match id:
			"engine", "engine_partial": pre.v = await _avg(r, "engine/power_w", 1.5)
			"mag_left", "mag_right": pre.v = await _avg(r, "engine/rpm", 1.5)
			"alternator": pre.v = r.p("systems/electrical/battery_amps")
			"pitot_blocked": pre.v = r.p("systems/pitot_static/pitot_pa")
			"static_blocked": pre.v = r.p("instruments/altimeter_ft")
			"trim": pre.v = r.f.get_node("Fdm").fdm.fcs.pitch_trim
			"nav1", "nav2", "adf", "gps": pre.v = r.p("avionics/%s/valid" % id, false)
			"dme": pre.v = r.p("avionics/nav1/dme_nm", -1.0)
		fm.fail_now(id)
		await r.wait(0.2)
		var ok := false
		var det := ""
		match id:
			"engine", "engine_partial":
				var post: float = await _avg(r, "engine/power_w", 3.0)
				ok = post < pre.v * (0.2 if id == "engine" else 0.92)
				det = "power %.0f -> %.0f W, rpm now %.0f" % [pre.v, post, r.p("engine/rpm")]
			"mag_left", "mag_right":
				var post: float = await _avg(r, "engine/rpm", 3.0)
				ok = post < pre.v - 10.0
				det = "rpm %.0f -> %.0f" % [pre.v, post]
			"fuel_leak_left", "fuel_leak_right":
				var side: String = id.get_slice("_", 2)
				var k0: float = r.p("fuel/%s_kg" % side)
				await r.wait(3.0)
				ok = float(r.p("fuel/leak_%s_kgs" % side)) > 0.0 and float(r.p("fuel/%s_kg" % side)) < k0
				det = "leak %.4f kg/s, %s tank %.2f -> %.2f kg" % [r.p("fuel/leak_%s_kgs" % side), side, k0, r.p("fuel/%s_kg" % side)]
			"alternator":
				await r.wait(2.0)
				ok = float(r.p("systems/electrical/battery_amps")) < 0.0
				det = "battery %.1f -> %.1f A, bus %.1f V" % [pre.v, r.p("systems/electrical/battery_amps"), r.p("systems/electrical/bus_volts")]
			"battery":
				await r.wait(1.0)
				ok = float(r.p("systems/electrical/bus_volts")) < 1.0
				det = "bus %.1f V, avionics powered=%s" % [r.p("systems/electrical/bus_volts"), r.p("systems/electrical/avionics_powered", "?")]
			"vacuum_pump":
				await r.wait(2.0)
				ok = float(r.p("systems/vacuum/suction_inhg")) < 1.0
				det = "suction %.2f inHg" % r.p("systems/vacuum/suction_inhg")
			"ai", "hi":
				var s0: float = gy.get("_%s_spin" % id)
				await r.wait(3.0)
				var s1: float = gy.get("_%s_spin" % id)
				ok = s1 < s0
				det = "gyro spin %.3f -> %.3f (spins down over minutes)" % [s0, s1]
			"tc":
				await r.wait(1.0)
				ok = bool(r.p("instruments/tc_flag", false))
				det = "tc_flag=%s" % r.p("instruments/tc_flag", false)
			"pitot_blocked":
				var k0: float = r.kias()
				Props.set_v("controls/throttle", 0.0)
				await r.wait(5.0)
				ok = absf(float(r.p("systems/pitot_static/pitot_pa")) - pre.v) < 5.0 and absf(float(r.p("instruments/asi_kt")) - r.kias()) > 3.0
				det = "true IAS %.0f -> %.0f kt, ASI %.0f kt, pitot %.0f -> %.0f Pa" % [k0, r.kias(), r.p("instruments/asi_kt"), pre.v, r.p("systems/pitot_static/pitot_pa")]
				Props.set_v("controls/throttle", 0.75)
			"static_blocked":
				var a0: float = r.alt_ft()
				var th: float = r.p("controls/throttle")
				r.pilot.pitch_tgt -= 6.0
				Props.set_v("controls/throttle", 0.0)
				await r.wait(6.0)
				r.pilot.pitch_tgt += 6.0
				Props.set_v("controls/throttle", th)
				ok = absf(float(r.p("instruments/altimeter_ft")) - pre.v) < 10.0 and absf(r.alt_ft() - a0) > 30.0
				det = "true alt %.0f -> %.0f ft, altimeter %.0f -> %.0f ft" % [a0, r.alt_ft(), pre.v, r.p("instruments/altimeter_ft")]
			"flaps":
				Props.set_v("controls/flaps", 1)
				await r.wait(4.0)
				ok = float(r.p("fdm/flap_deg")) < 1.0
				det = "flaps commanded 10 deg, at %.1f deg" % r.p("fdm/flap_deg")
				Props.set_v("controls/flaps", 0)
			"trim":
				Props.set_v("controls/pitch_trim", float(pre.v) + 0.3)
				await r.wait(0.5)
				var now: float = r.f.get_node("Fdm").fdm.fcs.pitch_trim
				ok = absf(now - pre.v) < 0.001
				det = "trim %.3f, commanded %.3f, now %.3f" % [pre.v, pre.v + 0.3, now]
				Props.set_v("controls/pitch_trim", pre.v)
			"brake_left", "brake_right":
				Props.set_v("controls/" + id, 1.0)
				await r.wait(0.2)
				var b: float = r.f.get_node("Fdm").fdm.gear.get(id)
				ok = b == 0.0
				det = "commanded 1.0, gear %s=%.2f" % [id, b]
				Props.set_v("controls/" + id, 0.0)
			"com1":  # the ATC session (atc/atc_session.gd) tells the pilot the radio is dead (last transmission, /atc/last_tx)
				await r.wait(1.5)
				var said := str(r.p("atc/last_tx", ""))
				ok = said.contains("dead")
				det = "ATC: '%s'" % said
			"com2", "xpdr":
				ok = radios != null and not radios._alive(id)
				det = "radio stack alive=%s" % (radios._alive(id) if radios else "no radio stack")
			"nav1", "nav2", "adf", "gps":
				await r.wait(1.0)
				var v = r.p("avionics/%s/valid" % id, false)
				ok = pre.v == true and v == false
				det = "valid %s -> %s" % [pre.v, v]
			"dme":
				await r.wait(1.0)
				ok = float(pre.v) > 0.0 and float(r.p("avionics/nav1/dme_nm")) < 0.0
				det = "dme %.1f -> %.1f nm" % [pre.v, r.p("avionics/nav1/dme_nm")]
		r.check("failure " + id, ok and bool(r.p("failures/" + id, false)), det)
		fm.repair(id)
		await r.wait(1.5)
	await r.wait(10.0)
	r.metric("engine_after_repair", "running=%s rpm=%.0f" % [r.p("engine/running", false), r.p("engine/rpm")])
	await r.shot("after_failures")


## Air start on a 5 nm final (--air=1500): ILS on NAV2 (default 108.1 = VABB 27),
## nearest VOR-DME on NAV1, nearest NDB on the ADF, GPS direct to the airport.
func nav(r) -> void:
	await r.wait(2.0)
	var st := _tune(r)
	await r.wait(3.0)
	var p: Vector3 = Props.get_v("fdm/position_enu", Vector3.ZERO)
	var ils_ok: bool = r.p("avionics/nav2/valid", false)
	r.check("ils_loc_valid", ils_ok, "nav2 %.2f MHz ident %s kind %s" % [r.p("controls/nav2/freq_mhz"), r.p("avionics/nav2/ident", ""), r.p("avionics/nav2/kind", "")])
	r.check("ils_loc_centred", absf(float(r.p("avionics/nav2/cdi"))) < 0.3, "cdi %.2f (on the extended centreline)" % r.p("avionics/nav2/cdi"))
	r.check("ils_gs_valid", r.p("avionics/nav2/gs_valid", false) and absf(float(r.p("avionics/nav2/gs"))) < 0.9, "gs %.2f (1500 ft at 5 nm ~ on the slope)" % r.p("avionics/nav2/gs"))
	var vor: Dictionary = st.vor
	var d := Vector2(p.x, p.y).distance_to(Vector2(vor.x, vor.y)) / 1852.0
	var radial := fposmod(rad_to_deg(atan2(p.x - vor.x, p.y - vor.y)) - float(vor.var_deg), 360.0)
	r.check("vor_receive", r.p("avionics/nav1/valid", false), "%s %.2f MHz at %.1f nm" % [vor.ident, vor.mhz, d])
	r.check("vor_radial", r.angle_diff(float(r.p("avionics/nav1/radial_deg")), radial) < 2.0, "radial %.1f, expected %.1f" % [r.p("avionics/nav1/radial_deg"), radial])
	r.check("dme_distance", absf(float(r.p("avionics/nav1/dme_nm")) - d) < 0.6, "dme %.2f nm, ground distance %.2f nm" % [r.p("avionics/nav1/dme_nm"), d])
	r.check("gps_direct_to", r.p("avionics/gps/valid", false) and float(r.p("avionics/gps/dist_nm")) > 2.0 and float(r.p("avionics/gps/dist_nm")) < 8.0,
		"GPS -> %s %.1f nm" % [r.p("avionics/gps/ident", ""), r.p("avionics/gps/dist_nm")])
	var ndb: Dictionary = st.ndb
	var nd := Vector2(p.x, p.y).distance_to(Vector2(ndb.x, ndb.y)) / 1852.0
	r.metric("nearest_ndb", "%s %.0f nm" % [ndb.ident, nd])
	if nd > 45.0:
		r.check("adf_out_of_range_parks", not r.p("avionics/adf/valid", false), "nearest NDB %s is %.0f nm away (> 50 nm range)" % [ndb.ident, nd])
		await _nav_end(r)
		return
	var brg := fposmod(rad_to_deg(atan2(ndb.x - p.x, ndb.y - p.y)) - r.hdg_deg(), 360.0)
	r.check("adf_receive", r.p("avionics/adf/valid", false) and r.angle_diff(float(r.p("avionics/adf/bearing_deg")), brg) < 5.0,
		"%s %.0f kHz rel bearing %.0f, expected %.0f" % [ndb.ident, ndb.khz, r.p("avionics/adf/bearing_deg"), brg])
	await _nav_end(r)


func _nav_end(r) -> void:
	await r.key(KEY_1)
	await r.wait(1.0)
	await r.shot("cockpit_nav")


## Frame times over 30 s of flight (after a 6 s warm-up).
func perf(r) -> void:
	await r.wait(6.0)
	var ms: Array = []
	var t0 := Time.get_ticks_usec()
	var last := t0
	while Time.get_ticks_usec() - t0 < 30_000_000:
		await r.get_tree().process_frame
		var now := Time.get_ticks_usec()
		ms.append((now - last) / 1000.0)
		last = now
	ms.sort()
	var total := 0.0
	for x in ms:
		total += x
	var n1 := maxi(ms.size() / 100, 1)
	var worst := 0.0
	for i in n1:
		worst += ms[ms.size() - 1 - i]
	r.metric("frames", ms.size())
	r.metric("avg_fps", 1000.0 * ms.size() / total)
	r.metric("low1_fps", 1000.0 / (worst / n1))
	r.metric("p99_ms", ms[int(ms.size() * 0.99)])
	r.metric("max_ms", ms[-1])
	r.metric("spikes_50ms", ms.filter(func(x): return x > 50.0).size())
	r.metric("spikes_100ms", ms.filter(func(x): return x > 100.0).size())
	r.metric("quality", Graphics.preset)
	r.check("perf_avg_fps_30", r.metrics.avg_fps >= 30.0, "avg %.1f FPS, 1%% low %.1f FPS, %d frames > 50 ms (max %.0f ms)" % [
		r.metrics.avg_fps, r.metrics.low1_fps, r.metrics.spikes_50ms, r.metrics.max_ms])
	await r.shot("perf")
