extends RefCounted
## One engine out on the A320 with the thrust line at the model's engines (config.json engines pos_m, y +-5.63 m;
## JSBSim's upstream FDE had y +-2.8775 m) and the rudder terms of aero.json x RUDDER_K (docs/A320-STATUS.md): the
## rudder (pilot pedal holding zero sideslip, the FBW law and its yaw damper in normal law) must hold the aircraft
## at V2 after an engine failure and in a one-engine go-around from the approach, with pedal to spare. Each case is
## also run on the upstream data (thrust points and rudder) and printed, to show the difference.

const B := preload("res://tests/test_fbw_a320.gd")
const KT := 0.514444
const FT := 0.3048
const DT := 1.0 / 60.0
const UPSTREAM := [2.8775, -1.04768]  # JSBSim FDE thrust points |y|, z (m)
const RUDDER_K := 3.0  # aero.json CYdr / Cldr / Cndr over the upstream values (tools/06_jsbsim_to_json.py rudder_k)
const RUDDER_TERMS := ["aero/coefficient/CYdr", "aero/coefficient/Cldr", "aero/coefficient/Cndr"]


## The A320 with the law; yz = [|y|, z] of both thrust points instead of config.json's ([] = config.json).
func _def(yz: Array) -> AircraftDef:
	var d := B.new()._def()
	if yz.is_empty():
		return d
	var cfg: Dictionary = d.config().duplicate(true)
	for e in cfg.engines:
		e.pos_m = [e.pos_m[0], signf(e.pos_m[1]) * yz[0], yz[1]]
	return AircraftDef.make("a320", d.data, "res://aircraft/a320", cfg)


## The upstream JSBSim data: its thrust points and its rudder (aero.json with the rudder terms / RUDDER_K, written
## to a scratch folder under user://; the aero file is the only one the FDM reads from the folder). _engine_out
## deletes the folder again once the FDM has read it (TMP_DIR), so no test files are left in the user data.
func _upstream_def() -> AircraftDef:
	var d := _def(UPSTREAM)
	var aero: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://aircraft/a320/aero.json"))
	for ax in aero.axes.values():
		for fn in ax:
			if fn.name in RUDDER_TERMS:
				fn.f.args[-1] = float(fn.f.args[-1]) / RUDDER_K
	var dir := TMP_DIR
	DirAccess.make_dir_recursive_absolute(dir)
	var fa := FileAccess.open(dir + "/aero.json", FileAccess.WRITE)
	fa.store_string(JSON.stringify(aero))
	fa.close()
	return AircraftDef.make("a320", d.data, dir, d.config())


const TMP_DIR := "user://test_a320_upstream"


func _drop_tmp() -> void:
	if DirAccess.dir_exists_absolute(TMP_DIR):
		DirAccess.remove_absolute(TMP_DIR + "/aero.json")
		DirAccess.remove_absolute(TMP_DIR)


