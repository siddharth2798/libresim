extends RefCounted
## The airliner parts of the FDM on the A320's own data (aircraft/a320/config.json + aero.json, built
## with AircraftDef.make because there is no A320 aircraft.json yet): expression operators and 3-D
## tables, the aero input context (strict: an unknown property name fails), per-surface controls,
## retractable gear, steering, autobrake, the table-driven turbofan with start and reverse, and
## ground roll / trimmed flight on direct control. The C172 suites cover the unchanged path.

const DT := 1.0 / 120.0
const KT := 0.514444
const FT := 0.3048


## Airliner limits and damage thresholds as the future aircraft.json will give them.
const DATA := {
	"limits": {"vne_kias": 350.0, "vd_kias": 400.0, "vfe_kias": [[10.5, 230.0], [15.5, 215.0], [20.5, 200.0], [1000.0, 177.0]], "g_pos": 2.5, "g_neg": -1.0},
	"damage": {"hard_landing_ms": 2.5, "collapse_ms": 4.0, "nose_collapse_ms": 3.0, "main_load_w": 2.5, "nose_load_w": 1.6},
}


func _fdm() -> FDM:
	return FDM.new(AircraftDef.make("a320", DATA, "res://aircraft/a320"))


func _run(f: FDM, seconds: float, dt := DT) -> void:
	for i in int(seconds / dt):
		f.step(dt)


## Airborne at a Mach number / altitude, engines running, trimmed (direct control).
func _cruise(mach: float, alt_m: float) -> FDM:
	var f := _fdm()
	f.atmo.update(alt_m)
	var tas := mach * f.atmo.sound_speed
	f.set_airborne(0.0, 0.0, alt_m, 0.0, tas)
	for u in f.units:
		u.warm_start(true)
	f.fcs.gear_cmd = 0
	f.gear.gear_pos = 0.0
	f.trim_level(tas)
	return f


# --- expressions and tables ---------------------------------------------------

func test_a320_expression_operators() -> String:
	var ctx := {"x": 2.0, "y": -3.0, "z": 0.0}
	var P := func(n): return {"p": n}
	var cases := [
		[{"op": "sum", "args": [1.0, 2.0, 3.0]}, 6.0], [{"op": "product", "args": [2.0, 3.0, P.call("y")]}, -18.0],
		[{"op": "min", "args": [4.0, 2.0, 3.0]}, 2.0], [{"op": "max", "args": [4.0, 2.0, 9.0]}, 9.0],
		[{"op": "avg", "args": [2.0, 4.0]}, 3.0], [{"op": "and", "args": [1.0, 0.5]}, 1.0], [{"op": "and", "args": [1.0, P.call("z")]}, 0.0],
		[{"op": "or", "args": [P.call("z"), 0.0]}, 0.0], [{"op": "or", "args": [P.call("z"), 2.0]}, 1.0],
		[{"op": "difference", "args": [10.0, 3.0, 2.0]}, 5.0], [{"op": "quotient", "args": [9.0, 3.0]}, 3.0],
		[{"op": "pow", "args": [2.0, 10.0]}, 1024.0], [{"op": "atan2", "args": [1.0, 1.0]}, PI / 4.0], [{"op": "mod", "args": [7.0, 4.0]}, 3.0],
		[{"op": "lt", "args": [1.0, 2.0]}, 1.0], [{"op": "le", "args": [2.0, 2.0]}, 1.0], [{"op": "gt", "args": [1.0, 2.0]}, 0.0],
		[{"op": "ge", "args": [1.0, 2.0]}, 0.0], [{"op": "eq", "args": [2.0, P.call("x")]}, 1.0], [{"op": "ne", "args": [2.0, P.call("x")]}, 0.0],
		[{"op": "abs", "args": [P.call("y")]}, 3.0], [{"op": "sqrt", "args": [16.0]}, 4.0], [{"op": "exp", "args": [0.0]}, 1.0],
		[{"op": "ln", "args": [exp(2.0)]}, 2.0], [{"op": "log2", "args": [8.0]}, 3.0], [{"op": "log10", "args": [1000.0]}, 3.0],
		[{"op": "sin", "args": [0.0]}, 0.0], [{"op": "cos", "args": [0.0]}, 1.0], [{"op": "tan", "args": [0.0]}, 0.0],
		[{"op": "asin", "args": [1.0]}, PI / 2.0], [{"op": "acos", "args": [1.0]}, 0.0], [{"op": "atan", "args": [1.0]}, PI / 4.0],
		[{"op": "floor", "args": [-1.5]}, -2.0], [{"op": "ceil", "args": [1.2]}, 2.0], [{"op": "fraction", "args": [-2.25]}, -0.25],
		[{"op": "not", "args": [P.call("z")]}, 1.0], [{"op": "neg", "args": [P.call("x")]}, -2.0],
		[{"op": "toradians", "args": [180.0]}, PI], [{"op": "todegrees", "args": [PI]}, 180.0],
		[{"op": "ifthen", "args": [P.call("x"), 5.0, 6.0]}, 5.0], [{"op": "ifthen", "args": [P.call("z"), 5.0, 6.0]}, 6.0],
		[{"op": "interpolate1d", "args": [P.call("x"), 0.0, 0.0, 4.0, 8.0, 10.0, 8.0]}, 4.0],
		[{"op": "interpolate1d", "args": [20.0, 0.0, 0.0, 4.0, 8.0, 10.0, 9.0]}, 9.0], [{"op": "interpolate1d", "args": [-1.0, 0.0, 3.0, 4.0, 8.0]}, 3.0],
	]
	for c in cases:
		var v := Expr.eval(c[0], ctx)
		if absf(v - c[1]) > 1e-9:
			return "%s = %.6f, expected %.6f" % [c[0].op, v, c[1]]
	return ""


