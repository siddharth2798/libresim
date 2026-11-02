extends RefCounted
## The generic aircraft code (AircraftDef, N engines / tanks, turbines, tail wheels) on aircraft built
## in code from the c172 data (tests/generic_fixtures.gd): a twin piston, a taildragger, a twin turbine.

const FX := preload("res://tests/generic_fixtures.gd")
const DT := 1.0 / 120.0


# --- the c172 itself ----------------------------------------------------------

func test_generic_c172_is_one_engine_two_tanks() -> String:
	var f := FDM.new(AircraftDef.load_def("c172"))
	if f.units.size() != 1 or f.mb.tanks.size() != 2 or f.tank_feed.size() != 2:
		return "c172: %d units, %d tanks" % [f.units.size(), f.mb.tanks.size()]
	if f.engine != f.units[0].engine or f.prop != f.units[0].thruster or not f.engine is EnginePiston:
		return "FDM.engine / prop must be unit 1 (a piston engine)"
	if f.mb.tank_side(0) != "left" or f.mb.tank_side(1) != "right":
		return "c172 tanks are left / right"
	var roles := f.gear.contacts.map(func(c): return c.role)
	if roles != ["nose", "main", "main", "skid", "tail_skid", "wingtip", "wingtip"]:
		return "derived gear roles %s" % [roles]
	return ""


# --- AircraftDef --------------------------------------------------------------

func test_generic_aircraft_def() -> String:
	var c := AircraftDef.load_def("c172")
	if c.path("config") != "res://aircraft/c172/config.json" or c.path("aero") != "res://aircraft/c172/aero.json":
		return "default file names: %s, %s" % [c.path("config"), c.path("aero")]
	var x := AircraftDef.make("x", {"files": {"config": "alt/cfg.json"}, "ground": {"ahead_m": 5.0}}, "res://aircraft/x")
	if x.path("config") != "res://aircraft/x/alt/cfg.json" or x.path("hull") != "res://aircraft/x/hull.json":
		return "files override: %s, %s" % [x.path("config"), x.path("hull")]
	var defaults := {"ahead_m": 3.3, "height_m": 2.5}
	var g := x.section_or("ground", defaults)
	if g.ahead_m != 5.0 or g.height_m != 2.5 or defaults.ahead_m != 3.3:
		return "section_or must merge over (a copy of) the defaults: %s / %s" % [g, defaults]
	if not x.section("nothing").is_empty():
		return "a missing section is {}"
	if not "c172" in AircraftDef.list_ids():
		return "list_ids %s lacks c172" % [AircraftDef.list_ids()]
	var u := AircraftDef.load_def("no_such_aircraft_id")
	if u == null or u.id != "c172":
		return "an unknown id must fall back to the c172"
	if c.engine_count() != 1 or AircraftDef.make("t", {}, "", FX.twin_config()).engine_count() != 2:
		return "engine_count (c172 1, twin 2)"
	return ""


# --- twin piston --------------------------------------------------------------

func test_generic_twin_units_and_tanks() -> String:
	var f := FX.fdm(FX.twin_config(), "twin")
	if f.units.size() != 2 or f.units[1].engine == f.units[0].engine or f.units[1].thruster == f.units[0].thruster:
		return "twin must have two separate units"
	if absf(f.units[0].pos.y + 1.6) > 1e-6 or absf(f.units[1].pos.y - 1.6) > 1e-6:
		return "engine positions %s %s" % [f.units[0].pos, f.units[1].pos]
	if f.tank_feed.size() != 3 or f.tank_leak_kgs.size() != 3:
		return "three tanks need three feed / leak entries"
	var sides := [0, 1, 2].map(func(i): return f.mb.tank_side(i))
	if sides != ["left", "right", "centre"]:
		return "tank sides %s" % [sides]
	f.mb.tanks[0].contents_kg = 10.0
	f.mb.tanks[1].contents_kg = 20.0
	f.mb.tanks[2].contents_kg = 30.0
	if f.mb.side_kg("left") != 10.0 or f.mb.side_kg("right") != 20.0 or f.mb.side_kg("centre") != 30.0 or f.mb.fuel_kg() != 60.0:
		return "side_kg / fuel_kg"
	f.mb.set_side_kg("centre", 12.0)
	return "" if absf(f.mb.tanks[2].contents_kg - 12.0) < 1e-9 else "set_side_kg"


