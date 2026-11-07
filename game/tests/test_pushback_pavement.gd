extends RefCounted
## PushbackFit aims the published arc so every wheel stays on the drawn strip (min(width, 23) m,
## or 15 m when the width is blank). Past the far edge or the end of a bend is grass.

const Fit := preload("res://world/pushback_fit.gd")


static func _a320() -> PackedVector2Array:
	return PackedVector2Array([Vector2(11.1, 0.0), Vector2(-1.4, -4.3), Vector2(-1.4, 4.3)])


static func _c172() -> PackedVector2Array:
	return PackedVector2Array([Vector2(0.6, 0.0), Vector2(-1.3, -1.1), Vector2(-1.3, 1.1)])


func test_published_pushback_crosses_the_far_edge_and_the_fit_does_not() -> String:
	var cases := [
		{"wheels": _a320(), "straight": 40.0, "radius": 30.0, "y": -40.0, "width": "15", "kind": "taxiway", "half": 7.5},
		{"wheels": _c172(), "straight": 30.0, "radius": 18.0, "y": -28.0, "width": "15", "kind": "taxiway", "half": 7.5},
		{"wheels": _a320(), "straight": 40.0, "radius": 30.0, "y": -36.0, "width": "24", "kind": "taxiway", "half": 11.5},
		{"wheels": _a320(), "straight": 40.0, "radius": 30.0, "y": -40.0, "width": "", "kind": "taxiway", "half": 7.5},
		{"wheels": _a320(), "straight": 40.0, "radius": 30.0, "y": -45.0, "width": "45", "kind": "runway", "half": 22.5},
	]
	var bad := []
	for c in cases:
		var wheels: PackedVector2Array = c.wheels
		var edge := float(c.y) - float(c.half)
		var old_len := PushbackPath.length(c.straight, c.radius)
		var old := _past(Vector2.ZERO, 0.0, 1.0, c.straight, c.radius, PI / 2.0, old_len, wheels, edge)
		if old < 2.0:
			bad.append("published arc no longer crosses a %s of width %s (%.1f m)" % [c.kind, c.width, old])
			continue
		for side in [1.0, -1.0]:
			var fit: Dictionary = Fit.plan(Vector2.ZERO, 0.0, _strip(c.y, c.width, c.kind), side, _prefer(c.straight, c.radius), null, false, true, wheels)
			var past := _past(Vector2.ZERO, 0.0, fit.side, fit.straight, fit.radius, fit.turn, fit.limit, wheels, edge)
			var end: Array = PushbackPath.pose(Vector2.ZERO, 0.0, fit.side, fit.limit, fit.straight, fit.radius, fit.turn)
			var pos: Vector2 = end[0]
			if past > 0.05 or absf(pos.y - float(c.y)) > 3.0 or absf(cos(end[1])) > 0.2 or float(fit.limit) < 8.0:
				bad.append("%s w=%s side %.0f: past %.2f end %s hdg %.2f limit %.1f" % [c.kind, c.width, side, past, pos, end[1], fit.limit])
	return "; ".join(bad)


func test_pushback_aligns_with_an_angled_taxiway() -> String:
	var dir := Vector2(sin(deg_to_rad(60.0)), cos(deg_to_rad(60.0)))
	var q := Vector2(0.0, -50.0)
	var taxi := {"nodes": {"a": q - dir * 160.0, "b": q + dir * 160.0}, "edges": [["a", "b", "B", "15", "taxiway"]]}
	var fit: Dictionary = Fit.plan(Vector2.ZERO, 0.0, taxi, 1.0, _prefer(40.0, 30.0), null, false, true, _a320())
	var end: Array = PushbackPath.pose(Vector2.ZERO, 0.0, fit.side, fit.limit, fit.straight, fit.radius, fit.turn)
	var pos: Vector2 = end[0]
	var fwd := Vector2(sin(end[1]), cos(end[1]))
	var off := _line_dist(pos, q, dir)
	var past := _past_far(Vector2.ZERO, 0.0, fit, _a320(), q, dir, 7.5)
	if off > 3.0 or absf(fwd.dot(dir)) < 0.95 or past > 0.05 or float(fit.limit) < 8.0:
		return "angled: off %.2f align %.2f past %.2f end %s limit %.1f" % [off, absf(fwd.dot(dir)), past, pos, fit.limit]
	return ""


