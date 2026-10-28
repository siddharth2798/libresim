extends RefCounted
## Airliner systems (systems/airliner_*.gd): electrical buses, hydraulics, the AircraftSystems factory, the
## failure catalogue (C172 list pinned) and the saveable round trips. Fuel, lights, cabin and the E/WD lines:
## tests/test_airliner_fuel.gd.

const F = preload("res://tests/airliner_fixtures.gd")
const C172_FAILURES := [
	["Engine", ["engine", "engine_partial", "mag_left", "mag_right"]],
	["Fuel", ["fuel_leak_left", "fuel_leak_right"]],
	["Electrical", ["alternator", "battery"]],
	["Vacuum & gyros", ["vacuum_pump", "ai", "hi", "tc"]],
	["Pitot-static", ["pitot_blocked", "static_blocked"]],
	["Flight controls", ["flaps", "trim", "brake_left", "brake_right"]],
	["Avionics", ["com1", "com2", "nav1", "nav2", "adf", "dme", "xpdr", "gps"]],
]


func _elec() -> AirlinerElectrical:
	return F.node(AirlinerElectrical, F.def())


func _buses(names: Array) -> String:
	var out := []
	for k in names:
		out.append("%s=%s" % [k, Props.get_b("systems/electrical/%s_on" % k)])
	return " ".join(out)


func test_airliner_elec_cold_and_dark_then_battery() -> String:
	return F.guard(func():
		F.engines(0.0, 0.0)
		var el := _elec()
		Props.set_v("controls/electrical/bat1", false)
		Props.set_v("controls/electrical/bat2", false)
		F.run([el], 1.0, 0.1)
		var dead := not Props.get_b("systems/electrical/ac_ess_on") and not Props.get_b("systems/electrical/dc_bat_on") \
			and not Props.get_b("systems/electrical/powered") and not Props.get_b("systems/electrical/starter_ok")
		Props.set_v("controls/electrical/bat1", true)
		Props.set_v("controls/electrical/bat2", true)
		F.run([el], 1.0, 0.1)
		var b := "systems/electrical/"
		var bat_only: bool = Props.get_b(b + "ac_ess_on") and Props.get_b(b + "dc_ess_on") and Props.get_b(b + "dc_bat_on") \
			and not Props.get_b(b + "ac1_on") and not Props.get_b(b + "dc1_on") and Props.get_v(b + "ac_ess_src") == "INV"
		var consumers: bool = Props.get_b(b + "powered") and Props.get_b(b + "avionics_powered") and Props.get_b(b + "gauges_powered") and Props.get_b(b + "starter_ok")
		var amps := Props.get_f(b + "battery_amps")
		var soc0: float = el.soc[0]
		F.run([el], 600.0, 1.0)
		var drained: bool = el.soc[0] < soc0 - 0.01 and el.soc[0] > 0.3
		el.soc = [0.05, 0.05]
		F.run([el], 1.0, 0.1)
		var low := Props.get_b(b + "low_volts")
		el.free()
		if not dead:
			return "buses powered with both batteries off"
		if not bat_only:
			return "battery only: " + _buses(["ac1", "ac_ess", "dc1", "dc_ess", "dc_bat"])
		if not consumers:
			return "consumer props (powered / avionics / gauges / starter_ok) not true on battery"
		if amps >= 0.0 or not drained:
			return "battery should discharge on its own (%.1f A, soc %.2f -> %.2f)" % [amps, soc0, el.soc[0]]
		if not low:
			return "LOW VOLTS expected with flat batteries"
		return "")