func test_a320_table_3d() -> String:
	# two layers (0 and 1), ragged rows: layer 0 has rows [0, 10], layer 1 rows [0, 5, 10]
	var t := {"row": "r", "col": "c", "layer": "l", "cols": [0.0, 1.0], "layers": [0.0, 1.0], "rows": null,
		"layer_rows": [[0.0, 10.0], [0.0, 5.0, 10.0]],
		"data": [[[0.0, 1.0], [10.0, 11.0]], [[100.0, 101.0], [100.0, 101.0], [200.0, 201.0]]]}
	var ctx := {"r": 5.0, "c": 0.5, "l": 0.0}
	if absf(Table.lookup(t, ctx) - 5.5) > 1e-9:
		return "layer 0: %.3f, expected 5.5" % Table.lookup(t, ctx)
	ctx.l = 1.0
	if absf(Table.lookup(t, ctx) - 100.5) > 1e-9:
		return "layer 1: %.3f, expected 100.5" % Table.lookup(t, ctx)
	ctx.l = 0.5
	if absf(Table.lookup(t, ctx) - 53.0) > 1e-9:
		return "between layers: %.3f, expected 53" % Table.lookup(t, ctx)
	ctx.l = 7.0  # clamped
	ctx.r = 99.0
	return "" if absf(Table.lookup(t, ctx) - 200.5) < 1e-9 else "clamping failed"


func test_a320_strict_mode_reports_unknown_names() -> String:
	Aero.strict = true
	Expr.quiet = true
	Expr.unknown.clear()
	var v := Expr.eval({"p": "no/such/property"}, {})
	var bad := Expr.unknown.size()
	Expr.unknown.clear()
	Aero.strict = false
	Expr.quiet = false
	if v != 0.0 or bad != 1:
		return "strict read of an unknown name: value %s, %d recorded (expected 0.0 and 1)" % [v, bad]
	Expr.eval({"p": "no/such/property"}, {})
	return "" if Expr.unknown.is_empty() else "non-strict mode must stay silent (the C172)"


# --- config and aero ----------------------------------------------------------