## Trimmed level at kcas / alt_ft with mass kg and flap detent (slat, flap deg); engine 1 fails, engine 2 goes to
## TOGA. A pilot holds zero sideslip with the pedals (PI, full travel = 1) and the heading with up to 5 deg of bank.
## Returns {pedal (mean of the last 5 s), sat (fraction of the run at full pedal), beta, bank, hdg (deg), cas_kt}.
func _engine_out(yz: Array, kg: float, kcas: float, alt_ft: float, detent: int, slat: float, flap: float, gear: bool, secs := 30.0, def: AircraftDef = null) -> Dictionary:
	B.new()._reset_props()
	var f := FDM.new(def if def else _def(yz))
	_drop_tmp()
	f.mb.tanks[2].contents_kg = clampf(f.mb.tanks[2].contents_kg + kg - f.mb.mass, 0.0, f.mb.tanks[2].capacity_kg)
	f.mb.update()
	f.atmo.update(alt_ft * FT)
	f.fcs.flap_cmd = detent
	f.fcs.flap_deg = flap
	f.fcs.slat_deg = slat
	f.set_airborne(0.0, 0.0, alt_ft * FT, 0.0, kcas * KT)
	for u in f.units:
		u.warm_start(true)
	f.fcs.gear_cmd = 1 if gear else 0
	f.gear.gear_pos = 1.0 if gear else 0.0
	f.fcs.settle()
	f.trim_level_cas(kcas * KT)
	f.units[0].engine.failed = true
	f.units[1].engine.throttle = 1.0
	var integ := 0.0
	var pedal_sum := 0.0
	var n_tail := 0
	var sat := 0
	var steps := int(secs / DT)
	for i in steps:
		var e := f.euler()
		var hdg := rad_to_deg(e.z if e.z < PI else e.z - TAU)
		var bank := rad_to_deg(e.x)
		var beta := rad_to_deg(f.beta)
		integ = clampf(integ + 0.15 * beta * DT, -1.0, 1.0)
		f.fcs.yaw = clampf(0.12 * beta + integ, -1.0, 1.0)
		var bank_tgt := clampf(-1.5 * hdg, -5.0, 5.0)
		f.fcs.roll = clampf(0.08 * (bank_tgt - bank) - 0.04 * rad_to_deg(f.w_b.x), -1.0, 1.0)
		f.fcs.pitch = clampf(0.04 * (f.cas / KT - kcas) - 0.3 * rad_to_deg(f.w_b.y), -0.5, 0.5)  # hold the speed
		f.step(DT)
		if absf(f.fcs.yaw) > 0.999:
			sat += 1
		if i >= steps - int(5.0 / DT):
			pedal_sum += f.fcs.yaw
			n_tail += 1
	var ee := f.euler()
	return {"pedal": pedal_sum / n_tail, "sat": float(sat) / steps, "beta": rad_to_deg(f.beta), "bank": rad_to_deg(ee.x),
		"hdg": rad_to_deg(ee.z if ee.z < PI else ee.z - TAU), "cas_kt": f.cas / KT, "rudder_deg": float(f.fcs.cmd.get("rudder", 0.0)),
		"crashed": f.damage.crashed}


## The model's thrust points with the upstream rudder (what moving the thrust alone would give).
func _arm_only_def() -> AircraftDef:
	var u := _upstream_def()
	return AircraftDef.make("a320", u.data, u.dir, B.new()._def().config())


func _line(tag: String, r: Dictionary) -> String:
	return "%s: pedal %+.2f (full %.0f %% of the time), rudder %+.1f deg, beta %+.2f, bank %+.1f, heading %+.1f deg, %.0f kt" % [
		tag, r.pedal, r.sat * 100.0, r.rudder_deg, r.beta, r.bank, r.hdg, r.cas_kt]


func _check(r: Dictionary) -> String:
	if r.crashed or r.sat > 0.02 or absf(r.pedal) > 0.9 or absf(r.beta) > 1.5 or absf(r.hdg) > 8.0 or absf(r.bank) > 7.0:
		return "not held: " + _line("", r)
	return ""


## Engine failure at V2 + 5 kt (70 t, CONF 1+F, gear up, 1,500 ft).
func test_a320_engine_out_at_v2() -> String:
	var up := _engine_out([], 70000.0, 150.0, 1500.0, 2, 18.0, 10.0, false, 30.0, _upstream_def())
	var arm := _engine_out([5.62977, -2.26943], 70000.0, 150.0, 1500.0, 2, 18.0, 10.0, false, 30.0, _arm_only_def())
	var now := _engine_out([], 70000.0, 150.0, 1500.0, 2, 18.0, 10.0, false)
	print("    V2 engine out, upstream data (y 2.88 m)   " + _line("", up))
	print("    V2 engine out, y 5.63 m, upstream rudder  " + _line("", arm))
	print("    V2 engine out, y 5.63 m, rudder x%.0f      " % RUDDER_K + _line("", now))
	return _check(now)


## One-engine go-around from the approach: CONF FULL, gear down, 64 t, 140 kt, the live engine at TOGA.
func test_a320_engine_out_go_around_from_approach() -> String:
	var up := _engine_out([], 64000.0, 140.0, 1000.0, 5, 27.0, 35.0, true, 20.0, _upstream_def())
	var now := _engine_out([], 64000.0, 140.0, 1000.0, 5, 27.0, 35.0, true, 20.0)
	print("    approach engine out + TOGA, upstream data " + _line("", up))
	print("    approach engine out + TOGA, now           " + _line("", now))
	return _check(now)
