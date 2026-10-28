extends RefCounted
## Airliner fuel feed (centre first, pumps, transfer, crossfeed, availability), lights, cabin pressure and the E/WD
## memo / warning lines (systems/airliner_*.gd). The rest: tests/test_airliner_systems.gd.

const F = preload("res://tests/airliner_fixtures.gd")
## A320 tank order: outer L, inner L, centre, inner R, outer R, engine 1 / engine 2 / APU pipes.
const TANKS := [690.0, 2000.0, 3000.0, 2000.0, 690.0, 0.0, 0.0, 0.0]


func _fuel(kg: Array, alt_m := 0.0) -> AirlinerFuel:
	Props.set_v("fuel/tank_kg", kg)
	Props.set_v("fdm/alt_m", alt_m)
	var f: AirlinerFuel = F.node(AirlinerFuel, F.def())
	F.run([f], 0.1)
	return f


func _feed() -> Array:
	return Props.get_v("fuel/feed")


func _near(a: Array, b: Array) -> bool:
	for i in a.size():
		if absf(float(a[i]) - float(b[i])) > 0.001:
			return false
	return a.size() == b.size()


func test_airliner_fuel_centre_first_and_pumps() -> String:
	return F.guard(func():
		var f := _fuel(TANKS)
		var centre := _near(_feed(), [0, 0, 1, 0, 0, 0, 0, 0])
		var avail: bool = Props.get_b("fuel/available") and Props.get_b("fuel/available_1") and Props.get_b("fuel/available_2")
		Props.set_v("failures/fuel_pump_centre", true)  # centre pumps failed: the wings feed
		F.run([f], 0.1)
		var wings := _near(_feed(), [0, 0.5, 0, 0.5, 0, 0, 0, 0])
		Props.set_v("failures/fuel_pump_centre", false)
		Props.set_v("fuel/tank_kg", [690.0, 2000.0, 10.0, 2000.0, 690.0, 0.0, 0.0, 0.0])  # centre empty (unusable only)
		F.run([f], 0.1)
		var empty := _near(_feed(), [0, 0.5, 0, 0.5, 0, 0, 0, 0])
		Props.set_v("fuel/tank_kg", TANKS)
		Props.set_v("controls/fuel/pump_centre", false)
		Props.set_v("engines/1/ff", 1.0)  # only engine 1 burns: its wing only
		Props.set_v("engines/2/ff", 0.0)
		F.run([f], 0.1)
		var one := _near(_feed(), [0, 1, 0, 0, 0, 0, 0, 0])
		Props.set_v("engines/1/ff", 0.5)  # both burn, the APU too (from the left wing)
		Props.set_v("engines/2/ff", 0.5)
		Props.set_v("apu/ff_kgs", 0.1)
		F.run([f], 0.1)
		var apu := absf(_feed()[1] - 0.6 / 1.1) < 0.01
		f.free()
		if not centre:
			return "centre tank should feed first: " + str(_feed())
		if not avail:
			return "fuel/available (and _1, _2) with fuel on board"
		if not wings:
			return "centre pumps failed: inner wing tanks should feed"
		if not empty:
			return "empty centre tank should hand over to the wings"
		if not one:
			return "one engine burning draws only from its own wing"
		if not apu:
			return "APU burn should come from the left wing: " + str(_feed())
		return "")


func test_airliner_fuel_transfer_pipes_and_sum() -> String:
	return F.guard(func():
		var f := _fuel([600.0, 700.0, 3000.0, 2000.0, 690.0, 0.0, 0.0, 0.0])
		Props.set_v("controls/fuel/pump_centre", false)
		F.run([f], 0.1)
		var fd := _feed()
		# left inner is below 750 kg: its outer tank is drawn; the right wing is still on its inner tank
		var transfer := _near(fd, [0.5, 0, 0, 0.5, 0, 0, 0, 0])
		var total := 0.0
		for x in fd:
			total += x
		var pipes: bool = fd[5] == 0.0 and fd[6] == 0.0 and fd[7] == 0.0
		f.free()
		if not transfer:
			return "outer-to-inner transfer (outer drawn once the inner is below 750 kg): " + str(fd)
		if absf(total - 1.0) > 0.001 or not pipes:
			return "feed fractions must sum to 1 and never touch the pipe tanks"
		return "")


