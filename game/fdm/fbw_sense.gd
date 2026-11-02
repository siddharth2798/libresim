class_name FbwSense
extends RefCounted
## What the flight control law measures each tick (ADIRS / accelerometer / radio altimeter in the real
## aircraft), in SI and radians: filled from the FDM state by update(). Load factor nz is the
## accelerometer reading along the lift axis (what the pilot feels perpendicular to the flight path), in g.

var dt := 0.0
var alpha := 0.0
var alpha_dot := 0.0  # rad/s, lightly filtered
var beta := 0.0
var cas_kt := 0.0
var mach := 0.0
var qbar := 0.0
var tas := 1.0
var p := 0.0  # body rates, rad/s
var q := 0.0
var r := 0.0
var phi := 0.0
var theta := 0.0
var gamma := 0.0  # flight path angle (inertial)
var nz := 1.0
var ra_ft := 1000.0  # radio altitude of the wheels
var wow := false
var gear_pos := 1.0
var flap_deg := 0.0
var slat_deg := 0.0
var lever := 0.0  # mean thrust lever
var sched := 1.0  # gain schedule q_ref / qbar
var _gear_h := 0.0  # m, CG height above the lowest wheel when level
var _alpha_prev := NAN


func update(f: FDM, par: FbwParams, step: float) -> void:
	dt = step
	alpha = f.alpha
	beta = f.beta
	alpha_dot = 0.0 if is_nan(_alpha_prev) else lerpf(alpha_dot, (alpha - _alpha_prev) / maxf(dt, 1e-6), 0.25)
	_alpha_prev = alpha
	cas_kt = f.cas / 0.514444
	mach = f.mach
	qbar = f.qbar
	tas = maxf(f.vt, 20.0)
	p = f.w_b.x
	q = f.w_b.y
	r = f.w_b.z
	var e := f.euler()
	phi = e.x
	theta = e.y
	var v := f.velocity_ned()
	gamma = atan2(-v.z, maxf(Vector2(v.x, v.y).length(), 0.1))
	nz = (f.accel_b.x * sin(alpha) - f.accel_b.z * cos(alpha)) / FDM.G
	wow = f.gear.wow
	ra_ft = (f.agl - _gear_h) / 0.3048
	flap_deg = f.fcs.flap_deg
	slat_deg = f.fcs.slat_deg
	gear_pos = f.fcs.gear_pos
	var lv := 0.0
	for x in f.fcs.thrust_lever:
		lv += float(x)
	lever = lv / maxf(f.fcs.thrust_lever.size(), 1)
	sched = clampf(par.f("q_ref_pa") / maxf(qbar, 1.0), par.f("sched_min"), par.f("sched_max"))


## CG height above the lowest wheel (m), from the gear contacts in the body frame.
func find_gear_height(f: FDM) -> void:
	_gear_h = 0.0
	for c in f.gear.contacts:
		if c.wheel:
			_gear_h = maxf(_gear_h, f.mb.body_of(c.pos).z)
