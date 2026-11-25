class_name AfPreview
extends RefCounted
## FCU values turned but not yet pulled or pushed, shown in their window for a while (systems/autoflight_logic.gd feeds it
## once a tick; ap/{vs, hdg, spd}_preset tell ui/displays/fcu_windows.gd to show the value instead of dashes):
##   V/S  turned outside V/S mode: the target is stored for VS_S, a pull flies it (Airbus Safety First, V/S-FPA preselection:
##        45 s on the A320 family). After that the window is dashes again and a pull flies the present vertical speed.
##   HDG  turned while managed (NAV): the heading shows for HDG_S, then dashes + dot return.
##   SPD  turned while managed: the speed shows for SPD_S, then dashes + dot return.
## HDG_S and SPD_S come from the FlyByWire A32NX documentation only (UNVERIFIED against the Airbus FCOM, docs/A320-FCU-REFERENCE.md).
## A pull (selected) or a push (managed again) ends the preview of that window; a turn restarts it.

const VS_S := 45.0
const HDG_S := 45.0
const SPD_S := 10.0

var vs := 0.0  # s left
var hdg := 0.0
var spd := 0.0
var _last := {}  # FCU values of the previous tick


func reset() -> void:
	vs = 0.0
	hdg = 0.0
	spd = 0.0
	_last = {}


## `vs_mode` = the vertical mode is V/S (the window shows the flown target then, no preview needed).
func update(i: AfInputs, vs_mode: bool) -> void:
	var f := i.f
	if _last.is_empty():
		_last = {"vs": f.vs, "hdg": f.hdg, "spd": f.spd}
	if vs_mode:
		vs = 0.0
	elif absf(f.vs - _last.vs) > 0.01:
		vs = VS_S
	else:
		vs = maxf(vs - i.dt, 0.0)
	hdg = _managed(hdg, bool(f.hdg_mgd), absf(wrapf(f.hdg - _last.hdg, -PI, PI)) > 1.0e-4, HDG_S, i.dt)
	spd = _managed(spd, bool(f.spd_mgd), absf(f.spd - _last.spd) > 1.0e-3, SPD_S, i.dt)
	_last = {"vs": f.vs, "hdg": f.hdg, "spd": f.spd}


static func _managed(left: float, managed: bool, turned: bool, secs: float, dt: float) -> float:
	if not managed:
		return 0.0
	return secs if turned else maxf(left - dt, 0.0)
