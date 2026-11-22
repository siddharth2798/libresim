class_name RouteLive
extends RefCounted
## Editing the planned route during the flight (the N map's edit mode, ui/map/map_route_edit.gd, and the pause screen's
## Edit route, ui/route_live_page.gd). The route ahead of the aircraft is what the GPS flies now (controls/gps/target +
## route_next) with the waypoints of Session.setup.route behind those idents (so free waypoints keep their position and
## every waypoint its altitude). The editors change that route ahead (RouteOps) and commit() it:
##   Session.setup.route = the waypoints already flown + the edited route ahead (a restart or a save flies the edit)
##   RouteSetup.update_live: GPS target and route, route waypoints, route/dest for ATC, the MCDU INIT FROM/TO.
## The editors draw and measure the route from "PPOS", the aircraft's present position: edit_setup() gives them a
## setup whose departure is PPOS (registered in NavDatabase.route_fixes), with the fuel on board now.

const PPOS := "PPOS"


## The route split at the aircraft: {route (the route ahead, normalized: wps from the active waypoint on, dest),
## passed (the plan's waypoints already flown), lead (idents the GPS flies before the route ahead: a departure runway
## fix), first (ident of the first point ahead, "" = none), orig (the plan as it was)}.
static func split(setup: Dictionary, d: NavDatabase) -> Dictionary:
	var ids: Array = []
	var t := str(Props.get_v("controls/gps/target", ""))
	if t != "":
		ids.append(t)
	for id in Props.get_v("controls/gps/route_next", []):
		ids.append(str(id))
	return split_ids(RouteEdit.route_of(setup), ids, d)


## split() for the GPS idents `ids`. A waypoint of the plan answers to its ident (the first one at or after the last
## match); any other ident becomes a waypoint from the nav data. The last ident is the destination when it is an
## airport. Runway fixes are not waypoints: a departure fix in front is `lead`, an arrival fix comes back from arr_rwy.
## Nothing of the plan ahead (the GPS flies elsewhere, or nothing): passed is empty and the edit replaces the plan.
static func split_ids(r: Dictionary, ids: Array, d: NavDatabase) -> Dictionary:
	var ahead: Array = ids.duplicate()
	var lead: Array = []
	while not ahead.is_empty() and _runway_fix(str(ahead[0]), "D"):
		lead.append(str(ahead.pop_front()))
	ahead = ahead.filter(func(id): return not _runway_fix(str(id), "F"))
	var out := r.duplicate(true)
	out.merge({"wps": [], "kind": "manual", "air_at": -1}, true)
	out.dest = str(ahead.pop_back()) if not ahead.is_empty() and d != null and not d.airport(str(ahead.back())).is_empty() else ""
	if out.dest != str(r.dest):
		out.arr_rwy = ""
	var first := -1
	var cursor := 0
	for id in ahead:
		var at := -1
		for i in range(cursor, r.wps.size()):
			if str(r.wps[i].id) == str(id):
				at = i
				break
		var wp: Dictionary = {}
		if at >= 0:
			first = at if first < 0 else first
			cursor = at + 1
			wp = (r.wps[at] as Dictionary).duplicate()
		else:
			wp = RouteBuilder.waypoint(str(id), d, float(r.cruise_ft))
		if not wp.is_empty():
			out.wps.append(wp)
	var passed: Array = []
	if first >= 0:
		passed = r.wps.slice(0, first)
	elif out.dest != "" and out.dest == str(r.dest) and out.wps.is_empty():
		passed = r.wps.duplicate(true)  # only the destination is left: every waypoint has been flown
	var ids_ahead := RouteSetup.idents(out)
	return {"route": out, "passed": passed, "lead": lead, "first": str(ids_ahead[0]) if not ids_ahead.is_empty() else "",
		"orig": r}


static func _runway_fix(id: String, end: String) -> bool:
	return str(RunwayWaypoints.parse(id).get("kind", "")) == end


## The whole plan after an edit of the route ahead: the waypoints flown, then the edited ones (a new free waypoint that
## took the name of a flown one is renamed); the start (air_at) and the auto-route kind stay when the plan did not change.
static func join(sp: Dictionary, ahead: Dictionary) -> Dictionary:
	var orig: Dictionary = sp.orig
	var full: Dictionary = ahead.duplicate(true)
	var passed: Array = (sp.passed as Array).duplicate(true)
	for i in full.wps.size():  # a free waypoint added ahead is named apart from the ones flown (WPTnn counts per editor)
		var w: Dictionary = full.wps[i]
		if str(w.get("kind", "")) == "user" and passed.any(func(p): return str(p.id) == str(w.id)):
			full.wps[i] = RouteBuilder.user_waypoint(Vector2(float(w.x), float(w.y)), passed + full.wps, float(w.alt_ft))
	full.wps = passed + full.wps
	var same: bool = full.wps == orig.wps and full.dest == orig.dest
	full.kind = str(orig.kind) if same else "manual"
	full.air_at = int(orig.air_at) if same else -1
	return full


## Put the edited route ahead into the flight: Session.setup.route and RouteSetup.update_live. The departure runway fix
## in front (lead) stays only while the first point ahead is unchanged.
static func commit(sp: Dictionary, ahead: Dictionary, d: NavDatabase, airliner: bool) -> void:
	Session.setup.route = join(sp, ahead)
	var ids := RouteSetup.idents(ahead)
	var keep_lead: bool = not ids.is_empty() and str(ids[0]) == str(sp.first)
	RouteSetup.update_live(Session.setup, d, airliner, (sp.passed as Array).size(), sp.lead if keep_lead else [])


## True for the flight's aircraft being an airliner (MCDU INIT is kept up to date).
static func airliner() -> bool:
	var def := AircraftDef.current()
	return def != null and AirlinerNodes.wanted(def)


# ---- the editors' view: from the present position ----

static func here() -> Vector2:
	var p: Vector3 = Props.get_v("fdm/position_enu", Vector3.ZERO)
	return Vector2(p.x, p.y)


## A setup for RouteEdit.legs, RouteTerrain and RouteFuel: departure PPOS at `ppos` (registered), `ahead` as its route,
## a stand start (no air start leg), with `fuel` the fuel on board now.
static func edit_setup(setup: Dictionary, ahead: Dictionary, ppos: Vector2, fuel := true) -> Dictionary:
	NavDatabase.route_fixes[PPOS] = ppos
	var s := setup.duplicate(true)
	s.merge({"airport": PPOS, "start": "stand", "runway": "", "route": ahead.duplicate(true)}, true)
	var on_board := fuel_setting(str(s.get("aircraft", ""))) if fuel else -1.0
	if on_board >= 0.0:
		s.fuel_gal = on_board
	return s


## The editors are closed: PPOS is no point of the route.
static func clear_ppos() -> void:
	NavDatabase.route_fixes.erase(PPOS)


## Fuel on board now (fuel/total_kg) as setup.fuel_gal: US gal per tank, or total kg for a "kg" aircraft; -1 unknown.
static func fuel_setting(aircraft: String) -> float:
	if not Props.has("fuel/total_kg") or aircraft == "":
		return -1.0
	var def := AircraftDef.load_def(aircraft)
	if def == null:
		return -1.0
	var kg := Props.get_f("fuel/total_kg")
	if WeightBalance.fuel_in_kg(def.data):
		return kg
	var tanks: Array = WeightBalance.load_config(def.data).get("tanks", [])
	return kg / maxf(WeightBalance.kg_per_gal(def.data), 0.1) / float(maxi(tanks.size(), 1))
