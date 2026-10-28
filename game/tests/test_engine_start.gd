extends RefCounted
## Engine start from cold: the starter must be able to take the engine above its firing speed,
## the engine then idles by itself, and nothing starts without mixture / magnetos / fuel / battery.
## (The e2e sweep found that a cold start was impossible: the starter alone turns the engine at
## 75-130 RPM and the engine used to fire only above 150 RPM.)

const DT := 1.0 / 120.0


func _engine() -> Array:
	var u := PowerUnit.from_config(AircraftDef.load_def("c172").config())[0]
	return [u.engine, u.thruster]


## Crank for `seconds` (starter held until it fires, then released). Returns {rpm, running, fire_t}.
func _crank(thr: float, mix: float, mags: int, seconds: float, fuel_ok := true) -> Dictionary:
	var ep := _engine()
	var e: EnginePiston = ep[0]
	var p: Propeller = ep[1]
	e.throttle = thr
	e.mixture = mix
	e.magnetos = mags
	e.fuel_ok = fuel_ok
	e.starter = true
	var fire_t := -1.0
	for i in int(seconds / DT):
		e.update(DT, p.rpm, 101325.0, 300.0, 0.0)
		p.update(DT, e.torque, 0.0, 1.17, 340.0)
		if e.running and fire_t < 0.0:
			fire_t = i * DT
		if fire_t >= 0.0 and i * DT > fire_t + 1.0:
			e.starter = false  # the pilot lets go
	return {"rpm": p.rpm, "running": e.running, "fire_t": fire_t}


func test_engine_starter_alone_reaches_firing_speed() -> String:
	for thr in [0.0, 0.1, 0.5, 1.0]:
		var r := _crank(thr, 0.0, 3, 6.0)  # mixture cut off: no combustion, the starter only
		print("    cranking at throttle %.1f: %.0f rpm (fires above %.0f)" % [thr, r.rpm, EnginePiston.FIRE_RPM])
		if r.rpm < EnginePiston.FIRE_RPM + 10.0:
			return "the starter only turns the engine at %.0f rpm at throttle %.1f, below the firing speed %.0f" % [r.rpm, thr, EnginePiston.FIRE_RPM]
	return ""


func test_engine_starts_and_idles_by_itself() -> String:
	for thr in [0.0, 0.1, 0.3]:  # closed, cracked (1/4 inch), a bit more
		var r := _crank(thr, 1.0, 3, 10.0)
		print("    start at throttle %.1f: fired after %.2f s, then %.0f rpm" % [thr, r.fire_t, r.rpm])
		if not r.running or r.fire_t < 0.8 or r.fire_t > 3.0:  # it cranks for a moment first, then catches
			return "engine did not start at throttle %.1f, or not in 0.8-3 s (fire_t %.2f s, running %s, %.0f rpm)" % [thr, r.fire_t, r.running, r.rpm]
		if r.rpm < 500.0 or r.rpm > 1700.0:
			return "idle %.0f rpm at throttle %.1f after the starter was released" % [r.rpm, thr]
	return ""


func test_engine_does_not_start_without_mixture_magnetos_or_fuel() -> String:
	var cases := {"mixture cut off": _crank(0.1, 0.0, 3, 8.0), "magnetos off": _crank(0.1, 1.0, 0, 8.0),
		"no fuel": _crank(0.1, 1.0, 3, 8.0, false)}
	for k in cases:
		if cases[k].running:
			return "engine started with %s" % k
	return ""


func test_engine_start_with_battery_and_starter_key() -> String:
	# switches as a cold & dark flight has them, then what the pilot does: master on, hold the starter
	for k in ["failures/alternator", "failures/battery", "failures/engine"]:
		Props.set_v(k, false)
	for k in ["master_bat", "master_alt"]:
		Props.set_v("controls/electrical/" + k, true)
	Props.set_v("controls/electrical/avionics", false)
	Props.set_v("controls/starter", false)
	Props.set_v("engine/rpm", 0.0)
	var el := Electrical.new()
	el._ready()
	var ep := _engine()
	var e: EnginePiston = ep[0]
	var p: Propeller = ep[1]
	e.throttle = 0.1
	e.mixture = 1.0
	e.magnetos = 3
	var bat := 0.0
	var ok_during := false
	var t := 0.0
	for i in int(12.0 / DT):
		t = i * DT
		var hold := t > 0.5 and not (e.running and t > 3.0)  # S held from 0.5 s until the engine runs
		Props.set_v("controls/starter", hold)
		el._physics_process(DT)
		if i == int(0.4 / DT):
			bat = Props.get_f("systems/electrical/bus_volts")
		ok_during = ok_during or (hold and Props.get_b("systems/electrical/starter_ok"))
		e.starter = hold and Props.get_b("systems/electrical/starter_ok")
		e.update(DT, p.rpm, 101325.0, 300.0, 0.0)
		p.update(DT, e.torque, 0.0, 1.17, 340.0)
		Props.set_v("engine/rpm", p.rpm)
	var bus := Props.get_f("systems/electrical/bus_volts")
	Props.set_v("controls/starter", false)
	el.free()
	print("    battery start: bus %.1f V before, %.1f V after, %.0f rpm, running %s" % [bat, bus, p.rpm, e.running])
	if not ok_during:
		return "the starter never engaged on the battery"
	if not e.running or p.rpm < 500.0:
		return "engine did not start from the battery (%.0f rpm)" % p.rpm
	if bus < bat + 1.0:
		return "alternator not charging after the start (bus %.1f V, battery %.1f V)" % [bus, bat]
	return ""