func test_pushback_insets_when_the_gear_is_wider_than_the_margin() -> String:
	var fit: Dictionary = Fit.plan(Vector2.ZERO, 0.0, _strip(-40.0, "8", "taxiway"), 1.0, _prefer(40.0, 30.0), null, false, true, _a320())
	var end: Array = PushbackPath.pose(Vector2.ZERO, 0.0, fit.side, fit.limit, fit.straight, fit.radius, fit.turn)
	var pos: Vector2 = end[0]
	var past := _past(Vector2.ZERO, 0.0, fit.side, fit.straight, fit.radius, fit.turn, fit.limit, _a320(), -44.0)
	if past > 0.05 or pos.y <= -40.0 or absf(cos(end[1])) > 0.2:
		return "narrow: past %.2f end %s hdg %.2f (CG must sit on the near side of the centre line)" % [past, pos, end[1]]
	return ""


func test_pushback_does_not_swing_past_a_bend() -> String:
	var taxi := {"nodes": {"a": [-140.0, -40.0], "b": [15.0, -40.0], "c": [15.0, -180.0]},
		"edges": [["a", "b", "A", "15", "taxiway"], ["b", "c", "A", "15", "taxiway"]]}
	var wheels := _a320()
	var fit: Dictionary = Fit.plan(Vector2.ZERO, 0.0, taxi, 1.0, _prefer(40.0, 30.0), null, false, true, wheels)
	var hit := {"q": Vector2(0.0, -40.0), "dir": Vector2(1.0, 0.0), "half": 7.5, "a": Vector2(-140.0, -40.0), "b": Vector2(15.0, -40.0)}
	var off := _off_the_strip(Vector2.ZERO, 0.0, fit, wheels, hit, taxi)
	if off > 0.05 or float(fit.limit) < 8.0:
		return "bend: %.2f m off the pavement, limit %.1f, side %.0f" % [off, fit.limit, fit.side]
	return ""


func test_pushback_without_a_taxiway_keeps_the_published_arc() -> String:
	var fit: Dictionary = Fit.plan(Vector2.ZERO, 0.5, {}, -1.0, _prefer(30.0, 18.0))
	var want := PushbackPath.length(30.0, 18.0)
	if absf(fit.straight - 30.0) > 1e-6 or absf(fit.radius - 18.0) > 1e-6 or absf(fit.turn - PI / 2.0) > 1e-6 \
			or absf(fit.limit - want) > 1e-4 or absf(fit.side + 1.0) > 1e-6:
		return "nominal %s" % fit
	return ""


func test_pushback_stays_on_the_pavement_at_every_stand() -> String:
	var data = Paths.load_json("airport_ops.json")
	if data == null:
		return ""  # data not built on this machine
	var craft := [["c172", AircraftDef.load_def("c172")], ["a320", AircraftDef.load_def("a320")]]
	var bad := []
	var checked := 0
	for icao in data:
		var taxi: Dictionary = data[icao].get("taxi", {})
		for st in data[icao].get("stands", []):
			for pair in craft:
				var def: AircraftDef = pair[1]
				var p0 := GroundParams.cg_at_stand(st, def)
				var h0 := deg_to_rad(float(st.heading_deg))
				var hit := _tail_strip(p0, h0, taxi)
				if hit.is_empty():
					continue
				checked += 1
				var gear := Fit.wheels(def)
				var prefer := GroundParams.pushback(def)
				var fit: Dictionary = Fit.plan(p0, h0, taxi, 1.0, prefer, def, false, true, gear)
				var past := _off_the_strip(p0, h0, fit, gear, hit, taxi)
				if past > 0.15:
					bad.append("%s %s %s off %.1f at %s hdg %.0f fit s=%.0f r=%.0f turn %.0f side %.0f lim %.0f" % [icao, st.get("ref", "?"), pair[0], past, p0, rad_to_deg(h0), fit.straight, fit.radius, rad_to_deg(fit.turn), fit.side, fit.limit])
					if bad.size() >= 6:
						return "%d stands checked; %s" % [checked, "; ".join(bad)]
	if checked < 50:
		return "only %d stands had a strip behind them" % checked
	return "" if bad.is_empty() else "%d stands checked; %s" % [checked, "; ".join(bad)]


