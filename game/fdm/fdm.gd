class_name FDM
extends RefCounted
## 6-DOF rigid-body flight model, flat earth over the world ENU frame.
## State: position NED (north = ENU y, east = ENU x, down = -alt) in 64-bit
## floats, body velocity/rates, attitude quaternion (body -> NED).
## Body axes: x forward, y right, z down. Everything SI except inside Aero.

const G := 9.80665
const LBF := 4.4482216
const LBF_FT := 1.3558179

var cfg: Dictionary
var atmo := AtmosphereISA.new()
var mb: MassBalance
var aero: Aero
var engine: EnginePiston
var prop: Propeller
var gear: GearGround
var fcs: FlightControls
var ground_height: Callable = func(_n: float, _e: float) -> float: return 0.0

# state
var pos_n := 0.0
var pos_e := 0.0
var pos_d := 0.0
var v_b := Vector3.ZERO
var w_b := Vector3.ZERO
var q := Quaternion.IDENTITY
var wind_ned := Vector3.ZERO  # air mass velocity (m/s, NED)
var time := 0.0

# derived (updated every step)
var alpha := 0.0
var beta := 0.0
var vt := 0.0  # true airspeed
var cas := 0.0
var qbar := 0.0
var mach := 0.0
var agl := 0.0
var load_factor := 1.0
var accel_b := Vector3.ZERO  # specific force (what an accelerometer feels), body
var _alpha_prev := 0.0
var _alphadot := 0.0
var _aero_rp: Vector3
var _eng_pos: Vector3


func _init(aircraft_dir := "res://aircraft/c172") -> void:
	cfg = Paths.load_res_json(aircraft_dir + "/c172_config.json")
	mb = MassBalance.new(cfg)
	aero = Aero.new(aircraft_dir + "/c172_aero.json", cfg.metrics)
	engine = EnginePiston.new(cfg.engine)
	prop = Propeller.new(cfg.propeller, cfg.engine)
	gear = GearGround.new(cfg)
	fcs = FlightControls.new(cfg)
	var a: Array = cfg.metrics.aero_ref_pt_m
	_aero_rp = Vector3(a[0], a[1], a[2])
	var e: Array = cfg.engine.pos_m
	_eng_pos = Vector3(e[0], e[1], e[2])


static func euler_to_quat(phi: float, theta: float, psi: float) -> Quaternion:
	return Quaternion(Vector3(0, 0, 1), psi) * Quaternion(Vector3(0, 1, 0), theta) * Quaternion(Vector3(1, 0, 0), phi)


## Returns Vector3(roll phi, pitch theta, heading psi) in radians.
func euler() -> Vector3:
	var phi := atan2(2.0 * (q.w * q.x + q.y * q.z), 1.0 - 2.0 * (q.x * q.x + q.y * q.y))
	var theta := asin(clampf(2.0 * (q.w * q.y - q.z * q.x), -1.0, 1.0))
	var psi := atan2(2.0 * (q.w * q.z + q.x * q.y), 1.0 - 2.0 * (q.y * q.y + q.z * q.z))
	return Vector3(phi, theta, fposmod(psi, TAU))


func altitude() -> float:
	return -pos_d


func velocity_ned() -> Vector3:
	return Basis(q) * v_b


## Start airborne, wings level, at a given true airspeed along the heading.
func set_airborne(n: float, e: float, alt: float, heading: float, tas: float, pitch := 0.03) -> void:
	pos_n = n; pos_e = e; pos_d = -alt
	q = euler_to_quat(0.0, pitch, heading)
	v_b = Vector3(tas * cos(pitch), 0.0, tas * sin(pitch))
	w_b = Vector3.ZERO
	_alpha_prev = pitch


## Start at rest on the ground with gear just touching; settles in ~1 s.
func set_on_ground(n: float, e: float, heading: float) -> void:
	q = euler_to_quat(0.0, 0.0, heading)
	pos_n = n; pos_e = e
	var low := -INF
	for c in gear.contacts:
		if c.wheel:
			low = maxf(low, mb.body_of(c.pos).z)
	pos_d = -ground_height.call(n, e) - low + 0.02
	v_b = Vector3.ZERO
	w_b = Vector3.ZERO


