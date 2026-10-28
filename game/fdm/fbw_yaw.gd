class_name FbwYaw
extends RefCounted
## Yaw law: rudder pedals (direct, with a travel limit that shrinks with speed), yaw damper and turn
## coordination. The coordination term nulls the sideslip (beta) and the damper acts on the yaw rate minus the
## rate a coordinated turn needs (g sin(phi) / V), so a steady turn is flown without rudder. Rudder command in
## degrees, + = nose right. The yaw damper works on the sidestick-independent loop, in every autopilot state.


func travel_deg(par: FbwParams, cas_kt: float, fac_ok: bool) -> float:
	return FbwParams.interp(par.d.yaw.travel_kt, cas_kt) if fac_ok else float(par.d.yaw.travel_kt[0][1])


func rudder(s: FbwSense, par: FbwParams, pedal: float, damper: bool, fac_ok: bool) -> float:
	var yp: Dictionary = par.d.yaw
	var out := pedal * travel_deg(par, s.cas_kt, fac_ok)
	if damper:
		var r_turn := FDM.G * sin(s.phi) * cos(s.theta) / s.tas
		var lim := float(yp.limit_deg)
		out += clampf(s.sched * (-float(yp.k_r) * (s.r - r_turn) + float(yp.k_beta) * s.beta), -lim, lim)
	return out
