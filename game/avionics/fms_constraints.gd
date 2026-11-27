class_name FmsConstraints
extends RefCounted
## The SID / STAR constraints of the GPS route (controls/gps/constraints, ProcedureRoute) for the managed climb and descent.
## Gps owns one and calls update() at 30 Hz with the route legs ahead (RoutePlan.legs). It publishes:
##   avionics/fms/cstr_ceiling_ft  the lowest at-or-below altitude of a SID fix still ahead: managed CLB levels there (ALT CST)
##                                 until the fix is passed. A SID constraint wholly above the cruise level is ignored (as on
##                                 the Airbus FMS); 0 = none.
##   avionics/fms/cstr_floor_ft    the highest at-or-above altitude of a STAR fix still ahead: managed DES levels there; 0 = none
##   avionics/fms/spd_cstr_kt      the speed limit: in a climb the next SID limit ahead; in a descent the lowest STAR limit passed,
##                                 or the next one ahead once within its deceleration distance; 0 = none
##   avionics/fms/cstr_log         [{ident, text, alt_ft, kt, met, skip}] each constrained fix as it was passed (the probe checks it)
##   avionics/fms/cstr_state       ident -> "met" | "missed" for the fixes ahead (a prediction) and passed (the log): the MCDU and
##                                 ND draw a constraint magenta when met, amber when missed
## caps() gives VerticalProfile the STAR's at-or-below limits ahead, so the top of descent accounts for them.

const NM := 1852.0
const ALT_TOL_FT := 100.0
const SPD_TOL_KT := 10.0
const CLIMB_FT_PER_NM := 450.0  # a prediction only: an A320 climbs 500 to 700 ft / nm below FL100 at 250 kt
const DESCENT_FT_PER_NM := 320.0  # idle descent, about 3 deg
const DECEL_KT_PER_NM := 5.0

var log: Array = []
var held_kt := 0.0  # the lowest STAR speed limit passed (a descent keeps it)
var _passed := {}


func reset() -> void:
	log = []
	held_kt = 0.0
	_passed = {}


## A constraint {lo, hi, spd, proc} wholly above the cruise level is not flown (SID only; 0 = no cruise level known).
static func applies(c: Dictionary, cruise_ft: float) -> bool:
	return str(c.get("proc", "")) != "SID" or cruise_ft <= 0.0 or float(c.get("lo", 0.0)) <= cruise_ft + 50.0


static func ceiling(legs: Array, cstr: Dictionary, cruise_ft: float) -> Dictionary:
	var best := {"ft": 0.0, "ident": ""}
	for lg in legs:
		var c: Dictionary = cstr.get(lg.ident, {})
		if c.is_empty() or str(c.proc) != "SID" or float(c.hi) <= 0.0 or not applies(c, cruise_ft):
			continue
		if cruise_ft > 0.0 and float(c.hi) >= cruise_ft:
			continue
		if best.ft <= 0.0 or float(c.hi) < best.ft:
			best = {"ft": float(c.hi), "ident": str(lg.ident)}
	return best


static func floor_of(legs: Array, cstr: Dictionary) -> Dictionary:
	var best := {"ft": 0.0, "ident": ""}
	for lg in legs:
		var c: Dictionary = cstr.get(lg.ident, {})
		if not c.is_empty() and str(c.proc) == "STAR" and float(c.lo) > best.ft:
			best = {"ft": float(c.lo), "ident": str(lg.ident)}
	return best


## [{s_nm (route distance from the aircraft), hi_ft}] of the STAR's at-or-below limits ahead, for VerticalProfile.decide.
static func caps(legs: Array, cstr: Dictionary) -> Array:
	var out: Array = []
	for lg in legs:
		var c: Dictionary = cstr.get(lg.ident, {})
		if not c.is_empty() and str(c.proc) == "STAR" and float(c.hi) > 0.0:
			out.append({"s_nm": float(lg.cum_m) / NM, "hi_ft": float(c.hi)})
	return out