func step(dt: float) -> void:
	var r_bn := Basis(q)
	var r_nb := r_bn.transposed()
	agl = -pos_d - ground_height.call(pos_n, pos_e)
	atmo.update(-pos_d)
	var v_air := v_b - r_nb * wind_ned
	vt = v_air.length()
	alpha = atan2(v_air.z, v_air.x) if vt > 0.1 else 0.0
	beta = asin(clampf(v_air.y / vt, -1.0, 1.0)) if vt > 0.1 else 0.0
	_alphadot = lerpf(_alphadot, (alpha - _alpha_prev) / dt, 0.2)
	_alpha_prev = alpha
	qbar = 0.5 * atmo.density * vt * vt
	mach = vt / atmo.sound_speed
	var qc := atmo.pressure * (pow(1.0 + 0.2 * mach * mach, 3.5) - 1.0)
	cas = AtmosphereISA.cas_from_qc(qc)

	fcs.update(dt)
	gear.steer_cmd = fcs.yaw
	engine.update(dt, prop.rpm, atmo.pressure, atmo.temperature, vt)
	prop.update(dt, engine.torque, v_air.x, atmo.density, atmo.sound_speed)

	# --- aerodynamics (wind axes -> body), moments about the aero ref point
	var res: Array = aero.evaluate({
		"vt": vt, "alpha": alpha, "alphadot": _alphadot, "beta": beta, "qbar": qbar,
		"agl": maxf(agl, 0.0), "rho": atmo.density, "u": v_air.x,
		"p": w_b.x, "q": w_b.y, "r": w_b.z, "v_induced": prop.v_induced,
		"elevator": fcs.elevator, "aileron": fcs.aileron, "rudder": fcs.rudder, "flap_deg": fcs.flap_deg})
	var fw: Vector3 = res[0] * LBF  # (D, Y, L)
	var ca := cos(alpha); var sa := sin(alpha); var cb := cos(beta); var sb := sin(beta)
	var f_aero := Vector3(
		-fw.x * ca * cb - fw.y * ca * sb + fw.z * sa,
		-fw.x * sb + fw.y * cb,
		-fw.x * sa * cb - fw.y * sa * sb - fw.z * ca)
	var m_aero: Vector3 = res[1] * LBF_FT + mb.body_of(_aero_rp).cross(f_aero)

	# --- propulsion
	var po := prop.p_factor_offset(v_air.x, v_air.y, v_air.z)
	var r_eng := mb.body_of(_eng_pos) + Vector3(0.0, po.x, po.y)
	var f_thr := Vector3(prop.thrust, 0.0, 0.0)
	var m_thr := r_eng.cross(f_thr) + Vector3(-prop.sense * prop.torque, 0.0, 0.0)

	# --- ground
	var gr: Array = gear.compute(mb, r_bn, Vector3(pos_n, pos_e, pos_d), v_b, w_b,
		func(n: float, e: float) -> float: return ground_height.call(n, e))
	var f_ext: Vector3 = f_aero + f_thr + gr[0]
	var m_tot: Vector3 = m_aero + m_thr + gr[1]
	var f_grav := r_nb * Vector3(0.0, 0.0, G * mb.mass)

	# --- rigid body integration (semi-implicit Euler)
	accel_b = f_ext / mb.mass
	load_factor = -accel_b.z / G
	var a_b := (f_ext + f_grav) / mb.mass - w_b.cross(v_b)
	var h := mb.inertia * w_b + Vector3(prop.angular_momentum(), 0.0, 0.0)
	var w_dot := mb.inertia_inv * (m_tot - w_b.cross(h))
	v_b += a_b * dt
	w_b += w_dot * dt
	var dq := Quaternion(w_b.x * dt * 0.5, w_b.y * dt * 0.5, w_b.z * dt * 0.5, 1.0)
	q = (q * dq).normalized()
	var v_ned := Basis(q) * v_b
	pos_n += v_ned.x * dt
	pos_e += v_ned.y * dt
	pos_d += v_ned.z * dt
	_burn_fuel(dt)
	time += dt


func _burn_fuel(dt: float) -> void:
	var burn := engine.fuel_flow_kgs * dt
	if burn <= 0.0:
		return
	var n_tanks := 0
	for t in mb.tanks:
		if t.contents_kg > 0.0:
			n_tanks += 1
	for t in mb.tanks:
		if t.contents_kg > 0.0:
			t.contents_kg = maxf(t.contents_kg - burn / n_tanks, 0.0)
	if int(time / dt) % 120 == 0:
		mb.update()
	engine.fuel_ok = mb.fuel_kg() > cfg.unusable_fuel_kg
