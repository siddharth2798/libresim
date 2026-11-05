extends RefCounted
## Test-only scripted A320 pilot of probe_a320_landing.gd. It writes the same Props the cockpit controls write
## (controls/pitch roll yaw, throttle(_1,_2), reverse_n, flaps, autobrake, brake_left/right) and reads only what a pilot sees
## (state dictionary of probe_a320_state.gd). Procedure: level at the start altitude until the 3 degree path comes up, then
## the path by flight-path angle (the pitch law holds the path with a neutral stick), CONF 3 at capture, CONF FULL below
## 1,900 ft, thrust holds the speed (Vapp = Vls + 5), flare at 30 ft, thrust idle at 20 ft, spoilers automatic, reverse,
## nose down, autobrake or pedals, rudder on the centreline.
## Phases: hands_off -> level -> glide -> flare -> roll -> stopped.  Options: autobrake 0..3, reverse 0 / 1 idle / 2 max.

const State := preload("res://tests/probe_a320_state.gd")
const HANDS_OFF_S := 8.0
const FLAP_CONF3 := 4
const FLAP_FULL := 5
var P := {"g_kp": 0.10, "g_slew": 1.0, "g_ki": 0.01, "f_kp": 0.22, "f_ki": 0.008, "f_ff": 0.05, "f_slew": 2.0, "v_lead": 8.0, "dec_kp": 0.15, "dec_kd": 0.2, "dec_ra": 90.0, "dev_k": 0.02, "flare_ra": 30.0, "retard_ra": 20.0,
	"fl_tau": 25.0, "fl_min": 170.0, "v_kp": 0.022, "v_ki": 0.0035, "lever_rate": 0.25, "bank_k": 1.6, "roll_kp": 0.045,
	"line_k": 0.04, "rud_kp": 0.06, "rud_kd": 0.05, "rud_cross": 0.01}

var autobrake := 2
var reverse := 1
var phase := "hands_off"
var rwy_hdg := 0.0
var lever := 0.0
var vapp := 139.0
var v_tgt := 160.0
var alt_hold_ft := 0.0
var log: Array[String] = []
var rng := RandomNumberGenerator.new()
var idle_mode := false  # --idle: CONF FULL, thrust idle, pitch holds Vapp, the steady descent angle is measured
var _stick_i := 0.0
var _lever_i := 0.0
var _ias_f := 0.0
var _ias_dot := 0.0
var _flaps_sel := 3
var _td_t := -1.0
var _nose_t := -1.0
var _cross_i := 0.0
var _rev_off := false
var _t_flaps_full := -1.0
var _g_int := 0.0
var _g_cmd := 0.0
var _g_phase := ""


func _event(t: float, text: String) -> void:
	log.append("LAND t=%6.1f %s" % [t, text])


func _write_levers(l: float) -> void:
	for k in ["throttle", "throttle_1", "throttle_2"]:
		Props.set_v("controls/" + k, l)


func _set_flaps(t: float, idx: int, s: Dictionary) -> void:
	_flaps_sel = idx
	Props.set_v("controls/flaps", idx)
	_event(t, "flaps -> %d at %.0f ft ias %.0f kt" % [idx, s.ra, s.ias])


func start(s: Dictionary) -> void:
	lever = s.lever
	_lever_i = s.lever
	_ias_f = s.ias
	alt_hold_ft = s.hw
	Props.set_v("controls/autobrake", 0)
	Props.set_v("controls/parking_brake", false)


