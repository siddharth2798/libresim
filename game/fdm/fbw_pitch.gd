class_name FbwPitch
extends RefCounted
## Pitch law of the A320-style fly-by-wire (flight mode). The sidestick (or the autopilot) demands a load
## factor, nz_c = cos(gamma) / cos(phi) + stick increment: neutral stick means "hold the flight path", also
## in a bank (turn compensation). Loops:
##   outer: pitch rate demand q_c = (g / V) * ((nz_c - cos(gamma) cos(phi)) + kn * (nz_c - nz) + ki * integral)
##          (the first term is the rate the manoeuvre needs, so the nz loop only corrects)
##   inner: elevator = -(sched * kq * (q_c - q) + I)  with I integrated (sched * kiq); I is the nose-up elevator
##          the law holds, and FbwTrim moves the THS until it is zero (auto-trim)
## `ground` blends the direct stick-to-elevator mapping (a speed-scheduled gain) in on the ground; I tracks it,
## so liftoff and touchdown are bumpless. Flare mode: below the flare height with the thrust levers back, a small
## nose-down bias, so the pilot has to flare. Elevator is in surface degrees, + = trailing edge down.

var i_deg := 0.0  # nose-up elevator held (the trim state)
var q_demand := 0.0  # last pitch rate demand, rad/s
var nz_demand := 1.0
var flare := false
var _nz_int := 0.0


func reset(elevator_mean_deg: float) -> void:
	i_deg = -elevator_mean_deg
	_nz_int = 0.0


## nz_c from the stick increment `inc` (g, already scaled by the stick curve) and the protections.
func demand(s: FbwSense, par: FbwParams, prot: FbwProtection, inc: float) -> float:
	var fl: Dictionary = par.d.flare
	flare = s.ra_ft < float(fl.ra_ft) and s.gear_pos > 0.9 and s.lever < float(fl.max_lever) and not s.wow
	var bias := 0.0
	if flare:
		bias = -float(fl.bias_g) * smoothstep(float(fl.ra_ft), float(fl.full_ft), s.ra_ft)
	var lim := prot.nz_limits(s, par)
	var base := cos(s.gamma) / maxf(cos(minf(absf(s.phi), deg_to_rad(par.d.roll.limit_deg))), 0.2)
	var want := base + inc + bias + prot.speed_bias_g(par)
	nz_demand = clampf(want, lim.x, lim.y)
	prot.nz_active = absf(nz_demand - want) > 1e-3
	return nz_demand


## Elevator command (deg) for the demand; `aft` is the stick aft fraction for the alpha protection.
func flight(s: FbwSense, par: FbwParams, prot: FbwProtection, nz_c: float, aft: float, protect: bool) -> float:
	var pp: Dictionary = par.d.pitch
	var k := FDM.G / s.tas
	var err_n := nz_c - s.nz
	var q_c := k * ((nz_c - cos(s.gamma) * cos(s.phi)) + float(pp.kn) * err_n + float(pp.ki) * _nz_int)
	var q_max := deg_to_rad(float(pp.q_max_dps))
	q_c = clampf(q_c, -q_max, q_max)
	if protect:
		q_c = prot.cap_rate(s, par, q_c, aft)
	var err_q := q_c - s.q
	q_demand = q_c
	var raw := -(s.sched * float(pp.kq) * err_q + i_deg)
	var sat := absf(raw) > 25.0
	if not sat:
		i_deg += s.sched * float(pp.kiq) * err_q * s.dt
		if not (protect and prot.alpha_active):
			_nz_int = clampf(_nz_int + err_n * s.dt, -0.5, 0.5)
	return -(s.sched * float(pp.kq) * err_q + i_deg)


## Direct stick-to-elevator (deg) with the ground gain schedule, and I follows it (bumpless blend).
func ground(s: FbwSense, par: FbwParams, stick: float, fcs: AirlinerControls) -> float:
	var g := FbwParams.interp(par.d.ground_gain, s.cas_kt)
	return -stick * (fcs._max("elevator-l") if stick > 0.0 else 15.0) * g


## Make the flight law continue from elevator command `e_deg` (called while the ground law is in charge).
func track(e_deg: float) -> void:
	i_deg = -e_deg
	_nz_int = 0.0
