class_name RoutePageData
extends RefCounted
## What the Route step (route_page.gd) shows that is not the route itself: the airport list (AirportData, read once),
## the runways the map draws, the departure line, the arrival runway choices and the end points the map rings.
## Pure statics, no nodes.

static var _airports: Array = []


## AirportData.load_all(), read on first use.
static func airports() -> Array:
	if _airports.is_empty():
		_airports = AirportData.load_all()
	return _airports


## Every runway of `apts` as {ends, width} (what MapFeatures.draw_airports draws).
static func runways(apts: Array) -> Array:
	var out := []
	for a in apts:
		out.append_array(a.runways)
	return out


## "VABB 27", "VABB · stand 12" or "VABB · in the air" (the departure as the Airport step set it).
static func from_text(s: Dictionary) -> String:
	var icao := str(s.get("airport", ""))
	match str(s.get("start", "runway")):
		"stand":
			return icao + " · stand"
		"air":
			return icao + " · in the air"
	var rw := str(s.get("runway", ""))
	if rw == "":
		rw = str(SetupChecks.runway_of(s).get("ident", ""))
	return (icao + " " + rw).strip_edges()


## Segmented options of the destination's runway ends: [["", "Any"], ["09", "09"], ...]; [] without a destination.
static func runway_options(apts: Array, dest: String) -> Array:
	if dest == "":
		return []
	var out := [["", "Any", "No arrival runway chosen"]]
	for a in apts:
		if str(a.icao) != dest:
			continue
		for r in a.runways:
			for e in r.ends:
				out.append([str(e.ident), str(e.ident), "Arrive on runway %s (%s m)" % [e.ident, AirportData.thousands(int(r.length))]])
	return out


## {id, pos} of the departure for the map's green ring; {} when the airport is not in the nav data.
static func dep_point(s: Dictionary, d: NavDatabase) -> Dictionary:
	var p = d.position_of(str(s.get("airport", "")))
	return {} if p == null else {"id": str(s.airport), "pos": p}


static func dest_point(r: Dictionary, d: NavDatabase) -> Dictionary:
	var p = d.position_of(str(r.dest)) if str(r.dest) != "" else null
	return {} if p == null else {"id": str(r.dest), "pos": p}