func test_generic_twin_burns_from_the_fed_tanks() -> String:
	var f := FX.fdm(FX.twin_config(), "twin")
	FX.fly_trimmed(f)
	f.set_throttle(0.8)
	f.tank_feed = PackedFloat64Array([0.5, 0.0, 0.5])
	var before := f.mb.tanks.map(func(t): return t.contents_kg)
	var flow := 0.0
	for i in int(10.0 / DT):
		f.step(DT)
		flow += (f.units[0].engine.fuel_flow_kgs + f.units[1].engine.fuel_flow_kgs) * DT
	var used := [0, 1, 2].map(func(i): return before[i] - f.mb.tanks[i].contents_kg)
	print("    10 s at 80 %%: used %s kg, engines drew %.3f kg" % [used.map(func(x): return snappedf(x, 0.001)), flow])
	if flow < 0.1:
		return "the engines should burn fuel (%.4f kg)" % flow
	if absf(used[1]) > 1e-9 or absf(used[0] - used[2]) > 1e-6 or absf(used[0] + used[2] - flow) > 0.01 * flow:
		return "fuel must come from tanks 1 and 3 only, equally, and match the engines' flow: %s vs %.3f" % [used, flow]
	return ""


func test_generic_twin_engines_are_independent() -> String:
	var yaw := []
	for left_strong in [false, true]:
		var f := FX.fdm(FX.twin_config(), "twin")
		f.set_airborne(0.0, 0.0, 900.0, 0.0, 50.0)
		for u in f.units:
			u.warm_start(true)
		f.units[0].engine.throttle = 1.0 if left_strong else 0.2
		f.units[1].engine.throttle = 0.2 if left_strong else 1.0
		FX.run(f, 0.6)
		yaw.append(f.w_b.z)
		if f.units[0].thruster.thrust < 50.0 or f.units[1].thruster.thrust < 50.0:
			return "both engines must push: %.0f / %.0f N" % [f.units[0].thruster.thrust, f.units[1].thruster.thrust]
		if absf(f.units[0].thruster.thrust - f.units[1].thruster.thrust) < 100.0:
			return "different throttles must give different thrust"
	print("    yaw rate after 0.6 s: right engine strong %+.3f, left engine strong %+.3f rad/s" % [yaw[0], yaw[1]])
	if yaw[0] > -0.01 or yaw[1] < 0.01:
		return "the strong engine must yaw the nose away from it (right strong: %+.3f, left strong: %+.3f)" % [yaw[0], yaw[1]]
	return ""


func test_generic_twin_trims_and_flies_hands_off() -> String:
	var f := FX.fdm(FX.twin_config(), "twin")
	FX.fly_trimmed(f)
	var alt0 := f.altitude()
	var cas0 := f.cas
	FX.run(f, 20.0)
	var bank := rad_to_deg(f.euler().x)
	print("    twin 20 s hands off: alt %+.0f m, %.0f -> %.0f m/s, bank %.1f deg, throttle %.2f" % [
		f.altitude() - alt0, cas0, f.cas, bank, f.units[0].engine.throttle])
	if f.damage.crashed:
		return "crashed: " + f.damage.crash_reason
	if absf(f.altitude() - alt0) > 150.0 or absf(f.cas - cas0) > 0.2 * cas0 or absf(bank) > 25.0:
		return "not stable: alt %+.0f m, cas %.0f -> %.0f, bank %.0f deg" % [f.altitude() - alt0, cas0, f.cas, bank]
	return ""