## One decision per physics tick from the state s.
func decide(s: Dictionary, dt: float) -> void:
	var t: float = s.t
	var prev := _ias_f
	_ias_f = lerpf(_ias_f, s.ias + rng.randfn(0.0, 0.4), 1.0 - exp(-dt / 0.6))
	_ias_dot = lerpf(_ias_dot, (_ias_f - prev) / maxf(dt, 1e-3), 1.0 - exp(-dt / 2.0))
	if phase == "hands_off":
		if t >= HANDS_OFF_S:
			phase = "level"
			alt_hold_ft = s.hw
			_event(t, "pilot takes over, holding %.0f ft, %.0f kt" % [alt_hold_ft, s.ias])
		return
	if s.wow or _td_t >= 0.0:  # after the first touch the pilot stays in the landing roll, a skip included
		_ground(s, dt)
		return
	if idle_mode and s.ra < 1500.0 and _flaps_sel == FLAP_FULL:
		_idle(s, dt)
		return
	if phase == "level" and s.dev_ft >= -5.0:
		phase = "glide"
		_set_flaps(t, FLAP_CONF3, s)
		v_tgt = 150.0
		Props.set_v("controls/autobrake", autobrake)
		_event(t, "path captured at %.0f ft, along %.0f m, ias %.0f" % [s.hw, s.along, s.ias])
	if phase == "glide" and s.ra < P.flare_ra:
		phase = "flare"
		_event(t, "flare: ra %.1f ft, pitch %.1f, vs %.0f fpm" % [s.ra, s.pitch, s.vs])
	if phase == "glide" and _flaps_sel == FLAP_CONF3 and s.ra < 1900.0 and _ias_f < 156.0:
		_set_flaps(t, FLAP_FULL, s)
		v_tgt = vapp
		_t_flaps_full = t
	if _flaps_sel == FLAP_FULL:
		v_tgt = vapp
	_thrust(s, dt)
	_pitch(s, dt)
	_lateral(s, dt)


func _thrust(s: Dictionary, dt: float) -> void:
	var target := lever
	if phase == "flare" and s.ra <= P.retard_ra:
		target = 0.0
		_lever_i = 0.0
	else:
		var e: float = v_tgt - (_ias_f + float(P.v_lead) * _ias_dot)
		_lever_i = clampf(_lever_i + P.v_ki * e * dt, 0.0, 0.6)
		target = clampf(_lever_i + P.v_kp * e, 0.0, 0.6)
	var rate: float = P.lever_rate * (3.0 if target == 0.0 else 1.0)
	lever = move_toward(lever, target, rate * dt)
	_write_levers(lever)


func _pitch(s: Dictionary, dt: float) -> void:
	var g_tgt := 0.0
	var kp: float = P.g_kp
	var ki: float = P.g_ki
	if phase == "level":
		g_tgt = clampf((alt_hold_ft - s.hw) * 0.02, -1.0, 1.0)
	elif phase == "glide":
		g_tgt = -State.PATH_DEG - clampf(s.dev_ft * P.dev_k, -1.5, 2.0)
		if s.ra < 400.0:  # nearer the ground the path error counts less
			g_tgt = -State.PATH_DEG - clampf(s.dev_ft * P.dev_k * 0.5, -1.0, 1.0)
	else:
		var vs_tgt := -maxf(P.fl_min, P.fl_tau * s.ra)  # fpm: the ground comes up, the sink goes down
		g_tgt = rad_to_deg(atan2(vs_tgt * 0.3048 / 60.0, maxf(s.gs * 0.514444, 1.0)))
		kp = P.f_kp
		ki = P.f_ki
	if phase != _g_phase:  # a new phase starts from the path angle flown
		_g_phase = phase
		_g_cmd = s.gamma
		if phase == "flare":  # the first pull on the stick
			_stick_i += P.f_ff
	_g_cmd = move_toward(_g_cmd, g_tgt, (P.f_slew if phase == "flare" else P.g_slew) * dt)
	var err: float = _g_cmd - s.gamma
	_stick_i = clampf(_stick_i + ki * err * dt, -0.4, 0.6)
	Props.set_v("controls/pitch", clampf(kp * err + _stick_i, -0.6, 0.8))


func _lateral(s: Dictionary, dt: float) -> void:
	_cross_i = clampf(_cross_i + s.cross * dt * 0.0005, -3.0, 3.0)
	var want_trk: float = rwy_hdg - clampf(s.cross * P.line_k + _cross_i, -8.0, 8.0)
	var trk_err := wrapf(want_trk - s.trk, -180.0, 180.0)
	var bank_tgt := clampf(P.bank_k * trk_err, -15.0, 15.0)
	Props.set_v("controls/roll", clampf(P.roll_kp * (bank_tgt - s.bank), -0.6, 0.6))
	var hdg_err := wrapf(rwy_hdg - s.hdg, -180.0, 180.0)
	var yaw := 0.0
	if s.ra < P.dec_ra and (phase == "flare" or phase == "glide"):  # kick off the crab just above the runway
		yaw = clampf(P.dec_kp * hdg_err - P.dec_kd * s.r, -0.9, 0.9)
	Props.set_v("controls/yaw", yaw)


