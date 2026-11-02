class_name FDM
extends RefCounted
## 6-DOF rigid-body flight model, flat earth over the world ENU frame.
## State: position NED (north = ENU y, east = ENU x, down = -alt) in 64-bit
## floats, body velocity/rates, attitude quaternion (body -> NED).
## Body axes: x forward, y right, z down. Everything SI except inside Aero.

const G := 9.80665
const LBF := 4.4482216
const LBF_FT := 1.3558179

var def: AircraftDef
var cfg: Dictionary
var atmo := AtmosphereISA.new()
var mb: MassBalance
var aero: Aero
var units: Array[PowerUnit] = []  # every engine with its thruster (PowerUnit)
var engine: Powerplant  # engine 1 (units[0]); the single engine of most aircraft
var prop: Thruster  # its propeller / jet
var gear: GearGround
var fcs: FlightControls
var ground_height: Callable = func(_n: float, _e: float) -> float: return 0.0
var surface: Callable = func(_n: float, _e: float) -> int: return 0  # land class (255 = water)
## Solids near a point: (east, north, radius, alt_lo, alt_hi) -> Array of ObstacleShapes records.
var obstacles: Callable = func(_e: float, _n: float, _r: float, _lo: float, _hi: float) -> Array: return []
var in_corridor: Callable = func(_e: float, _n: float) -> bool: return false  # on a taxiway / runway (see ObstacleCollision)
var obstacle_collision: ObstacleCollision
var damage: Damage

# state
var pos_n := 0.0
var pos_e := 0.0
var pos_d := 0.0
var v_b := Vector3.ZERO
var w_b := Vector3.ZERO
var q := Quaternion.IDENTITY
var wind_ned := Vector3.ZERO  # air mass velocity (m/s, NED)
var tank_feed := PackedFloat64Array()  # share of the fuel flow drawn from each tank (fuel system), sums to 1
var tank_leak_kgs := PackedFloat64Array()  # kg/s each tank loses to a leak
var fuel_available := true
var extra_burn_kgs := 0.0  # fuel burnt outside the engines (APU), kg/s, set by its system
var time := 0.0

# derived (updated every step)
var alpha := 0.0
var beta := 0.0
var vt := 0.0  # true airspeed
var cas := 0.0
var qbar := 0.0
var mach := 0.0
var agl := 0.0
var load_factor := 1.0  # total (what the pilot feels, incl. ground contact)
var flight_load_factor := 1.0  # aerodynamic + thrust only (structural flight limits)
var accel_b := Vector3.ZERO  # specific force (what an accelerometer feels), body
var _alpha_prev := 0.0
var _alphadot := 0.0
var _aero_rp: Vector3


## The aircraft in `aircraft` (null: the one chosen on the start screen, Session.setup.aircraft).
func _init(aircraft: AircraftDef = null) -> void:
	def = aircraft if aircraft else AircraftDef.current()
	cfg = def.config()
	mb = MassBalance.new(cfg)
	aero = Aero.new(def.path("aero"), cfg.metrics)
	units = PowerUnit.from_config(cfg, def.section("damage").get("prop_hubs_m", []))
	engine = units[0].engine
	prop = units[0].thruster
	gear = Gears.make(cfg)
	fcs = AirlinerControls.new(cfg) if cfg.controls.flaps is Dictionary else FlightControls.new(cfg)
	fcs.law = FbwLaw.for_def(def) if fcs is AirlinerControls else null  # aircraft.json "fcs"; null = direct control
	damage = Damage.new(def)
	obstacle_collision = ObstacleCollision.new(def)
	var a: Array = cfg.metrics.aero_ref_pt_m
	_aero_rp = Vector3(a[0], a[1], a[2])
	tank_feed.resize(mb.tanks.size())
	tank_feed = _default_feed()
	tank_leak_kgs.resize(mb.tanks.size())


