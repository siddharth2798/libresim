class_name FbwTrim
extends RefCounted
## The stabilizer (THS) command of the law. Two modes, always bumpless:
##   auto:   normal / alternate law in flight: the THS follows the elevator offset the pitch law needs, so the
##           elevator returns to neutral and releasing the stick holds the flight path (auto-trim);
##   manual: on the ground and in direct law: the trim wheel (fcs.pitch_trim) moves the THS from where it
##           was when the mode started (base), not to an absolute stop.

var _base := 0.0  # THS deg when manual mode was (re)based
var _ref := 0.0  # fcs.pitch_trim then


static func _wheel_deg(c: AirlinerControls, t: float) -> float:
	var st: SurfaceActuator = c._acts.stabilizer
	return t * st.lo if t >= 0.0 else -t * st.hi


## Manual mode starts from the current THS position and wheel setting.
func rebase(c: AirlinerControls) -> void:
	_base = c.surface("stabilizer")
	_ref = c.pitch_trim


func manual(c: AirlinerControls) -> float:
	return _base + _wheel_deg(c, c.pitch_trim) - _wheel_deg(c, _ref)


## Auto mode: `offset_deg` is the nose-up elevator the pitch law holds; nose-up THS is negative.
func auto(c: AirlinerControls, offset_deg: float, gain: float, dead_deg: float) -> float:
	rebase(c)
	var pos := c.surface("stabilizer")
	return pos if absf(offset_deg) < dead_deg else pos - gain * offset_deg