## Speed limit (kt, 0 = none). `climbing` = the FMS is in CLB: the next SID limit ahead. Otherwise (cruise, descent) the next STAR
## limit once within its deceleration distance, so the aircraft is slow by the fix even when the descent starts just before it
## (VELKO 230 kt, 2 nm after the top of descent: it was passed at 274 kt); `descent` (DES / APPR) adds `held`, the lowest passed.
## `cas_kt` = the present speed.
static func speed_limit(legs: Array, cstr: Dictionary, descent: bool, held: float, cas_kt: float, climbing := false) -> float:
	var proc := "SID" if climbing else "STAR"
	var lim := held if descent else 0.0
	for lg in legs:
		var c: Dictionary = cstr.get(lg.ident, {})
		if c.is_empty() or str(c.proc) != proc or float(c.spd) <= 0.0:
			continue
		var s := float(c.spd)
		if not climbing and float(lg.cum_m) / NM > decel_nm(cas_kt, s):
			break  # not yet: slow down when it is this close
		lim = s if lim <= 0.0 else minf(lim, s)
		break
	return lim


## Distance (nm) to slow from cas_kt to kt: a level deceleration at idle is about 0.5 kt per second (5 kt per nm at 220 to 280 kt),
## plus 2 nm.
static func decel_nm(cas_kt: float, kt: float) -> float:
	return 2.0 + maxf(cas_kt - kt, 0.0) / DECEL_KT_PER_NM


## Altitude (ft) and speed (kt) inside the constraint, with the tolerances.
static func met(c: Dictionary, alt_ft: float, kt: float) -> bool:
	if float(c.get("lo", 0.0)) > 0.0 and alt_ft < float(c.lo) - ALT_TOL_FT:
		return false
	if float(c.get("hi", 0.0)) > 0.0 and alt_ft > float(c.hi) + ALT_TOL_FT:
		return false
	return float(c.get("spd", 0.0)) <= 0.0 or kt <= float(c.spd) + SPD_TOL_KT


## "met" | "missed": can the constraint `dist_nm` ahead still be met from `alt_ft`. A STAR constraint while climbing is "met".
static func predicted(c: Dictionary, alt_ft: float, dist_nm: float, descent: bool) -> String:
	if str(c.get("proc", "")) == "SID" and not descent:
		var ok := float(c.lo) <= 0.0 or alt_ft + dist_nm * CLIMB_FT_PER_NM >= float(c.lo) - ALT_TOL_FT
		return "met" if ok else "missed"
	if str(c.get("proc", "")) == "STAR" and descent:
		var ok2 := float(c.hi) <= 0.0 or alt_ft - dist_nm * DESCENT_FT_PER_NM <= float(c.hi) + ALT_TOL_FT
		ok2 = ok2 and (float(c.lo) <= 0.0 or alt_ft >= float(c.lo) - ALT_TOL_FT)
		return "met" if ok2 else "missed"
	return "met"


## A constrained fix was passed (the GPS sequenced it) at alt_ft / kt.
func passed(ident: String, cstr: Dictionary, alt_ft: float, kt: float, cruise_ft: float) -> void:
	var c: Dictionary = cstr.get(ident, {})
	if c.is_empty() or _passed.has(ident):
		return
	var skip := not applies(c, cruise_ft)
	var ok := met(c, alt_ft, kt)
	_passed[ident] = "met" if ok or skip else "missed"
	log.append({"ident": ident, "text": Procedures.text(c), "alt_ft": roundf(alt_ft), "kt": roundf(kt), "met": ok, "skip": skip})
	if str(c.proc) == "STAR" and float(c.spd) > 0.0:
		held_kt = float(c.spd) if held_kt <= 0.0 else minf(held_kt, float(c.spd))
	Props.set_v("avionics/fms/cstr_log", log.duplicate(true))


## Publish the limits for the managed modes and the met / missed state for the displays. `phase` = avionics/fms/phase.
func update(legs: Array, cstr: Dictionary, alt_ft: float, cas_kt: float, cruise_ft: float, phase: String) -> void:
	var descent := phase == "DES" or phase == "APPR"
	var ceil := ceiling(legs, cstr, cruise_ft) if not descent else {"ft": 0.0}
	Props.set_v("avionics/fms/cstr_ceiling_ft", ceil.ft)
	Props.set_v("avionics/fms/cstr_floor_ft", floor_of(legs, cstr).ft if descent else 0.0)
	Props.set_v("avionics/fms/spd_cstr_kt", speed_limit(legs, cstr, descent, held_kt, cas_kt, phase == "CLB"))
	var state := _passed.duplicate()
	for lg in legs:
		var c: Dictionary = cstr.get(lg.ident, {})
		if not c.is_empty():
			state[lg.ident] = predicted(c, alt_ft, float(lg.cum_m) / NM, descent) if applies(c, cruise_ft) else "met"
	if state != Props.get_v("avionics/fms/cstr_state", {}):
		Props.set_v("avionics/fms/cstr_state", state)