## Equal share per tank, except fuel-line "pipe" tanks (capacity < 1 % of the total): plumbing, no supply.
func _default_feed() -> PackedFloat64Array:
	var feed := PackedFloat64Array()
	feed.resize(mb.tanks.size())
	var total := 0.0
	for t in mb.tanks:
		total += t.capacity_kg
	var n := 0
	for i in feed.size():
		feed[i] = 0.0 if mb.tanks[i].capacity_kg < 0.01 * total else 1.0
		n += 1 if feed[i] > 0.0 else 0
	for i in feed.size():
		feed[i] = feed[i] / maxf(n, 1.0) if n > 0 else 1.0 / maxf(feed.size(), 1.0)
	return feed


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


## Start airborne, wings level, at a given true airspeed through the air mass
## (wind_ned is added, so the start is not a sudden gust when there is wind).
func set_airborne(n: float, e: float, alt: float, heading: float, tas: float, pitch := 0.03) -> void:
	pos_n = n; pos_e = e; pos_d = -alt
	q = euler_to_quat(0.0, pitch, heading)
	v_b = Vector3(tas * cos(pitch), 0.0, tas * sin(pitch)) + Basis(q).transposed() * wind_ned
	w_b = Vector3.ZERO
	_alpha_prev = pitch
	fcs.settle()
	fcs.restart_law()


## Trim for steady level flight at the current position/heading (see trim.gd).
func trim_level(tas: float) -> void:
	var law := fcs.law  # trim on direct control, then the law continues from the trimmed surfaces
	fcs.law = null
	Trim.trim_level(self, tas)
	fcs.law = law
	fcs.restart_law()


## Trim for level flight at a calibrated airspeed (iterates TAS; atmosphere and wind as set).
func trim_level_cas(cas_target: float) -> void:
	var tas := cas_target
	for i in 3:
		trim_level(tas)
		step(1e-4)
		tas *= cas_target / maxf(cas, 1.0)
		set_airborne(pos_n, pos_e, -pos_d, euler().z, tas)
	trim_level(tas)


