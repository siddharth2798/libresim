class_name ReplayChannels
extends RefCounted
## What a replay frame records and how it is played back. Two groups of float32
## channels: FDM state (read directly by the 3-D model, gyros, compass and camera)
## and Props (read by gauges, audio, lights, moving map). The Props lists were
## derived by grepping what aircraft/, ui/gauges, ui/hud.gd, instruments/ and
## avionics/ read. A prop that did not exist when recorded is stored as NaN and
## left alone on playback.

## FDM state: q (4), v_ned (3), w_b (3), accel_b (3), then scalars.
const S_Q := 0
const S_V := 4
const S_W := 7
const S_A := 10
const S_SCALARS := ["elevator", "aileron", "rudder", "flap_deg", "alpha", "beta", "vt", "cas", "agl", "load_factor"]
const S_SC := 13
const N_STATE := 23

const P_LERP := [
	"fdm/tas_mps", "fdm/cas_mps", "fdm/groundspeed_mps", "fdm/vs_mps", "fdm/alt_m", "fdm/agl_m",
	"fdm/alpha_rad", "fdm/beta_rad", "fdm/load_factor", "fdm/flap_deg", "fdm/mass_kg",
	"engine/rpm", "engine/map_pa", "engine/fuel_flow_kgs", "engine/egt_k", "engine/cht_k",
	"engine/oil_temp_k", "engine/oil_press_pa", "engine/power_w", "engine/thrust_n",
	"fuel/total_kg", "fuel/left_kg", "fuel/right_kg",
	"controls/pitch", "controls/roll", "controls/yaw", "controls/throttle", "controls/mixture",
	"controls/pitch_trim", "controls/brake_left", "controls/brake_right",
	"instruments/asi_kt", "instruments/altimeter_ft", "instruments/vsi_fpm",
	"instruments/ai/pitch_rad", "instruments/tc_rate", "instruments/tc_ball",
	"instruments/tach_rpm", "instruments/oil_temp_f", "instruments/oil_press_psi", "instruments/egt_f",
	"instruments/fuel_flow_gph", "instruments/fuel_left_gal", "instruments/fuel_right_gal",
	"instruments/suction_inhg", "instruments/ammeter_a", "instruments/altimeter/kollsman_inhg",
	"systems/vacuum/suction_inhg", "systems/electrical/battery_amps", "systems/electrical/bus_volts",
	"systems/pitot_static/pitot_pa", "systems/pitot_static/static_pa",
	"avionics/nav1/cdi", "avionics/nav1/gs", "avionics/nav1/dme_nm", "avionics/nav2/cdi", "avionics/nav2/gs",
	"avionics/gps/dist_nm", "avionics/gps/ete",
]
const P_ANG_RAD := ["fdm/roll_rad", "fdm/pitch_rad", "fdm/heading_rad", "fdm/track_rad", "instruments/ai/roll_rad"]
const P_ANG_DEG := ["instruments/hi_deg", "instruments/compass_deg", "avionics/adf/bearing_deg", "avionics/gps/brg_mag"]
const P_BOOL := [
	"fdm/wow", "fdm/stall_warning", "engine/running", "controls/starter", "controls/parking_brake",
	"controls/lights/beacon", "controls/lights/nav", "controls/lights/strobe", "controls/lights/taxi", "controls/lights/landing",
	"controls/electrical/master_bat", "controls/electrical/master_alt", "controls/electrical/avionics",
	"systems/electrical/powered", "systems/electrical/avionics_powered", "systems/electrical/gauges_powered",
	"systems/electrical/tc_powered", "systems/electrical/low_volts", "systems/electrical/flap_motor_running",
	"instruments/ai/flag", "instruments/tc_flag",
	"avionics/nav1/valid", "avionics/nav1/gs_valid", "avionics/nav2/valid", "avionics/nav2/gs_valid", "avionics/adf/valid",
]
const P_INT := ["controls/flaps", "controls/magnetos", "avionics/nav1/to_from", "avionics/nav2/to_from"]

var keys: Array[String] = []  # prop keys in channel order (after the state block)
var key_kinds := PackedByteArray()  # 0 float, 1 bool, 2 int
var kinds := PackedByteArray()  # buffer interpolation kinds, all channels


func _init() -> void:
	for i in N_STATE:
		kinds.append(ReplayBuffer.K_LERP)
	kinds[S_Q] = ReplayBuffer.K_QUAT
	for i in 3:
		kinds[S_Q + 1 + i] = ReplayBuffer.K_QUAT_REST
	_add(P_LERP, ReplayBuffer.K_LERP, 0)
	_add(P_ANG_RAD, ReplayBuffer.K_ANG_RAD, 0)
	_add(P_ANG_DEG, ReplayBuffer.K_ANG_DEG, 0)
	_add(P_BOOL, ReplayBuffer.K_STEP, 1)
	_add(P_INT, ReplayBuffer.K_STEP, 2)


func _add(list: Array, kind: int, vtype: int) -> void:
	for k in list:
		keys.append(k)
		key_kinds.append(vtype)
		kinds.append(kind)


func count() -> int:
	return kinds.size()


