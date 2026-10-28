extends RefCounted
## The A320 fly-by-wire law, part 2 (tests/test_fbw_a320.gd has the helpers and the flight-path tests): ground
## mode, law reversion, published Props, high speed protection, autopilot interface, the real control
## pipeline (FdmNode) and a takeoff with the law on.

const B := preload("res://tests/test_fbw_a320.gd")
var b := B.new()


# --- ground, reversion, props, autopilot, pipeline ------------------------------

func test_fbw_ground_mode_is_direct() -> String:
	var f := FDM.new(b._def())
	f.set_on_ground(0.0, 0.0, 0.0)
	f.fcs.pitch = 0.5
	f.fcs.roll = 0.4
	b._run(f, 0.5)
	var c: AirlinerControls = f.fcs
	print("    ground: elevator cmd %.1f deg, aileron %.1f deg, ground mode %s" % [c.cmd["elevator-l"], c.cmd["aileron-l"], Props.get_b("fcs/ground_mode")])
	return "" if absf(c.cmd["elevator-l"] + 15.0) < 0.1 and absf(c.cmd["aileron-l"] - 10.0) < 0.1 and Props.get_b("fcs/ground_mode") else "ground mapping must be direct"


func test_fbw_reversion_to_alternate_and_direct() -> String:
	b._reset_props()
	var f := b._cruise(250.0, 10000.0)
	b._run(f, 0.5)
	var ok: bool = Props.get_v("fcs/law") == "NORMAL" and Props.get_v("fcs/law_id") == 0
	Props.set_v("failures/adr", true)
	f.fcs.roll = 0.5
	f.fcs.pitch = 0.0
	b._run(f, 0.5)
	var alt: bool = Props.get_v("fcs/law") == "ALTERNATE" and Props.get_v("fcs/law_reason") == "ADR"
	var direct_roll: bool = absf(f.fcs.cmd["aileron-l"] - 0.5 * 25.0) < 0.1  # roll is direct in alternate law
	f.fcs.gear_cmd = 1
	f.fcs.roll = 0.0
	f.fcs.pitch = 0.5
	b._run(f, 20.0, 1.0 / 30.0)  # gear down: direct law
	var dir: bool = Props.get_v("fcs/law") == "DIRECT" and absf(f.fcs.cmd["elevator-l"] + 15.0) < 0.1
	var why: String = Props.get_v("fcs/law_reason")
	b._reset_props()
	print("    reversion: normal %s, alternate (ADR) %s roll direct %s, gear down -> direct %s (%s)" % [ok, alt, direct_roll, dir, why])
	return "" if ok and alt and direct_roll and dir else "law selection: %s %s %s %s" % [ok, alt, direct_roll, dir]


func test_fbw_hydraulic_failures_select_law() -> String:
	b._reset_props()
	var f := b._cruise(250.0, 10000.0)
	Props.set_v("failures/hyd_g", true)
	b._run(f, 0.2)
	var one: int = Props.get_v("fcs/law_id")
	Props.set_v("failures/hyd_b", true)
	b._run(f, 0.2)
	var two: int = Props.get_v("fcs/law_id")
	Props.set_v("failures/hyd_y", true)
	b._run(f, 0.2)
	var three: int = Props.get_v("fcs/law_id")
	b._reset_props()
	b._run(f, 0.2)
	return "" if one == 0 and two == 1 and three == 2 and Props.get_v("fcs/law_id") == 0 else "law ids %s %s %s then %s" % [one, two, three, Props.get_v("fcs/law_id")]


func test_fbw_protection_props_published() -> String:
	b._reset_props()
	var f := b._cruise(250.0, 10000.0)
	b._run(f, 0.3)
	for k in ["fcs/law", "fcs/law_id", "fcs/law_reason", "fcs/alpha_prot_deg", "fcs/alpha_max_deg", "fcs/alpha_floor_deg", "fcs/alpha_stall_deg",
			"fcs/alpha_floor", "fcs/stall_warning", "fcs/prot/alpha", "fcs/prot/speed", "fcs/prot/bank", "fcs/prot/pitch", "fcs/prot/nz", "fcs/ground_mode", "ap/cmd/takeover"]:
		if not Props.has(k):
			return "Prop %s not published" % k
	var p: float = Props.get_f("fcs/alpha_prot_deg")
	return "" if absf(p - 8.6) < 0.2 and Props.get_f("fcs/alpha_max_deg") > p else "clean alpha prot %.2f deg (JSBSim 8.6)" % p


func test_fbw_high_speed_protection() -> String:
	var f := b._cruise(250.0, 10000.0)
	f.v_b *= 1.45  # about 365 kt CAS, past VMO + 6
	f.fcs.pitch = -1.0
	b._run(f, 1.5)
	var nz := b._law(f).s.nz
	print("    high speed: CAS %.0f kt, forward stick, nz %.2f, protection %s" % [f.cas / B.KT, nz, Props.get_b("fcs/prot/speed")])
	return "" if Props.get_b("fcs/prot/speed") and nz > 0.5 else "high speed protection not acting (nz %.2f)" % nz