func test_airliner_elec_apu_and_engine_generators() -> String:
	return F.guard(func():
		var el := _elec()
		var b := "systems/electrical/"
		F.engines(0.0, 0.0)
		Props.set_v("apu/running", true)
		F.run([el], 1.0, 0.1)
		var apu_ok: bool = Props.get_b(b + "ac1_on") and Props.get_b(b + "ac2_on") and Props.get_b(b + "dc1_on") \
			and Props.get_v(b + "ac1_src") == "APU" and Props.get_b(b + "apu_gen_on") and Props.get_f(b + "battery_amps") > 0.0
		Props.set_v("controls/electrical/apu_gen", false)
		F.run([el], 1.0, 0.1)
		var apu_off: bool = not Props.get_b(b + "ac1_on") and Props.get_v(b + "ac_ess_src") == "INV"
		Props.set_v("controls/electrical/apu_gen", true)
		Props.set_v("apu/running", false)
		F.engines(60.0, 60.0)
		F.run([el], 1.0, 0.1)
		var eng_ok: bool = Props.get_v(b + "ac1_src") == "GEN1" and Props.get_v(b + "ac2_src") == "GEN2" \
			and Props.get_f(b + "bus_volts") > 27.0 and Props.get_f(b + "ac1_v") > 110.0 and Props.get_f(b + "gen1_load_pct") > 0.0
		Props.set_v("failures/gen1", true)
		F.run([el], 1.0, 0.1)
		var tie: bool = Props.get_v(b + "ac1_src") == "TIE" and Props.get_b(b + "ac1_on") and not Props.get_b(b + "gen1_on")
		Props.set_v("failures/gen2", true)
		F.engines(60.0, 60.0, false)
		F.run([el], 1.0, 0.1)
		var emer: bool = Props.get_b(b + "emer") and Props.get_v(b + "ac_ess_src") == "INV" and not Props.get_b(b + "ac1_on")
		F.engines(30.0, 30.0)  # below the generator threshold
		Props.set_v("failures/gen1", false)
		Props.set_v("failures/gen2", false)
		F.run([el], 1.0, 0.1)
		var slow: bool = not Props.get_b(b + "gen1_on")
		el.free()
		if not apu_ok:
			return "APU generator should power both AC buses and charge the batteries"
		if not apu_off:
			return "APU GEN off should drop AC 1 (AC ESS on the inverter)"
		if not eng_ok:
			return "engine generators: " + str(Props.get_v(b + "ac1_src")) + "/" + str(Props.get_v(b + "ac2_src"))
		if not tie:
			return "GEN 1 failure: AC 1 should come over the bus tie from GEN 2"
		if not emer:
			return "both generators lost in the air: emergency, AC ESS on the inverter"
		if not slow:
			return "generator available below N2 50 %"
		return "")


func test_airliner_elec_ext_power_and_battery_failure() -> String:
	return F.guard(func():
		var el := _elec()
		var b := "systems/electrical/"
		F.engines(0.0, 0.0)
		Props.set_v("ground/gpu_connected", true)
		F.run([el], 1.0, 0.1)
		var ext: bool = Props.get_v(b + "ac1_src") == "EXT" and Props.get_v(b + "ac2_src") == "EXT" and Props.get_b(b + "ext_on") and Props.get_b(b + "dc2_on")
		F.engines(60.0, 0.0)
		F.run([el], 1.0, 0.1)
		var mixed: bool = Props.get_v(b + "ac1_src") == "GEN1" and Props.get_v(b + "ac2_src") == "EXT"
		F.engines(0.0, 0.0)
		Props.set_v("controls/electrical/ext_pwr", false)
		Props.set_v("failures/battery", true)
		F.run([el], 1.0, 0.1)
		var none: bool = not Props.get_b(b + "ac_ess_on") and not Props.get_b(b + "dc_bat_on") and not Props.get_b(b + "powered")
		Props.set_v("controls/electrical/ext_pwr", true)
		F.run([el], 1.0, 0.1)
		var no_charge: bool = Props.get_b(b + "dc1_on") and is_zero_approx(Props.get_f(b + "battery_amps"))
		Props.set_v("failures/battery", false)
		Props.set_v("systems/hydraulics/flaps_ok", false)
		F.run([el], 1.0, 0.1)
		var flaps_off: bool = not Props.get_b(b + "flaps_powered") and Props.get_b(b + "gauges_powered")
		el.free()
		if not ext:
			return "ground power should feed both AC buses"
		if not mixed:
			return "GEN 1 feeds AC 1, ground power AC 2"
		if not none:
			return "no source and failed batteries: everything dead"
		if not no_charge:
			return "failed batteries must not charge (ground power on)"
		if not flaps_off:
			return "flaps_powered should follow hydraulics flaps_ok"
		return "")


