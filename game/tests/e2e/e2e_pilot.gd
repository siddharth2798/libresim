extends Node
## Minimal test autopilot for the E2E sweep: PD(+I) loops from attitude targets to
## controls/pitch, roll, yaw. A scenario sets `active`, the targets, or a `guide`
## callable (called every physics tick before the loops, to update the targets).
## Not a real autopilot: just enough to fly scripted takeoffs and approaches.

var active := false
var pitch_tgt := 0.0  # deg
var roll_tgt := 0.0  # deg
var hdg_tgt := -1.0  # deg true; >= 0: rudder steers to it on the ground
var guide: Callable  # func(dt) -> void, may change the targets / throttle / brakes
var _pi := 0.0
var _prev_pitch := 0.0
var _prev_roll := 0.0


func pitch_deg() -> float:
	return rad_to_deg(Props.get_f("fdm/pitch_rad"))


func roll_deg() -> float:
	return rad_to_deg(Props.get_f("fdm/roll_rad"))


func _physics_process(dt: float) -> void:
	if not active or dt <= 0.0:
		return
	if guide.is_valid():
		guide.call(dt)
	var pd := pitch_deg()
	var rd := roll_deg()
	var q := (pd - _prev_pitch) / dt
	var pr := (rd - _prev_roll) / dt
	_prev_pitch = pd
	_prev_roll = rd
	var e := pitch_tgt - pd
	_pi = clampf(_pi + 0.02 * e * dt, -0.6, 0.6)
	Props.set_v("controls/pitch", clampf(0.07 * e - 0.025 * q + _pi, -1.0, 1.0))
	Props.set_v("controls/roll", clampf(0.045 * (roll_tgt - rd) - 0.012 * pr, -1.0, 1.0))
	if hdg_tgt >= 0.0 and Props.get_b("fdm/wow"):
		var h := rad_to_deg(Props.get_f("fdm/heading_rad"))
		var r: Vector3 = Props.get_v("fdm/body_rates", Vector3.ZERO)
		var he := wrapf(hdg_tgt - h, -180.0, 180.0)
		Props.set_v("controls/yaw", clampf(0.12 * he - 0.6 * rad_to_deg(r.z) * 0.05, -1.0, 1.0))
	else:
		Props.set_v("controls/yaw", 0.0)


## Roll target that flies a track toward `want_trk` (deg true), limited bank.
func bank_for_track(want_trk: float, limit := 20.0) -> float:
	var trk := rad_to_deg(Props.get_f("fdm/track_rad"))
	return clampf(2.0 * wrapf(want_trk - trk, -180.0, 180.0), -limit, limit)
