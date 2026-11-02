class_name AfTestLaw
extends RefCounted
## TEST-ONLY stand-in for the fly-by-wire law (fdm/fbw_*.gd is written elsewhere): maps the autopilot's
## demands ap/cmd/nz_g (g increment over the flight-path hold) and ap/cmd/roll_rate_dps to the surface
## commands of AirlinerControls (fcs.cmd, degrees). Load-factor loop with a rate damper and an automatic
## stabilizer trim for the pitch axis, a roll-rate loop and a yaw damper for the rest. With the AP off the
## demands are zero: it holds the flight path and the bank, like the real normal law with a free stick.

const KP_NZ := 6.0  # deg of elevator per g of error
const KI_NZ := 5.0  # deg per g per s
const KQ := 1.2  # deg per deg/s of pitch rate
const KP_P := 1.0  # deg of aileron per deg/s of roll rate error
const KI_P := 0.4
const KR := 0.012  # rudder (fraction of full) per deg/s of yaw rate
const TRIM_RATE := 0.1  # 1/s: stabilizer follows the integrated elevator

var _de := 0.0
var _stab := 0.0
var _ail := 0.0
var _started := false


func update(dt: float, fdm: FDM) -> void:
	var c: AirlinerControls = fdm.fcs
	if not _started:
		_de = c.cmd["elevator-l"]
		_stab = c.cmd["stabilizer"]
		_started = true
	var active := Props.get_b("ap/cmd/active")
	var nz := Props.get_f("ap/cmd/nz_g") if active else 0.0
	var p_cmd := Props.get_f("ap/cmd/roll_rate_dps") if active else 0.0
	var v := fdm.velocity_ned()
	var gamma := asin(clampf(-v.z / maxf(fdm.vt, 20.0), -0.5, 0.5))
	var roll := fdm.euler().x
	var err := cos(gamma) / maxf(cos(roll), 0.5) + nz - fdm.load_factor
	var q := rad_to_deg(fdm.w_b.y)
	_de = clampf(_de - KI_NZ * err * dt, -25.0, 12.0)
	var de := clampf(_de - KP_NZ * err + KQ * q, -30.0, 15.0)
	_stab = clampf(_stab + TRIM_RATE * _de * dt, -13.5, 4.0)
	c.cmd["elevator-l"] = de
	c.cmd["elevator-r"] = de
	c.cmd["stabilizer"] = _stab
	var p := rad_to_deg(fdm.w_b.x)
	_ail = clampf(_ail + KI_P * (p_cmd - p) * dt, -10.0, 10.0)
	var ail := clampf(_ail + KP_P * (p_cmd - p), -25.0, 25.0)
	c.cmd["aileron-l"] = ail
	c.cmd["aileron-r"] = -ail
	var r := rad_to_deg(fdm.w_b.z)
	c.cmd["rudder"] = clampf(2.0 * fdm.beta - KR * r, -1.0, 1.0) * 25.0
	for k in c.spoiler_cmd.size():
		c.spoiler_cmd[k] = 0.0