func test_generic_twin_situation_round_trip() -> String:
	var a := FX.fdm(FX.twin_config(), "twin")
	FX.fly_trimmed(a)
	a.units[0].engine.throttle = 0.7
	a.units[1].engine.throttle = 0.35
	a.tank_feed = PackedFloat64Array([0.2, 0.3, 0.5])
	a.mb.tanks[0].contents_kg = 11.0
	a.mb.tanks[1].contents_kg = 22.0
	a.mb.tanks[2].contents_kg = 33.0
	FX.run(a, 1.5)
	var d: Dictionary = JSON.parse_string(JSON.stringify(Situation.capture_fdm(a), "", false, true))
	var b := FX.fdm(FX.twin_config(), "twin")
	b.set_on_ground(100.0, 100.0, 1.0)
	Situation.apply_fdm(b, d)
	for i in 3:
		if absf(b.mb.tanks[i].contents_kg - a.mb.tanks[i].contents_kg) > 1e-9 or absf(b.tank_feed[i] - a.tank_feed[i]) > 1e-12:
			return "tank %d: %.4f kg / feed %.2f restored as %.4f / %.2f" % [i, a.mb.tanks[i].contents_kg, a.tank_feed[i], b.mb.tanks[i].contents_kg, b.tank_feed[i]]
	var e2a := a.units[1]
	var e2b := b.units[1]
	if absf(e2b.engine.throttle - 0.35) > 1e-9 or absf(e2b.thruster.rpm - e2a.thruster.rpm) > 1e-6 or absf(e2b.engine.map_pa - e2a.engine.map_pa) > 1e-6 or e2b.engine.running != e2a.engine.running:
		return "engine 2 state not restored (throttle %.2f, rpm %.1f vs %.1f)" % [e2b.engine.throttle, e2b.thruster.rpm, e2a.thruster.rpm]
	if absf(b.units[0].thruster.rpm - a.units[0].thruster.rpm) > 1e-6 or absf(b.pos_d - a.pos_d) > 1e-9:
		return "engine 1 / position not restored"
	FX.run(a, 2.0)
	FX.run(b, 2.0)
	var dp := Vector3(a.pos_n - b.pos_n, a.pos_e - b.pos_e, a.pos_d - b.pos_d).length()
	return "" if dp < 1e-6 and absf(a.units[1].thruster.rpm - b.units[1].thruster.rpm) < 1e-6 else "restored twin diverged by %.2e m" % dp


# --- taildragger --------------------------------------------------------------

func test_generic_taildragger_sits_on_its_tail() -> String:
	var f := FX.fdm(FX.taildragger_config(), "tail")
	var tail: Array = f.gear.contacts.filter(func(c): return c.name == "TAIL_WHEEL")
	if tail.size() != 1 or tail[0].role != "tail" or not tail[0].wheel:
		return "the tail wheel's role must be derived as tail: %s" % [tail]
	if f.gear.steered_wheels().map(func(c): return c.name) != ["TAIL_WHEEL"] or f.gear.main_wheels().size() != 2:
		return "steered wheel is the tail wheel, two mains"
	f.set_on_ground(0.0, 0.0, 0.0)
	var pitch0 := rad_to_deg(f.euler().y)
	if pitch0 < 5.0 or pitch0 > 20.0:
		return "a taildragger sits nose-up by 5..20 deg, not %.1f" % pitch0
	FX.run(f, 5.0)
	print("    taildragger: pitch %.1f -> %.1f deg, moved %.2f m, wow %s" % [pitch0, rad_to_deg(f.euler().y), f.pos_n, f.gear.wow])
	if f.damage.crashed or not f.gear.wow or absf(f.pos_n) > 0.5 or absf(rad_to_deg(f.euler().y) - pitch0) > 2.0 or not f.damage.events.is_empty():
		return "did not sit still: crashed=%s pitch %.1f, moved %.2f m, events %s" % [f.damage.crashed, rad_to_deg(f.euler().y), f.pos_n, f.damage.events]
	return ""


func _drop(sink: float) -> FDM:
	var f := FX.fdm(FX.taildragger_config(), "tail")
	f.set_on_ground(0.0, 0.0, 0.0)
	f.pos_d -= 0.08
	f.v_b = Basis(f.q).transposed() * Vector3(0.0, 0.0, sink)
	FX.run(f, 0.5)
	return f


func test_generic_taildragger_tail_wheel_is_the_weaker_leg() -> String:
	var hard := _drop(3.0)  # ~3.2 m/s at the wheels: above the tail / nose limit (2.6), below the mains' (4.6)
	if not hard.damage.gear_failed.has("TAIL_WHEEL") or hard.damage.gear_failed.has("LEFT_MAIN") or hard.damage.gear_failed.has("RIGHT_MAIN"):
		return "only the tail wheel should collapse: %s %s" % [hard.damage.gear_failed.keys(), hard.damage.events]
	var soft := _drop(1.0)
	if not soft.damage.gear_failed.is_empty() or soft.damage.crashed:
		return "a gentle touchdown must not break anything: %s" % [soft.damage.events]
	return ""


# --- twin turbine -------------------------------------------------------------

func _jet() -> Array:
	var cfg: Dictionary = FX.turbine_config().engines[0]
	var e := EngineTurbine.new(cfg)
	return [e, TurbineThruster.new(e)]


