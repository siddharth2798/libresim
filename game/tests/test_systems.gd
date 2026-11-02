extends RefCounted
## M6 systems & weather tests.

const DT := 1.0 / 120.0


func _reset_props() -> void:
	for k in ["failures/alternator", "failures/battery", "failures/engine", "controls/fuel/shutoff"]:
		Props.set_v(k, false)
	for k in ["master_bat", "master_alt", "avionics"]:
		Props.set_v("controls/electrical/" + k, true)
	Props.set_v("controls/fuel/selector", 3)


func test_sys_alternator_failure_drains_battery() -> String:
	_reset_props()
	var el := Electrical.new()
	el._ready()
	Props.set_v("engine/rpm", 2300.0)
	Props.set_v("controls/lights/landing", true)
	for i in int(5.0 / DT):
		el._physics_process(DT)
	var v_ok := Props.get_f("systems/electrical/bus_volts")
	Props.set_v("failures/alternator", true)
	var soc0 := el.soc
	for i in int(600.0 / DT):  # 10 minutes
		el._physics_process(DT)
	var v_bad := Props.get_f("systems/electrical/bus_volts")
	print("    bus %.1f V normal, %.1f V after 10 min on battery (SOC %.0f%% -> %.0f%%), LOW VOLTS %s" % [
		v_ok, v_bad, soc0 * 100.0, el.soc * 100.0, Props.get_b("systems/electrical/low_volts")])
	Props.set_v("failures/alternator", false)
	Props.set_v("controls/lights/landing", false)
	var soc1 := el.soc
	var low := Props.get_b("systems/electrical/low_volts")
	el.free()
	if v_ok < 28.0:
		return "alternator not regulating"
	if not (v_bad < 25.0 and soc1 < soc0 - 0.05):
		return "battery did not discharge"
	if not low:
		return "LOW VOLTS annunciator should be on with the alternator failed"
	return ""


func test_sys_fuel_starvation_stops_engine() -> String:
	_reset_props()
	var h := FdmHarness.new(2300.0)
	var fn := FdmNode.new()
	fn.fdm = h.f
	var fuel := FuelSystem.new()
	fuel._ready()
	h.f.set_airborne(0, 0, 1000.0, 0.0, 50.0)
	h.f.prop.rpm = 2400.0
	h.f.engine.throttle = 0.7
	h.mode = "alt"
	h.target_alt = 1000.0
	var run := func(sec: float):
		for i in int(sec / DT):
			fn._publish()
			fuel._physics_process(DT)
			var feed: Array = Props.get_v("fuel/feed")
			for t in feed.size():
				h.f.tank_feed[t] = feed[t]
			h.f.fuel_available = Props.get_b("fuel/available")
			h._autopilot()
			h.f.step(DT)
	run.call(5.0)
	Props.set_v("controls/fuel/selector", 0)  # OFF
	run.call(3.0)
	var still := h.f.engine.running
	run.call(6.0)
	var stopped := not h.f.engine.running
	Props.set_v("controls/fuel/selector", 3)
	run.call(3.0)
	print("    selector OFF: running after 3 s = %s, stopped after 9 s = %s, restarts on BOTH = %s" % [still, stopped, h.f.engine.running])
	fn.free()
	fuel.free()
	if not still:
		return "engine stopped instantly (no line fuel)"
	if not stopped:
		return "engine kept running without fuel"
	if not h.f.engine.running:
		return "windmilling engine did not restart with fuel restored"
	return ""


func test_sys_wind_and_ridge_lift() -> String:
	_reset_props()
	var w := Weather.new()
	w._ready()
	Props.set_v("weather/turbulence", 0.0)
	Props.set_v("weather/gust_kt", 0.0)
	Props.set_v("weather/wind_dir_deg", 270.0)
	Props.set_v("weather/wind_kt", 20.0)
	var low: Vector3 = w.wind_at(10.0)
	var high: Vector3 = w.wind_at(300.0)
	print("    west wind 20 kt: at 10 m %.1f kt toward east, at 300 m %.1f kt" % [low.y / 0.5144, high.length() / 0.5144])
	if low.y < 9.0 or absf(low.x) > 1.0:
		return "wind from 270 should blow toward the east (+E)"
	if high.length() <= low.length():
		return "no wind gradient with height"
	# ridge lift: a westerly onto the Western Ghats escarpment (rises to the east)
	var cache := TerrainTileCache.new()
	var tq := TerrainQuadtree.new()
	tq.cache = cache
	w.terrain = tq
	var best := 0.0
	for x in range(-12000, 6000, 500):  # walk east across the escarpment near Lonavala
		Props.set_v("fdm/position_enu", Vector3(x, -2000.0, 600.0))
		Props.set_v("fdm/agl_m", 100.0)
		w._physics_process(DT)
		best = maxf(best, Props.get_f("environment/ridge_lift_mps"))
	print("    strongest ridge lift on the Ghats escarpment: %.1f m/s (%.0f fpm)" % [best, best * 196.85])
	tq.free()
	w.free()
	if best < 1.0 or best > 6.5:
		return "ridge lift %.1f m/s not in a plausible 1-6 m/s range" % best
	return ""


func test_sys_starter_engages_on_battery() -> String:
	_reset_props()
	Props.set_v("controls/electrical/master_alt", false)
	var el := Electrical.new()
	el._ready()
	el.soc = 0.8
	Props.set_v("engine/rpm", 0.0)
	Props.set_v("controls/starter", true)
	for i in 30:
		el._physics_process(DT)
	var ok := Props.get_b("systems/electrical/starter_ok")
	var v := Props.get_f("systems/electrical/bus_volts")
	Props.set_v("controls/starter", false)
	Props.set_v("controls/electrical/master_alt", true)
	el.free()
	print("    cranking on battery (SOC 80 %%): bus %.1f V, starter %s" % [v, ok])
	return "" if ok else "starter does not engage on a healthy battery (bus %.1f V)" % v