## Current FDM state + Props as one channel row.
func capture(f: FDM) -> PackedFloat32Array:
	var c := PackedFloat32Array()
	c.resize(kinds.size())
	var q := f.q
	c[S_Q] = q.x; c[S_Q + 1] = q.y; c[S_Q + 2] = q.z; c[S_Q + 3] = q.w
	_put3(c, S_V, f.velocity_ned())
	_put3(c, S_W, f.w_b)
	_put3(c, S_A, f.accel_b)
	var sc := [f.fcs.elevator, f.fcs.aileron, f.fcs.rudder, f.fcs.flap_deg, f.alpha, f.beta, f.vt, f.cas, f.agl, f.load_factor]
	for i in sc.size():
		c[S_SC + i] = sc[i]
	for i in keys.size():
		var v: Variant = Props.get_v(keys[i])
		c[N_STATE + i] = NAN if v == null else float(v)
	return c


## Put a recorded frame into the FDM object (position, attitude, rates, surfaces,
## prop rpm), so everything that reads the FDM directly follows the replay.
func apply_state(fr: Dictionary, f: FDM) -> void:
	var c: PackedFloat32Array = fr.ch
	var p: PackedFloat64Array = fr.pos
	f.pos_e = p[0]
	f.pos_n = p[1]
	f.pos_d = -p[2]
	f.q = Quaternion(c[S_Q], c[S_Q + 1], c[S_Q + 2], c[S_Q + 3]).normalized()
	f.v_b = Basis(f.q).transposed() * _get3(c, S_V)
	f.w_b = _get3(c, S_W)
	f.accel_b = _get3(c, S_A)
	f.fcs.elevator = c[S_SC]
	f.fcs.aileron = c[S_SC + 1]
	f.fcs.rudder = c[S_SC + 2]
	f.fcs.flap_deg = c[S_SC + 3]
	f.alpha = c[S_SC + 4]
	f.beta = c[S_SC + 5]
	f.vt = c[S_SC + 6]
	f.cas = c[S_SC + 7]
	f.agl = c[S_SC + 8]
	f.load_factor = c[S_SC + 9]
	var rpm: Variant = prop_value(c, "engine/rpm")
	if rpm != null:
		f.prop.rpm = rpm
	var run: Variant = prop_value(c, "engine/running")
	if run != null:
		f.engine.running = run


## Write the recorded Props (plus the vector props derived from the state).
func apply_props(fr: Dictionary) -> void:
	var c: PackedFloat32Array = fr.ch
	for i in keys.size():
		var x: float = c[N_STATE + i]
		if is_nan(x):
			continue
		match key_kinds[i]:
			0: Props.set_v(keys[i], x)
			1: Props.set_v(keys[i], x >= 0.5)
			2: Props.set_v(keys[i], int(roundf(x)))
	var p: PackedFloat64Array = fr.pos
	Props.set_v("fdm/position_enu", Vector3(p[0], p[1], p[2]))
	Props.set_v("fdm/body_rates", _get3(c, S_W))
	Props.set_v("fdm/accel_body", _get3(c, S_A))


## A recorded prop's value with its type (null if it was not recorded / absent).
func prop_value(c: PackedFloat32Array, key: String) -> Variant:
	var i := keys.find(key)
	if i < 0 or is_nan(c[N_STATE + i]):
		return null
	var x: float = c[N_STATE + i]
	match key_kinds[i]:
		1: return x >= 0.5
		2: return int(roundf(x))
	return x


static func velocity_ned(c: PackedFloat32Array) -> Vector3:
	return _get3(c, S_V)


## Exact copy of the FDM fields apply_state() overwrites (to return to live flight).
static func save_live(f: FDM) -> Dictionary:
	return {"n": f.pos_n, "e": f.pos_e, "d": f.pos_d, "q": f.q, "v_b": f.v_b, "w_b": f.w_b,
		"accel_b": f.accel_b, "el": f.fcs.elevator, "ail": f.fcs.aileron, "rud": f.fcs.rudder,
		"flap": f.fcs.flap_deg, "alpha": f.alpha, "beta": f.beta, "vt": f.vt, "cas": f.cas,
		"agl": f.agl, "nz": f.load_factor, "rpm": f.prop.rpm, "running": f.engine.running}


static func restore_live(f: FDM, s: Dictionary) -> void:
	f.pos_n = s.n; f.pos_e = s.e; f.pos_d = s.d
	f.q = s.q; f.v_b = s.v_b; f.w_b = s.w_b; f.accel_b = s.accel_b
	f.fcs.elevator = s.el; f.fcs.aileron = s.ail; f.fcs.rudder = s.rud; f.fcs.flap_deg = s.flap
	f.alpha = s.alpha; f.beta = s.beta; f.vt = s.vt; f.cas = s.cas; f.agl = s.agl
	f.load_factor = s.nz; f.prop.rpm = s.rpm; f.engine.running = s.running


static func _put3(c: PackedFloat32Array, o: int, v: Vector3) -> void:
	c[o] = v.x; c[o + 1] = v.y; c[o + 2] = v.z


static func _get3(c: PackedFloat32Array, o: int) -> Vector3:
	return Vector3(c[o], c[o + 1], c[o + 2])