func _hyd(n2_1: float, n2_2: float, sec := 12.0) -> AirlinerHydraulics:
	F.engines(n2_1, n2_2)
	var h: AirlinerHydraulics = F.node(AirlinerHydraulics, F.def())
	F.run([h], sec, 0.05)
	return h


func test_airliner_hyd_pressure_follows_n2() -> String:
	return F.guard(func():
		var h := _hyd(0.0, 0.0, 5.0)
		var off: bool = h.psi.green < 1.0 and h.psi.yellow < 1.0 and h.psi.blue < 1.0 and not Props.get_b("systems/hydraulics/antiskid")
		F.engines(25.0, 25.0)  # slow engines: pumps part way
		F.run([h], 12.0, 0.05)
		var part: bool = h.psi.green > 1000.0 and h.psi.green < 2900.0
		F.engines(60.0, 60.0)
		F.run([h], 12.0, 0.05)
		var full: bool = h.psi.green > 2950.0 and h.psi.blue > 2950.0 and h.psi.yellow > 2950.0
		var units: bool = absf(Props.get_f("systems/hydraulics/green_pa") - h.psi.green * 6894.757) < 1.0 and absf(Props.get_f("hyd/green_psi") - h.psi.green) < 0.01
		var cons: bool = Props.get_b("systems/hydraulics/antiskid") and Props.get_b("systems/hydraulics/gear_ok") and Props.get_b("systems/hydraulics/flaps_ok") \
			and Props.get_f("systems/hydraulics/flaps_rate_factor") == 1.0 and Props.get_v("systems/hydraulics/spoiler_ok") == [true, true, true, true, true]
		Props.set_v("systems/electrical/ac1_on", false)  # blue pump has no power
		F.engines(0.0, 0.0)
		F.run([h], 40.0, 0.05)
		var cold: bool = h.psi.green < 1.0 and h.psi.blue < 1.0
		Props.set_v("systems/electrical/ac1_on", true)
		F.engines(0.0, 0.0)
		Props.set_v("controls/hyd/blue_ovrd", true)
		F.run([h], 8.0, 0.05)
		var ovrd: bool = h.psi.blue > 2950.0
		h.free()
		if not off:
			return "pressure without engines"
		if not part:
			return "pumps at N2 25 %% should give part pressure (%.0f psi)" % h.psi.green
		if not full:
			return "full pressure at N2 60 %%: G %.0f B %.0f Y %.0f" % [h.psi.green, h.psi.blue, h.psi.yellow]
		if not units:
			return "Pa / psi publish mismatch"
		if not cons:
			return "consumer props with all three systems up"
		if not cold:
			return "pressure should bleed off with the engines stopped"
		if not ovrd:
			return "blue pump override should pressurise BLUE with the engines off"
		return "")