func test_airliner_fuel_available_crossfeed_and_line_fuel() -> String:
	return F.guard(func():
		var f := _fuel(TANKS, 9000.0)  # too high to gravity-feed
		Props.set_v("controls/fuel/pump_centre", false)
		Props.set_v("failures/fuel_pump_left", true)
		F.run([f], 3.0, 0.05)
		var line := Props.get_b("fuel/available_1") and Props.get_b("fuel/available_2")  # line fuel still there
		F.run([f], 5.0, 0.05)
		var starved := not Props.get_b("fuel/available_1") and Props.get_b("fuel/available_2") and Props.get_b("fuel/available")
		Props.set_v("controls/fuel/crossfeed", true)
		F.run([f], 0.1)
		var cross := Props.get_b("fuel/available_1") and _near(_feed(), [0, 0, 0, 1, 0, 0, 0, 0])
		Props.set_v("controls/fuel/crossfeed", false)
		Props.set_v("failures/fuel_pump_right", true)
		F.run([f], 8.0, 0.05)
		var none := not Props.get_b("fuel/available") and not Props.get_b("fuel/available_2")
		Props.set_v("fdm/alt_m", 1000.0)  # gravity feed below the ceiling
		F.run([f], 0.1)
		var gravity := Props.get_b("fuel/available") and _near(_feed(), [0, 0.5, 0, 0.5, 0, 0, 0, 0])
		Props.set_v("failures/fuel_pump_left", false)
		Props.set_v("failures/fuel_pump_right", false)
		Props.set_v("fdm/alt_m", 9000.0)
		F.run([f], 0.1)
		var back := Props.get_b("fuel/available") and Props.get_b("fuel/available_1")
		Props.set_v("fuel/tank_kg", [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
		F.run([f], 8.0, 0.05)
		var dry := not Props.get_b("fuel/available")
		f.free()
		if not line:
			return "engine should run on its line fuel for a few seconds after the supply is lost"
		if not starved:
			return "engine 1 should starve after the line fuel (left pumps failed, no crossfeed, high)"
		if not cross:
			return "crossfeed should feed engine 1 from the right wing"
		if not none:
			return "no pumps either side at altitude: no fuel available"
		if not gravity:
			return "gravity feed from the inner tanks below the ceiling"
		if not back or not dry:
			return "available should return with the pumps and drop with empty tanks"
		return "")


func test_airliner_fuel_low_used_and_leak() -> String:
	return F.guard(func():
		var f := _fuel([100.0, 300.0, 0.0, 2000.0, 690.0, 0.0, 0.0, 0.0])
		var low: bool = Props.get_b("fuel/low_left") and not Props.get_b("fuel/low_right") and Props.get_b("fuel/low")
		Props.set_v("engines/1/ff", 2.0)
		Props.set_v("engines/2/ff", 1.0)
		F.run([f], 10.0, 0.05)
		var used := absf(f.used[0] - 20.0) < 0.1 and absf(f.used[1] - 10.0) < 0.1 and absf(Props.get_f("fuel/used_total_kg") - 30.0) < 0.2
		Props.set_v("failures/fuel_leak_left", true)
		F.run([f], 0.1)
		var leak: Array = Props.get_v("fuel/leak_kgs")
		var leaking: bool = leak[0] > 0.0 and leak[1] > 0.0 and leak[2] == 0.0 and leak[3] == 0.0 and leak[5] == 0.0
		f.free()
		if not low:
			return "FUEL LO LVL flag: left wing 400 kg, right wing 2690 kg"
		if not used:
			return "fuel used per engine: %s" % [f.used]
		if not leaking:
			return "left leak should drain the left wing tanks only: " + str(leak)
		return "")


func test_airliner_lights_follow_bus_and_extend() -> String:
	return F.guard(func():
		var l: AirlinerLights = F.node(AirlinerLights, F.def())
		F.set_all({"systems/electrical/ac_ess_on": true, "controls/lights/landing": true, "controls/lights/nav": true})
		F.run([l], 1.0, 0.1)
		var mid: bool = Props.get_f("systems/lights/landing_l_pos") > 0.2 and Props.get_f("systems/lights/landing_l_pos") < 0.9 and not Props.get_b("systems/lights/landing_l_on")
		F.run([l], 3.0, 0.1)
		var up: bool = Props.get_f("systems/lights/landing_r_pos") == 1.0 and Props.get_b("systems/lights/landing_l_on") and Props.get_b("systems/lights/nav_on") \
			and not Props.get_b("systems/lights/strobe_on")
		Props.set_v("systems/electrical/ac_ess_on", false)
		F.run([l], 0.2, 0.1)
		var dead := not Props.get_b("systems/lights/nav_on") and not Props.get_b("systems/lights/landing_l_on") and Props.get_f("systems/lights/landing_l_pos") == 1.0
		Props.set_v("controls/lights/landing", false)
		F.run([l], 4.0, 0.1)
		var stowed := Props.get_f("systems/lights/landing_l_pos") == 0.0
		l.free()
		if not mid:
			return "landing lights extend before they light"
		if not up:
			return "landing lights on and extended, nav on, strobe (switch off) dark"
		if not dead:
			return "lights go dark without AC ESS; extended landing lights stay out"
		return "" if stowed else "landing lights should retract with the switch off"
	)


func test_airliner_cabin_pressure_schedule() -> String:
	return F.guard(func():
		var c: AirlinerCabin = F.node(AirlinerCabin, F.def())
		F.set_all({"fdm/alt_m": 0.0, "fdm/wow": true, "atmosphere/pressure_pa": 101325.0})
		F.engines(60.0, 60.0)
		F.run([c], 5.0, 0.1)
		var ground: bool = Props.get_f("systems/cabin/alt_m") < 1.0 and Props.get_f("systems/cabin/delta_p_pa") < 1.0 \
			and Props.get_b("systems/bleed/eng1_on") and Props.get_b("systems/packs/1_on") and Props.get_f("systems/bleed/pressure_pa") > 1.0e5
		F.set_all({"fdm/alt_m": 11900.0, "fdm/wow": false, "atmosphere/pressure_pa": AirlinerCabin.isa_pa(11900.0)})
		F.run([c], 60.0, 1.0)
		var vs := Props.get_f("systems/cabin/vs_mps")
		F.run([c], 1500.0, 1.0)
		var cabin := Props.get_f("systems/cabin/alt_m")
		var dp := Props.get_f("systems/cabin/delta_p_pa")
		var cruise: bool = cabin > 2200.0 and cabin < 2500.0 and dp > 50000.0 and dp < 59400.0 and absf(Props.get_f("systems/cabin/vs_mps")) < 0.01
		c.cabin_alt_m = 0.0  # no bleed air: the cabin follows the ambient altitude
		F.engines(0.0, 0.0, false)
		Props.set_v("apu/running", false)
		F.run([c], 100.0, 1.0)
		var leak: bool = Props.get_f("systems/cabin/alt_m") > 700.0 and not Props.get_b("systems/bleed/avail")
		c.free()
		if not ground:
			return "on the ground the cabin is at field altitude, bleed from the running engines"
		if vs < 2.0 or vs > 2.6:
			return "cabin climb should be limited to ~500 ft/min (%.2f m/s)" % vs
		if not cruise:
			return "cruise cabin altitude %.0f m, delta P %.0f Pa" % [cabin, dp]
		return "" if leak else "without bleed air the cabin should follow the ambient altitude"
	)


func _warn() -> AirlinerWarnings:
	var w: AirlinerWarnings = F.node(AirlinerWarnings, F.def())
	w.update()
	return w


func _lines(key: String) -> Array:
	return Props.get_v(key, []).map(func(l): return l[0])


func test_airliner_ewd_memo_lines() -> String:
	return F.guard(func():
		var w := _warn()
		var empty: bool = _lines("ewd/memo").is_empty() and Props.get_v("ewd/memo_text") == ""
		F.set_all({"controls/signs/seatbelts": true, "controls/signs/no_smoking": true, "controls/lights/landing": true,
			"controls/autobrake": 1, "fdm/speedbrake": 0.5, "controls/spoilers_armed": true, "apu/running": true,
			"controls/parking_brake": true, "fdm/wow": false, "fdm/gear_pos": 1.0})
		w.update()
		var m := _lines("ewd/memo")
		var want := ["LDG GEAR DN", "SEAT BELTS", "NO SMOKING", "LDG LT", "AUTO BRK LO", "SPEED BRK", "GND SPLRS ARMED", "PARK BRK", "APU AVAIL"]
		var text: String = Props.get_v("ewd/memo_text")
		Props.set_v("controls/autobrake", 3)
		w.update()
		var max_ab := "AUTO BRK MAX" in _lines("ewd/memo")
		var colours: bool = Props.get_v("ewd/memo").all(func(l): return l[1] == "green")
		w.free()
		if not empty:
			return "memo should be empty with everything off"
		if m != want:
			return "memo lines: " + str(m)
		if text != "\n".join(want):
			return "ewd/memo_text should be the lines joined by newlines"
		return "" if max_ab and colours else "AUTO BRK MAX / memo colour"
	)


func test_airliner_ewd_warnings_priority_and_rules() -> String:
	return F.guard(func():
		var w := _warn()
		F.engines(60.0, 60.0)
		F.set_all({"controls/engine_master_1": true, "controls/engine_master_2": true, "fdm/wow": false, "fdm/agl_m": 1500.0,
			"fdm/gear_pos": 1.0, "systems/electrical/gen1_on": true, "systems/electrical/gen2_on": true})
		w.update()
		var quiet: bool = _lines("ewd/warnings").is_empty() and not Props.get_b("ewd/master_warning")
		F.set_all({"hyd/low_g": true, "fuel/low_right": true, "failures/engine_fire": true, "fdm/stall_warning": true})
		w.update()
		var l := _lines("ewd/warnings")
		var order := l == ["ENG 1 FIRE", "STALL", "HYD G SYS LO PR", "FUEL R WING TK LO LVL"]
		var cols: Array = Props.get_v("ewd/warnings").map(func(x): return x[1])
		var master: bool = Props.get_b("ewd/master_warning") and Props.get_b("ewd/master_caution")
		var text: String = Props.get_v("ewd/warnings_text")
		F.set_all({"hyd/low_g": false, "fuel/low_right": false, "failures/engine_fire": false, "fdm/stall_warning": false})
		Props.set_v("engines/2/running", false)  # flame-out of an engine that ran: ENG 2 FAIL until its master goes off
		Props.set_v("engines/2/n2", 10.0)
		Props.set_v("systems/electrical/ac2_on", false)
		Props.set_v("systems/electrical/gen2_on", false)
		w.update()
		var fail := "ENG 2 FAIL" in _lines("ewd/warnings") and "ELEC AC BUS 2 FAULT" in _lines("ewd/warnings")
		Props.set_v("controls/engine_master_2", false)
		w.update()
		var cleared := not ("ENG 2 FAIL" in _lines("ewd/warnings"))
		w.free()
		if not quiet:
			return "no warnings expected: " + str(l)
		if not order:
			return "red before amber, by priority: " + str(l)
		if cols != ["red", "red", "amber", "amber"] or not master:
			return "colours / master warning and caution: " + str(cols)
		if text != "\n".join(l):
			return "ewd/warnings_text"
		if not fail:
			return "ENG 2 FAIL and the AC BUS 2 fault expected: " + str(_lines("ewd/warnings"))
		return "" if cleared else "ENG 2 FAIL should clear when the master goes off"
	)


func test_airliner_ewd_config_gear_overspeed_gating() -> String:
	return F.guard(func():
		var w := _warn()
		F.engines(0.0, 0.0)
		F.set_all({"hyd/low_g": true, "systems/electrical/ac1_on": false})  # cold and dark: no hydraulic / bus warnings
		w.update()
		var cold := _lines("ewd/warnings").is_empty()
		F.set_all({"controls/throttle_1": 0.95, "controls/parking_brake": true, "fdm/flap_lever": 0.0, "fdm/speedbrake": 0.5})
		w.update()
		var cfg := _lines("ewd/warnings")
		var config: bool = cfg.size() == 3 and cfg.all(func(s): return s.begins_with("CONFIG"))
		F.set_all({"controls/throttle_1": 0.0, "controls/parking_brake": false, "fdm/speedbrake": 0.0, "fdm/wow": false,
			"fdm/agl_m": 200.0, "fdm/gear_pos": 0.0, "fdm/flap_lever": 3.0})
		w.update()
		var gear := "L/G GEAR NOT DOWN" in _lines("ewd/warnings")
		Props.set_v("fdm/gear_pos", 1.0)
		Props.set_v("fdm/agl_m", 900.0)
		w.update()
		var gear_ok := not ("L/G GEAR NOT DOWN" in _lines("ewd/warnings"))
		Props.set_v("fdm/cas_mps", 365.0 * Units.KT)
		w.update()
		var over := "OVERSPEED" in _lines("ewd/warnings")
		Props.set_v("fdm/cas_mps", 250.0 * Units.KT)
		Props.set_v("fdm/mach", 0.85)
		w.update()
		var mmo := "OVERSPEED" in _lines("ewd/warnings")
		w.free()
		if not cold:
			return "hydraulic / bus warnings must stay quiet before any engine runs"
		if not config:
			return "take-off CONFIG warnings (park brake, flaps, speed brake): " + str(cfg)
		if not gear:
			return "L/G GEAR NOT DOWN below 1000 ft with gear up and flaps 3"
		if not gear_ok:
			return "no gear warning with the gear down"
		return "" if over and mmo else "OVERSPEED above VMO and MMO"
	)
