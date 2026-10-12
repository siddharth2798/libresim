extends Node
## Stand data in data/processed/airport_ops.json (tools/13_airport_ops.py + airport_stands.py):
## Kochi's airliner stands derived from its jet bridges (gates at the cab tips, remote bays, each
## linked into the taxi graph), stand lines drawn the wrong way round in OSM (Mangaluru, Goa), and GA
## tie-downs kept off the taxiways. Needs data/processed.

var _ops = null
var _term = null


func _data() -> Dictionary:
	if _ops == null:
		_ops = Paths.load_json("airport_ops.json")
		_term = Paths.load_json("terminals/VOCI.json")
	return _ops if _ops != null else {}


func _rings() -> Array:  # terminal and terminal-part footprints of Kochi as PackedVector2Array
	var out := []
	if _term == null:
		return out
	for k in ["terminals", "parts"]:
		for b in _term.get(k, []):
			for ring in b.outers:
				var pts := PackedVector2Array()
				for p in ring:
					pts.append(Vector2(p[0], p[1]))
				out.append(pts)
	return out


func _ring_dist(p: Vector2, ring: PackedVector2Array) -> float:
	var best := INF
	for i in ring.size():
		var q := Geometry2D.get_closest_point_to_segment(p, ring[i], ring[(i + 1) % ring.size()])
		best = minf(best, p.distance_to(q))
	return best


func _new_stands(a: Dictionary) -> Array:
	return a.stands.filter(func(s): return s.get("src", "") in ["bridge", "gate", "remote"])


func test_voci_gates_at_the_bridges() -> String:
	var a: Dictionary = _data().get("VOCI", {})
	if a.is_empty():
		return "no VOCI in airport_ops.json"
	var rings := _rings()
	var gates: Array = a.stands.filter(func(s): return s.get("src", "") == "bridge")
	if gates.size() < 10:
		return "%d bridge gates at VOCI, want at least 10 (16 jet bridges, 5 + 6 gates)" % gates.size()
	var bad := []
	for s in gates:
		var p := Vector2(s.x, s.y)
		if not (s.jetbridge and s.kind == "gate"):
			bad.append("%s not flagged as a jetbridge gate" % s.ref)
		var cab := INF  # the aircraft's L1 door stands at a bridge's cab tip
		for jb in a.jetbridges:
			for end in [jb.pts[0], jb.pts[-1]]:
				cab = minf(cab, p.distance_to(Vector2(end[0], end[1])))
		if cab > 8.0:
			bad.append("%s is %.0f m from the nearest bridge end" % [s.ref, cab])
		var d := INF
		for ring in rings:
			d = minf(d, _ring_dist(p, ring))
		if d > 120.0:
			bad.append("%s is %.0f m from the terminal" % [s.ref, d])
		var hd := deg_to_rad(float(s.heading_deg))
		var nose := p + Vector2(sin(hd), cos(hd)) * 4.8
		var tail := p - Vector2(sin(hd), cos(hd)) * 32.0
		for ring in rings:
			if Geometry2D.is_point_in_polygon(nose, ring) or Geometry2D.is_point_in_polygon(tail, ring) or Geometry2D.is_point_in_polygon(p, ring):
				bad.append("%s: the aircraft stands inside a terminal footprint" % s.ref)
	return "" if bad.is_empty() else "; ".join(bad)


func test_voci_stands_have_taxi_routes() -> String:
	var all := _data()
	var a: Dictionary = all.get("VOCI", {})
	var rw = Paths.load_json("runways.json")
	if a.is_empty() or rw == null:
		return "no VOCI data"
	var ops := AirportOps.new()
	ops.data = all
	var ends := []
	for r in rw.runways:
		if r.airport == "VOCI":
			for e in r.ends:
				ends.append(Vector2(e.x, e.y))
	var bad := []
	var n := 0
	for s in a.stands:
		if s.get("src", "") not in ["bridge", "gate", "remote", "osm"]:
			continue
		n += 1
		for e in ends:
			var r: Dictionary = ops.route("VOCI", e, Vector2(s.x, s.y))
			if r.is_empty() or r.path.size() < 2:
				bad.append("%s: no route from the runway end at %.0f,%.0f" % [s.ref, e.x, e.y])
			elif (r.path[-1] as Vector2).distance_to(Vector2(s.x, s.y)) > 2.0:
				bad.append("%s: the route ends %.0f m from the stand" % [s.ref, (r.path[-1] as Vector2).distance_to(Vector2(s.x, s.y))])
	ops.free()
	if n < 20:
		return "only %d real stands at VOCI" % n
	return "" if bad.is_empty() else "; ".join(bad.slice(0, 6))


