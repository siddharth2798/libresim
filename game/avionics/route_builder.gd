class_name RouteBuilder
extends RefCounted
## Builds the optional pre-flight route (Session.setup.route; core/route_setup.gd takes it into the flight).
## A waypoint is {id, kind: "airport" | "vor" | "ndb" | "fix" | "user", x, y (ENU m), alt_ft (the leg that ends there)}.
## auto():
##   direct  no waypoints.
##   vor     a chain of VOR / NDB stations, every leg at most VOR_MAX_HOP_M. Shortest by a cost that grows faster than
##           the leg length (d x (1 + (d / max hop)^2) + a small cost per hop), so a station close to the straight line
##           splits a long leg, a detour does not pay, and a trip under about 35 nm stays direct. Stations within
##           VOR_NEAR_END_M of either end are not hops (the airport's own VOR). No chain under the max hop: once more with
##           VOR_FAR_HOP_M, then an error. Deterministic.
##   airway  shortest path over the published airways (airways.json; direction honoured). The route joins the network at
##           a fix within AIRWAY_JOIN_M of the departure and leaves it at one within AIRWAY_JOIN_M of the destination,
##           and flies at least one airway segment.
## parse(): "VABB DCT PAPRI W15 GOA VAPO" or "VABB/PAPRI/VAPO" (airway.gd expands designators).

const NM := 1852.0
const VOR_MAX_HOP_M := 120.0 * NM
const VOR_FAR_HOP_M := 200.0 * NM  # tried when no chain has every leg under VOR_MAX_HOP_M (sparse stations down south)
const VOR_NEAR_END_M := 3.0 * NM
const VOR_HOP_COST_M := 2.0 * NM
const AIRWAY_JOIN_M := 60.0 * NM


## Auto-route from `from` (departure airport ident) to `to` (destination ident).
## kind: "direct" -> wps = [] ; "vor" -> VOR/NDB hops ; "airway" -> fixes along published airways (shortest path),
## falling back to an error when no airway path exists.
static func auto(kind: String, from: String, to: String, db: NavDatabase, cruise_ft: float) -> Dictionary:
	var a: Variant = db.position_of(from.strip_edges().to_upper()) if db != null else null
	var b: Variant = db.position_of(to.strip_edges().to_upper()) if db != null else null
	if a == null:
		return _fail("Unknown departure %s" % from)
	if b == null:
		return _fail("Unknown destination %s" % to)
	if not kind in ["direct", "vor", "airway"]:
		return _fail("Unknown route kind %s" % kind)
	if kind == "direct" or a.distance_to(b) < NM:  # a round trip back to the departure has nothing to route
		return {"ok": true, "error": "", "wps": []}
	match kind:
		"vor":
			var r := _vor(a, b, db, cruise_ft, VOR_MAX_HOP_M)
			return r if r.ok else _vor(a, b, db, cruise_ft, VOR_FAR_HOP_M)
		"airway":
			return RouteAirways.shortest(from.to_upper(), to.to_upper(), a, b, db, cruise_ft)
	return _fail("Unknown route kind %s" % kind)  # not reached


## Text entry "VABB DCT PAPRI W15 GOA VAPO" or "VABB/PAPRI/VAPO": first ident = departure (ignored if it equals
## `from`), last ident = destination when it is an airport. DCT tokens are dropped, airways expanded (airway.gd).
static func parse(text: String, from: String, db: NavDatabase, cruise_ft: float) -> Dictionary:
	var toks: Array = []
	for t in text.to_upper().replace("/", " ").replace(",", " ").replace("\t", " ").replace("\n", " ").split(" ", false):
		var s := str(t).strip_edges()
		if s != "" and s != "DCT":
			toks.append(s)
	if toks.is_empty():
		return {"ok": true, "error": "", "dest": "", "wps": []}
	var dep := from.strip_edges().to_upper()
	if dep != "" and toks[0] != dep:
		toks.push_front(dep)  # an airway right after the departure needs it as the entry
	var airways: Dictionary = db.airways if db != null else {}
	var exp := Airway.expand(toks, airways)
	if not exp.ok:
		return {"ok": false, "error": _airway_error(toks, airways, str(exp.error)), "dest": "", "wps": []}
	var parts: Array = exp.parts
	if dep != "":
		parts = parts.slice(1)
	var wps: Array = []
	for id in parts:
		var w := waypoint(str(id), db, cruise_ft)
		if w.is_empty():
			return {"ok": false, "error": "Unknown waypoint %s" % id, "dest": "", "wps": []}
		if wps.is_empty() or str(wps.back().id) != w.id:
			wps.append(w)
	var dest := ""
	if not wps.is_empty() and wps.back().kind == "airport":
		dest = str(wps.pop_back().id)
	return {"ok": true, "error": "", "dest": dest, "wps": wps}


