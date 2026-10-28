extends RefCounted
## The A320's turbofan (table-driven thrust, FADEC detents, start, reverse) and ground behaviour
## (autobrake, anti-skid brakes, takeoff roll on direct control); the rest is in test_fdm_a320.gd.

const A := preload("res://tests/test_fdm_a320.gd")
const DT := 1.0 / 120.0
const KT := 0.514444
const FT := 0.3048


func _fdm() -> FDM:
	return FDM.new(AircraftDef.make("a320", A.DATA, "res://aircraft/a320"))


func _run(f: FDM, seconds: float, dt := DT) -> void:
	for i in int(seconds / dt):
		f.step(dt)


# --- turbofan -----------------------------------------------------------------

func _engine(extra := {}) -> EngineTurbineFadec:
	var c: Dictionary = AircraftDef.make("a320", {}, "res://aircraft/a320").config()
	var ec: Dictionary = c.engines[0].merged({"fadec_limits": c.fadec_limits}).merged(extra)
	return EngineTurbineFadec.new(ec)


## Step one engine in ISA air at alt (m) and speed (m/s).
func _spin(e: EngineTurbineFadec, seconds: float, alt := 0.0, v := 0.0) -> void:
	var a := AtmosphereISA.new()
	a.update(alt)
	for i in int(seconds / DT):
		e.update(DT, 0.0, a.pressure, a.temperature, v)


func test_a320_engine_start_sequence() -> String:
	var e := _engine()
	e.fuel_ok = true
	_spin(e, 5.0)
	if e.running or e.n2 > 0.001:
		return "nothing without the starter"
	e.master = true
	e.starter = true
	var t_light := -1.0
	var t_idle := -1.0
	for i in int(120.0 / DT):
		_spin(e, DT)
		if e.running and t_light < 0.0:
			t_light = i * DT
		if e.running and t_idle < 0.0 and absf(e.n1 - e.idle_n1) < 0.003 and e.n2 >= e.idle_n2 - 0.003:
			t_idle = i * DT
			break
	print("    start: light-off after %.1f s (N2 %.0f %%), idle after %.1f s: N1 %.1f N2 %.1f EGT %.0f C, thrust %.0f N, ff %.3f kg/s" % [
		t_light, e.n2 * 100.0, t_idle, e.n1 * 100.0, e.n2 * 100.0, e.egt_k - 273.15, e.thrust_n, e.fuel_flow_kgs])
	if t_light < 12.0 or t_light > 30.0 or t_idle < 30.0 or t_idle > 70.0:
		return "light-off in 12-30 s and idle in 30-70 s expected (%.1f / %.1f)" % [t_light, t_idle]
	_spin(e, 30.0)
	e.starter = false
	if absf(e.n1 - 0.189) > 0.005 or e.egt_k < 640.0 or e.egt_k > 720.0 or e.thrust_n < 3000.0 or e.thrust_n > 9000.0:
		return "idle values: N1 %.3f, EGT %.0f K, thrust %.0f N" % [e.n1, e.egt_k, e.thrust_n]
	e.master = false  # fuel cut
	_spin(e, 60.0)
	return "" if not e.running and e.n2 < 0.12 else "master off must shut it down and it spools down (N2 %.2f)" % e.n2


func test_a320_engine_toga_thrust_and_lapse() -> String:
	var e := _engine()
	e.warm_start(0.2)
	e.master = true
	e.throttle = 1.0
	_spin(e, 25.0)
	var c: Dictionary = e._cfg
	print("    TOGA static SL: %.0f N, N1 %.1f %%, N2 %.1f %%, fuel %.2f kg/s, EGT %.0f C" % [e.thrust_n, e.n1 * 100.0, e.n2 * 100.0, e.fuel_flow_kgs, e.egt_k - 273.15])
	if absf(e.thrust_n - c.thrust_n) > 0.02 * c.thrust_n:
		return "static TOGA at sea level should be thrust_n %.0f (x1.0 table), got %.0f" % [c.thrust_n, e.thrust_n]
	if e.fuel_flow_kgs < 1.5 or e.fuel_flow_kgs > 2.3:
		return "TOGA fuel flow %.2f kg/s" % e.fuel_flow_kgs
	# at 3,000 m (about 10,000 ft density altitude), Mach 0.4: the table says 0.692
	var a := AtmosphereISA.new()
	a.update(3048.0)
	var v := 0.4 * a.sound_speed
	_spin(e, 25.0, 3048.0, v)
	var da := AtmosphereISA.density_altitude(a.density) / FT
	var tab: float = Table.lookup(c.thrust_table, {"velocities/mach": 0.4, "atmosphere/density-altitude": da})
	var idle: float = c.thrust_n * Table.lookup(c.idle_thrust_table, {"velocities/mach": 0.4, "atmosphere/density-altitude": da})
	var want: float = idle + (c.thrust_n - idle) * tab
	print("    TOGA at 3048 m M0.4: %.0f N (table %.3f, expected %.0f N)" % [e.thrust_n, tab, want])
	if absf(e.thrust_n - want) > 0.03 * want or e.thrust_n > 0.8 * c.thrust_n:
		return "thrust at altitude must follow the table: %.0f vs %.0f N" % [e.thrust_n, want]
	# the spool: idle -> TOGA through the rate tables
	var s := _engine()
	s.warm_start(0.2)
	s.master = true
	s.throttle = 1.0
	var t90 := -1.0
	for i in int(30.0 / DT):
		_spin(s, DT)
		if s.thrust_n > 0.9 * c.thrust_n * 0.97 and t90 < 0.0:
			t90 = i * DT
	print("    spool-up idle -> 90 %% thrust: %.1f s" % t90)
	return "" if t90 > 4.0 and t90 < 16.0 else "spool-up %.1f s (JSBSim tables give ~8-13 s)" % t90