func test_voci_stand_refs_and_links() -> String:
	var a: Dictionary = _data().get("VOCI", {})
	if a.is_empty():
		return "no VOCI data"
	var seen := {}
	var bad := []
	var at := {}  # stand position -> true for taxi nodes at a stand
	for id in a.taxi.nodes:
		at["%.1f,%.1f" % [a.taxi.nodes[id][0], a.taxi.nodes[id][1]]] = id
	var linked := {}
	for e in a.taxi.edges:
		if e[4] == "parking_position":
			linked[e[0]] = true
			linked[e[1]] = true
	for s in _new_stands(a):
		if str(s.ref) == "" or seen.has(s.ref):
			bad.append("duplicate or empty ref '%s'" % s.ref)
		seen[s.ref] = true
		var id = at.get("%.1f,%.1f" % [s.x, s.y], "")
		if id == "" or not linked.has(id):
			bad.append("%s has no lead-in edge" % s.ref)
	return "" if bad.is_empty() else "; ".join(bad.slice(0, 6))


func test_voci_remote_bays_fit_an_airliner() -> String:
	var a: Dictionary = _data().get("VOCI", {})
	var bays: Array = a.stands.filter(func(s): return s.get("src", "") == "remote")
	if bays.size() < 8:
		return "%d remote bays at VOCI, want at least 8" % bays.size()
	var bad := []
	for i in bays.size():
		for j in range(i + 1, bays.size()):
			var d := Vector2(bays[i].x, bays[i].y).distance_to(Vector2(bays[j].x, bays[j].y))
			if d < 40.0:
				bad.append("%s and %s are %.0f m apart" % [bays[i].ref, bays[j].ref, d])
	return "" if bad.is_empty() else "; ".join(bad.slice(0, 4))


func test_stand_lines_stop_at_the_terminal_end() -> String:
	# Mangaluru and Goa draw some stand lines from the stop point out to the taxiway: the stand is the
	# end that does not touch the taxiway. Before the fix 11 of 15 (VOML) and 8 of 11 (VOGO) stood on
	# a taxiway; one VOML line is drawn taxiway to taxiway and stays.
	var all := _data()
	var bad := []
	for icao in ["VOML", "VOGO"]:
		var a: Dictionary = all.get(icao, {})
		if a.is_empty():
			return "no %s data" % icao
		var on_taxiway := 0
		for s in a.stands:
			if s.get("src", "") != "osm":
				continue
			for e in a.taxi.edges:
				if e[4] != "taxiway":
					continue
				var q := Geometry2D.get_closest_point_to_segment(Vector2(s.x, s.y), Vector2(a.taxi.nodes[e[0]][0], a.taxi.nodes[e[0]][1]), Vector2(a.taxi.nodes[e[1]][0], a.taxi.nodes[e[1]][1]))
				if q.distance_to(Vector2(s.x, s.y)) < 12.0:
					on_taxiway += 1
					break
		if on_taxiway > 1:
			bad.append("%s: %d stands within 12 m of a taxiway" % [icao, on_taxiway])
	var voml: Dictionary = all.get("VOML", {})
	var gates: int = voml.stands.filter(func(s): return s.jetbridge).size() if not voml.is_empty() else 0
	if gates < 6:
		bad.append("VOML: %d stands at the 6 jet bridges, want 6" % gates)
	return "" if bad.is_empty() else "; ".join(bad)


func test_ga_tiedowns_clear_of_taxiways() -> String:
	var bad := []
	for icao in _data():
		var a: Dictionary = _data()[icao]
		var edges: Array = a.taxi.edges.filter(func(e): return e[4] != "parking_position")
		for s in a.stands:
			if s.get("src", "") != "synth":
				continue
			var p := Vector2(s.x, s.y)
			for e in edges:
				var q := Geometry2D.get_closest_point_to_segment(p, Vector2(a.taxi.nodes[e[0]][0], a.taxi.nodes[e[0]][1]), Vector2(a.taxi.nodes[e[1]][0], a.taxi.nodes[e[1]][1]))
				if q.distance_to(p) < (10.0 if e[4] == "taxilane" else 14.0):  # taxilanes are narrower
					bad.append("%s %s is %.0f m from a %s" % [icao, s.ref, q.distance_to(p), e[4]])
					break
	return "" if bad.is_empty() else "%d: %s" % [bad.size(), "; ".join(bad.slice(0, 4))]