## One waypoint dict for an ident known to db ({} if unknown), with its kind and position.
static func waypoint(ident: String, db: NavDatabase, alt_ft: float) -> Dictionary:
	var id := ident.strip_edges().to_upper()
	if id == "" or db == null:
		return {}
	var kind := ""
	var ap := db.airport(id)
	if not ap.is_empty():
		kind = "airport"
		id = str(ap.icao) if str(ap.get("icao", "")) != "" else str(ap.ident)
	elif db.vors.any(func(v): return str(v.ident) == id):
		kind = "vor"
	elif db.ndbs.any(func(n): return str(n.ident) == id):
		kind = "ndb"
	elif db.fixes.has(id) or RunwayWaypoints.position(id, db.airports) != null:
		kind = "fix"
	elif NavDatabase.route_fixes.has(id):
		kind = "user"
	var p: Variant = db.position_of(id) if kind != "" else null
	if p == null:
		return {}
	return {"id": id, "kind": kind, "x": float(p.x), "y": float(p.y), "alt_ft": alt_ft}


## Free waypoint at a world position, id = next free "WPTnn" not used in `wps`.
static func user_waypoint(pos: Vector2, wps: Array, alt_ft: float) -> Dictionary:
	var used := {}
	for w in wps:
		if w is Dictionary:
			used[str(w.get("id", ""))] = true
	var n := 1
	while used.has("WPT%02d" % n):
		n += 1
	return {"id": "WPT%02d" % n, "kind": "user", "x": pos.x, "y": pos.y, "alt_ft": alt_ft}


static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg, "wps": []}


## VOR / NDB chain: Dijkstra over [departure, destination, stations] (24 nodes at most, O(n^2)).
static func _vor(a: Vector2, b: Vector2, db: NavDatabase, cruise_ft: float, max_hop: float) -> Dictionary:
	var ids: Array = ["", ""]
	var pts: Array = [a, b]
	for s in db.vors + db.ndbs:
		var p := Vector2(float(s.x), float(s.y))
		if str(s.ident) in ids or p.distance_to(a) < VOR_NEAR_END_M or p.distance_to(b) < VOR_NEAR_END_M:
			continue
		if db.position_of(str(s.ident)) != p:  # an ident another station or airport answers to first: not a usable hop
			continue
		ids.append(str(s.ident))
		pts.append(p)
	var n := pts.size()
	var dist: Array = []
	var prev: Array = []
	var done: Array = []
	for i in n:
		dist.append(INF)
		prev.append(-1)
		done.append(false)
	dist[0] = 0.0
	while true:
		var u := -1
		for i in n:
			if not done[i] and dist[i] < INF and (u < 0 or dist[i] < dist[u]):
				u = i
		if u < 0 or u == 1:
			break
		done[u] = true
		for v in n:
			if done[v] or v == u:
				continue
			var c := _hop_cost(pts[u].distance_to(pts[v]), max_hop)
			if dist[u] + c < dist[v]:
				dist[v] = dist[u] + c
				prev[v] = u
	if prev[1] < 0:
		return _fail("No VOR/NDB route with legs under %d nm" % int(max_hop / NM))
	var chain: Array = []
	var k: int = prev[1]
	while k > 0:
		chain.push_front(k)
		k = prev[k]
	var wps: Array = []
	for i in chain:
		wps.append(waypoint(str(ids[i]), db, cruise_ft))
	return {"ok": true, "error": "", "wps": wps}


static func _hop_cost(d: float, max_hop: float) -> float:
	if d > max_hop:
		return INF
	var r := d / VOR_MAX_HOP_M
	return d * (1.0 + r * r) + VOR_HOP_COST_M


## A readable reason for a failed airway expansion: which airway and which idents.
static func _airway_error(toks: Array, airways: Dictionary, code: String) -> String:
	for i in range(1, toks.size() - 1):
		var aw := str(toks[i])
		if not airways.has(aw) or airways.has(str(toks[i + 1])):
			continue
		var r := Airway.expand([toks[i - 1], aw, toks[i + 1]], airways)
		if r.ok:
			continue
		match str(r.error):
			Airway.WRONG_WAY:
				return "Airway %s is one way: it cannot be flown from %s to %s" % [aw, toks[i - 1], toks[i + 1]]
			Airway.AMBIGUOUS:
				return "%s or %s is on airway %s twice" % [toks[i - 1], toks[i + 1], aw]
			_:
				return "%s and %s are not both on airway %s" % [toks[i - 1], toks[i + 1], aw]
	return "Airway: " + code.capitalize()