func test_pushback_reads_each_aircrafts_wheels() -> String:
	var c := Fit.wheels(AircraftDef.load_def("c172"))
	var a := Fit.wheels(AircraftDef.load_def("a320"))
	if c.size() < 3 or a.size() < 3:
		return "wheel counts c172 %d a320 %d" % [c.size(), a.size()]
	var cn := _extreme(c, true)
	var an := _extreme(a, true)
	var ct := _extreme(c, false)
	var at := _extreme(a, false)
	if an < 8.0 or cn > 4.0 or at < 6.0 or ct >= at:
		return "c172 nose %.2f track %.2f, a320 nose %.2f track %.2f" % [cn, ct, an, at]
	return ""


static func _prefer(straight: float, radius: float) -> Dictionary:
	return {"straight_m": straight, "radius_m": radius, "speed_mps": 1.5}


static func _strip(y: float, width: String, kind: String) -> Dictionary:
	return {"nodes": {"a": [-220.0, y], "b": [220.0, y]}, "edges": [["a", "b", "A", width, kind]]}


static func _wheel(pos: Vector2, hdg: float, w: Vector2) -> Vector2:
	return pos + Vector2(sin(hdg), cos(hdg)) * w.x + Vector2(cos(hdg), -sin(hdg)) * w.y


static func _past(p0: Vector2, h0: float, side: float, straight: float, radius: float, turn: float, limit: float, wheels: PackedVector2Array, edge_y: float) -> float:
	var worst := -1.0e6
	var s := 0.0
	while s <= limit + 0.01:
		var pose: Array = PushbackPath.pose(p0, h0, side, minf(s, limit), straight, radius, turn)
		for w in wheels:
			worst = maxf(worst, edge_y - _wheel(pose[0], pose[1], w).y)
		s += 0.5
	return worst


static func _line_dist(p: Vector2, q: Vector2, dir: Vector2) -> float:
	return absf((p - q).cross(dir))


static func _past_far(p0: Vector2, h0: float, fit: Dictionary, wheels: PackedVector2Array, q: Vector2, dir: Vector2, half: float) -> float:
	var n := Vector2(-dir.y, dir.x)
	if (p0 - q).dot(n) < 0.0:
		n = -n
	var worst := -1.0e6
	var s := 0.0
	var lim := float(fit.limit)
	while s <= lim + 0.01:
		var pose: Array = PushbackPath.pose(p0, h0, fit.side, minf(s, lim), fit.straight, fit.radius, fit.turn)
		for w in wheels:
			worst = maxf(worst, -half - (_wheel(pose[0], pose[1], w) - q).dot(n))
		s += 0.5
	return worst


static func _tail_strip(p0: Vector2, h0: float, taxi: Dictionary) -> Dictionary:
	var nodes: Dictionary = taxi.get("nodes", {})
	var back := -Vector2(sin(h0), cos(h0))
	var best := {}
	var best_t := INF
	for e in taxi.get("edges", []):
		if e.size() < 5 or str(e[4]) not in ["taxiway", "taxilane", "runway"]:
			continue
		if not nodes.has(str(e[0])) or not nodes.has(str(e[1])):
			continue
		var a := Vector2(float(nodes[str(e[0])][0]), float(nodes[str(e[0])][1]))
		var b := Vector2(float(nodes[str(e[1])][0]), float(nodes[str(e[1])][1]))
		var v := b - a
		if v.length() < 0.5:
			continue
		var den := back.x * v.y - back.y * v.x
		if absf(den) < 1e-8:
			continue
		var w := a - p0
		var t := (w.x * v.y - w.y * v.x) / den
		var u := (w.x * back.y - w.y * back.x) / den
		if t < 4.0 or t > 170.0 or u < 0.0 or u > 1.0 or t >= best_t:
			continue
		var fwd := Vector2(sin(h0), cos(h0))
		if absf(fwd.dot(v / v.length())) > 0.92:
			continue
		best_t = t
		best = {"q": p0 + back * t, "dir": v / v.length(), "half": _spec_half(str(e[4]), e[3]), "a": a, "b": b}
	return best


