class_name AfThrust
extends RefCounted
## Autothrust of the autoflight (pure logic, no Props). Lever positions are on the detent scale of
## controls/throttle_<n>: IDLE 0, CL 0.556, FLX/MCT 0.778, TOGA 1.0.
## A/THR states: `armed` (the button; the FMA shows A/THR), `active` (it commands the levers). Active when
## armed, in flight and the pilot's levers are at or below the CL detent: the lever position is the most it
## may command (limit = min(lever, CL)). A lever pushed beyond CL makes it MAN (armed, thrust = lever); back
## in the CL detent it is active again. On the ground it never commands.
## Modes (FMA thrust column): SPEED / MACH (hold the target CAS; PI on the lever), THR CLB (limit),
## THR IDLE (OP DES) / THR DES (managed DES), RETARD (below 20 ft on the glide slope), A.FLOOR (alpha
## floor from the control law: TOGA whatever the levers say), TOGA LK (thrust stays TOGA after the alpha
## floor until A/THR is disconnected). When not active: MAN TOGA / MAN FLX <temp> / MAN MCT / MAN THR.
## "LVR CLB" asks for the levers back to CL above the thrust reduction altitude with A/THR armed.

const CL := 0.556
const MCT := 0.778
const TOGA := 1.0
const DETENT_TOL := 0.03
const KP := 0.06  # lever per m/s of speed error
const KI := 0.004
const RETARD_M := 6.1  # 20 ft

var armed := false
var active := false
var mode := ""  # SPEED MACH THR CLB THR IDLE THR DES RETARD A.FLOOR TOGA LK or "" (manual)
var lever_cmd := 0.0  # what the engines get while active
var limit := CL  # thrust limit the levers allow
var _i := 0.0
var _was_active := false
var _toga_lk := false


func reset() -> void:
	drop()


func drop() -> void:
	armed = false
	active = false
	mode = ""
	_toga_lk = false
	_was_active = false


## `vmode` = vertical mode, `target` m/s CAS, `mach` = the target came from the Mach limit, `land` = on
## the glide slope. Sets `mode`, `active`, `lever_cmd`.
func update(i: AfInputs, vmode: String, target: float, mach: bool, land: bool) -> void:
	limit = minf(i.lever, CL)
	if i.alpha_floor and not i.wow:  # alpha floor arms the A/THR by itself
		armed = true
		_toga_lk = true
	if _toga_lk and i.wow:
		_toga_lk = false
	var in_cl := i.lever <= CL + DETENT_TOL
	active = armed and not i.wow and (in_cl or _toga_lk)
	if not active:
		mode = ""
		_was_active = false
		return
	if not _was_active:
		_i = clampf(i.engine_lever, 0.0, limit)  # bumpless: start from the thrust the engines have
		_was_active = true
	if i.alpha_floor:
		mode = "A.FLOOR"
		lever_cmd = TOGA
	elif _toga_lk:
		mode = "TOGA LK"
		lever_cmd = TOGA
	elif land and Units.m_to_ft(i.ra_m) < 20.0:
		mode = "RETARD"
		lever_cmd = 0.0
	elif vmode == "OP CLB" or vmode == "CLB":
		mode = "THR CLB"
		lever_cmd = limit
	elif vmode == "OP DES" or vmode == "DES":
		mode = "THR IDLE" if vmode == "OP DES" else "THR DES"
		lever_cmd = 0.0
	else:
		mode = "MACH" if mach else "SPEED"
		var e := target - i.cas  # too slow -> more thrust
		var raw := KP * e + _i
		if raw > 0.0 and raw < limit:
			_i = clampf(_i + KI * e * i.dt, 0.0, limit)  # no windup at the limits
		lever_cmd = clampf(raw, 0.0, limit)
		_i = minf(_i, limit)


## Text of the FMA thrust column for the present state (levers in `i`).
func fma(i: AfInputs, above_reduction: bool) -> String:
	if active:
		return mode
	if armed and not i.wow and above_reduction and i.lever > CL + DETENT_TOL:
		return "LVR CLB"
	if i.lever < 0.05 or (i.wow and i.lever < 0.7):
		return ""
	if i.lever >= TOGA - DETENT_TOL:
		return "MAN\nTOGA"
	if absf(i.lever - MCT) <= DETENT_TOL:
		return "MAN\nFLX %d" % roundi(i.flex_c) if i.flex_c > 0.0 else "MAN\nMCT"
	return "MAN\nTHR"


## "TOGA", "FLX 50" or "MCT" for the takeoff limit, "CLB" in flight (E/WD).
func limit_text(i: AfInputs) -> String:
	if not i.wow and i.lever <= CL + DETENT_TOL:
		return "CLB"
	if i.lever >= TOGA - DETENT_TOL or (i.wow and i.flex_c <= 0.0):
		return "TOGA"
	return "FLX %d" % roundi(i.flex_c) if i.flex_c > 0.0 else "MCT"
