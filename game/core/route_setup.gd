class_name RouteSetup
extends RefCounted
## The planned route of the start screen (Session.setup.route, see RouteBuilder) going into the flight.
##   route = {dest, arr_rwy, wps: [{id, kind, x, y, alt_ft}], cruise_ft, kind, air_at}
## clear() (Session.apply_to_props) drops the last flight's route. apply() (world/flight.gd _reset, every start and
## restart, only when there is a route) registers the waypoints (NavDatabase.route_fixes) and sets:
##   controls/gps/target + controls/gps/route_next   the waypoints then the destination, as INIT FROM/TO files them:
##       a runway start on a chosen runway flies its departure fix first (RunwayWaypoints "D"), an arrival runway adds
##       its final fix (8 nm, "F") before the destination. An air start on leg k (air_at) begins at point k + 1.
##   route/dest                                      destination ident ("" = none), read by ATC (atc_world.gd)
##   airliners: mcdu/init/{from_to, dep_rwy, arr_rwy, cruise_fl}, controls/fms/origin, controls/fcu/alt_ft,
##       controls/fcu/vs_managed and controls/fcu/hdg_managed (NAV), as typing them on the INIT page does (without filing over the route again).
## restore() puts back what a saved flight does not hold in its props (route waypoints, route/dest, MCDU INIT).

const DEST_PROP := "route/dest"
const MCDU_KEYS := ["mcdu/init/from_to", "mcdu/init/dep_rwy", "mcdu/init/arr_rwy", "controls/fms/origin"]
const DEFAULT_CRUISE_FT := 4500.0


## A route as Session keeps it, repaired: not a dictionary -> {} (no route); wps not an array -> []; a waypoint that is
## not a dictionary or has no id or numeric x / y is dropped. Missing keys get defaults. {} stays {}.
static func repair(v: Variant) -> Dictionary:
	if not v is Dictionary or (v as Dictionary).is_empty():
		return {}
	var r: Dictionary = v
	var cruise := float(r.cruise_ft) if r.get("cruise_ft") is float or r.get("cruise_ft") is int else DEFAULT_CRUISE_FT
	var wps: Array = []
	for w in (r.wps if r.get("wps") is Array else []):
		if not w is Dictionary or str(w.get("id", "")).strip_edges() == "" or not _num(w.get("x")) or not _num(w.get("y")):
			continue
		var id := str(w.id).strip_edges().to_upper()
		var kind := str(w.get("kind", "user" if id.begins_with("WPT") else "fix"))
		wps.append({"id": id, "kind": kind, "x": float(w.x), "y": float(w.y),
			"alt_ft": float(w.alt_ft) if _num(w.get("alt_ft")) else cruise})
	return {"dest": str(r.get("dest", "")).strip_edges().to_upper() if r.get("dest") is String else "",
		"arr_rwy": str(r.get("arr_rwy", "")) if r.get("arr_rwy") is String else "", "wps": wps, "cruise_ft": cruise,
		"kind": str(r.get("kind", "manual")) if r.get("kind") is String else "manual",
		"air_at": int(r.air_at) if _num(r.get("air_at")) else -1}


static func _num(v: Variant) -> bool:
	return v is float or v is int


## True when the route has a destination or at least one waypoint.
static func active(route: Variant) -> bool:
	var r := repair(route)
	return not r.is_empty() and (str(r.dest) != "" or not (r.wps as Array).is_empty())


## Idents after the departure: the waypoints, then the destination.
static func idents(route: Dictionary) -> Array:
	var out: Array = []
	for w in route.get("wps", []):
		out.append(str(w.id))
	if str(route.get("dest", "")) != "":
		out.append(str(route.dest))
	return out


## The leg an air start begins on: air_at clamped to the legs of [departure, wps..., dest]; -1 = not on the route.
static func air_leg(setup: Dictionary) -> int:
	var r := repair(setup.get("route", {}))
	if str(setup.get("start", "")) != "air" or not active(r) or int(r.air_at) < 0:
		return -1
	return mini(int(r.air_at), idents(r).size() - 1)


## Altitude (ft MSL) of each leg of [departure, wps..., dest]: leg k ends at point k + 1 and flies that waypoint's
## alt_ft; the leg into the destination flies the last waypoint's (cruise_ft when there are none).
static func leg_alts(route: Dictionary) -> Array:
	var out: Array = []
	var wps: Array = route.get("wps", [])
	for w in wps:
		out.append(float(w.alt_ft))
	if str(route.get("dest", "")) != "":
		out.append(float(wps.back().alt_ft) if not wps.is_empty() else float(route.get("cruise_ft", DEFAULT_CRUISE_FT)))
	return out