static func _off_the_strip(p0: Vector2, h0: float, fit: Dictionary, wheels: PackedVector2Array, hit: Dictionary, taxi: Dictionary) -> float:
	var reach := 2.0
	var leadw := 2.0
	for w in wheels:
		reach = maxf(reach, w.x + 1.0)
		leadw = maxf(leadw, absf(w.y) + 1.5)
	var base := PackedFloat32Array()
	var worst := 0.0
	var s := 0.0
	var lim := float(fit.limit)
	while s <= lim + 0.01:
		var pose: Array = PushbackPath.pose(p0, h0, fit.side, minf(s, lim), fit.straight, fit.radius, fit.turn)
		var i := 0
		for w in wheels:
			var off := _outside(p0, hit.q, reach, leadw, _wheel(pose[0], pose[1], w), taxi)
			if base.size() < wheels.size():
				base.append(off)
			else:
				worst = maxf(worst, off - base[i])
			i += 1
		s += 2.0
	return worst


static func _outside(p0: Vector2, goal: Vector2, reach: float, leadw: float, p: Vector2, taxi: Dictionary) -> float:
	var nodes: Dictionary = taxi.get("nodes", {})
	var off := 1.0e6
	var near := 1.0e6
	var apron := false
	var blocked := false
	var saw := false
	for e in taxi.get("edges", []):
		if e.size() < 5 or str(e[4]) not in ["taxiway", "taxilane", "runway"]:
			continue
		if not nodes.has(str(e[0])) or not nodes.has(str(e[1])):
			continue
		var a := Vector2(float(nodes[str(e[0])][0]), float(nodes[str(e[0])][1]))
		var b := Vector2(float(nodes[str(e[1])][0]), float(nodes[str(e[1])][1]))
		var ab := b - a
		var l2 := ab.length_squared()
		if l2 < 0.25:
			continue
		saw = true
		var u := (p - a).dot(ab) / l2
		var c: Vector2 = a + ab * clampf(u, 0.0, 1.0)
		var d := p.distance_to(c)
		var half := _spec_half(str(e[4]), e[3])
		near = minf(near, d)
		off = minf(off, d - half)
		if u < 0.0 or u > 1.0:
			continue
		var n := Vector2(-ab.y, ab.x)
		if (p0 - c).dot(n) < 0.0:
			n = -n
		if (p - c).dot(n) / ab.length() < -half:
			blocked = true
		elif d > half:
			apron = true
	if not saw or off <= 0.05 or p.distance_to(p0) + 1.0 < near:
		return 0.0
	if blocked:
		return maxf(off, 0.0)
	if apron or _on_lead(p0, goal, reach, leadw, p):
		return 0.0
	return maxf(off, 0.0)


static func _on_lead(p0: Vector2, goal: Vector2, reach: float, leadw: float, p: Vector2) -> bool:
	var back := goal - p0
	var span := back.length()
	if span < 1.0:
		return false
	var a := p0 - back * (reach / span)
	var lead := goal - a
	var u := clampf((p - a).dot(lead) / lead.length_squared(), 0.0, 1.0)
	return p.distance_to(a + lead * u) <= leadw

static func _spec_half(kind: String, raw) -> float:
	var w := 0.0
	if raw is String and raw != "":
		w = float(raw)
	elif raw is float or raw is int:
		w = float(raw)
	if kind == "runway":
		return (w if w > 1.0 else 30.0) * 0.5
	return minf(w if w > 1.0 else 15.0, 23.0) * 0.5


static func _extreme(wheels: PackedVector2Array, nose: bool) -> float:
	var m := -1.0e6 if nose else 0.0
	for w in wheels:
		m = maxf(m, w.x) if nose else maxf(m, absf(w.y) * 2.0)
	return m