## Advance one engine in ISA air at `alt` m and `v` m/s.
func _spin(e: EngineTurbine, t: TurbineThruster, seconds: float, alt := 0.0, v := 0.0) -> void:
	var a := AtmosphereISA.new()
	a.update(alt)
	for i in int(seconds / DT):
		e.update(DT, t.rpm, a.pressure, a.temperature, v)
		t.update(DT, e.torque, v, a.density, a.sound_speed)


func test_generic_turbine_starts_and_idles() -> String:
	var j := _jet()
	var e: EngineTurbine = j[0]
	e.fuel_ok = true
	_spin(e, j[1], 3.0)
	if e.running:
		return "no start without the starter"
	e.starter = true
	_spin(e, j[1], 8.0)
	e.starter = false
	_spin(e, j[1], 10.0)
	print("    turbine: N1 %.3f (idle %.2f), thrust %.0f N, running %s" % [e.n1, e.idle_n1, e.thrust_n, e.running])
	if not e.running or absf(e.n1 - e.idle_n1) > 0.02 or e.thrust_n <= 0.0 or e.thrust_n > 0.1 * e.thrust_sl:
		return "should spool to idle by itself after the start"
	var cold := _jet()
	cold[0].starter = true
	cold[0].fuel_ok = false
	_spin(cold[0], cold[1], 10.0)
	return "" if not cold[0].running else "no fuel, no light-off"


func test_generic_turbine_thrust_altitude_and_fuel_flow() -> String:
	var j := _jet()
	var e: EngineTurbine = j[0]
	e.warm_start(e.idle_n1)
	e.throttle = 1.0
	_spin(e, j[1], 8.0)
	var sl := e.thrust_n
	print("    sea-level static thrust %.0f N (rated 12000), fuel %.3f kg/s" % [sl, e.fuel_flow_kgs])
	if absf(sl - 12000.0) > 300.0 or absf(j[1].thrust - sl) > 1e-9:
		return "full throttle at sea level static should give ~12000 N, got %.0f (thruster %.0f)" % [sl, j[1].thrust]
	if absf(e.fuel_flow_kgs - e.tsfc * sl) > 1e-9:
		return "fuel flow %.5f != tsfc * thrust %.5f" % [e.fuel_flow_kgs, e.tsfc * sl]
	_spin(e, j[1], 8.0, 5000.0, 0.0)
	var hi := e.thrust_n
	print("    at 5000 m: %.0f N" % hi)
	if hi > 0.8 * sl or hi < 0.4 * sl or absf(e.fuel_flow_kgs - e.tsfc * hi) > 1e-9:
		return "thrust at 5000 m should fall to 40..80 %% of sea level (got %.0f of %.0f)" % [hi, sl]
	e.failed = true
	_spin(e, j[1], 20.0, 0.0, 100.0)
	print("    failed engine at 100 m/s: %.0f N, running %s" % [e.thrust_n, e.running])
	if e.running or e.thrust_n >= 0.0 or e.thrust_n < -0.02 * e.thrust_sl or e.fuel_flow_kgs != 0.0:
		return "a failed engine windmills: small negative thrust, no fuel flow (%.0f N)" % e.thrust_n
	return ""


func test_generic_turbine_aircraft_accelerates_on_the_ground() -> String:
	var f := FX.fdm(FX.turbine_config(), "jet")
	if f.units.size() != 2 or not f.engine is EngineTurbine or not f.prop is TurbineThruster or f.prop.diameter != 0.0:
		return "two turbine units expected"
	f.set_on_ground(0.0, 0.0, 0.0)
	for u in f.units:
		u.warm_start(false)
		u.engine.throttle = 1.0
	var fuel0 := f.mb.fuel_kg()
	FX.run(f, 4.0)
	print("    jet: %.1f m/s after 4 s, thrust %.0f + %.0f N, fuel %.2f kg" % [f.v_b.x, f.units[0].thruster.thrust, f.units[1].thruster.thrust, fuel0 - f.mb.fuel_kg()])
	if f.damage.crashed:
		return "crashed: " + f.damage.crash_reason
	if f.v_b.x < 15.0 or f.units[0].thruster.thrust < 8000.0 or fuel0 - f.mb.fuel_kg() < 0.5:
		return "should accelerate hard on full thrust (v %.1f m/s, thrust %.0f N)" % [f.v_b.x, f.units[0].thruster.thrust]
	var roles := f.units.map(func(u): return u.engine.extra_state_keys())
	return "" if roles[0] == ["n1", "thrust_n"] else "turbine state keys for saves"