func test_a320_engine_reverse_only_on_the_ground() -> String:
	var e := _engine()
	e.warm_start(0.2)
	e.master = true
	e.on_ground = true
	e.reverse = 1.0
	_spin(e, 22.0, 0.0, 30.0)
	var rev := e.thrust_n
	print("    reverse (lever -1) on the ground at 30 m/s: %.0f N, deploy %.2f, N1 %.1f %%" % [rev, e.reverser_pos, e.n1 * 100.0])
	if rev > -15000.0 or rev < -60000.0 or e.reverser_pos < 0.99:
		return "reverse thrust should be -x, 15-60 kN (got %.0f)" % rev
	e.reverse = 0.0
	_spin(e, 12.0, 0.0, 30.0)
	if e.thrust_n < 0.0 or e.reverser_pos > 0.0:
		return "stowing the reverser brings the thrust back: %.0f, %.2f" % [e.thrust_n, e.reverser_pos]
	var air := _engine()
	air.warm_start(0.2)
	air.master = true
	air.on_ground = false
	air.reverse = 1.0
	_spin(air, 8.0, 3000.0, 100.0)
	return "" if air.reverser_pos == 0.0 and air.thrust_n > 0.0 else "no reverse in the air: deploy %.2f, thrust %.0f" % [air.reverser_pos, air.thrust_n]


func test_a320_engine_levers_and_detents() -> String:
	var e := _engine()
	e.warm_start(0.2)
	e.master = true
	var out := []
	for lever in [0.0, 0.556, 0.778, 1.0]:
		e.throttle = lever
		_spin(e, 30.0)
		out.append(snappedf(e.n1 * 100.0, 0.1))
	var f := e.fadec
	print("    N1 at the detents (idle CL MCT TOGA): %s; limits toga %.1f mct %.1f climb %.1f" % [out, f.limits["toga-table"], f.limits["mct-table"], f.limits["climb-table"]])
	if absf(out[3] - f.limits["toga-table"]) > 0.3 or absf(out[2] - f.limits["mct-table"]) > 0.3 or out[0] > 20.0 or not (out[0] < out[1] and out[1] < out[2] and out[2] <= out[3]):
		return "detent N1s must be monotone and match the FADEC limit tables"
	e.flex_temp_c = 50.0
	_spin(e, 30.0)
	return "" if e.n1 * 100.0 <= out[3] + 0.01 else "FLX limit not above TOGA"


# --- ground -------------------------------------------------------------------

## On the ground at `mass_kg` (fuel in the centre tank adjusted), engines idling.
func _ground(mass_kg := 70000.0) -> FDM:
	var f := _fdm()
	var extra := mass_kg - f.mb.mass
	f.mb.tanks[2].contents_kg = clampf(f.mb.tanks[2].contents_kg + extra, 0.0, f.mb.tanks[2].capacity_kg)
	f.mb.update()
	f.set_on_ground(0.0, 0.0, 0.0)
	for u in f.units:
		u.warm_start(false)
		u.engine.master = true
	f.step(DT)
	return f


