extends RefCounted
## The every-stand pushback check of tests/test_pushback_pavement.gd and the strip geometry its tests share.
## every_stand(part, parts) checks the stand/aircraft pairs whose index i (airports, stands, aircraft in file order)
## has i % parts == part, so the shares 0..parts-1 of one count cover every pair exactly once; the parallel launcher
## (tests/parallel/) runs them as separate jobs, the single runner calls it with 0/1. Per airport the taxi edges are
## read once (pieces()) and PushbackFit gets its segments() once: the same numbers in the same order as reading the
## taxi graph again for every wheel sample, so each pair gets the same result.

const Fit := preload("res://world/pushback_fit.gd")
const KINDS := ["taxiway", "taxilane", "runway"]
const MAX_BAD := 6


static func every_stand(part: int, parts: int) -> String:
	var data = Paths.load_json("airport_ops.json")
	if data == null:
		return ""  # data not built on this machine
	var craft := []
	for id in ["c172", "a320"]:
		var def := AircraftDef.load_def(id)
		craft.append({"id": id, "def": def, "gear": Fit.wheels(def), "prefer": GroundParams.pushback(def)})
	var bad := []
	var checked := 0  # pairs of this share with a strip behind them
	var covered := 0  # pairs of this share
	var all_checked := 0  # pairs of every share with a strip behind them (the < 50 floor is on the whole set)
	var i := -1
	for icao in data:
		var taxi: Dictionary = data[icao].get("taxi", {})
		var edges := pieces(taxi)
		var segs := Fit.segments(taxi)
		for st in data[icao].get("stands", []):
			for c in craft:
				i += 1
				var mine := i % parts == part
				covered += 1 if mine else 0
				var def: AircraftDef = c.def
				var p0 := GroundParams.cg_at_stand(st, def)
				var h0 := deg_to_rad(float(st.heading_deg))
				var hit := tail_strip(p0, h0, edges)
				if hit.is_empty():
					continue
				all_checked += 1
				if not mine or bad.size() >= MAX_BAD:
					continue
				checked += 1
				var gear: PackedVector2Array = c.gear
				var fit: Dictionary = Fit.plan(p0, h0, taxi, 1.0, c.prefer, def, false, true, gear, segs)
				var past := off_the_strip(p0, h0, fit, gear, hit, edges)
				if past > 0.15:
					bad.append("%s %s %s off %.1f at %s hdg %.0f fit s=%.0f r=%.0f turn %.0f side %.0f lim %.0f" % [icao, st.get("ref", "?"), c.id, past, p0, rad_to_deg(h0), fit.straight, fit.radius, rad_to_deg(fit.turn), fit.side, fit.limit])
	print("    pushback every stand: part %d/%d covered %d of %d stand-aircraft pairs, %d of %d with a strip behind" % [part, parts, covered, i + 1, checked, all_checked])
	if bad.size() >= MAX_BAD:
		return "%d stands checked; %s" % [checked, "; ".join(bad)]
	if all_checked < 50:
		return "only %d stands had a strip behind them" % all_checked
	return "" if bad.is_empty() else "%d stands checked; %s" % [checked, "; ".join(bad)]


## The taxiway, taxilane and runway edges of one airport's taxi graph, in file order: {a, b, half}.
static func pieces(taxi: Dictionary) -> Array:
	var nodes: Dictionary = taxi.get("nodes", {})
	var out := []
	for e in taxi.get("edges", []):
		if e.size() < 5 or str(e[4]) not in KINDS:
			continue
		if not nodes.has(str(e[0])) or not nodes.has(str(e[1])):
			continue
		var a := Vector2(float(nodes[str(e[0])][0]), float(nodes[str(e[0])][1]))
		var b := Vector2(float(nodes[str(e[1])][0]), float(nodes[str(e[1])][1]))
		out.append({"a": a, "b": b, "half": spec_half(str(e[4]), e[3])})
	return out


## The strip the tail points at (first edge hit 4-170 m behind, not along the nose), or {}.
static func tail_strip(p0: Vector2, h0: float, edges: Array) -> Dictionary:
	var back := -Vector2(sin(h0), cos(h0))
	var best := {}
	var best_t := INF
	for e in edges:
		var a: Vector2 = e.a
		var b: Vector2 = e.b
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
		best = {"q": p0 + back * t, "dir": v / v.length(), "half": e.half, "a": a, "b": b}
	return best


## Worst metres a wheel ends up further off the pavement than it was parked, along the fitted arc.
static func off_the_strip(p0: Vector2, h0: float, fit: Dictionary, wheels: PackedVector2Array, hit: Dictionary, edges: Array) -> float:
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
			var off := _outside(p0, hit.q, reach, leadw, wheel(pose[0], pose[1], w), edges)
			if base.size() < wheels.size():
				base.append(off)
			else:
				worst = maxf(worst, off - base[i])
			i += 1
		s += 2.0
	return worst


static func wheel(pos: Vector2, hdg: float, w: Vector2) -> Vector2:
	return pos + Vector2(sin(hdg), cos(hdg)) * w.x + Vector2(cos(hdg), -sin(hdg)) * w.y


static func _outside(p0: Vector2, goal: Vector2, reach: float, leadw: float, p: Vector2, edges: Array) -> float:
	var off := 1.0e6
	var near := 1.0e6
	var apron := false
	var blocked := false
	var saw := false
	for e in edges:
		var a: Vector2 = e.a
		var b: Vector2 = e.b
		var ab := b - a
		var l2 := ab.length_squared()
		if l2 < 0.25:
			continue
		saw = true
		var u := (p - a).dot(ab) / l2
		var c: Vector2 = a + ab * clampf(u, 0.0, 1.0)
		var d := p.distance_to(c)
		var half: float = e.half
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


static func spec_half(kind: String, raw) -> float:
	var w := 0.0
	if raw is String and raw != "":
		w = float(raw)
	elif raw is float or raw is int:
		w = float(raw)
	if kind == "runway":
		return (w if w > 1.0 else 30.0) * 0.5
	return minf(w if w > 1.0 else 15.0, 23.0) * 0.5