func test_airliner_hyd_ptu_and_failures() -> String:
	return F.guard(func():
		var h := _hyd(0.0, 60.0, 20.0)  # engine 2 only: the PTU lifts GREEN
		var ptu: bool = h.psi.yellow > 2950.0 and h.psi.green > 2000.0 and h.psi.green < 2800.0 and Props.get_b("hyd/ptu_active")
		Props.set_v("controls/hyd/ptu", false)
		F.run([h], 40.0, 0.05)
		var no_ptu: bool = h.psi.green < 10.0 and Props.get_b("hyd/low_g") and not Props.get_b("systems/hydraulics/gear_ok")
		Props.set_v("controls/hyd/ptu", true)
		F.engines(60.0, 60.0)
		Props.set_v("failures/hyd_G", true)
		F.run([h], 15.0, 0.05)
		var g_fail: bool = h.psi.green < 10.0 and h.psi.yellow > 2950.0 and Props.get_b("systems/hydraulics/antiskid") \
			and Props.get_f("systems/hydraulics/flaps_rate_factor") == 0.5 and Props.get_v("systems/hydraulics/spoiler_ok") == [false, true, true, true, false] \
			and Props.get_v("systems/hydraulics/reverser_ok") == [false, true]
		Props.set_v("failures/hyd_Y", true)
		F.run([h], 15.0, 0.05)
		var gy_fail: bool = not Props.get_b("systems/hydraulics/antiskid") and not Props.get_b("systems/hydraulics/nws_ok") and Props.get_b("systems/hydraulics/flaps_ok")
		Props.set_v("failures/hyd_B", true)
		F.run([h], 15.0, 0.05)
		var all_fail: bool = not Props.get_b("systems/hydraulics/flaps_ok") and Props.get_f("systems/hydraulics/flaps_rate_factor") == 0.0 and Props.get_b("hyd/low_b")
		h.free()
		if not ptu:
			return "PTU should lift GREEN with only engine 2 running (G %.0f Y %.0f)" % [h.psi.green, h.psi.yellow]
		if not no_ptu:
			return "GREEN should bleed off with the PTU off and engine 1 stopped"
		if not g_fail:
			return "hyd_G failure: GREEN lost, YELLOW and the flags that follow (%.0f psi)" % h.psi.green
		if not gy_fail:
			return "GREEN + YELLOW lost: no anti-skid / nose wheel steering, flaps on BLUE"
		if not all_fail:
			return "all three systems lost: no flaps"
		return "")


func test_airliner_factory_profile_selection() -> String:
	var ga := AircraftSystems.new()
	ga.def = F.def({"profile": "ga"})
	ga.build()
	var unk := AircraftSystems.new()
	unk.def = F.def({"profile": "nonsense"})
	unk.build()
	var c172 := AircraftSystems.new()
	c172.def = AircraftDef.load_def("c172")
	c172.build()
	var ok := ga.get_child_count() == 0 and unk.get_child_count() == 0 and c172.get_child_count() == 0 \
		and AircraftSystems.profile_of(c172.def) == "ga" and AircraftSystems.profile_of(F.def()) == "airliner"
	# airliner: the six parts + PitotStatic; the C172 siblings go, an existing PitotStatic stays
	var parent := Node.new()
	for n in ["Electrical", "Fuel", "Vacuum", "PitotStatic", "Failures"]:
		var c := Node.new()
		c.name = n
		parent.add_child(c)
	var al := AircraftSystems.new()
	al.def = F.def()
	parent.add_child(al)
	var parts := al.build()
	var names := parts.map(func(p): return str(p.name))
	var kept := ["PitotStatic", "Failures"].all(func(n): return parent.get_node_or_null(n) != null) \
		and ["Electrical", "Fuel", "Vacuum"].all(func(n): return parent.get_node_or_null(n) == null)
	var alone := AircraftSystems.new()  # no sibling PitotStatic: makes its own
	alone.def = F.def()
	var alone_names := alone.build().map(func(p): return str(p.name))
	var again := al.build().size()  # build() is idempotent
	var bad := ""
	if not ok:
		bad = "ga / unknown profile / c172 must create nothing"
	elif names != ["AirlinerElectrical", "AirlinerHydraulics", "AirlinerFuel", "AirlinerLights", "AirlinerCabin", "AirlinerWarnings"]:
		bad = "airliner parts " + str(names)
	elif not kept:
		bad = "C172-only nodes should be removed, PitotStatic and Failures kept"
	elif not alone_names.has("PitotStatic") or alone_names.size() != 7 or again != 6:
		bad = "PitotStatic when none exists / idempotent build: " + str(alone_names)
	for n in [ga, unk, c172, parent, alone]:
		n.free()
	return bad


