class_name RouteOps
extends RefCounted
## The map gestures as route edits, shared by the Route step (route_page.gd), the in-flight Edit route page
## (ui/route_live_page.gd) and the N map's edit mode (ui/map/map_route_edit.gd). Pure statics over a normalized route
## dict (RouteEdit.normalized), changed in place; `d` is the NavDatabase that names points. Each returns what the
## caller shows: {ok, msg, warn, sel} (sel = the wps index to select, -1 = none). `taken`: more waypoints whose names a new
## free waypoint must not take (in flight: the ones already flown, which are not in the route ahead).

## A waypoint for the named point `ident` (RouteBuilder.waypoint), else a free one at `world` (named WPTnn, not in `wps`).
static func make(world: Vector2, ident: String, alt: float, wps: Array, d: NavDatabase) -> Dictionary:
	var wp := RouteBuilder.waypoint(ident, d, alt) if ident != "" else {}
	return wp if not wp.is_empty() else RouteBuilder.user_waypoint(world, wps, alt)


## A click on the map at `world` over `ident` ("" = empty map). `dep` is the departure ident (never added).
## {dest: icao} when Shift+click on an airport asks for a new destination (the caller sets it, maybe auto-routing).
static func click(r: Dictionary, world: Vector2, ident: String, shift: bool, dep: String, d: NavDatabase, taken := []) -> Dictionary:
	if shift and ident != "" and d != null and not d.airport(ident).is_empty():
		return {"ok": false, "dest": ident, "msg": "", "warn": false, "sel": -1}
	if ident != "" and ident == str(r.dest):
		return _res(false, "%s is already the destination." % ident, -1)
	if ident != "" and ident == dep:
		return _res(false, "%s is the departure." % ident, -1)
	return add(r, world, ident, d, taken)


## Add the named point (or a free waypoint at `world`) at the end, before the destination.
static func add(r: Dictionary, world: Vector2, ident: String, d: NavDatabase, taken := []) -> Dictionary:
	var wp := make(world, ident, float(r.cruise_ft), r.wps + taken, d)
	if not RouteEdit.add(r, wp):
		return _res(false, "", -1)
	return _res(true, "%s added." % wp.id, r.wps.size() - 1)


## Waypoint i dropped at `world` (on `ident`): that named point, else a free waypoint (a free one keeps its name).
static func drag(r: Dictionary, i: int, world: Vector2, ident: String, d: NavDatabase, taken := []) -> Dictionary:
	if i < 0 or i >= r.wps.size():
		return _res(false, "", -1)
	var old: Dictionary = r.wps[i]
	var others: Array = r.wps.filter(func(w): return w != old)
	var wp := make(world, ident, float(old.alt_ft), others + taken, d)
	if wp.kind == "user" and str(old.kind) == "user":
		wp.id = old.id
	RouteEdit.replace(r, i, wp)
	return _res(true, "%s moved." % wp.id if wp.id == old.id else "%s replaces %s." % [wp.id, old.id], i)


## A new waypoint on the leg that ends at wps[at] (at = wps.size(): the leg into the destination).
static func insert(r: Dictionary, at: int, world: Vector2, ident: String, d: NavDatabase, taken := []) -> Dictionary:
	var wp := make(world, ident, RouteEdit.leg_alt(r, at if at < r.wps.size() else -2), r.wps + taken, d)
	RouteEdit.insert(r, at, wp)
	return _res(true, "%s added on the leg." % wp.id, clampi(at, 0, r.wps.size() - 1))


static func remove(r: Dictionary, i: int) -> Dictionary:
	if i < 0 or i >= r.wps.size():
		return _res(false, "", -1)
	var id := str(r.wps[i].id)
	RouteEdit.remove(r, i)
	return _res(true, "%s removed." % id, -1)


static func _res(ok: bool, msg: String, sel: int) -> Dictionary:
	return {"ok": ok, "msg": msg, "warn": false, "sel": sel}
