extends RefCounted
## Test-only control laws of tests/play_landing.gd: a student pilot who only holds / releases keys
## (Input.parse_input_event) and decides every TICK seconds from what can be seen in the cockpit.
## Pitch holds speed, power holds the 3 degree path, trim takes the pressure off, flaps by distance,
## the flare is a sink-rate hold, then nose down and brakes.

const TICK := 0.1
const KEYS := {"pitch_up": KEY_DOWN, "pitch_down": KEY_UP, "roll_left": KEY_LEFT, "roll_right": KEY_RIGHT,
	"yaw_left": KEY_Z, "yaw_right": KEY_X, "throttle_up": KEY_PAGEUP, "throttle_down": KEY_PAGEDOWN,
	"trim_up": KEY_END, "trim_down": KEY_HOME, "brakes": KEY_B}
const WHEEL_FT := 3.5   # fdm/agl reads this much with the wheels on the ground

## Gains (tuning hooks: --p_<name>=value on the command line).
var P := {"v_kp": 0.15, "v_ki": 0.012, "pit_max": 3.0, "stk_kp": 0.03, "stk_kd": 0.05, "flare_h": 30.0, "fl_slope": 13.0, "line_k": 0.1, "line_i": 0.004, "bank_k": 2.0, "roll_kp": 0.05, "rud_kp": 0.04, "rud_kd": 0.03,
	"thr_kp": 0.0003, "thr_ki": 0.00008, "fl_ki": 0.002, "fl_kp": 0.004, "fl_amt": 5.0, "fl_stk_kp": 0.06}
var rwy_hdg := 0.0
var vref := 65.0
var rng: RandomNumberGenerator
var dbg := ""
var _held := {}
var _started := false
var _ias_f := 0.0
var _vs_f := 0.0
var _pitch_int := 0.0
var _thr_cmd := 0.0
var _flare_p := 0.0
var _flare_p0 := 0.0
var _flaring := false
var _stick_f := 0.0
var _trim_t := 0.0
var _cross_i := 0.0
var _flaps_t := -99.0
var _td_t := -1.0


func _key(action: String, down: bool) -> void:
	if _held.get(action, false) == down:
		return
	_held[action] = down
	var e := InputEventKey.new()
	e.keycode = KEYS[action]
	e.physical_keycode = KEYS[action]
	e.pressed = down
	Input.parse_input_event(e)


func release_all() -> void:
	for k in KEYS:
		_key(k, false)


func is_held(action: String) -> bool:
	return _held.get(action, false)


## Hold the key pair so a rate-based control moves towards `target` (dead band db).
func _axis(cur: float, target: float, pos: String, neg: String, db := 0.03) -> void:
	_key(pos, target - cur > db)
	_key(neg, cur - target > db)


## One decision from the snapshot s (training_session._snapshot) at time t.
func decide(s: Dictionary, t: float) -> void:
	var wow: bool = s.wow > 0.5
	var ias_read: float = s.ias + rng.randfn(0.0, 0.5)  # reading an airspeed needle
	if not _started:
		_started = true
		_ias_f = ias_read
		_vs_f = s.vs
		_pitch_int = s.pitch
		_thr_cmd = s.throttle
	_ias_f = lerpf(_ias_f, ias_read, 0.15)
	_vs_f = lerpf(_vs_f, s.vs, 0.3)
	_flaps(s, t)
	if wow:
		if _td_t < 0.0:
			_td_t = t
		_rollout(s, t)
		return
	_throttle(s)
	_pitch(s)
	_lateral(s)


func _flaps(s: Dictionary, t: float) -> void:
	var fl := int(s.flaps)
	if t - _flaps_t < 4.0 or s.wow > 0.5:
		return
	var want := 0
	if s.along > -4600.0:
		want = 1
	if s.along > -3600.0 and _ias_f < 90.0:
		want = 2
	if s.along > -2200.0 and _ias_f < 80.0:
		want = 3
	if want > fl and (fl == 0 or _ias_f < 100.0):
		_flaps_t = t
		Props.set_v("controls/flaps", fl + 1)  # the flap key (injected press events do not reach its handler headless)
		print("PLAY flaps -> %d at ias %.0f along %.0f" % [fl + 1, _ias_f, s.along])


func _v_target(s: Dictionary) -> float:
	var f := int(s.flaps)
	if f >= 3:
		return vref + 3.0 if s.along < -700.0 else vref
	return [80.0, 75.0, 70.0][f]


func _throttle(s: Dictionary) -> void:
	var h := maxf(s.agl - WHEEL_FT, 0.0)
	var tgt := 0.0
	if h > 30.0 or s.along < -300.0 and h > 12.0:
		# power holds the path: the descent rate that keeps the 3 degree line, more when above it
		var vs_des := clampf(-s.gs * 5.3 - 250.0 * s.gp_dev, -450.0 if h < 100.0 else -650.0, -100.0)
		var err := vs_des - _vs_f
		_thr_cmd = clampf(_thr_cmd + P.thr_ki * err * TICK, 0.0, 0.85)
		tgt = clampf(_thr_cmd + P.thr_kp * err, 0.0, 0.85)
	else:
		_thr_cmd = 0.0  # close the throttle for the flare
	_axis(s.throttle, tgt, "throttle_up", "throttle_down", 0.02)


