extends RefCounted
## Tick rates, systems that feed the flight model (battery, fuel, hydraulics, APU) at 60 Hz and the vacuum pump at 30 Hz: each
## runs at the old 120 Hz and at its new rate through the same scripted Props (tests/tick_twin.gd) and the outputs are compared.
## The scripts' events (switch flips, failures) fall on whole seconds and the samples between them, so a difference is the
## lag of the slower rate and nothing else. See also tests/test_tick_rate.gd and tests/test_tick_instruments.gd.

const DT := 1.0 / 120.0


func _c172_electrical_inputs(t: float) -> void:
	var rpm := 150.0 if t < 4.0 else minf(150.0 + (t - 4.0) * 550.0, 2300.0)  # cranking, then up to 2300 by 8 s
	Props.set_v("engine/rpm", rpm)
	Props.set_v("controls/starter", t < 4.0)
	Props.set_v("failures/alternator", t >= 60.0 and t < 180.0)
	for l in ["landing", "nav", "beacon", "strobe", "taxi"]:
		Props.set_v("controls/lights/" + l, t >= 100.0)
	Props.set_v("controls/electrical/pitot_heat", t >= 30.0)


func test_tick_electrical_battery_and_bus_match() -> String:
	var snap: Dictionary = Props._p.duplicate(true)
	for k in ["master_bat", "master_alt", "avionics"]:
		Props.set_v("controls/electrical/" + k, true)
	Props.set_v("failures/battery", false)
	var pair := TickTwin.twin(Electrical, 300.0, _c172_electrical_inputs, func(n): n._ready(),
		["@soc", "systems/electrical/bus_volts", "systems/electrical/battery_amps", "systems/electrical/starter_ok",
		"systems/electrical/low_volts", "systems/electrical/powered", "systems/electrical/avionics_powered"])
	Props._p = snap
	var soc_moved := absf(pair[0][-1]["@soc"] - pair[0][0]["@soc"])
	if soc_moved < 0.02:
		return "the scenario must move the battery (moved %.4f)" % soc_moved
	return TickTwin.check("C172 electrical, 5 min with starter, alternator failure, lights", pair,
		{"@soc": 2e-5, "systems/electrical/bus_volts": 0.02, "systems/electrical/battery_amps": 0.1})


func test_tick_fuel_selector_line_and_leak_match() -> String:
	var snap: Dictionary = Props._p.duplicate(true)
	var n_tanks: int = AircraftDef.current().config().tanks.size()
	var tanks := []
	for i in n_tanks:
		tanks.append(40.0)
	var inputs := func(t: float):
		Props.set_v("fuel/tank_kg", tanks)
		Props.set_v("controls/fuel/selector", 0 if (t >= 5.0 and t < 14.0) else 3)  # OFF 5..14 s: the line empties 6 s later
		Props.set_v("failures/fuel_leak_left", t >= 20.0 and t < 25.0)
	var pair := TickTwin.twin(FuelSystem, 30.0, inputs, func(n): n._ready(),
		["fuel/available", "fuel/feed", "fuel/leak_kgs", "@_line"], 0.1, 0.05)
	Props._p = snap
	var off_at := -1.0
	for row in pair[1]:
		if off_at < 0.0 and not row["fuel/available"]:
			off_at = row["t"]
	if absf(off_at - 11.0) > 0.2:
		return "line fuel should run out about 6 s after the selector went OFF (11 s), got %.2f s" % off_at
	return TickTwin.check("C172 fuel selector OFF, line fuel, tank leak", pair, {"@_line": 1.0 / 60.0 + 1e-6})


func test_tick_fuel_burn_in_the_flight_model_matches() -> String:
	var snap: Dictionary = Props._p.duplicate(true)
	var res := []
	for ref in [true, false]:
		Props._p = snap.duplicate(true)
		Props.set_v("controls/fuel/selector", 3)
		Props.set_v("failures/fuel_leak_left", false)
		Props.set_v("failures/fuel_leak_right", false)
		Props.set_v("controls/fuel/shutoff", false)
		var h := FdmHarness.new(2300.0)
		var fn := FdmNode.new()
		fn.fdm = h.f
		var fuel := FuelSystem.new()
		fuel._ready()
		if ref:
			fuel._tick = TickRate.new(120.0)
		h.f.set_airborne(0, 0, 1000.0, 0.0, 50.0)
		h.f.prop.rpm = 2400.0
		h.f.engine.throttle = 0.7
		h.mode = "alt"
		h.target_alt = 1000.0
		for i in int(24.0 / DT):
			var t := i * DT
			Props.set_v("controls/fuel/selector", 1 if t >= 8.0 and t < 16.0 else 3)  # LEFT tank only for 8 s
			fn._publish()
			fuel._physics_process(DT)
			var feed: Array = Props.get_v("fuel/feed")
			for k in feed.size():
				h.f.tank_feed[k] = feed[k]
			h.f.fuel_available = Props.get_b("fuel/available")
			h._autopilot()
			h.f.step(DT)
		res.append(h.f.mb.tanks.map(func(tk): return tk.contents_kg))
		fn.free()
		fuel.free()
	Props._p = snap
	var worst := 0.0
	for i in res[0].size():
		worst = maxf(worst, absf(res[0][i] - res[1][i]))
	print("    fuel burn, 24 s with the LEFT tank selected for 8 s (120 Hz / 60 Hz): tanks %s / %s kg, worst %.5f kg" % [res[0], res[1], worst])
	if worst > 0.002:
		return "tank contents differ by %.5f kg between the fuel system at 120 Hz and 60 Hz" % worst
	return ""