func test_a320_config_loads() -> String:
	var f := _fdm()
	if f.units.size() != 2 or not f.engine is EngineTurbineFadec or not f.fcs is AirlinerControls or not f.gear is RetractableGear:
		return "A320 classes: %d units, %s, %s, %s" % [f.units.size(), f.engine, f.fcs, f.gear]
	if f.mb.tanks.size() != 8 or f.tank_feed[5] != 0.0 or f.tank_feed[6] != 0.0 or f.tank_feed[7] != 0.0 or absf(f.tank_feed[0] - 0.2) > 1e-9:
		return "feed must skip the three pipe tanks: %s" % [f.tank_feed]
	if absf(f.units[0].thrust_dir.z + sin(deg_to_rad(2.0))) > 1e-6 or f.units[0].thrust_dir.y <= 0.0 or f.units[1].thrust_dir.y >= 0.0:
		return "engine orientation (pitch 2, yaw toe-in): %s %s" % [f.units[0].thrust_dir, f.units[1].thrust_dir]
	return "" if f.fcs.flap_detents() == 6 and f.fcs.spoiler.size() == 10 else "flap detents / spoiler panels"


func test_a320_aero_strict_no_unknown_names() -> String:
	Aero.strict = true
	Expr.quiet = true
	Expr.unknown.clear()
	var f := _cruise(0.5, 3048.0)
	f.fcs.flap_cmd = 3
	f.fcs.pitch = 0.2
	f.fcs.roll = 0.3
	f.fcs.yaw = -0.2
	f.fcs.speedbrake_cmd = 1.0
	f.fcs.gear_cmd = 1
	f.fcs.landing_light_l = 1.0
	_run(f, 3.0, 1.0 / 60.0)
	var miss := Expr.unknown.keys()
	Aero.strict = false
	Expr.quiet = false
	Expr.unknown.clear()
	if not miss.is_empty():
		return "unknown properties in the A320 aero: %s" % [miss]
	var fin: Array = f.aero.coeffs.values()
	for v in fin:
		if is_nan(v) or is_inf(v):
			return "non-finite aero term"
	return "" if f.aero.coeffs.size() > 40 and f.aero.ctx["fcs/slat-pos-norm"] > 0.0 else "terms %d, slat norm %.2f" % [f.aero.coeffs.size(), f.aero.ctx["fcs/slat-pos-norm"]]


func test_a320_trimmed_level_flight_hands_off() -> String:
	var f := _cruise(0.5, 3048.0)
	var a0 := f.altitude()
	var tas0 := f.vt
	print("    trim: THS %.2f deg, elevator %.2f deg, lever %.3f, N1 %.1f %%, pitch %.1f deg, mass %.0f kg" % [
		f.fcs.stabilizer_deg, f.fcs.surface("elevator-l"), f.units[0].engine.throttle, f.units[0].engine.n1 * 100.0, rad_to_deg(f.euler().y), f.mb.mass])
	_run(f, 30.0, 1.0 / 60.0)
	print("    30 s hands off: alt %+.0f m, TAS %.1f -> %.1f m/s, bank %.1f deg, mach %.3f" % [f.altitude() - a0, tas0, f.vt, rad_to_deg(f.euler().x), f.mach])
	if f.damage.crashed:
		return "crashed: " + f.damage.crash_reason
	if absf(f.altitude() - a0) > 150.0 or absf(f.vt - tas0) > 0.08 * tas0 or absf(rad_to_deg(f.euler().x)) > 15.0:
		return "not holding: alt %+.0f m, TAS %.1f -> %.1f, bank %.1f" % [f.altitude() - a0, tas0, f.vt, rad_to_deg(f.euler().x)]
	return ""


# --- controls and gear --------------------------------------------------------