func _pitch(s: Dictionary) -> void:
	var h := maxf(s.agl - WHEEL_FT, 0.0)
	var q_deg: float = rad_to_deg(Props.get_v("fdm/body_rates", Vector3.ZERO).y)
	var pitch_tgt: float
	var kp: float = P.stk_kp
	if h < P.flare_h and s.along > -300.0:
		if not _flaring:
			_flaring = true
			_flare_p = 0.0
			_flare_p0 = s.pitch
		# the flare: the nose comes up as the ground comes up (a picture that depends on height), and the
		# sink rate is watched: too fast a sink pulls a little more
		var vs_tgt := -clampf(h * P.fl_slope, 70.0, 400.0)
		var err := vs_tgt - _vs_f
		var frac := clampf((P.flare_h - h) / (P.flare_h - 2.0), 0.0, 1.0)
		_flare_p = clampf(_flare_p + P.fl_ki * err * TICK, -2.0, 4.0)
		pitch_tgt = clampf(lerpf(_flare_p0, P.fl_amt, frac) + _flare_p + P.fl_kp * err, -3.0, 10.0)
		kp = P.fl_stk_kp
	else:
		# fly the attitude: the speed error picks the pitch, the stick holds it, trim holds the stick
		var verr := _ias_f - _v_target(s)
		_pitch_int = clampf(_pitch_int + P.v_ki * verr * TICK, -12.0, 8.0)
		pitch_tgt = clampf(_pitch_int + P.v_kp * verr, _pitch_int - P.pit_max, _pitch_int + P.pit_max)
	var stick_tgt := clampf(kp * (pitch_tgt - s.pitch) - P.stk_kd * q_deg, -0.4, 0.7)
	_stick_f = lerpf(_stick_f, stick_tgt, 0.07)
	dbg = "ptgt %+.1f stk %+.2f" % [pitch_tgt, stick_tgt]
	_axis(s.pitch_in, stick_tgt, "pitch_up", "pitch_down")
	if h > 60.0 and absf(_stick_f) > 0.04:  # trim off the pressure that has been held a while
		_trim_t += TICK
	else:
		_trim_t = 0.0
	var trimming := _trim_t > 1.0
	_key("trim_up", trimming and _stick_f > 0.0)
	_key("trim_down", trimming and _stick_f < 0.0)


func _lateral(s: Dictionary) -> void:
	var h := maxf(s.agl - WHEEL_FT, 0.0)
	var track := fposmod(rad_to_deg(Props.get_f("fdm/track_rad")), 360.0)
	# hold the runway line: track the extended centreline, offset towards it when beside it
	_cross_i = clampf(_cross_i + s.cross * TICK * P.line_i, -4.0, 4.0)
	var want_trk := rwy_hdg - clampf(s.cross * P.line_k + _cross_i, -10.0, 10.0)
	var trk_err := wrapf(want_trk - track, -180.0, 180.0)
	var bank_tgt := clampf(P.bank_k * trk_err, -15.0, 15.0)
	var p_deg: float = rad_to_deg(Props.get_v("fdm/body_rates", Vector3.ZERO).x)
	var stick := clampf(P.roll_kp * (bank_tgt - s.bank) - 0.012 * p_deg, -0.5, 0.5)
	var roll_now := Props.get_f("controls/roll")
	_axis(roll_now, stick, "roll_right", "roll_left")
	var hdg_err := wrapf(rwy_hdg - s.hdg, -180.0, 180.0)
	# feet follow the hands; just above the runway they take the crab out
	var yaw := clampf(roll_now * 0.5, -0.4, 0.4) if h > 15.0 else clampf(hdg_err * 0.05, -0.5, 0.5)
	_axis(Props.get_f("controls/yaw"), yaw, "yaw_right", "yaw_left", 0.05)


func _rollout(s: Dictionary, t: float) -> void:
	for k in ["throttle_up", "trim_up", "trim_down"]:
		_key(k, false)
	_key("throttle_down", true)
	var since := t - _td_t
	# a little back pressure while the speed is high, then let the nose come down
	var stick_tgt := 0.2 if (_ias_f > 45.0 and since < 4.0) else 0.0
	_axis(s.pitch_in, stick_tgt, "pitch_up", "pitch_down")
	# wings level with the aileron (into the wind), the nose straight with the rudder, damped
	var rates: Vector3 = Props.get_v("fdm/body_rates", Vector3.ZERO)
	var ail := clampf(P.roll_kp * (0.0 - s.bank) - 0.012 * rad_to_deg(rates.x), -0.5, 0.5)
	_axis(Props.get_f("controls/roll"), ail, "roll_right", "roll_left")
	var hdg_err := wrapf(rwy_hdg - s.hdg, -180.0, 180.0)
	var yaw := clampf(P.rud_kp * hdg_err - 0.01 * s.cross * 0.5 + P.rud_kd * rad_to_deg(rates.z) * -1.0, -1.0, 1.0)
	_axis(Props.get_f("controls/yaw"), yaw, "yaw_right", "yaw_left", 0.05)
	_key("brakes", _ias_f < 40.0 and s.pitch < 3.0)
