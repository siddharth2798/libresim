class_name RouteChecks
extends RefCounted
## The planned route's warnings for SetupChecks (all "warn", never blocking) and the NavDatabase the start screen reads
## (loaded once, shared by the Route step through RouteEdit.db()). Lives in core so the setup checks do not depend on a
## menu page. Warnings: [id, text]
##   route_dest  the destination is not in the nav data
##   route_far   a waypoint more than FAR_NM from the departure
##   route_leg   an "In the air" start on a leg the route no longer has (route.air_at)

const NM := 1852.0
const FAR_NM := 600.0

static var _db: NavDatabase


## The navigation data (airports, VOR / NDB, airway fixes), read on first use.
static func db() -> NavDatabase:
	if _db == null:
		_db = NavDatabase.new()
	return _db


static func problems(setup: Dictionary) -> Array:
	var r := RouteSetup.repair(setup.get("route", {}))
	if not RouteSetup.active(r):
		return []
	var out := []
	var d := db()
	var dest_known: bool = r.dest != "" and d.position_of(r.dest) != null
	if r.dest != "" and not dest_known:
		out.append(["route_dest", "Route destination %s is not in the nav data" % r.dest])
	var home: Variant = d.position_of(str(setup.get("airport", "")))
	for w in r.wps:
		if home != null and Vector2(float(w.x), float(w.y)).distance_to(home) > FAR_NM * NM:
			out.append(["route_far", "Waypoint %s is more than %d nm away" % [str(w.id), int(FAR_NM)]])
			break
	var points: int = (r.wps as Array).size() + (1 if home != null else 0) + (1 if dest_known else 0)
	if str(setup.get("start", "")) == "air" and int(r.air_at) >= maxi(points - 1, 0):
		out.append(["route_leg", "The start leg is no longer on the route"])
	return out
