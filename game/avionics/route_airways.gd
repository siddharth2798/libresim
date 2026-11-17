class_name RouteAirways
extends RefCounted
## Shortest route over the published airways (NavDatabase.airways: designator -> {fixes, direction}) for
## RouteBuilder.auto("airway"). A fix's position is what NavDatabase.position_of gives (fixes, or a navaid / airport of
## that ident), so the GPS flies the same point. Direction: "forward" = published order only, "back" = reverse only.
## Graph (AStar2D, every cost is a straight distance): departure -> every fix within JOIN_M (layer 0); an airway
## segment u -> v leads into layer 1 (v1) from u0 and u1; layer-1 fixes within JOIN_M of the destination -> destination.
## Fixes within 3 nm of either end are left out of the result (the airport's own VOR). Layer 1 means "flew at least one airway segment", so a fix near both ends is never the whole route.


static func shortest(from: String, to: String, a: Vector2, b: Vector2, db: NavDatabase, cruise_ft: float) -> Dictionary:
	var join := RouteBuilder.AIRWAY_JOIN_M
	var idx := {}  # fix ident -> 0..n-1
	var pos: Array = []
	var names: Array = []
	var segs: Array = []  # [u, v] directed
	var keys: Array = db.airways.keys()
	keys.sort()
	for k in keys:
		var aw: Variant = db.airways[k]
		if typeof(aw) != TYPE_DICTIONARY:
			continue
		var fixes: Array = aw.get("fixes", [])
		var way := str(aw.get("direction", "both"))
		var prev := -1
		for f in fixes:
			var id := str(f)
			if not idx.has(id):
				var p: Variant = db.position_of(id)
				if p == null:
					prev = -1
					continue
				idx[id] = pos.size()
				pos.append(p)
				names.append(id)
			var cur: int = idx[id]
			if prev >= 0 and prev != cur:
				if way != "back":
					segs.append([prev, cur])
				if way != "forward":
					segs.append([cur, prev])
			prev = cur
	var n := pos.size()
	var g := AStar2D.new()
	g.reserve_space(2 * n + 2)
	for i in n:
		g.add_point(i, pos[i])
		g.add_point(n + i, pos[i])
	var src := 2 * n
	var dst := 2 * n + 1
	g.add_point(src, a)
	g.add_point(dst, b)
	var entries := 0
	var exits := 0
	for i in n:
		if a.distance_to(pos[i]) <= join:
			g.connect_points(src, i, false)
			entries += 1
		if b.distance_to(pos[i]) <= join:
			g.connect_points(n + i, dst, false)
			exits += 1
	if entries == 0:
		return {"ok": false, "error": "No airway within %d nm of %s" % [int(join / RouteBuilder.NM), from], "wps": []}
	if exits == 0:
		return {"ok": false, "error": "No airway within %d nm of %s" % [int(join / RouteBuilder.NM), to], "wps": []}
	for s in segs:
		g.connect_points(s[0], n + s[1], false)
		g.connect_points(n + s[0], n + s[1], false)
	var path := g.get_id_path(src, dst)
	if path.is_empty():
		return {"ok": false, "error": "No airway route from %s to %s" % [from, to], "wps": []}
	var wps: Array = []
	for id in path:
		if id == src or id == dst:
			continue
		var name := str(names[id % n])
		var at: Vector2 = pos[id % n]
		if at.distance_to(a) < RouteBuilder.VOR_NEAR_END_M or at.distance_to(b) < RouteBuilder.VOR_NEAR_END_M:
			continue  # e.g. the airport's own VOR (BBB at VABB): a 0.5 nm first leg the GPS would pass at once
		if name == from or name == to or (not wps.is_empty() and str(wps.back().id) == name):
			continue
		var w := RouteBuilder.waypoint(name, db, cruise_ft)
		if not w.is_empty():
			wps.append(w)
	return {"ok": true, "error": "", "wps": wps}
