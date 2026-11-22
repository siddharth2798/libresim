class_name PlanImport
extends RefCounted
## Between libresim routes (Session.setup.route + setup.airport) and the PlanFile plan Dictionary (MSFS / Little Navmap
## .PLN). Positions go through Geo (the world's Transverse Mercator), so a plan exported here opens where it should in
## MSFS and Little Navmap, and their plans land on the same spots here.
## Import: the departure must be an airport of the nav data (else an error: the world does not have it). Each waypoint
## whose ident the nav data knows (within MATCH_M of the file's position) becomes that point; any other with a position
## inside the world becomes a free (user) waypoint WPTnn there; waypoints outside the world are left out (a note says
## which). Altitudes: a waypoint's WorldPosition altitude when above 0, else CruisingAlt (else the default cruise).

const FT := 0.3048
const MATCH_M := 10.0 * 1852.0
const WORLD_M := 900000.0  # without terrain data: "inside the world" = this far from the origin
const KINDS := {"airport": "Airport", "vor": "VOR", "ndb": "NDB", "fix": "Intersection", "user": "User"}


## The setup's route as a PlanFile plan; {} when there is no route or the departure is unknown.
static func from_setup(setup: Dictionary, d: NavDatabase) -> Dictionary:
	var r := RouteSetup.repair(setup.get("route", {}))
	var dep := str(setup.get("airport", ""))
	var dep_ap := d.airport(dep) if d != null else {}
	if not RouteSetup.active(r) or dep_ap.is_empty():
		return {}
	var cruise := float(r.cruise_ft)
	var wps := [_airport_wp(dep_ap)]
	for w in r.wps:
		wps.append({"id": str(w.id), "type": KINDS.get(str(w.kind), "Intersection"), "airway": "",
			"lla": _lla(Vector2(float(w.x), float(w.y)), float(w.alt_ft))})
	var dest_ap := d.airport(str(r.dest)) if str(r.dest) != "" else {}
	if not dest_ap.is_empty():
		wps.append(_airport_wp(dest_ap))
	var to: String = str(wps.back().id)
	var ifr := str(r.kind) == "airway" or cruise >= 18000.0
	var rtype: String = {"direct": "Direct", "vor": "VOR"}.get(str(r.kind), "HighAlt" if cruise >= 18000.0 else "LowAlt")
	return {"title": "%s to %s" % [_ident(dep_ap), to], "fp_type": "IFR" if ifr else "VFR", "route_type": rtype,
		"cruise_ft": cruise, "dep_id": _ident(dep_ap), "dep": wps[0].lla, "dest_id": _ident(dest_ap) if not dest_ap.is_empty() else "",
		"dest": wps.back().lla if not dest_ap.is_empty() else {}, "wps": wps}


static func _ident(ap: Dictionary) -> String:
	return str(ap.icao) if str(ap.get("icao", "")) != "" else str(ap.get("ident", ""))


static func _airport_wp(ap: Dictionary) -> Dictionary:
	return {"id": _ident(ap), "type": "Airport", "airway": "", "lla": _lla(Vector2(float(ap.x), float(ap.y)), float(ap.get("elev_m", 0.0)) / FT)}


static func _lla(p: Vector2, alt_ft: float) -> Dictionary:
	var ll := Geo.to_latlon(p.x, p.y)
	return {"lat": ll.x, "lon": ll.y, "alt_ft": alt_ft}


## The plan as a route: {ok, error, airport (departure ident), route (Session.setup.route shape), notes: [String]}.
## `inside` = Callable(Vector2 world m) -> bool (world_inside() by default).
static func to_route(plan: Dictionary, d: NavDatabase, default_cruise: float, inside := Callable()) -> Dictionary:
	if not inside.is_valid():
		inside = world_inside()
	var fail := func(msg: String) -> Dictionary: return {"ok": false, "error": msg, "airport": "", "route": {}, "notes": []}
	var wps: Array = plan.get("wps", []).duplicate()
	var dep_id := str(plan.get("dep_id", ""))
	if dep_id == "" and not wps.is_empty() and str(wps[0].type) == "Airport":
		dep_id = str(wps[0].id)
	if dep_id == "":
		return fail.call("The plan names no departure airport")
	var dep_ap := d.airport(dep_id)
	if dep_ap.is_empty():
		return fail.call("Departure %s is not in libresim's world: the plan cannot start there" % dep_id)
	if not wps.is_empty() and str(wps[0].id) == dep_id:
		wps.pop_front()
	var dest_id := str(plan.get("dest_id", ""))
	if dest_id == "" and not wps.is_empty() and str(wps.back().type) == "Airport":
		dest_id = str(wps.back().id)
	if dest_id != "" and not wps.is_empty() and str(wps.back().id) == dest_id:
		wps.pop_back()
	var cruise := float(plan.get("cruise_ft", 0.0))
	if cruise <= 0.0:
		cruise = default_cruise
	var notes: Array = []
	var outside: Array = []
	var dest := ""
	if dest_id != "":
		if not d.airport(dest_id).is_empty():
			dest = _ident(d.airport(dest_id))
		else:
			wps.append({"id": dest_id, "type": "User", "lla": plan.get("dest", {}), "airway": ""})
			notes.append("Destination %s is not in the nav data: it is the last waypoint" % dest_id)
	var out := []
	for w in wps:
		var lla: Dictionary = w.get("lla", {})
		var alt := float(lla.get("alt_ft", 0.0))
		if alt <= 0.0 or str(w.type) == "Airport":
			alt = cruise
		var file_pos: Variant = Geo.to_enu(float(lla.lat), float(lla.lon)) if not lla.is_empty() else null
		var known := RouteBuilder.waypoint(str(w.id), d, alt)
		if not known.is_empty() and (file_pos == null or Vector2(known.x, known.y).distance_to(file_pos) < MATCH_M):
			out.append(known)
		elif file_pos == null:
			outside.append(str(w.id))
		elif not inside.call(file_pos):
			outside.append(str(w.id))
		else:
			out.append(RouteBuilder.user_waypoint(file_pos, out, alt))
	if not outside.is_empty():
		notes.append("Left out %d waypoint%s outside libresim's world or not in its nav data: %s" % [outside.size(),
			"" if outside.size() == 1 else "s", ", ".join(outside)])
	var route := {"dest": dest, "arr_rwy": "", "wps": out, "cruise_ft": cruise, "kind": "manual", "air_at": -1}
	return {"ok": true, "error": "", "airport": _ident(dep_ap), "route": route, "notes": notes}


## Inside the world: a terrain tile covers it (any level); without terrain data, within WORLD_M of the origin.
static func world_inside() -> Callable:
	var th := TerrainHeights.shared()
	if th.meta.levels.is_empty():
		return func(p: Vector2) -> bool: return p.length() < WORLD_M
	return func(p: Vector2) -> bool: return th.covers(p.x, p.y)


## A .PLN file's bytes as text: UTF-8, else Latin-1 (older FSX files), each byte one character.
static func decode(bytes: PackedByteArray) -> String:
	var t := bytes.get_string_from_utf8()
	if t.length() > 0 and not t.contains("�"):
		return t
	var out := PackedStringArray()
	for b in bytes:
		out.append(char(b) if b > 0 else "")
	return "".join(out)
