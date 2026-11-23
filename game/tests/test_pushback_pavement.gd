extends RefCounted
## PushbackFit aims the published arc so every wheel stays on the drawn strip (min(width, 23) m,
## or 15 m when the width is blank). Past the far edge or the end of a bend is grass.

const Fit := preload("res://world/pushback_fit.gd")
const Strip := preload("res://tests/pushback_strip_check.gd")


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
	var off := Strip.off_the_strip(Vector2.ZERO, 0.0, fit, wheels, hit, Strip.pieces(taxi))
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


## Every stand of every airport, both aircraft (tests/pushback_strip_check.gd). The parallel launcher runs it in parts.
func test_pushback_stays_on_the_pavement_at_every_stand(part := 0, parts := 1) -> String:
	return Strip.every_stand(part, parts)


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


static func _extreme(wheels: PackedVector2Array, nose: bool) -> float:
	var m := -1.0e6 if nose else 0.0
	for w in wheels:
		m = maxf(m, w.x) if nose else maxf(m, absf(w.y) * 2.0)
	return m