func test_a320_autobrake_decelerations() -> String:
	var out := []
	for mode in [1, 2]:
		var f := _ground(65000.0)
		f.v_b = Vector3(60.0, 0.0, 0.0)
		(f.gear as RetractableGear).autobrake_mode = mode
		_run(f, 3.0, 1.0 / 60.0)  # the ground spoilers deploy first (about 1.5 s)
		var v0 := f.v_b.x
		_run(f, 5.0, 1.0 / 60.0)
		out.append((v0 - f.v_b.x) / 5.0)
		if not f.gear.autobrake_on:
			return "autobrake %d not active (spoilers %.0f deg, wow %s)" % [mode, f.fcs.spoiler[2], f.gear.wow]
		if mode == 2:  # a pedal press switches it off
			f.gear.brake_left = 0.5
			f.gear.brake_right = 0.5
			_run(f, 0.1, 1.0 / 60.0)
			if f.gear.autobrake_on:
				return "pedals must disarm the autobrake"
	print("    autobrake mean deceleration LO %.2f, MED %.2f m/s^2" % [out[0], out[1]])
	if absf(out[0] - 1.7) > 0.4 or absf(out[1] - 3.0) > 0.5:
		return "autobrake LO / MED should decelerate at 1.7 / 3.0 m/s^2: %.2f / %.2f" % [out[0], out[1]]
	return ""


func test_a320_brakes_use_brake_mu_and_antiskid() -> String:
	var decel := []
	for skid in [true, false]:
		var f := _ground(65000.0)
		f.v_b = Vector3(40.0, 0.0, 0.0)
		f.gear.antiskid = skid
		f.gear.brake_left = 1.0
		f.gear.brake_right = 1.0
		_run(f, 0.5, 1.0 / 60.0)
		var v0 := f.v_b.x
		_run(f, 2.0, 1.0 / 60.0)
		decel.append((v0 - f.v_b.x) / 2.0)
	print("    full pedals: anti-skid on %.2f m/s^2, off %.2f" % [decel[0], decel[1]])
	return "" if decel[0] > 2.5 and decel[1] < 0.85 * decel[0] else "anti-skid on must brake harder than a skidding tyre: %s" % [decel]


## Brake release to liftoff on direct control: TOGA, rotate at VR. Returns distance, speed and the time.
func _takeoff(mass_kg: float) -> Dictionary:
	var f := _ground(mass_kg)
	f.fcs.flap_cmd = 2  # 1+F
	f.fcs.flap_deg = 10.0
	f.fcs.slat_deg = 18.0
	f.fcs.pitch_trim = 0.15
	f.fcs.settle()
	f.gear.brake_left = 1.0
	f.gear.brake_right = 1.0
	for u in f.units:
		u.engine.throttle = 0.45
	_run(f, 16.0, 1.0 / 60.0)  # run-up against the brakes
	f.gear.brake_left = 0.0
	f.gear.brake_right = 0.0
	for u in f.units:
		u.engine.throttle = 1.0
	var vr := 69.5  # 135 kt
	var t := 0.0
	var dt := 1.0 / 120.0
	var pitch_max := 0.0
	while t < 60.0 and not f.damage.crashed:
		var e := f.euler()
		f.fcs.yaw = clampf(-1.5 * e.z - 0.5 * f.w_b.z, -0.3, 0.3) if f.cas < 60.0 else clampf(-2.0 * (e.z if e.z < PI else e.z - TAU) - 1.0 * f.w_b.z, -1.0, 1.0)
		f.gear.steer_cmd = f.fcs.yaw
		if f.cas > vr:
			f.fcs.pitch = clampf(0.45 - 8.0 * (e.y - deg_to_rad(11.0)) - 4.0 * f.w_b.y, -0.5, 0.6)
		f.step(dt)
		t += dt
		pitch_max = maxf(pitch_max, e.y)
		if not f.gear.wow and t > 5.0:
			break
	return {"dist": f.pos_n, "v": f.cas, "t": t, "pitch": rad_to_deg(pitch_max), "crashed": f.damage.crashed, "reason": f.damage.crash_reason, "f": f}


func test_a320_takeoff_roll_70_tonnes() -> String:
	var r := _takeoff(70000.0)
	print("    takeoff roll at 70 t: liftoff after %.0f m, %.1f s, CAS %.1f kt, max pitch %.1f deg" % [r.dist, r.t, r.v / KT, r.pitch])
	if r.crashed:
		return "crashed: " + r.reason
	# Thrust budget: 2 x ~115 kN at 70 t is 3.2 m/s^2 less rolling friction and drag, so a rotation at 135 kt
	# lifts off after about 0.9-1.5 km (the 1,800-2,200 m of the plan is the distance to 35 ft / flex thrust,
	# not reproduced here; tools/a320_reference.json will say what JSBSim gives).
	if r.dist < 800.0 or r.dist > 1600.0 or r.v < 62.0 or r.v > 82.0:
		return "takeoff roll %.0f m at %.0f kt: expected 800-1600 m at 120-160 kt" % [r.dist, r.v / KT]
	return ""
