class_name RouteEdit
extends RefCounted
## The route of the Free-flight Route step as data: Session.setup.route (shape in the route contract, also read by
## core/route_setup.gd at flight start):
##   {dest, arr_rwy, wps: [{id, kind, x, y, alt_ft}], cruise_ft, kind, air_at}
## The departure is always setup.airport and is never in wps. Pure statics over a setup-shaped Dictionary (no nodes):
## the edits the page and its map make (add, insert, move, remove, replace), the points and legs with magnetic course,
## distance, time and altitude, the rail / chip texts (warnings: core/route_checks.gd). Waypoint dicts come from
## RouteBuilder (avionics/route_builder.gd). The NavDatabase is loaded once (db()).

const NM := 1852.0
const FALLBACK_KT := RouteFuel.FALLBACK_KT  # cruise speed when the aircraft names none
const JET_KT := 250.0  # at or above this cruise speed the default cruise altitude is a flight level

## The navigation data (airports, VOR / NDB, airway fixes), read on first use.
static func db() -> NavDatabase:
	return RouteChecks.db()


## A full route dict from whatever setup.route holds (missing keys get their defaults; a copy, never the live dict).
static func normalized(r: Variant, aircraft := "") -> Dictionary:
	var src: Dictionary = r if r is Dictionary else {}
	var cruise := float(src.get("cruise_ft", default_cruise_ft(aircraft)))
	var out := {"dest": str(src.get("dest", "")), "arr_rwy": str(src.get("arr_rwy", "")), "wps": [], "cruise_ft": cruise,
		"kind": str(src.get("kind", "manual")), "air_at": int(src.get("air_at", -1))}
	var wps = src.get("wps", [])
	for w in (wps if wps is Array else []):
		if w is Dictionary and w.has("id"):
			var c: Dictionary = w.duplicate()
			c.alt_ft = float(c.get("alt_ft", cruise))
			out.wps.append(c)
	return out


static func route_of(setup: Dictionary) -> Dictionary:
	return normalized(setup.get("route", {}), str(setup.get("aircraft", "")))


## A route is planned when it has a destination or at least one waypoint.
static func planned(r: Dictionary) -> bool:
	return str(r.get("dest", "")) != "" or not (r.get("wps", []) as Array).is_empty()


## The route's points in order: [{id, kind ("dep" | waypoint kind | "dest"), pos (Vector2 world metres), wp}] where wp
## is the index in wps, -1 for the departure and -2 for the destination. An unknown departure or destination is left out.
static func points(setup: Dictionary, d: NavDatabase) -> Array:
	var r := route_of(setup)
	var out := []
	var dep = d.position_of(str(setup.get("airport", ""))) if d != null else null
	if dep != null:
		out.append({"id": str(setup.airport), "kind": "dep", "pos": dep, "wp": -1})
	for i in r.wps.size():
		var w: Dictionary = r.wps[i]
		out.append({"id": str(w.id), "kind": str(w.get("kind", "fix")), "pos": Vector2(float(w.x), float(w.y)), "wp": i})
	if r.dest != "" and d != null:
		var p = d.position_of(r.dest)
		if p != null:
			out.append({"id": r.dest, "kind": "dest", "pos": p, "wp": -2})
	return out


## One dict per leg, for the map (MapRouteLayer reads a, b, ident, active, dist_m, cum_m) and the nav log:
## from, kind, course_mag (deg), ete_s and cum_s at `tas_kt`, alt_ft (planned altitude of the leg), wp (index in wps of
## the leg's end, -2 = destination) and insert_at (where a waypoint put on this leg goes in wps).
static func legs(setup: Dictionary, d: NavDatabase, tas_kt: float) -> Array:
	var r := route_of(setup)
	var pts := points(setup, d)
	var mps := maxf(tas_kt, 1.0) * NM / 3600.0
	var out := []
	var cum := 0.0
	for k in range(1, pts.size()):
		var a: Vector2 = pts[k - 1].pos
		var b: Vector2 = pts[k].pos
		var dist := a.distance_to(b)
		cum += dist
		var wp: int = pts[k].wp
		out.append({"a": a, "b": b, "ident": pts[k].id, "from": pts[k - 1].id, "kind": pts[k].kind, "active": false,
			"dist_m": dist, "cum_m": cum, "course_mag": course_mag(a, b), "ete_s": dist / mps, "cum_s": cum / mps,
			"alt_ft": leg_alt(r, wp), "wp": wp, "insert_at": wp if wp >= 0 else r.wps.size()})
	return out