func test_fbw_autopilot_interface_and_takeover() -> String:
	b._reset_props()
	var f := b._cruise(250.0, 10000.0)
	Props.set_v("ap/cmd/active", true)
	Props.set_v("ap/cmd/nz_g", 0.3)
	Props.set_v("ap/cmd/roll_rate_dps", 5.0)
	b._run(f, 1.5)
	var nz := b._law(f).s.nz
	var p := rad_to_deg(f.w_b.x)
	var quiet := not Props.get_b("ap/cmd/takeover")
	f.fcs.pitch = 0.3
	f.step(B.DT)
	var taken := Props.get_b("ap/cmd/takeover")
	b._reset_props()
	print("    autopilot demands 0.3 g / 5 deg/s: nz %.3f, p %.2f deg/s, takeover flag %s -> %s on stick" % [nz, p, not quiet, taken])
	return "" if quiet and taken and absf(nz - 1.3) < 0.1 and absf(p - 5.0) < 1.0 else "AP interface: nz %.3f p %.2f takeover %s/%s" % [nz, p, quiet, taken]


func test_fbw_real_control_pipeline_reaches_the_law() -> String:
	var f := b._cruise(250.0, 10000.0)
	var n := FdmNode.new()
	n.fdm = f
	Props.set_v("controls/pitch", 0.4)
	Props.set_v("controls/roll", 0.5)
	Props.set_v("controls/yaw", 0.2)
	n._read_controls(1.0)
	var ok := absf(f.fcs.pitch - 0.4) < 0.01 and absf(f.fcs.roll - 0.5) < 0.01 and absf(f.fcs.yaw - 0.2) < 0.01
	b._run(f, 1.0)
	var q := rad_to_deg(f.w_b.y)
	var p := rad_to_deg(f.w_b.x)
	for k in ["controls/pitch", "controls/roll", "controls/yaw"]:
		Props.set_v(k, 0.0)
	n.free()
	return "" if ok and q > 0.5 and p > 3.0 else "controls/* -> fcs -> law: stick %s, q %.2f p %.2f" % [ok, q, p]


# --- takeoff with the law on -----------------------------------------------------

func test_fbw_takeoff_70_tonnes_with_the_law() -> String:
	b._reset_props()
	var f := FDM.new(b._def())
	f.mb.tanks[2].contents_kg = clampf(f.mb.tanks[2].contents_kg + 70000.0 - f.mb.mass, 0.0, f.mb.tanks[2].capacity_kg)
	f.mb.update()
	f.set_on_ground(0.0, 0.0, 0.0)
	for u in f.units:
		u.warm_start(false)
		u.engine.master = true
	f.fcs.flap_cmd = 2  # 1+F
	f.fcs.flap_deg = 10.0
	f.fcs.slat_deg = 18.0
	f.fcs.pitch_trim = 0.15
	f.step(B.DT)
	f.gear.brake_left = 1.0
	f.gear.brake_right = 1.0
	for u in f.units:
		u.engine.throttle = 0.45
	b._run(f, 8.0, 1.0 / 30.0)
	f.gear.brake_left = 0.0
	f.gear.brake_right = 0.0
	for u in f.units:
		u.engine.throttle = 1.0
	var t := 0.0
	var vr := 142.0 * B.KT
	var d_lift := -1.0
	var d35 := -1.0
	var pitch_max := 0.0
	while t < 70.0 and not f.damage.crashed and d35 < 0.0:
		var e := f.euler()
		var th := rad_to_deg(e.y)
		var hdg := e.z if e.z < PI else e.z - TAU
		f.fcs.yaw = clampf(-2.0 * hdg - 1.0 * f.w_b.z, -0.3 if f.cas < 30.0 else -1.0, 0.3 if f.cas < 30.0 else 1.0)
		f.gear.steer_cmd = f.fcs.yaw
		if f.cas > vr:  # rotate to about 12 deg, then hold it
			f.fcs.pitch = clampf(0.30 + 0.12 * (12.0 - th) - 0.10 * rad_to_deg(f.w_b.y), -0.3, 0.8)
		f.step(B.DT)
		t += B.DT
		pitch_max = maxf(pitch_max, th)
		if d_lift < 0.0 and not f.gear.wow:
			d_lift = f.pos_n
		if f.agl > 10.668 + 3.0 and d_lift > 0.0:  # 35 ft above the ground (CG about 3 m above the wheels on the runway)
			d35 = f.pos_n
	print("    takeoff 70 t TOGA 1+F with the law: liftoff after %.0f m, 35 ft after %.0f m (t %.1f s), max pitch %.1f deg, CAS %.0f kt (oracle JSBSim: 1125 / 1393 m)" % [d_lift, d35, t, pitch_max, f.cas / B.KT])
	if f.damage.crashed:
		return "crashed: " + f.damage.crash_reason
	return "" if d_lift > 800.0 and d_lift < 1500.0 and d35 > d_lift and d35 < 1900.0 and pitch_max < 16.0 else "takeoff: liftoff %.0f m, 35 ft %.0f m, pitch %.1f" % [d_lift, d35, pitch_max]