func _ground(s: Dictionary, dt: float) -> void:
	var t: float = s.t
	if _td_t < 0.0:
		_td_t = t
		phase = "roll"
		_event(t, "main gear down: ias %.0f gs %.0f pitch %.1f" % [s.ias, s.gs, s.pitch])
	if s.nose and _nose_t < 0.0:
		_nose_t = t
	lever = move_toward(lever, 0.0, 1.0 * dt)
	_write_levers(lever)
	var since := t - _td_t
	# reverse: after a moment on the ground, stowed below 60 kt
	var rev := 0.0
	if reverse > 0 and since > 1.0 and not _rev_off:
		rev = 0.1 if reverse == 1 else (1.0 if s.gs > 90.0 else 0.1)
		if s.gs < 62.0:
			_rev_off = true
			rev = 0.0
	Props.set_v("controls/reverse_1", rev)
	Props.set_v("controls/reverse_2", rev)
	# derotation: the nose comes down at about 1.5 deg/s, then neutral
	var stick := 0.0
	if s.pitch > 0.5 and not s.nose:
		stick = clampf(0.06 * (-1.5 - s.q), -0.5, 0.1)
	elif s.pitch > 0.5:
		stick = -0.1
	Props.set_v("controls/pitch", stick)
	# wings level with the aileron, centreline with rudder (then the nose wheel)
	Props.set_v("controls/roll", clampf(P.roll_kp * (0.0 - s.bank), -0.5, 0.5))
	var hdg_err := wrapf(rwy_hdg - s.hdg, -180.0, 180.0)
	var yaw_cmd: float = P.rud_kp * hdg_err - P.rud_cross * s.cross - P.rud_kd * s.r
	Props.set_v("controls/yaw", clampf(yaw_cmd, -1.0, 1.0))
	# brakes: autobrake does it; with it off, pedals once the nose wheel is down
	var brake := 0.0
	if autobrake == 0 and _nose_t >= 0.0 and t - _nose_t > 1.0:
		brake = 0.55 if s.gs > 15.0 else 0.4
	elif autobrake > 0 and s.gs < 20.0 and _nose_t >= 0.0:
		brake = 0.5  # pedals at walking speed: the autobrake is off and the idle thrust would keep the aircraft creeping
	Props.set_v("controls/brake_left", brake)
	Props.set_v("controls/brake_right", brake)
	if s.gs < 0.5 and s.t - _td_t > 5.0:
		phase = "stopped"
		Props.set_v("controls/parking_brake", true)


## Idle-thrust descent (--idle): the normal approach down to 1,500 ft, then the levers go to idle and the pitch holds Vapp.
func _idle(s: Dictionary, dt: float) -> void:
	if phase != "idle":
		phase = "idle"
		_g_int = s.gamma
		_event(s.t, "idle descent from %.0f ft at %.1f kt, fpa %.2f" % [s.ra, s.ias, s.gamma])
	lever = move_toward(lever, 0.0, 0.1 * dt)
	_write_levers(lever)
	var ve := _ias_f + 8.0 * _ias_dot - vapp  # too fast (with the trend): raise the path angle
	_g_int = clampf(_g_int + 0.04 * ve * dt, -9.0, 1.0)
	var g_tgt := clampf(_g_int + 0.5 * ve, -9.0, 1.5)
	var err: float = g_tgt - s.gamma
	_stick_i = clampf(_stick_i + P.g_ki * err * dt, -0.4, 0.6)
	Props.set_v("controls/pitch", clampf(P.g_kp * err + _stick_i, -0.6, 0.8))
	Props.set_v("controls/roll", clampf(P.roll_kp * (0.0 - s.bank), -0.6, 0.6))