func test_airliner_failure_catalog() -> String:
	var old_aircraft = Session.setup.get("aircraft", "c172")
	var bad := ""
	Session.setup.aircraft = "c172"
	FailureCatalog._cache.clear()
	var ids := FailureCatalog.categories().map(func(c): return [c[0], c[1].map(func(f): return f[0])])
	if ids != C172_FAILURES:
		bad = "C172 failure list changed: " + str(ids)
	elif FailureCatalog.CATEGORIES.map(func(c): return [c[0], c[1].map(func(f): return f[0])]) != C172_FAILURES:
		bad = "FailureCatalog.CATEGORIES changed"
	var d := F.def({}, {"failures": {"disabled": FailureCatalog.AIRLINER_HIDDEN}})
	d.id = "a320_catalog_test"
	AircraftDef._cache[d.id] = d
	Session.setup.aircraft = d.id
	if bad.is_empty():
		var all := FailureCatalog.all_ids()
		for need in ["gen1", "gen2", "apu_gen", "hyd_G", "hyd_B", "hyd_Y", "fuel_pump_left", "fuel_pump_centre", "fuel_pump_right",
				"engine_fire", "engine_fire_2", "apu", "adr_1", "adr_2", "adr_3", "gear", "spoilers", "engine", "engine_2", "battery", "pitot_blocked"]:
			if not need in all:
				bad = "airliner failure missing: " + need
		for gone in FailureCatalog.AIRLINER_HIDDEN:
			if gone in all:
				bad = "piston failure still listed: " + gone
		if FailureCatalog.label("hyd_G") == "hyd_G":
			bad = "no label for hyd_G"
	AircraftDef._cache.erase(d.id)
	Session.setup.aircraft = old_aircraft
	FailureCatalog._cache.clear()
	return bad


func test_airliner_systems_saveable() -> String:
	return F.guard(func():
		var d := F.def()
		var root := Node.new()
		var made := {}
		for cls in [AirlinerElectrical, AirlinerHydraulics, AirlinerFuel, AirlinerLights, AirlinerCabin, AirlinerWarnings]:
			var n: Node = F.node(cls, d)
			root.add_child(n)
			made[n.save_key()] = n
		var found := SituationSystems.saveables(root).size()
		var el: AirlinerElectrical = made["airliner_electrical"]
		var hy: AirlinerHydraulics = made["airliner_hydraulics"]
		var fu: AirlinerFuel = made["airliner_fuel"]
		var li: AirlinerLights = made["airliner_lights"]
		var ca: AirlinerCabin = made["airliner_cabin"]
		var wa: AirlinerWarnings = made["airliner_warnings"]
		el.soc = [0.41, 0.62]
		hy.psi = {"green": 1234.0, "blue": 2500.0, "yellow": 10.0}
		fu.used = [12.5, 13.5]
		fu._line = [2.0, 6.0]
		li.landing_pos = [0.3, 0.9]
		ca.cabin_alt_m = 1500.0
		ca.field_m = 120.0
		wa._was_running = [true, false]
		var saved: Dictionary = JSON.parse_string(JSON.stringify(SituationSystems.capture(root)))
		var d2 := F.def()
		var root2 := Node.new()
		for cls in [AirlinerElectrical, AirlinerHydraulics, AirlinerFuel, AirlinerLights, AirlinerCabin, AirlinerWarnings]:
			root2.add_child(F.node(cls, d2))
		SituationSystems.apply(root2, saved)
		var g := func(k: String) -> Node:
			for n in root2.get_children():
				if n.save_key() == k:
					return n
			return null
		var bad := ""
		if found != 6 or made.size() != 6:
			bad = "all six systems should be saveable and have distinct keys"
		elif g.call("airliner_electrical").soc != [0.41, 0.62] or g.call("airliner_hydraulics").psi.green != 1234.0 or g.call("airliner_hydraulics").psi.blue != 2500.0:
			bad = "electrical / hydraulics state lost"
		elif g.call("airliner_fuel").used != [12.5, 13.5] or g.call("airliner_fuel")._line != [2.0, 6.0]:
			bad = "fuel state lost"
		elif g.call("airliner_lights").landing_pos != [0.3, 0.9] or g.call("airliner_cabin").cabin_alt_m != 1500.0 or g.call("airliner_cabin").field_m != 120.0:
			bad = "lights / cabin state lost"
		elif g.call("airliner_warnings")._was_running != [true, false]:
			bad = "warning latches lost"
		root.free()
		root2.free()
		return bad)
