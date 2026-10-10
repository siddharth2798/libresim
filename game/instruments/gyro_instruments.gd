class_name GyroInstruments
extends Node
## Vacuum gyros and the electric turn coordinator.
## Attitude indicator: the gyro holds a reference "down" vector fixed in space;
##   an erection mechanism (~3 deg/min) slowly pulls it toward the apparent
##   vertical (specific force). This reproduces turn/acceleration errors
##   naturally. Low rotor speed (vacuum failure) -> erection stops, gyro wanders/tumbles.
## Heading indicator: integrates true heading with slow drift; random wander when
##   the rotor runs down. Sync knob: Props "instruments/hi/sync" (bool, UI sets).
## Turn coordinator: rate gyro canted 30 deg (senses yaw + some roll rate), plus slip ball.
## Inputs come from the FDM object directly (needs attitude quaternion).

const ERECT_RATE := deg_to_rad(3.0) / 60.0
const HI_DRIFT := deg_to_rad(4.0) / 900.0  # ~4 deg per 15 min
const SPIN_UP := 1.0 / 60.0  # fraction per second
const SPIN_DOWN := 1.0 / 240.0

var fdm: FDM
var _down := Vector3(0, 0, 1)  # gyro reference vertical, NED
var _ai_spin := 0.0
var _hi_spin := 0.0
var _hi_offset := 0.0
var _hi_drift_dir := 1.0
var _tc := 0.0
var _ball := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_hi_drift_dir = 1.0 if _rng.randf() > 0.5 else -1.0


func start_running() -> void:
	_ai_spin = 1.0
	_hi_spin = 1.0
	_down = Vector3(0, 0, 1)
	_hi_offset = _rng.randf_range(-2.0, 2.0) * PI / 180.0


func _physics_process(dt: float) -> void:
	if fdm == null:
		return
	var suction := Props.get_f("systems/vacuum/suction_inhg")
	var drive := clampf((suction - 3.0) / 1.5, 0.0, 1.0)  # rated 4.5-5.5 inHg
	var ai_drive := 0.0 if Props.get_b("failures/ai") else drive  # seized gyro: spins down, wanders
	var hi_drive := 0.0 if Props.get_b("failures/hi") else drive
	_ai_spin = move_toward(_ai_spin, ai_drive, (SPIN_UP if ai_drive > _ai_spin else SPIN_DOWN) * dt)
	_hi_spin = move_toward(_hi_spin, hi_drive, (SPIN_UP if hi_drive > _hi_spin else SPIN_DOWN) * dt)
	_attitude(dt)
	_heading(dt)
	_turn_coordinator(dt)


func _attitude(dt: float) -> void:
	var r_bn := Basis(fdm.q)
	var sf := r_bn * fdm.accel_b  # specific force, NED (points "up" in level flight)
	var app_down := (-sf).normalized() if sf.length() > 1.0 else Vector3(0, 0, 1)
	if _ai_spin > 0.6:
		var ang := _down.angle_to(app_down)
		if ang > 1e-6:
			_down = _down.slerp(app_down, minf(ERECT_RATE * dt / ang, 1.0)).normalized()
	else:
		# rotor too slow: precession wander, growing as it slows
		var wander := (1.0 - _ai_spin) * 0.15 * dt
		_down = (_down + Vector3(_rng.randfn(0, wander), _rng.randfn(0, wander), 0.0)).normalized()
	var v := r_bn.transposed() * _down  # gyro vertical in body axes
	Props.set_v("instruments/ai/pitch_rad", asin(clampf(-v.x, -1.0, 1.0)))
	Props.set_v("instruments/ai/roll_rad", atan2(v.y, v.z))
	Props.set_v("instruments/ai/flag", _ai_spin < 0.6)


func _heading(dt: float) -> void:
	if Props.get_b("instruments/hi/sync"):
		Props.set_v("instruments/hi/sync", false)
		_hi_offset = deg_to_rad(Props.get_f("instruments/compass_deg")) - fdm.euler().z
	var adj := Props.get_f("instruments/hi/adjust_deg")
	if adj != 0.0:
		_hi_offset += deg_to_rad(adj)
		Props.set_v("instruments/hi/adjust_deg", 0.0)
	var drift := HI_DRIFT * _hi_drift_dir
	if _hi_spin < 0.7:
		drift += _rng.randfn(0.0, (1.0 - _hi_spin) * 0.05)
	_hi_offset += drift * dt
	Props.set_v("instruments/hi_deg", fposmod(rad_to_deg(fdm.euler().z + _hi_offset), 360.0))


func _turn_coordinator(dt: float) -> void:
	var powered := Props.get_b("systems/electrical/tc_powered", true) and not Props.get_b("failures/tc")
	var rate := fdm.w_b.z * cos(PI / 6.0) + fdm.w_b.x * sin(PI / 6.0)
	var target := rate / deg_to_rad(3.0) if powered else 0.0  # 1.0 = standard-rate mark
	_tc = lerpf(_tc, clampf(target, -2.0, 2.0), clampf(dt * 3.0, 0.0, 1.0))
	var a := fdm.accel_b
	var ball_target := atan2(a.y, -a.z) if absf(a.z) > 0.5 else 0.0
	_ball = lerpf(_ball, clampf(ball_target / 0.25, -1.0, 1.0), clampf(dt * 4.0, 0.0, 1.0))
	Props.set_v("instruments/tc_rate", _tc)
	Props.set_v("instruments/tc_ball", _ball)
	Props.set_v("instruments/tc_flag", not powered)
