extends RefCounted
## E2E gameplay scenarios: takeoff, 60 s hands-off, scripted landing, cold & dark start.


## Full throttle, steer the centreline, rotate at 55 KIAS, hold 8 deg pitch: does it climb?
func takeoff(r) -> void:
	await r.wait(3.0)
	r.take_controls()
	var pl = r.pilot
	var rwy: float = float(r.f._start.heading_deg)
	var st := {"rot_t": -1.0, "lift_t": -1.0, "t": 0.0}
	Props.set_v("controls/parking_brake", false)
	Props.set_v("controls/brake_left", 0.0)
	Props.set_v("controls/brake_right", 0.0)
	Props.set_v("controls/mixture", 1.0)
	pl.hdg_tgt = rwy
	pl.pitch_tgt = 0.0
	pl.guide = func(dt):
		st.t += dt
		Props.set_v("controls/throttle", minf(st.t / 2.0, 1.0))
		if st.rot_t < 0.0 and r.kias() >= 55.0:
			st.rot_t = st.t
		if st.rot_t >= 0.0:
			pl.pitch_tgt = minf((st.t - st.rot_t) * 4.0, 8.0)
		if st.lift_t < 0.0 and not Props.get_b("fdm/wow"):
			st.lift_t = st.t
		pl.roll_tgt = 0.0 if Props.get_b("fdm/wow") else pl.bank_for_track(rwy, 10.0)
	pl.active = true
	var alt0: float = r.alt_ft()
	await r.wait(70.0)
	var climbed: float = r.alt_ft() - alt0
	r.metric("rotate_at_s", st.rot_t)
	r.metric("liftoff_at_s", st.lift_t)
	r.metric("alt_gain_ft_70s", climbed)
	r.metric("vs_fpm", Props.get_f("fdm/vs_mps") * 196.85)
	r.metric("kias_end", r.kias())
	r.metric("rpm_end", r.p("engine/rpm"))
	r.check("reaches_55kt", st.rot_t > 0.0 and st.rot_t < 40.0, "rotate at %.1f s" % st.rot_t)
	r.check("lifts_off", st.lift_t > 0.0, "liftoff at %.1f s" % st.lift_t)
	r.check("climbs", climbed > 300.0 and not r.p("damage/crashed", false), "gained %.0f ft in 70 s, now %.0f KIAS, VS %.0f fpm" % [climbed, r.kias(), r.metrics.vs_fpm])
	await r.shot("climb")


## Air start, no input for 60 s: record roll, heading and altitude drift.
func handsoff(r) -> void:
	await r.wait(1.0)
	r.take_controls()
	for c in ["pitch", "roll", "yaw"]:
		Props.set_v("controls/" + c, 0.0)
	var h0: float = r.hdg_deg()
	var a0: float = r.alt_ft()
	var k0: float = r.kias()
	var max_roll := 0.0
	var max_dh := 0.0
	var t := 0.0
	var trace := []
	while t < 60.0:
		await r.wait(0.5)
		t += 0.5
		if fmod(t, 10.0) == 0.0:
			trace.append("t%.0f roll %.1f hdg %.0f alt %.0f kias %.0f" % [t, rad_to_deg(Props.get_f("fdm/roll_rad")), r.hdg_deg(), r.alt_ft(), r.kias()])
		max_roll = maxf(max_roll, absf(rad_to_deg(Props.get_f("fdm/roll_rad"))))
		max_dh = maxf(max_dh, r.angle_diff(r.hdg_deg(), h0))
	var dalt: float = r.alt_ft() - a0
	r.metric("trace", trace)
	r.metric("max_roll_deg", max_roll)
	r.metric("final_roll_deg", rad_to_deg(Props.get_f("fdm/roll_rad")))
	r.metric("heading_drift_deg", wrapf(r.hdg_deg() - h0, -180.0, 180.0))
	r.metric("max_heading_dev_deg", max_dh)
	r.metric("alt_change_ft", dalt)
	r.metric("kias_start_end", [k0, r.kias()])
	r.check("handsoff_roll", max_roll < 20.0, "max |roll| %.1f deg, final %.1f deg" % [max_roll, r.metrics.final_roll_deg])
	r.check("handsoff_heading", max_dh < 25.0, "heading drift %.1f deg (max dev %.1f)" % [r.metrics.heading_drift_deg, max_dh])
	r.check("handsoff_altitude", absf(dalt) < 500.0, "altitude change %.0f ft, %.0f -> %.0f KIAS" % [dalt, k0, r.kias()])
	await r.shot("after60s")


