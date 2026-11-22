class_name RouteChecks
extends RefCounted
## The planned route's problems for SetupChecks and the NavDatabase the start screen reads (loaded once, shared by the
## Route step through RouteEdit.db()). Lives in core so the setup checks do not depend on a menu page.
## Problems: [id, text, level]
##   route_terrain   bad   a leg planned under the terrain (RouteTerrain, take-off and landing ends not judged)
##   route_fuel      bad   fuel on board below trip + reserve (RouteFuel)
##   route_dest      warn  the destination is not in the nav data
##   route_far       warn  a waypoint more than FAR_NM from the departure
##   route_leg       warn  an "In the air" start on a leg the route no longer has (route.air_at)
##   route_low       warn  a leg less than RouteTerrain.MARGIN_FT above the terrain
##   route_fuel_low  warn  lands with less than twice the reserve
##   route_dest_rwy  warn  the destination's runway (the arrival runway, else the longest) is shorter than the
##                         aircraft's ground.min_runway_m (the Airport step's rule)
## Terrain heights: TerrainHeights.shared(), or `height_override` (tests).

const NM := 1852.0
const FAR_NM := 600.0

static var _db: NavDatabase
static var height_override := Callable()  # Callable(east, north) -> m; tests set it
static var _heights := Callable()


## The navigation data (airports, VOR / NDB, airway fixes), read on first use.
static func db() -> NavDatabase:
	if _db == null:
		_db = NavDatabase.new()
	return _db


## The terrain height source of the checks and the profile strip (one Callable, so RouteTerrain.profile's memo holds).
static func heights() -> Callable:
	if height_override.is_valid():
		return height_override
	if not _heights.is_valid():
		_heights = TerrainHeights.shared().height_at
	return _heights


static func problems(setup: Dictionary, ac: AircraftDef = null) -> Array:
	var r := RouteSetup.repair(setup.get("route", {}))
	if not RouteSetup.active(r):
		return []
	var out := []
	var d := db()
	var dest_known: bool = r.dest != "" and d.position_of(r.dest) != null
	if r.dest != "" and not dest_known:
		out.append(["route_dest", "Route destination %s is not in the nav data" % r.dest, "warn"])
	var home: Variant = d.position_of(str(setup.get("airport", "")))
	for w in r.wps:
		if home != null and Vector2(float(w.x), float(w.y)).distance_to(home) > FAR_NM * NM:
			out.append(["route_far", "Waypoint %s is more than %d nm away" % [str(w.id), int(FAR_NM)], "warn"])
			break
	var points: int = (r.wps as Array).size() + (1 if home != null else 0) + (1 if dest_known else 0)
	if str(setup.get("start", "")) == "air" and int(r.air_at) >= maxi(points - 1, 0):
		out.append(["route_leg", "The start leg is no longer on the route", "warn"])
	_terrain(setup, d, out)
	_fuel(setup, d, out)
	if ac == null:
		ac = AircraftDef.load_def(str(setup.get("aircraft", AircraftDef.DEFAULT_ID)))
	if dest_known and ac != null:
		_dest_runway(ac, r, out)
	return out


static func _terrain(setup: Dictionary, d: NavDatabase, out: Array) -> void:
	var p := RouteTerrain.profile(setup, d, heights())
	var v: Dictionary = p.get("verdict", {})
	if v.is_empty() or int(v.low_leg) < 0:
		return
	if int(v.below_leg) >= 0:
		out.append(["route_terrain", "Route %s is planned below the terrain" % RouteTerrain.leg_name(p, int(v.below_leg)), "bad"])
	else:
		out.append(["route_low", "Route %s is only %d ft above the terrain" % [RouteTerrain.leg_name(p, int(v.leg)),
			maxi(int(v.clear_ft), 0)], "warn"])


static func _fuel(setup: Dictionary, d: NavDatabase, out: Array) -> void:
	var f := RouteFuel.for_setup(setup, d)
	if f.is_empty() or f.level == "ok":
		return
	if f.level == "bad":
		out.append(["route_fuel", "Not enough fuel for the route: needs %s (trip + reserve), %s on board" % [
			RouteFuel.amount(f.need, f.unit), RouteFuel.amount(f.on_board, f.unit, false)], "bad"])
	else:
		out.append(["route_fuel_low", "Lands with %s of fuel, under twice the %s reserve" % [
			RouteFuel.amount(maxf(f.landing, 0.0), f.unit, false), RouteFuel.amount(f.reserve, f.unit)], "warn"])


static func _dest_runway(ac: AircraftDef, r: Dictionary, out: Array) -> void:
	var need := float(GroundParams.ground(ac).min_runway_m)
	var rwy := SetupChecks.runway_of({"airport": r.dest, "runway": r.arr_rwy})
	if need <= 0.0 or rwy.is_empty() or float(rwy.length_m) >= need:
		return
	var which := "runway %s is" % rwy.ident if str(r.arr_rwy) != "" else "longest runway is"
	out.append(["route_dest_rwy", "Destination %s: %s %d m, too short (needs %d m)" % [r.dest, which, int(rwy.length_m),
		ceili(need)], "warn"])
