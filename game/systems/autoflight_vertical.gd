class_name AfVertical
extends RefCounted
## Vertical modes of the autoflight (pure logic, no Props). Every mode produces a flight path angle
## command gamma_cmd; nz() turns it into the load-factor demand the control law gets
## (`ap/cmd/nz_g`: the g INCREMENT over the 1 g flight-path hold; 0 = keep the flight path, + = pull).
##   SRS      takeoff / go-around: pitch holds V2 + 10 (AfSpeeds.srs_target), thrust is manual
##   V/S      selected vertical speed (FCU)
##   OP CLB   open climb to the FCU altitude: thrust CLB, pitch holds the speed (selected or managed)
##   OP DES   open descent: thrust idle, pitch holds the speed
##   CLB/DES  managed climb / descent: same laws with the managed speed schedule (no vertical profile)
##   ALT*     capture of the FCU altitude: constant deceleration profile (A_CAP) ending in a linear approach
##   ALT      altitude hold ("ALT CRZ" on the FMA when it was reached in a managed climb / descent)
##   G/S*, G/S  glide slope capture and track (-3 deg path through the glide slope antenna)
## Armed: "ALT" (a level-off is ahead), "G/S" (APPR pressed).
## The speed-on-pitch laws are a PI: gamma = KP x (speed - target) + integral (bumpless at mode entry).

const G := AfInputs.G
const A_CAP := 1.0  # m/s2 vertical deceleration of the altitude capture
const K_ALT := 0.15  # 1/s: vertical speed per metre of altitude error in the final approach to the altitude
const TAU_G := 3.0  # s, flight path loop
const NZ_MAX := 0.3
const NZ_MIN := -0.2
const KP_SPD := 0.012  # rad per m/s of speed error
const KI_SPD := 0.0015
const K_GS := 0.002  # rad per m above the glide path
const GS_MAX := deg_to_rad(3.0)
const SPEED_MODES := ["SRS", "OP CLB", "OP DES", "CLB", "DES"]

var mode := ""
var armed: Array = []
var crz := false  # the ALT came from a managed CLB / DES
var gamma_cmd := 0.0
var land := false  # glide slope below 400 ft: the FMA says LAND
var _i_spd := 0.0
var _fresh := true  # first tick of a speed-on-pitch mode: initialise the integral


func reset() -> void:
	mode = ""
	armed = []
	crz = false
	gamma_cmd = 0.0
	land = false
	_fresh = true


func set_mode(m: String) -> void:
	if m != mode:
		mode = m
		_fresh = true
		if m != "ALT":
			crz = false


func is_speed_mode() -> bool:
	return mode in SPEED_MODES


## One tick. `spd_target` m/s (CAS) for the speed-on-pitch modes; `loc_ok` = the lateral localizer is captured.
func update(i: AfInputs, spd_target: float, loc_ok: bool) -> void:
	var alt_err: float = i.f.alt - i.alt_m
	land = false
	_follow_selection(i, alt_err)
	_gs_logic(i, loc_ok)
	match mode:
		"SRS": gamma_cmd = _speed_law(i, spd_target, 0.0, 0.2, 0.1)  # initial climb gradient as the starting integral
		"OP CLB", "CLB": gamma_cmd = _speed_law(i, spd_target, -0.05, 0.17)
		"OP DES", "DES": gamma_cmd = _speed_law(i, spd_target, -0.17, 0.05)
		"V/S": gamma_cmd = _gamma_of(i, i.f.vs)
		"ALT*": gamma_cmd = _gamma_of(i, _capture_vs(alt_err))
		"ALT": gamma_cmd = _gamma_of(i, clampf(K_ALT * alt_err, -8.0, 8.0))
		"G/S*", "G/S":
			land = Units.m_to_ft(i.ra_m) < 400.0
			gamma_cmd = -i.ils.gs_rad - clampf(K_GS * i.gs_error_m(), -GS_MAX, GS_MAX)
		_: gamma_cmd = 0.0
	if i.wow:
		_fresh = true  # nothing to integrate on the ground
	_armed(i, alt_err)


func nz(i: AfInputs) -> float:
	var d := gamma_cmd - i.gamma()
	return clampf(maxf(i.tas, 20.0) / G * d / TAU_G, NZ_MIN, NZ_MAX)