## 3 nm final (start with --air=950 --e2e_nm=3): fly the 3-degree path, flare, stop.
func landing(r) -> void:
	r.take_controls()
	var pl = r.pilot
	var thr_pos: Vector2 = r.f._start.pos  # runway start point, 25 m past the threshold
	var rwy: float = float(r.f._start.heading_deg)
	var fwd := Vector2(sin(deg_to_rad(rwy)), cos(deg_to_rad(rwy)))
	var right := Vector2(fwd.y, -fwd.x)
	var aim := thr_pos + fwd * 250.0
	var elev: float = r.f.get_node("Terrain").height_at(aim.x, aim.y)
	var st := {"td_t": -1.0, "td_vs": 0.0, "t": 0.0, "it": 0.0, "max_dev": 0.0}
	Props.set_v("controls/flaps", 1)  # 10 deg (VFE 110 kt); 20 deg below 80 kt
	pl.guide = func(dt):
		st.t += dt
		var p3: Vector3 = Props.get_v("fdm/position_enu", Vector3.ZERO)
		var rel := Vector2(p3.x, p3.y) - aim
		var along := -rel.dot(fwd)  # metres before the aim point
		var xtk := rel.dot(right)  # + = right of centreline
		var h := p3.z - elev
		var agl := Props.get_f("fdm/agl_m")
		if Props.get_b("fdm/wow") or st.td_t >= 0.0:
			if st.td_t < 0.0:
				st.td_t = st.t
				st.td_vs = Props.get_f("fdm/vs_mps") * 196.85
			Props.set_v("controls/throttle", 0.0)
			pl.pitch_tgt = 0.0
			pl.roll_tgt = 0.0
			pl.hdg_tgt = rwy
			var b := 1.0 if st.t - st.td_t > 2.0 else 0.0
			Props.set_v("controls/brake_left", b)
			Props.set_v("controls/brake_right", b)
			st.max_dev = maxf(st.max_dev, absf(xtk))
			st.gp = maxf(st.get("gp", -90.0), pl.pitch_deg())
			return
		pl.roll_tgt = pl.bank_for_track(rwy - clampf(xtk * 0.15, -25.0, 25.0), 15.0)
		if agl < 7.0:  # flare
			Props.set_v("controls/throttle", 0.0)
			pl.pitch_tgt = 6.0
			return
		var want_h := maxf(along, 0.0) * tan(deg_to_rad(3.0))
		var gs_mps := Props.get_f("fdm/groundspeed_mps")
		var vs_want := -gs_mps * tan(deg_to_rad(3.0)) + 0.15 * (want_h - h)
		var vs := Props.get_f("fdm/vs_mps")
		pl.pitch_tgt = clampf(-1.0 + 2.0 * (vs_want - vs) + 0.3 * pl.pitch_tgt * 0.0, -8.0, 8.0)
		if r.kias() < 80.0:
			Props.set_v("controls/flaps", 2)
		var spd_err: float = 68.0 - r.kias()
		st.it = clampf(st.it + 0.004 * spd_err * dt, -0.3, 0.3)
		Props.set_v("controls/throttle", clampf(0.35 + 0.04 * spd_err + st.it, 0.0, 1.0))
	pl.active = true
	var t := 0.0
	var shot_done := false
	while t < 260.0:
		await r.wait(1.0)
		t += 1.0
		if not shot_done and Props.get_f("fdm/agl_m") < 60.0:
			shot_done = true
			await r.shot("short_final")
		if r.p("damage/crashed", false) or (st.td_t >= 0.0 and Props.get_f("fdm/groundspeed_mps") < 1.0):
			break
	var p3: Vector3 = Props.get_v("fdm/position_enu", Vector3.ZERO)
	var rel := Vector2(p3.x, p3.y) - thr_pos
	r.metric("touchdown_vs_fpm", st.td_vs)
	r.metric("touchdown_t", st.td_t)
	r.metric("stop_distance_past_threshold_m", rel.dot(fwd))
	r.metric("max_centreline_dev_m", st.max_dev)
	r.metric("max_pitch_on_ground_deg", st.get("gp", 0.0))
	var ev: Array = r.p("damage/events", [])
	r.metric("damage_events_n", ev.size())
	r.check("no_event_spam", ev.size() < 10, "%d damage events, unique: %s" % [ev.size(), str(ev.reduce(func(a, x): return a if x in a else a + [x], []))])
	r.metric("last_touchdown", str(r.p("damage/last_touchdown", "")))
	r.check("lands", st.td_t >= 0.0, "touchdown at %.0f s, %.0f fpm" % [st.td_t, st.td_vs])
	r.check("landing_not_crashed", not r.p("damage/crashed", false), "reason=%s events=%s" % [r.p("damage/reason", ""), str(r.p("damage/events", []))])
	r.check("stops_on_runway", st.td_t >= 0.0 and Props.get_f("fdm/groundspeed_mps") < 1.0 and st.max_dev < 25.0,
		"gs %.1f m/s, %.0f m past threshold, max %.1f m off centreline" % [Props.get_f("fdm/groundspeed_mps"), rel.dot(fwd), st.max_dev])
	await r.shot("stopped")