func test_a320_flaps_slats_spoilers_stabilizer() -> String:
	var f := _fdm()
	f.set_airborne(0.0, 0.0, 3000.0, 0.0, 120.0)
	f.fcs.flap_cmd = 5  # FULL: slats 27, flaps 35
	f.fcs.speedbrake_cmd = 1.0
	f.fcs.pitch_trim = 1.0  # full nose-up trim
	_run(f, 3.0, 1.0 / 60.0)
	var c: AirlinerControls = f.fcs
	if absf(c.slat_deg - 27.0 * 0.0) > 5.0 * 1.35 + 0.1 or c.slat_deg <= 0.0:
		return "slats should be moving at 1.35 deg/s: %.2f" % c.slat_deg
	if absf(c.stabilizer_deg + 3.0 * 0.25) > 0.1:
		return "THS rate 0.25 deg/s toward -13.5: %.3f after 3 s" % c.stabilizer_deg
	var sp: float = c.spoiler[1]
	if sp < 45.0 or c.spoiler[0] > 0.1 or c.spoiler[4] > 0.1 or absf(c.spoiler[6] - sp) > 0.5:
		return "speedbrake: panels 2-4 of both wings at 50 deg, 1 and 5 retracted: %s" % [c.spoiler]
	_run(f, 60.0, 1.0 / 30.0)
	if absf(c.flap_deg - 35.0) > 0.01 or absf(c.slat_deg - 27.0) > 0.01 or absf(c.stabilizer_deg + 13.5) > 0.01:
		return "end state: flaps %.2f slats %.2f THS %.2f" % [c.flap_deg, c.slat_deg, c.stabilizer_deg]
	f.fcs.pitch_trim = -1.0
	_run(f, 80.0, 1.0 / 30.0)
	return "" if absf(c.stabilizer_deg - 4.0) < 0.01 else "THS nose-down limit +4: %.2f" % c.stabilizer_deg


func test_a320_surfaces_follow_the_stick_with_rate_limits() -> String:
	var f := _fdm()
	f.set_airborne(0.0, 0.0, 3000.0, 0.0, 150.0)
	f.fcs.roll = 1.0
	f.fcs.pitch = 1.0
	f.fcs.yaw = 1.0
	_run(f, 0.1, 1.0 / 240.0)
	var c: AirlinerControls = f.fcs
	if c.surface("aileron-l") <= 5.0 or c.surface("aileron-r") >= -5.0 or c.surface("aileron-l") > 82.0 * 0.1 + 0.5:
		return "ailerons opposite and rate limited (82 deg/s): %.1f / %.1f after 0.1 s" % [c.surface("aileron-l"), c.surface("aileron-r")]
	_run(f, 1.0, 1.0 / 240.0)
	if absf(c.surface("aileron-l") - 25.0) > 0.1 or absf(c.surface("elevator-l") + 30.0) > 0.1 or absf(c.surface("rudder") - 25.0) > 0.1:
		return "full stick: ail %.1f elev %.1f rudder %.1f" % [c.surface("aileron-l"), c.surface("elevator-l"), c.surface("rudder")]
	f.fcs.pitch = -1.0
	_run(f, 1.0, 1.0 / 240.0)
	return "" if absf(c.surface("elevator-l") - 15.0) < 0.1 else "forward stick clip +15: %.2f" % c.surface("elevator-l")


func test_a320_control_law_seam() -> String:
	var f := _fdm()
	f.set_airborne(0.0, 0.0, 3000.0, 0.0, 150.0)
	var law := GDScript.new()
	law.source_code = "extends RefCounted\nvar calls := 0\nfunc update(_dt, fdm):\n\tcalls += 1\n\tfdm.fcs.cmd['elevator-l'] = 7.0\n"
	law.reload()
	f.fcs.law = law.new()
	f.fcs.pitch = 1.0  # direct mapping must be skipped
	_run(f, 1.0, 1.0 / 120.0)
	var c: AirlinerControls = f.fcs
	return "" if f.fcs.law.calls == 120 and absf(c.surface("elevator-l") - 7.0) < 0.05 else "law called %d times, elevator-l %.2f" % [f.fcs.law.calls, c.surface("elevator-l")]