func test_tick_vacuum_suction_matches() -> String:
	var inputs := func(t: float):
		Props.set_v("engine/rpm", minf(t * 400.0, 2300.0))
		Props.set_v("failures/vacuum_pump", t >= 60.0)
	var snap: Dictionary = Props._p.duplicate(true)
	var pair := TickTwin.twin(Vacuum, 90.0, inputs, func(_n): pass, ["systems/vacuum/suction_inhg", "@suction"])
	Props._p = snap
	return TickTwin.check("vacuum pump, spin-up and failure", pair, {"systems/vacuum/suction_inhg": 0.06, "@suction": 0.06})  # the ramp is 1.7 inHg/s: a 30 Hz hold is 0.056


func test_tick_apu_start_matches() -> String:
	var cfg: Dictionary = AircraftDef.load_def("a320").config().get("apu", {})
	if cfg.is_empty():
		return ""
	var snap: Dictionary = Props._p.duplicate(true)
	var inputs := func(t: float):
		Props.set_v("controls/apu_master", t >= 2.0)
		Props.set_v("controls/apu_start", t >= 2.0 and t < 4.0)
	var setup := func(n: Apu):
		n.fdm = FDM.new()
		n.model = ApuModel.new(cfg)
	var pair := TickTwin.twin(Apu, 60.0, inputs, setup, ["apu/n_pct", "apu/running", "apu/starting", "apu/ff_kgs"], 1.0, 0.3)
	Props._p = snap
	return TickTwin.check("APU start to available in about 30 s", pair, {"apu/n_pct": 0.2, "apu/ff_kgs": 1e-4})


func _airliner(f: Callable) -> String:
	return AirlinerFixtures.guard(f)


func test_tick_airliner_battery_and_ground_power_match() -> String:
	return _airliner(func():
		var inputs := func(t: float):
			Props.set_v("ground/gpu_connected", t >= 100.0 and t < 200.0)  # external power charges the batteries from 100 s to 200 s
		var pair := TickTwin.twin(AirlinerElectrical, 240.0, inputs, func(n): n.def = AirlinerFixtures.def(); n._ready(),
			["@soc", "systems/electrical/bus_volts", "systems/electrical/battery_amps", "systems/electrical/dc_ess_on",
			"systems/electrical/ac_ess_on", "systems/electrical/starter_ok"])
		return TickTwin.check("A320 batteries, then ground power", pair, {"@soc": 2e-5, "systems/electrical/bus_volts": 0.05,
			"systems/electrical/battery_amps": 0.2}))


func test_tick_airliner_hydraulics_pressure_matches() -> String:
	return _airliner(func():
		var inputs := func(t: float):
			var n2 := clampf((t - 5.0) * 12.0, 0.0, 60.0)  # engine 1 starts at 5 s, 60 % N2 at 10 s
			Props.set_v("engines/1/n2", n2)
			Props.set_v("engines/1/running", n2 >= 50.0)
			Props.set_v("failures/hyd_Y", t >= 30.0)
		var pair := TickTwin.twin(AirlinerHydraulics, 40.0, inputs, func(n): n.def = AirlinerFixtures.def(); n._ready(),
			["hyd/green_psi", "hyd/blue_psi", "hyd/yellow_psi", "systems/hydraulics/gear_ok", "systems/hydraulics/antiskid"])
		return TickTwin.check("A320 hydraulics, engine start and a yellow failure", pair,
			{"hyd/green_psi": 800.0 / 60.0 + 1.0, "hyd/blue_psi": 800.0 / 60.0 + 1.0, "hyd/yellow_psi": 800.0 / 60.0 + 1.0}))


func test_tick_airliner_fuel_used_matches() -> String:
	return _airliner(func():
		var inputs := func(t: float):
			Props.set_v("engines/1/ff", 0.3 if t < 30.0 else 0.5)
			Props.set_v("engines/2/ff", 0.3 if t < 30.0 else 0.45)
			Props.set_v("apu/ff_kgs", 0.02)
		var setup := func(n):
			n.def = AirlinerFixtures.def()
			n._ready()
			var tanks := []
			for i in n._tank.size():
				tanks.append(1000.0)
			Props.set_v("fuel/tank_kg", tanks)
		var pair := TickTwin.twin(AirlinerFuel, 60.0, inputs, setup, ["@used", "fuel/used_total_kg", "fuel/feed", "fuel/available"])
		return TickTwin.check("A320 fuel used per engine, 1 minute", pair, {"@used": 0.01, "fuel/used_total_kg": 0.02}))
