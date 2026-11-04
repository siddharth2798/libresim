class_name AirportMapMath
extends RefCounted
## The maths of the airport diagram, no nodes: how the airport fits a control (north up, local ENU metres) and which
## runway end or stand is under the pointer. airport_diagram.gd draws with view() / to_screen() and asks pick() on a
## click or hover; tests call the same functions headless.
## A runway is a runways.json entry ({ends: [{x, y, ident, ...}, {...}], width}); a stand a dictionary with x and y.

const END_LABEL_M := 16.0  # px: where the runway ident is drawn, beyond the end
const STAND_TOL_PX := 11.0  # how close to a stand's dot counts as on it
const END_TOL_PX := 15.0  # ... to a runway ident
const RUNWAY_TOL_PX := 12.0  # ... to a runway's centre line (the drawn half width counts when it is wider)


## World rectangle that holds the runways and stands, plus a 300 m margin.
static func bounds(runways: Array, stands: Array) -> Rect2:
	var pts := PackedVector2Array()
	for w in runways:
		for e in w.ends:
			pts.append(Vector2(e.x, e.y))
	for s in stands:
		pts.append(Vector2(s.x, s.y))
	if pts.is_empty():
		return Rect2()
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r.grow(300.0)


## How `b` fits a control of `size` (pixels, with `pad` px kept free at every edge): {scale, center, size}.
static func view(b: Rect2, size: Vector2, pad := 0.0) -> Dictionary:
	var avail := (size - Vector2(pad, pad) * 2.0).max(Vector2(1, 1))
	var s := minf(avail.x / maxf(b.size.x, 1.0), avail.y / maxf(b.size.y, 1.0))
	return {"scale": s, "center": b.get_center(), "size": size}


static func to_screen(v: Dictionary, p: Vector2) -> Vector2:
	var c: Vector2 = v.center
	return (v.size as Vector2) * 0.5 + Vector2(p.x - c.x, c.y - p.y) * float(v.scale)


static func to_world(v: Dictionary, q: Vector2) -> Vector2:
	var c: Vector2 = v.center
	var d: Vector2 = (q - (v.size as Vector2) * 0.5) / float(v.scale)
	return Vector2(c.x + d.x, c.y - d.y)


## Where the ident of end `i` (0 / 1) of runway `w` is drawn (screen px).
static func end_label_pos(v: Dictionary, w: Dictionary, i: int) -> Vector2:
	var a := to_screen(v, Vector2(w.ends[0].x, w.ends[0].y))
	var z := to_screen(v, Vector2(w.ends[1].x, w.ends[1].y))
	var p := a if i == 0 else z
	var away := (p - (z if i == 0 else a)).normalized()
	return p + away * END_LABEL_M


## What is under `pos` (screen px): {} for nothing, {kind: "stand", index} (index into `stands`) or
## {kind: "runway", ident, runway: index into `runways`}. A stand dot within STAND_TOL_PX wins; then a runway ident
## label or end; then the runway's centre line (the nearer end gives the end). The nearest candidate wins in each group.
static func pick(v: Dictionary, runways: Array, stands: Array, pos: Vector2) -> Dictionary:
	var best := -1
	var best_d := STAND_TOL_PX
	for i in stands.size():
		var d := pos.distance_to(to_screen(v, Vector2(stands[i].x, stands[i].y)))
		if d <= best_d:
			best_d = d
			best = i
	if best >= 0:
		return {"kind": "stand", "index": best}
	var hit := {}
	var hit_d := INF
	for k in runways.size():  # idents and ends
		var w: Dictionary = runways[k]
		for i in 2:
			var d := minf(pos.distance_to(end_label_pos(v, w, i)), pos.distance_to(to_screen(v, Vector2(w.ends[i].x, w.ends[i].y))))
			if d <= END_TOL_PX and d < hit_d:
				hit_d = d
				hit = {"kind": "runway", "ident": str(w.ends[i].ident), "runway": k}
	if not hit.is_empty():
		return hit
	for k in runways.size():  # the strip itself
		var w: Dictionary = runways[k]
		var a := to_screen(v, Vector2(w.ends[0].x, w.ends[0].y))
		var z := to_screen(v, Vector2(w.ends[1].x, w.ends[1].y))
		var d := pos.distance_to(Geometry2D.get_closest_point_to_segment(pos, a, z))
		if d <= maxf(RUNWAY_TOL_PX, strip_px(v, w) * 0.5) and d < hit_d:
			hit_d = d
			hit = {"kind": "runway", "ident": str(w.ends[0 if pos.distance_to(a) <= pos.distance_to(z) else 1].ident), "runway": k}
	return hit


## Drawn width of a runway in px (at least 4).
static func strip_px(v: Dictionary, w: Dictionary) -> float:
	return maxf(float(w.get("width", 30.0)) * float(v.scale), 4.0)
