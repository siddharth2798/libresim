class_name RetractableGear
extends GearGround
## GearGround of an aircraft with retractable gear (config gear[].retractable, A320): the lever
## (fcs.gear_cmd) drives gear_pos 0 (up) .. 1 (down) over controls.gear_transit {leg: {down_s, up_s}}
## (one travel for the whole gear, the slowest leg's times); a retractable wheel has ground contact only
## when fully down, and the lever is locked down while the wheels are loaded (WOW switch). Extra on top:
##   nose wheel: gear[].steer {tiller_deg, pedal_deg, fade_mps: [lo, hi]}; defaults for a wheel that
##     turns 30 deg or more: tiller = its max_steer_deg, pedals 6 deg, authority fading linearly from
##     full at 10 m/s to none at 36 m/s (20 -> 70 kt). angle = authority * (tiller * tiller_deg +
##     pedal * pedal_deg), `tiller` (-1..1) is set by FdmNode (controls/tiller).
##   brakes: gear[].brake_mu per wheel (base class), anti-skid (`antiskid`: off = hard braking at speed
##     skids, mu x SKID_MU) and autobrake `autobrake_mode` 0 off / 1 LO / 2 MED / 3 MAX: after touchdown
##     (WOW, ground spoilers out, thrust levers idle) or RTO it brakes for AUTOBRAKE_DECEL m/s^2
##     (MAX: full pressure); pedal pressure above PEDAL_DISARM switches it off until the mode is reselected.
## State saved with a situation: gear_pos gear_cmd gear_state door_pos.

const AUTOBRAKE_DECEL := [0.0, 1.7, 3.0, 99.0]
const PEDAL_DISARM := 0.3
const AB_GAIN := 0.3  # brake demand per (m/s^2 of deceleration error) per second
const SKID_MU := 0.6  # braking friction factor of a skidding tyre (anti-skid off)

var gear_pos := 1.0
var gear_cmd := 1
var gear_state := 1  # 0 up and locked, 1 down and locked, 2 in transit
var door_pos := 0.0  # 0..1 doors open (mid-travel)
var tiller := 0.0
var antiskid := true
var autobrake_mode := 0
var autobrake_on := false
var ground_speed := 0.0
var _down_s := 0.0
var _up_s := 0.0
var _auth := 1.0
var _ab_cmd := 0.0
var _ab_off := false  # a pedal press switched it off
var _ab_mode := 0
var _decel := 0.0
var _gs_prev := 0.0


func _init(cfg: Dictionary) -> void:
	super(cfg)
	for leg in cfg.controls.get("gear_transit", {}).values():
		_down_s = maxf(_down_s, float(leg.down_s))
		_up_s = maxf(_up_s, float(leg.up_s))
	_down_s = _down_s if _down_s > 0.0 else 10.0
	_up_s = _up_s if _up_s > 0.0 else 10.0


func prepare(dt: float, f: Object) -> void:
	var fcs: FlightControls = f.fcs
	var lever: int = fcs.get("gear_cmd") if "gear_cmd" in fcs else 1
	gear_cmd = 1 if (wow and lever == 0) else lever  # locked down on the ground
	var target := float(gear_cmd)
	gear_pos = move_toward(gear_pos, target, dt / (_down_s if target > gear_pos else _up_s))
	gear_state = 1 if gear_pos >= 1.0 else (0 if gear_pos <= 0.0 else 2)
	door_pos = clampf(6.0 * minf(gear_pos, 1.0 - gear_pos), 0.0, 1.0)
	var v: Vector3 = f.velocity_ned()
	ground_speed = Vector2(v.x, v.y).length()
	_auth = 1.0
	for c in contacts:
		if c.wheel and c.steer >= deg_to_rad(30.0) or c.steer_spec.has("fade_mps"):
			var fade: Array = c.steer_spec.get("fade_mps", [10.0, 36.0])
			_auth = clampf((fade[1] - ground_speed) / (fade[1] - fade[0]), 0.0, 1.0)
	_autobrake(dt, fcs)
	if "gear_pos" in fcs:
		fcs.gear_pos = gear_pos
		fcs.gear_cmd = gear_cmd


func _active(c: Dictionary) -> bool:
	return not c.retract or gear_pos >= 0.98


func _steer_angle(c: Dictionary) -> float:
	var sp: Dictionary = c.steer_spec
	var big: bool = c.steer >= deg_to_rad(30.0)
	var tiller_max: float = deg_to_rad(sp.get("tiller_deg", rad_to_deg(c.steer)))
	var pedal_max: float = deg_to_rad(sp.get("pedal_deg", 6.0 if big else rad_to_deg(c.steer)))
	var a := _auth if (big or sp.has("fade_mps")) else 1.0
	return clampf(a * (tiller * tiller_max + steer_cmd * pedal_max), -c.steer, c.steer)


func _brake_input(group: int) -> float:
	var b := super(group)
	return maxf(b, _ab_cmd) if group > 0 and autobrake_on else b


func _mu_braked(c: Dictionary, b: float, v_long: float) -> float:
	if not antiskid and b > 0.8 and absf(v_long) > 10.0:
		return lerpf(c.mu_roll, c.mu_brake * SKID_MU, b)
	return super(c, b, v_long)


func _autobrake(dt: float, fcs: FlightControls) -> void:
	var raw := (_gs_prev - ground_speed) / dt if dt > 0.0 else 0.0
	_gs_prev = ground_speed
	_decel = lerpf(_decel, raw, 1.0 - exp(-dt / 0.5))
	if autobrake_mode != _ab_mode:
		_ab_mode = autobrake_mode
		_ab_off = false
	var pedal := maxf(brake_left, brake_right)
	if pedal > PEDAL_DISARM and autobrake_mode > 0:
		_ab_off = true
	if autobrake_mode == 0 or _ab_off or not wow or ground_speed < 1.0:
		autobrake_on = false
		_ab_cmd = 0.0
		return
	if not autobrake_on:
		var sp: Variant = fcs.get("spoiler") if "spoiler" in fcs else []
		var out: bool = sp is Array and not sp.is_empty() and (sp as Array).max() > 25.0
		var idle: bool = fcs.get("thrust_idle") if "thrust_idle" in fcs else true
		if out and idle and ground_speed > 10.0:
			autobrake_on = true
			_decel = 0.0
		return
	var want: float = AUTOBRAKE_DECEL[clampi(autobrake_mode, 0, 3)]
	_ab_cmd = 1.0 if autobrake_mode == 3 else clampf(_ab_cmd + AB_GAIN * (want - _decel) * dt, 0.0, 1.0)
