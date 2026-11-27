class_name AfThrust
extends RefCounted
## Autothrust of the autoflight (pure logic, no Props). Lever positions are on the detent scale of controls/throttle_<n>: IDLE 0,
## CL 0.556, FLX/MCT 0.778, TOGA 1.0.
## A/THR states: `armed` (the FMA shows A/THR), `active` (it commands the thrust). Armed by the FCU button, or on the ground by
## moving the levers into TOGA, or FLX/MCT with a flex temperature set, with a flight director on (arm_by_levers: on the way in, once;
## FBW pedestal and fifth-column pages). Active when armed, in flight and the levers are at or below the CL detent: the lever position
## is the most it may command (limit = min(lever, CL)). A lever beyond CL makes it MAN (armed, thrust = lever); back in CL it is
## active again. On the ground it never commands. The levers never move by themselves (the engines get `lever_cmd`, the levers keep
## the pilot's position). Levers at idle in flight disconnect it (the Flying Engineer autoflight page). The instinctive disconnect
## (athr_disc) drops it.
## Modes (FMA thrust column): SPEED / MACH (hold the target CAS; PI on the lever), THR CLB (limit), THR IDLE (OP DES) / THR DES
## (managed DES), THR IDLE (flare, from 30 ft) / RETARD (from 10 ft and on the roll out of an autoland), A.FLOOR (alpha floor from the control law: TOGA whatever the levers
## say), TOGA LK (TOGA stays after the alpha floor until A/THR is disconnected). When not active: MAN TOGA / MAN FLX <temp> /
## MAN MCT / MAN THR. "LVR CLB" (flashing) asks for the levers back to CL above the thrust reduction altitude (1500 ft, the acceleration altitude) after a
## takeoff or go-around with A/THR armed; in other phases a lever beyond CL is just MAN THR.

const CL := 0.556
const MCT := 0.778
const TOGA := 1.0
const DETENT_TOL := 0.03
const KP := 0.06  # lever per m/s of speed error
const KI := 0.004
const RETARD_M := 6.1  # 20 ft
const IDLE_LEVER := 0.03  # at or below this the levers are at the idle detent

var armed := false
var active := false
var mode := ""  # SPEED MACH THR CLB THR IDLE THR DES RETARD A.FLOOR TOGA LK or "" (manual)
var lever_cmd := 0.0  # what the engines get while active
var limit := CL  # thrust limit the levers allow
var _i := 0.0
var _was_active := false
var _toga_lk := false
var reduction_pending := false  # a takeoff or go-around began: above the reduction altitude LVR CLB asks for the CL detent (until it is there)
var _lever_arm_was := false  # the levers were in a takeoff detent last tick
var _ground_idle := false  # after an autoland roll out, on the ground with the levers still in the CL range: hold idle


func reset() -> void:
	drop()


## On the ground a lever move into TOGA (or FLX/MCT with a flex temperature entered) with a flight director on arms the A/THR
## without the FCU button (MAN TOGA / MAN FLX in white, A/THR cyan). Only the move in arms it, so a pilot who disarms it keeps it off.
func arm_by_levers(i: AfInputs) -> void:
	var detent: bool = i.lever >= TOGA - DETENT_TOL or (absf(i.lever - MCT) <= DETENT_TOL and i.flex_c > 0.0)
	var want: bool = i.wow and i.powered and bool(i.f.fd) and detent
	if want and not _lever_arm_was and not armed and not i.f.athr_disc:
		armed = true
	_lever_arm_was = want
	if armed and not i.wow and i.lever <= IDLE_LEVER:  # levers to idle in flight: A/THR disconnects (thrust is then the lever: idle)
		drop()


func drop() -> void:
	armed = false
	active = false
	mode = ""
	_toga_lk = false
	_was_active = false
	reduction_pending = false
	_ground_idle = false


## `vmode` = vertical mode, `target` m/s CAS, `mach` = the target came from the Mach limit, `retard` = the autoland flare asks for
## idle (1 from 30 ft: THR IDLE, 2 from 10 ft and on the roll out: RETARD), `rolling` = an autoland roll out (A/THR goes on commanding
## idle on the ground until the levers leave the CL range, also after the AP has let go at 20 kt: `_ground_idle`; before, the engines
## then went to the levers' climb thrust on the runway. Levers to idle on the ground after that disconnect it, as after a landing).
## Sets `mode`, `active`, `lever_cmd`.
func update(i: AfInputs, vmode: String, target: float, mach: bool, retard := 0, rolling := false) -> void:
	limit = minf(i.lever, CL)
	if i.alpha_floor and not i.wow:  # alpha floor arms the A/THR by itself
		armed = true
		_toga_lk = true
	if _toga_lk and i.wow:
		_toga_lk = false
	var in_cl := i.lever <= CL + DETENT_TOL
	if not i.wow or not armed or not in_cl:
		_ground_idle = false
	elif rolling:
		_ground_idle = true
	elif _ground_idle and i.lever <= IDLE_LEVER:  # the pilot retarded after the autoland: A/THR off
		drop()
	active = armed and (not i.wow or rolling or _ground_idle) and (in_cl or _toga_lk)
	if active or not armed:
		reduction_pending = false
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
	elif retard > 0 or _ground_idle:
		mode = "RETARD" if retard >= 2 or _ground_idle else "THR IDLE"
		lever_cmd = 0.0
	elif vmode == "OP CLB" or vmode == "CLB" or vmode == "SRS":
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
	if armed and not i.wow and above_reduction and reduction_pending and i.lever > CL + DETENT_TOL:
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