func test_a320_gear_retract_extend_and_drag() -> String:
	var f := _fdm()
	f.set_airborne(0.0, 0.0, 3000.0, 0.0, 100.0)
	var g: RetractableGear = f.gear
	if g.gear_pos != 1.0 or g.gear_state != 1:
		return "starts down and locked"
	var drag_down := _drag(f)
	f.fcs.gear_cmd = 0
	_run(f, 5.0, 1.0 / 60.0)
	if g.gear_state != 2 or g.gear_pos < 0.3 or g.gear_pos > 0.7 or g.door_pos <= 0.0:
		return "5 s into the retraction: pos %.2f state %d doors %.2f" % [g.gear_pos, g.gear_state, g.door_pos]
	_run(f, 6.0, 1.0 / 60.0)
	if g.gear_pos != 0.0 or g.gear_state != 0 or f.fcs.gear_pos != 0.0:
		return "up after ~10.5 s: pos %.2f, fcs mirror %.2f" % [g.gear_pos, f.fcs.gear_pos]
	if not g.contacts.filter(func(c): return c.retract).all(func(c): return not g._active(c)):
		return "contacts of a retracted gear must be inactive"
	var drag_up := _drag(f)
	f.fcs.gear_cmd = 1
	_run(f, 8.0, 1.0 / 60.0)
	var mid: float = g.gear_pos
	_run(f, 9.0, 1.0 / 60.0)
	print("    gear drag: down %.0f N, up %.0f N; extension 8 s: %.2f" % [drag_down, drag_up, mid])
	if mid < 0.4 or mid > 0.6 or g.gear_pos != 1.0 or drag_down < drag_up + 3000.0:
		return "extension takes ~16 s and gear drag must show: mid %.2f, end %.2f, drag %.0f vs %.0f" % [mid, g.gear_pos, drag_down, drag_up]
	return ""


func _drag(f: FDM) -> float:
	f.step(DT)
	return -f.aero.ctx["aero/qbar-psf"] * 0.0 + f.aero.coeffs["aero/coefficient/CDgear"] * FDM.LBF


func test_a320_gear_locked_down_on_the_ground() -> String:
	var f := _fdm()
	f.set_on_ground(0.0, 0.0, 0.0)
	_run(f, 2.0, 1.0 / 60.0)
	f.fcs.gear_cmd = 0
	_run(f, 2.0, 1.0 / 60.0)
	return "" if f.gear.gear_pos == 1.0 and f.fcs.gear_cmd == 1 and f.gear.wow else "gear lever must be locked on the ground (pos %.2f, wow %s)" % [f.gear.gear_pos, f.gear.wow]


func test_a320_nose_wheel_steering_fades_with_speed() -> String:
	var f := _fdm()
	f.set_on_ground(0.0, 0.0, 0.0)
	var nose: Dictionary = f.gear.contacts[0]
	f.gear.tiller = 1.0
	var out := []
	for v in [2.0, 23.0, 40.0]:
		f.v_b = Vector3(v, 0.0, 0.0)
		f.gear.prepare(DT, f)
		out.append(rad_to_deg(f.gear._steer_angle(nose)))
	f.gear.tiller = 0.0
	f.gear.steer_cmd = 1.0
	f.v_b = Vector3(2.0, 0.0, 0.0)
	f.gear.prepare(DT, f)
	var pedals := rad_to_deg(f.gear._steer_angle(nose))
	print("    steering: tiller %s deg at 2 / 23 / 40 m/s, pedals %.1f deg" % [out.map(func(x): return snappedf(x, 0.1)), pedals])
	if absf(out[0] - 75.0) > 0.5 or out[1] < 25.0 or out[1] > 50.0 or out[2] > 0.5 or absf(pedals - 6.0) > 0.2:
		return "tiller 75 deg at taxi speed, fading to 0 by 36 m/s, pedals 6 deg"
	return ""