## {target, next, dep_rwy, arr_rwy} for the GPS. `known` = Callable(ident) -> bool (synthetic runway fixes are used only
## when it knows them).
static func gps_plan(setup: Dictionary, known: Callable) -> Dictionary:
	var r := repair(setup.get("route", {}))
	var ids := idents(r) if not r.is_empty() else []
	if ids.is_empty():
		return {"target": "", "next": [], "dep_rwy": "", "arr_rwy": ""}
	var leg := air_leg(setup)
	if leg >= 0:
		ids = ids.slice(leg)
	var dep_rwy := ""
	var arr_rwy := ""
	var dep := str(setup.get("airport", ""))
	if leg < 0 and str(setup.get("start", "")) == "runway" and str(setup.get("runway", "")) != "":
		var d := RunwayWaypoints.ident(dep, str(setup.runway), "D")
		if known.call(d):
			ids.push_front(d)
			dep_rwy = str(setup.runway)
	if str(r.dest) != "" and str(r.arr_rwy) != "":
		var f := RunwayWaypoints.ident(str(r.dest), str(r.arr_rwy), "F")
		if known.call(f):
			ids.insert(ids.size() - 1, f)
			arr_rwy = str(r.arr_rwy)
	return {"target": str(ids[0]), "next": ids.slice(1), "dep_rwy": dep_rwy, "arr_rwy": arr_rwy}


## Drop the last flight's route: GPS target and route, route waypoints, destination, MCDU INIT route fields.
static func clear() -> void:
	Props.set_v("controls/gps/target", "")
	Props.set_v("controls/gps/route_next", [])
	Props.set_v(DEST_PROP, "")
	NavDatabase.route_fixes.clear()
	for k in MCDU_KEYS:  # CRZ FL stays: Props has no "unset" and 0 would show as FL 0
		Props.set_v(k, "")


## The route into a starting (or restarting) flight. `db` is the flight's NavDatabase; `airliner` fills the MCDU.
## Without a route nothing changes (a restart keeps a direct-to the pilot set; the flight start cleared the last one).
static func apply(setup: Dictionary, db: NavDatabase, airliner: bool) -> void:
	var r := repair(setup.get("route", {}))
	if not active(r):
		return
	clear()
	register(r)
	var plan := gps_plan(setup, func(id: String) -> bool: return db != null and db.position_of(id) != null)
	Props.set_v("controls/gps/target", plan.target)
	Props.set_v("controls/gps/route_next", plan.next)
	Props.set_v(DEST_PROP, str(r.dest))
	if airliner:
		_mcdu(setup, r, plan)
		Props.set_v("controls/fcu/alt_ft", clampf(float(Props.get_v("mcdu/init/cruise_fl")), 1.0, 390.0) * 100.0)
		Props.set_v("controls/fcu/vs_managed", true)
		Props.set_v("controls/fcu/hdg_managed", true)  # NAV, as filing INIT does: the autopilot flies the route


## After a saved flight is loaded (Situation.apply): the saved setup's route waypoints, destination and MCDU INIT. The
## GPS route itself is in the saved props (controls/).
static func restore(setup: Dictionary, db: NavDatabase, airliner: bool) -> void:
	NavDatabase.route_fixes.clear()
	var r := repair(setup.get("route", {}))
	Props.set_v(DEST_PROP, str(r.get("dest", "")))
	if not active(r):
		return
	register(r)
	if airliner:
		_mcdu(setup, r, gps_plan(setup, func(id: String) -> bool: return db != null and db.position_of(id) != null))


## The NavDatabase of a flight scene (null when it has none).
static func db_of(root: Node) -> NavDatabase:
	var nav := root.get_node_or_null("Avionics/Nav")
	return nav.get("db") if nav != null else null


## Every waypoint position, so NavDatabase.position_of resolves user waypoints (and route fixes the data lost).
static func register(route: Dictionary) -> void:
	for w in route.get("wps", []):
		NavDatabase.route_fixes[str(w.id)] = Vector2(float(w.x), float(w.y))


## INIT page as the pilot would have typed it: FROM/TO = departure / waypoints / destination, runways, cruise level.
static func _mcdu(setup: Dictionary, r: Dictionary, plan: Dictionary) -> void:
	var dep := str(setup.get("airport", ""))
	Props.set_v("mcdu/init/from_to", "/".join([dep] + idents(r)))
	Props.set_v("mcdu/init/dep_rwy", str(plan.dep_rwy))
	Props.set_v("mcdu/init/arr_rwy", str(plan.arr_rwy))
	Props.set_v("controls/fms/origin", dep)
	var top := float(r.cruise_ft)
	for a in leg_alts(r):
		top = maxf(top, float(a))
	Props.set_v("mcdu/init/cruise_fl", float(roundi(top / 100.0)))