func _gamma_of(i: AfInputs, vs: float) -> float:
	return asin(clampf(vs / maxf(i.tas, 20.0), -0.5, 0.5))


## Mode transitions that follow the altitude: capture, direction of OP / managed modes, ALT*, ALT.
func _follow_selection(i: AfInputs, alt_err: float) -> void:
	match mode:
		"OP CLB", "CLB", "OP DES", "DES", "V/S":
			if mode == "OP CLB" and alt_err < -30.0:
				set_mode("OP DES")
			elif mode == "OP DES" and alt_err > 30.0:
				set_mode("OP CLB")
			elif mode == "CLB" and alt_err < -30.0:
				set_mode("DES")
			elif mode == "DES" and alt_err > 30.0:
				set_mode("CLB")
			if _capture_due(i, alt_err):
				crz = mode == "CLB" or mode == "DES"
				set_mode("ALT*")
		"ALT*":
			if absf(alt_err) < 8.0 and absf(i.vs_mps) < 2.0:
				set_mode("ALT")


## Level-off starts when the remaining distance equals the deceleration distance (plus the loop lag).
func _capture_due(i: AfInputs, alt_err: float) -> bool:
	var vs := i.vs_mps
	if mode == "V/S" and alt_err * vs <= 0.0:
		return false  # climbing away from the selected altitude: no capture
	if absf(alt_err) < 15.0:
		return mode != "V/S" or alt_err * vs > 0.0
	if alt_err * vs <= 0.0:
		return false
	return absf(alt_err) <= vs * vs / (2.0 * A_CAP) + absf(vs) * TAU_G * 0.5 + 15.0


func _capture_vs(alt_err: float) -> float:
	var e := absf(alt_err)
	var v := K_ALT * e if e < 2.0 * A_CAP / (K_ALT * K_ALT) else sqrt(2.0 * A_CAP * e)
	return signf(alt_err) * v


## Glide slope arming and capture (needs the localizer captured, G/S valid and the aircraft near the path).
func _gs_logic(i: AfInputs, loc_ok: bool) -> void:
	var on := mode == "G/S*" or mode == "G/S"
	var ok: bool = i.f.appr and loc_ok and not i.ils.is_empty() and i.ils.gs_valid
	if on and not ok:
		set_mode("V/S")  # lost: hold the current vertical speed
		return
	if on:
		if mode == "G/S*" and absf(i.gs_error_m()) < 8.0:
			set_mode("G/S")
		return
	if ok and mode != "SRS":
		var h := i.gs_error_m()
		var lead := maxf(25.0, 6.0 * maxf(i.gs_mps, 30.0) * sin(i.ils.gs_rad))
		if h < 15.0 and h > -lead:
			set_mode("G/S*")


## PI: too fast -> climb (gamma up). Starts from the present flight path angle.
func _speed_law(i: AfInputs, target: float, lo: float, hi: float, init := NAN) -> float:
	var e := i.cas - target
	if _fresh:
		_i_spd = clampf(i.gamma() - KP_SPD * e if is_nan(init) else init, lo, hi)
		_fresh = false
	var g := KP_SPD * e + _i_spd
	if g >= lo and g <= hi:
		_i_spd = clampf(_i_spd + KI_SPD * e * i.dt, lo, hi)  # no windup while saturated
	return clampf(g, lo, hi)


func _armed(i: AfInputs, alt_err: float) -> void:
	armed = []
	var dir := 0.0
	match mode:
		"OP CLB", "CLB": dir = 1.0
		"OP DES", "DES": dir = -1.0
		"V/S": dir = signf(i.vs_mps) if absf(i.vs_mps) > 0.3 else 0.0
	if dir != 0.0 and alt_err * dir > 0.0:
		armed.append("ALT")
	if i.f.appr and mode != "G/S*" and mode != "G/S":
		armed.append("G/S")


func save_state() -> Dictionary:
	return {"mode": mode, "crz": crz}


func load_state(d: Dictionary) -> void:
	mode = str(d.get("mode", ""))
	crz = bool(d.get("crz", false))
	_fresh = true  # the speed integral restarts from the present flight path (bumpless)
