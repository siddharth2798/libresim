class_name AirportData
extends RefCounted
## What the Airport step lists: every airport with a runway (airports.json + runways.json + airport_ops.json), as
##   {icao, name, city, elev_m, runways (longest first), stands, taxiways, type}
## `city` comes from world/airport_cities.json (the airports data has none; "" when not listed). Heliports are left out.

const CITIES := "res://world/airport_cities.json"


static func load_all() -> Array:
	var out := []
	var apts = Paths.load_json("airports.json")
	var rw = Paths.load_json("runways.json")
	var ops = Paths.load_json("airport_ops.json")
	if apts == null or rw == null:
		return out
	ops = ops if ops else {}
	var cities = Paths.load_res_json(CITIES)
	cities = cities if cities is Dictionary else {}
	for a in apts:
		var code: String = a.icao if str(a.icao) != "" else a.ident
		var rws: Array = rw.runways.filter(func(r): return r.airport == code)
		if rws.is_empty() or a.type == "heliport":
			continue
		rws.sort_custom(func(x, y): return x.length > y.length)
		out.append({"icao": code, "name": a.name, "city": str(cities.get(code, "")), "elev_m": float(a.elev_m), "runways": rws,
			"stands": ops.get(code, {}).get("stands", []), "taxiways": _taxiways(rw, rws), "type": a.type})
	out.sort_custom(func(x, y): return x.type < y.type if x.type != y.type else x.icao < y.icao)
	return out


## The taxiway polylines that start within 2.5 km of the runway ends: [PackedVector2Array].
static func _taxiways(rw: Dictionary, rws: Array) -> Array:
	var box := Rect2(Vector2(rws[0].ends[0].x, rws[0].ends[0].y), Vector2.ZERO)
	for r in rws:
		for e in r.ends:
			box = box.expand(Vector2(e.x, e.y))
	box = box.grow(2500.0)
	var tws := []
	for t in rw.taxiways:
		if box.has_point(Vector2(t.pts[0][0], t.pts[0][1])):
			tws.append(t.pts.map(func(p): return Vector2(p[0], p[1])))
	return tws


## "VABB  Chhatrapati Shivaji Maharaj International Airport · Mumbai" style row text of the search list.
static func row_text(a: Dictionary) -> String:
	var t := "%s  %s" % [a.icao, a.name]
	return t + " · " + str(a.city) if str(a.get("city", "")) != "" else t


## The entries of the search box for `airports`: [{id, ident, name, city, text, note, short}]. `min_runway_m`: a field whose
## longest runway is shorter is flagged `short` (too short for the aircraft).
static func search_items(airports: Array, min_runway_m: float) -> Array:
	var out := []
	for a in airports:
		var longest := float(a.runways[0].length) if not a.runways.is_empty() else 0.0
		out.append({"id": a.icao, "ident": a.icao, "name": str(a.name), "city": str(a.get("city", "")), "text": row_text(a),
			"note": "%s m longest%s" % [AirportData.thousands(int(longest)), " · %d stands" % a.stands.size() if not a.stands.is_empty() else ""],
			"short": longest < min_runway_m})
	return out


static func thousands(n: int) -> String:
	var t := str(absi(n))
	for i in range(t.length() - 3, 0, -3):
		t = t.insert(i, ",")
	return ("-" if n < 0 else "") + t


## Head / cross wind (kt) on a runway of `heading_deg` for a wind from `wind_dir_deg` at `wind_kt`: {head (negative = tail),
## cross (positive = from the right)}.
static func wind_parts(wind_dir_deg: float, wind_kt: float, heading_deg: float) -> Dictionary:
	var rel := deg_to_rad(wind_dir_deg - heading_deg)
	return {"head": wind_kt * cos(rel), "cross": wind_kt * sin(rel)}


## "head 8 · cross 0 kt" / "TAIL 6 · cross 3 kt".
static func wind_text(w: Dictionary) -> String:
	return "%s %d · cross %d kt" % ["head" if w.head >= 0.0 else "TAIL", roundi(absf(w.head)), roundi(absf(w.cross))]


## True when the wind on that runway would make Fly ask (SetupChecks: tailwind above 5 kt, crosswind above the limit).
static func wind_bad(w: Dictionary, max_crosswind_kt: float) -> bool:
	return -float(w.head) > SetupChecks.TAILWIND_KT or absf(float(w.cross)) > max_crosswind_kt
