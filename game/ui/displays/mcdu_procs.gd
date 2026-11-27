class_name McduProcs
extends RefCounted
## MCDU INIT: filing FROM/TO with the runways and the published procedures (split from mcdu.gd).
##   L6 SID / R6 STAR (mcdu/init/sid, mcdu/init/star): with an empty scratchpad a press offers the next procedure published for
##   DEP RWY / ARR RWY (Procedures; after the last one, none); a typed name is taken when it is published for that runway.
##   Either re-files the route (file_route): the SID replaces the departure fix, the STAR comes before the arrival fix, and their
##   constraints go to controls/gps/constraints (FlightPlan.with_procedures, ProcedureRoute).

const NONE_MSG := "NO SID/STAR FOR RWY"


## The name after `current` in `names` ("" after the last one, the first after "").
static func next_name(names: Array, current: String) -> String:
	if names.is_empty():
		return ""
	var i := names.find(current)
	return str(names[0]) if i < 0 else (str(names[i + 1]) if i + 1 < names.size() else "")


## Line key L6 / R6 of INIT. `d` = the MCDU.
static func line_key(d: MCDU, side: String, s: String) -> void:
	var sid := side == "l"
	var prop := "mcdu/init/sid" if sid else "mcdu/init/star"
	var ft := FlightPlan.split_from_to(str(Props.get_v("mcdu/init/from_to", "")))
	var icao := (str(ft[0]) if sid else str(ft.back())) if not ft.is_empty() else str(Props.get_v("controls/fms/origin", ""))
	var rwy := str(Props.get_v("mcdu/init/dep_rwy" if sid else "mcdu/init/arr_rwy", ""))
	var names := Procedures.names(icao, "SID" if sid else "STAR", rwy) if rwy != "" else []
	var pick := ""
	if s == "":
		if names.is_empty():
			Props.set_v("mcdu/scratch", NONE_MSG)
			return
		pick = next_name(names, str(Props.get_v(prop, "")))
	else:
		pick = s.strip_edges().to_upper().replace(" ", "")
		if not pick in names:
			Props.set_v("mcdu/scratch", FlightPlan.NOT_IN_DB)
			return
	Props.set_v(prop, pick)
	Props.set_v("mcdu/scratch", "")
	var text := str(Props.get_v("mcdu/init/from_to", ""))
	if text != "":
		file_route(d, text)


## FROM/TO typed (or a runway / procedure changed): file the route, as the INIT page does.
static func file_route(d: MCDU, text: String) -> void:
	var exp := Airway.expand(FlightPlan.split_from_to(text), d._airways())
	if not exp.ok:
		Props.set_v("mcdu/scratch", exp.error)
		return
	var known := Callable(d, "_known")
	var filed := FlightPlan.file(exp.parts, known)
	if not filed.ok:
		Props.set_v("mcdu/scratch", filed.error)
		return
	var db: Object = d._db()
	var airports: Array = db.get("airports") if db != null and db.get("airports") is Array else []
	filed = FlightPlan.with_procedures(filed, str(Props.get_v("mcdu/init/dep_rwy", "")), str(Props.get_v("mcdu/init/arr_rwy", "")),
		str(Props.get_v("mcdu/init/sid", "")), str(Props.get_v("mcdu/init/star", "")), airports)
	if not known.call(str(filed.target)) or filed.next.any(func(id): return not known.call(str(id))):
		Props.set_v("mcdu/scratch", FlightPlan.NOT_IN_DB)
		return
	Props.set_v("mcdu/init/sid", str(filed.get("sid", "")))
	Props.set_v("mcdu/init/star", str(filed.get("star", "")))
	Props.set_v(RouteSetup.CSTR_PROP, filed.get("cstr", {}))
	d._commit(str(filed.target), filed.next, true)
	Props.set_v("controls/fms/origin", filed.origin)
	if Props.get_b("fdm/wow"):  # filed before departure: managed speed, as a Route-step route (RouteSetup.apply); in flight the pilot's
		Props.set_v("controls/fcu/spd_managed", true)