## Magnetic course (deg 0..360) from a to b, with the variation the GPS uses.
static func course_mag(a: Vector2, b: Vector2) -> float:
	return fposmod(RoutePlan.bearing_deg(a, b) - Gps.VAR_DEG, 360.0)


## Planned altitude of the leg that ends at wps[wp]; the leg into the destination (wp < 0) flies the last waypoint's.
static func leg_alt(r: Dictionary, wp: int) -> float:
	var wps: Array = r.wps
	if wp >= 0 and wp < wps.size():
		return float(wps[wp].alt_ft)
	return float(wps.back().alt_ft) if not wps.is_empty() else float(r.cruise_ft)


# ---- edits (on a normalized route dict, in place) ----

## Append a waypoint before the destination. False (nothing added) when it repeats the last point.
static func add(r: Dictionary, wp: Dictionary) -> bool:
	var last: String = str(r.wps.back().id) if not r.wps.is_empty() else ""
	if wp.is_empty() or str(wp.id) == last:
		return false
	r.wps.append(wp)
	r.kind = "manual"
	return true


static func insert(r: Dictionary, at: int, wp: Dictionary) -> void:
	r.wps.insert(clampi(at, 0, r.wps.size()), wp)
	r.kind = "manual"


static func replace(r: Dictionary, i: int, wp: Dictionary) -> void:
	if i >= 0 and i < r.wps.size():
		r.wps[i] = wp
		r.kind = "manual"


static func remove(r: Dictionary, i: int) -> void:
	if i >= 0 and i < r.wps.size():
		r.wps.remove_at(i)
		r.kind = "manual"


## Move wps[i] up (delta -1) or down (+1); returns its new index.
static func move(r: Dictionary, i: int, delta: int) -> int:
	var j := i + delta
	if i < 0 or i >= r.wps.size() or j < 0 or j >= r.wps.size():
		return i
	var w = r.wps[i]
	r.wps.remove_at(i)
	r.wps.insert(j, w)
	r.kind = "manual"
	return j


## New cruise altitude: waypoints that were at the old one follow it.
static func set_cruise(r: Dictionary, ft: float) -> void:
	for w in r.wps:
		if is_equal_approx(float(w.alt_ft), float(r.cruise_ft)):
			w.alt_ft = ft
	r.cruise_ft = ft


## Number of legs of the route (departure, wps, destination).
static func leg_count(setup: Dictionary) -> int:
	return legs(setup, db(), FALLBACK_KT).size()


## The route as idents, "VABB PAPRI GOA VAPO" (what the text box shows).
static func as_text(setup: Dictionary) -> String:
	var r := route_of(setup)
	if not planned(r):
		return ""
	var ids := PackedStringArray([str(setup.get("airport", ""))])
	for w in r.wps:
		ids.append(str(w.id))
	if r.dest != "":
		ids.append(r.dest)
	return " ".join(ids)


# ---- texts ----

## Rail line: "VABB → VAPO · 3 wpts · 62 nm", "VABB → VAPO · direct · 62 nm" or "Not planned".
static func rail_text(setup: Dictionary) -> String:
	var r := route_of(setup)
	if not planned(r):
		return "Not planned"
	var n: int = r.wps.size()
	var to: String = r.dest if r.dest != "" else str(r.wps.back().id)
	var via := "direct" if n == 0 else "%d wpt%s" % [n, "" if n == 1 else "s"]
	return "%s → %s · %s · %d nm" % [str(setup.get("airport", "")), to, via, roundi(total_nm(setup))]


## Chip: "→ VAPO · 62 nm" or "No route".
static func chip_text(setup: Dictionary) -> String:
	var r := route_of(setup)
	if not planned(r):
		return "No route"
	return "→ %s · %d nm" % [r.dest if r.dest != "" else str(r.wps.back().id), roundi(total_nm(setup))]


static func total_nm(setup: Dictionary) -> float:
	var ls := legs(setup, db(), FALLBACK_KT)
	return ls.back().cum_m / NM if not ls.is_empty() else 0.0


# ---- the aircraft ----

## Cruise true airspeed (kt) for times (RouteFuel.cruise_kt: the "Cruise" line of aircraft.json specs).
static func cruise_kt(aircraft: String) -> float:
	return RouteFuel.cruise_kt(aircraft)


## Default cruise altitude: 4,500 ft for a light aircraft, FL240 for a jet (cruise at or above JET_KT).
static func default_cruise_ft(aircraft: String) -> float:
	return 24000.0 if aircraft != "" and cruise_kt(aircraft) >= JET_KT else 4500.0