## Start at rest on the ground in the natural sitting attitude (all wheels touching).
func set_on_ground(n: float, e: float, heading: float) -> void:
	pos_n = n; pos_e = e
	var wheels: Array = gear.contacts.filter(func(c): return c.wheel)
	var steered: Array = gear.steered_wheels()
	var mains: Array = gear.main_wheels()
	if steered.is_empty() or mains.is_empty():  # a castoring wheel or a single gear line: lie level
		steered = [wheels[0]]
		mains = [wheels[-1]]
	var bn := mb.body_of(steered[0].pos)
	var bm := Vector3.ZERO
	for c in mains:
		bm += mb.body_of(c.pos) / mains.size()
	# sit with both wheel lines at the same height: dz * cos(pitch) = dx * sin(pitch) (nose or tailwheel)
	var pitch := atan((bn.z - bm.z) / (bn.x - bm.x)) if absf(bn.x - bm.x) > 1e-3 else 0.0
	q = euler_to_quat(0.0, pitch, heading)
	var r_bn := Basis(q)
	var low := -INF
	for c in wheels:
		low = maxf(low, (r_bn * mb.body_of(c.pos)).z)
	pos_d = -ground_height.call(n, e) - low + 0.005
	v_b = Vector3.ZERO
	w_b = Vector3.ZERO
	fcs.settle()
	fcs.restart_law()


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

	if damage.flaps_jammed:
		fcs.flaps_powered = false
	fcs.bank = euler().x
	fcs.airborne = not gear.wow
	_airliner_inputs()
	gear.prepare(dt, self)
	if fcs.law != null:
		fcs.law.update(dt, self)
	fcs.update(dt)
	gear.steer_cmd = fcs.yaw
	var v_induced := 0.0
	for u in units:
		u.engine.on_ground = gear.wow
		u.update(dt, atmo, v_air.x, vt)
		v_induced += u.thruster.v_induced / units.size()

	# --- aerodynamics (wind axes -> body), moments about the aero ref point
	var res: Array = aero.evaluate({
		"vt": vt, "alpha": alpha, "alphadot": _alphadot, "beta": beta, "qbar": qbar,
		"agl": maxf(agl, 0.0), "rho": atmo.density, "u": v_air.x,
		"p": w_b.x, "q": w_b.y, "r": w_b.z, "v_induced": v_induced,
		"elevator": fcs.elevator, "aileron": fcs.aileron, "rudder": fcs.rudder, "flap_deg": fcs.flap_deg,
		"mach": mach, "temperature": atmo.temperature, "ctx": fcs.aero_ctx()})
	var fw: Vector3 = res[0] * LBF  # (D, Y, L)
	var ca := cos(alpha); var sa := sin(alpha); var cb := cos(beta); var sb := sin(beta)
	var f_aero := Vector3(
		-fw.x * ca * cb - fw.y * ca * sb + fw.z * sa,
		-fw.x * sb + fw.y * cb,
		-fw.x * sa * cb - fw.y * sa * sb - fw.z * ca)
	var m_aero: Vector3 = res[1] * LBF_FT + mb.body_of(_aero_rp).cross(f_aero)

	# --- propulsion (every engine: thrust at its own point, reaction torque, gyroscopic momentum)
	var f_thr := Vector3.ZERO
	var m_thr := Vector3.ZERO
	var h_prop := 0.0
	for u in units:
		var th := u.thruster
		var po := th.p_factor_offset(v_air.x, v_air.y, v_air.z)
		var r_eng := mb.body_of(u.pos) + Vector3(0.0, po.x, po.y)
		var f_u := u.thrust_dir * th.thrust
		f_thr += f_u
		m_thr += r_eng.cross(f_u) + Vector3(-th.sense * th.torque, 0.0, 0.0)
		h_prop += th.angular_momentum()

	# --- ground
	var gr: Array = gear.compute(mb, r_bn, Vector3(pos_n, pos_e, pos_d), v_b, w_b,
		func(n: float, e: float) -> float: return ground_height.call(n, e))
	damage.update(self, dt, gear.info, surface)
	if not damage.crashed:
		var hit := obstacle_collision.check(self)
		if not hit.is_empty():
			damage._crash(ObstacleCollision.reason(hit, self))
	var f_ext: Vector3 = f_aero + f_thr + gr[0]
	var m_tot: Vector3 = m_aero + m_thr + gr[1]
	var f_grav := r_nb * Vector3(0.0, 0.0, G * mb.mass)

	# --- rigid body integration (semi-implicit Euler)
	accel_b = f_ext / mb.mass
	load_factor = -accel_b.z / G
	flight_load_factor = -(f_aero + f_thr).z / (mb.mass * G)
	var a_b := (f_ext + f_grav) / mb.mass - w_b.cross(v_b)
	var h := mb.inertia * w_b + Vector3(h_prop, 0.0, 0.0)
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


## What the airliner controls and gear need from the rest of the FDM (nothing for fixed-gear aircraft).
func _airliner_inputs() -> void:
	if not fcs is AirlinerControls:
		return
	var vn := velocity_ned()
	fcs.ground_speed = Vector2(vn.x, vn.y).length()
	var idle := true
	for i in units.size():
		var e := units[i].engine
		var lever: float = e.lever if e is EngineTurbineFadec else e.throttle
		fcs.thrust_lever[i] = lever
		idle = idle and lever <= 0.05
	fcs.thrust_idle = idle


## All engines' throttle levers to one position (trim, tests).
func set_throttle(x: float) -> void:
	for u in units:
		u.engine.throttle = x


func _burn_fuel(dt: float) -> void:
	var burn := extra_burn_kgs
	for u in units:
		burn += u.engine.fuel_flow_kgs
	burn *= dt
	for i in mb.tanks.size():
		var t: Dictionary = mb.tanks[i]
		t.contents_kg = maxf(t.contents_kg - burn * tank_feed[i] - tank_leak_kgs[i] * dt, 0.0)
	if int(time / dt) % 120 == 0:
		mb.update()
	var ok := fuel_available and mb.fuel_kg() > 0.0
	for u in units:
		u.engine.fuel_ok = ok