## Cold & dark (--cold): master, mixture rich, throttle cracked, mags BOTH, starter.
func coldstart(r) -> void:
	await r.wait(3.0)
	r.take_controls()
	r.check("starts_cold", not r.p("engine/running", false) and float(r.p("engine/rpm")) < 50.0, "running=%s rpm=%.0f" % [r.p("engine/running", false), r.p("engine/rpm")])
	Props.set_v("controls/electrical/master_bat", true)
	Props.set_v("controls/electrical/master_alt", true)
	Props.set_v("controls/lights/beacon", r.arg("e2e_beacon", "1") == "1")
	await r.wait(1.0)
	r.metric("bus_volts_bat", r.p("systems/electrical/bus_volts"))
	Props.set_v("controls/mixture", 1.0)
	Props.set_v("controls/throttle", 0.1)
	Props.set_v("controls/magnetos", 3)
	await r.wait(0.5)
	var t := 0.0
	Props.set_v("controls/starter", true)
	var diag := []
	while t < 10.0 and not r.p("engine/running", false):
		await r.wait(0.25)
		t += 0.25
		var e = r.f.get_node("Fdm").fdm.engine
		diag.append("%.2f:%.0frpm/%.1fV/ok=%s/eng.starter=%s" % [t, r.p("engine/rpm"), r.p("systems/electrical/bus_volts"),
			r.p("systems/electrical/starter_ok", "?"), e.starter])
	r.metric("crank_trace", diag.slice(0, 12))
	Props.set_v("controls/starter", false)
	r.metric("crank_s", t)
	await r.wait(6.0)
	var rpm: float = r.p("engine/rpm")
	r.metric("rpm_after", rpm)
	r.metric("bus_volts_running", r.p("systems/electrical/bus_volts"))
	r.check("engine_starts", r.p("engine/running", false) and rpm > 500.0, "cranked %.2f s, rpm %.0f, running=%s" % [t, rpm, r.p("engine/running", false)])
	r.check("alternator_charging", float(r.p("systems/electrical/bus_volts")) > float(r.metrics.bus_volts_bat), "bus %.1f V -> %.1f V" % [r.metrics.bus_volts_bat, r.p("systems/electrical/bus_volts")])
	Props.set_v("controls/mixture", 0.0)  # shut down with the mixture
	await r.wait(8.0)
	r.check("mixture_cutoff_stops", not r.p("engine/running", false), "rpm %.0f" % r.p("engine/rpm"))
	await r.shot("after_start")
