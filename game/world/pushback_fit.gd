class_name PushbackFit
extends RefCounted
## Chooses the pushback arc (PushbackPath) so every wheel stays on pavement. The published
## straight_m / radius_m is the preferred arc. PushbackSurface decides what is pavement;
## a bend or a far edge cuts the arc, and a collinear run of pieces is one strip to aim at.

const MIN_R := 6.0
const TAXI_W := 15.0
const DRAWN_MAX := 23.0  # airport_builder.gd caps a taxiway mesh at this
const _Surf := preload("res://world/pushback_surface.gd")


## Body-frame wheel offsets (x forward, y right, metres) from config.json gear and the empty CG.
static func wheels(aircraft: AircraftDef) -> PackedVector2Array:
	var out := PackedVector2Array()
	if aircraft == null:
		return out
	var cfg: Dictionary = aircraft.config()
	if not cfg.has("mass") or not cfg.has("gear"):
		return out
	var c: Array = cfg.mass.empty_cg_m
	var cg := Vector3(float(c[0]), float(c[1]), float(c[2]))
	for g in cfg.gear:
		if str(g.get("type", "")) != "BOGEY":
			continue
		var p: Array = g.pos_m
		var d := Vector3(float(p[0]), float(p[1]), float(p[2])) - cg
		out.append(Vector2(-d.x, d.y))
	return out


## taxi: one airport's airport_ops.json "taxi". side: +1 tail to the right. prefer: GroundParams.pushback.
## lock_side keeps `side` (corridors sweep both); otherwise the side that lands on the strip wins.
## pave walks the wheels and stops the arc at the edge. Returns {side, straight, radius, turn, limit}.
static func plan(p0: Vector2, h0: float, taxi: Dictionary, side: float, prefer: Dictionary, aircraft: AircraftDef = null, lock_side := false, pave := true, wheel_pts: PackedVector2Array = PackedVector2Array()) -> Dictionary:
	var straight := float(prefer.get("straight_m", PushbackPath.STRAIGHT))
	var radius := float(prefer.get("radius_m", PushbackPath.RADIUS))
	var nominal := {"side": side, "straight": straight, "radius": radius, "turn": PI / 2.0, "limit": PushbackPath.length(straight, radius)}
	var segs := _segments(taxi)
	var tgt := _target(p0, h0, segs)
	if tgt.is_empty():
		return nominal
	var gear := wheel_pts if not wheel_pts.is_empty() else wheels(aircraft)
	if gear.is_empty():
		gear = PackedVector2Array([Vector2(2.0, 0.0), Vector2(-1.0, -1.2), Vector2(-1.0, 1.2)])
	if pave:
		_Surf.prepare(tgt, gear)
	var best := {}
	var best_score := -1.0e12
	for sd in ([side] if lock_side else [side, -side]):
		for h1 in _headings(tgt):
			var a: float = float(sd) * _wrap(h0 - float(h1))
			if a < 0.35 or a > 2.2:
				continue
			var sol := _solve(p0, h0, sd, a, tgt, straight, radius, 0.0)
			if sol.is_empty():
				continue
			var score := _rank(p0, h0, sol, tgt, segs, gear, pave)
			score -= absf(a - PI / 2.0) * 5.0
			if absf(sd - side) < 0.1:
				score += 0.5
			if score > best_score:
				best_score = score
				best = sol
	if best.is_empty():
		best = nominal
	if not pave:
		return best
	return _hold_on_pavement(p0, h0, best, tgt, segs, gear, straight, radius)


static func _hold_on_pavement(p0: Vector2, h0: float, sol: Dictionary, tgt: Dictionary, segs: Array, gear: PackedVector2Array, prefer_s: float, prefer_r: float) -> Dictionary:
	var inset := 0.0
	for _i in 6:
		var lim := _Surf.prefix(p0, h0, sol, tgt, segs, gear)
		if lim >= float(sol.limit) - 0.8:
			sol.limit = float(sol.limit)
			return sol
		var pen := _Surf.overshoot(p0, h0, sol, tgt, segs, gear)
		if pen < 0.15 or inset > float(tgt.half):
			sol.limit = maxf(lim, 0.0)
			return sol
		inset += pen + 0.35
		var nxt := _solve(p0, h0, float(sol.side), float(sol.turn), tgt, prefer_s, prefer_r, inset)
		if nxt.is_empty():
			sol.limit = maxf(lim, 0.0)
			return sol
		sol = nxt
	sol.limit = maxf(_Surf.prefix(p0, h0, sol, tgt, segs, gear), 0.0)
	return sol


static func _solve(p0: Vector2, h0: float, side: float, turn: float, tgt: Dictionary, prefer_s: float, prefer_r: float, inset: float) -> Dictionary:
	var back := -Vector2(sin(h0), cos(h0))
	var right := Vector2(cos(h0), -sin(h0))
	var rgt := right * side
	var k := rgt - rgt.rotated(side * turn)  # end = p0 + back * S + rho * k  (same as PushbackPath.pose)
	var n: Vector2 = tgt.N
	var q: Vector2 = tgt.q
	var rhs: float = (q - p0).dot(n) + inset  # (end - q) · n = inset, n points back toward the aircraft
	var bn := back.dot(n)
	var kn := k.dot(n)
	var rho := prefer_r
	var s := prefer_s
	if absf(bn) > 0.25:
		s = (rhs - kn * rho) / bn
	elif absf(kn) > 0.08:
		s = minf(prefer_s, 12.0)
		rho = (rhs - bn * s) / kn
	else:
		return {}
	if s < 0.0:
		s = 0.0
		if absf(kn) < 0.08:
			return {}
		rho = rhs / kn
	if rho < MIN_R:
		rho = MIN_R
		if absf(bn) > 0.25:
			s = (rhs - kn * rho) / bn
		s = maxf(s, 0.0)
	if rho > 90.0:
		rho = 90.0
		if absf(bn) > 0.25:
			s = maxf((rhs - kn * rho) / bn, 0.0)
	s = minf(s, 150.0)
	if rho < MIN_R:
		return {}
	return {"side": side, "straight": s, "radius": rho, "turn": turn, "limit": PushbackPath.length(s, rho, turn)}


static func _segments(taxi: Dictionary) -> Array:
	var nodes: Dictionary = taxi.get("nodes", {})
	var out: Array = []
	for e in taxi.get("edges", []):
		if e.size() < 5 or not nodes.has(str(e[0])) or not nodes.has(str(e[1])):
			continue
		var kind := str(e[4])
		if kind != "taxiway" and kind != "taxilane" and kind != "runway":
			continue
		var a := Vector2(float(nodes[str(e[0])][0]), float(nodes[str(e[0])][1]))
		var b := Vector2(float(nodes[str(e[1])][0]), float(nodes[str(e[1])][1]))
		if a.distance_to(b) < 0.5:
			continue
		out.append({"a": a, "b": b, "half": _half(kind, e[3]), "kind": kind})
	return out


static func _half(kind: String, raw) -> float:
	var w := _num(raw)
	if kind == "runway":
		return (w if w > 1.0 else 30.0) * 0.5
	if w <= 1.0:
		w = TAXI_W
	return minf(w, DRAWN_MAX) * 0.5


static func _num(v) -> float:
	if v is float or v is int:
		return float(v)
	if v is String and v != "":
		return float(v)
	return 0.0


static func _target(p0: Vector2, h0: float, segs: Array) -> Dictionary:
	var back := -Vector2(sin(h0), cos(h0))
	var fwd := -back
	var best := {}
	var best_t := INF
	for s in segs:
		if absf(fwd.dot((s.b - s.a).normalized())) > 0.92:
			continue
		var t := _ray(p0, back, s.a, s.b)
		if t < 4.0 or t > 170.0 or t >= best_t:
			continue
		best_t = t
		best = s.duplicate()
		best.q = p0 + back * t
	if best.is_empty():
		best = _nearest(p0, back, fwd, segs)
	if best.is_empty():
		return {}
	_grow(best, segs)
	var ab: Vector2 = best.b - best.a
	var tdir := ab / ab.length()
	var n := Vector2(-tdir.y, tdir.x)
	if (p0 - best.q).dot(n) < 0.0:
		n = -n
	best.N = n
	best.p0 = p0
	best.reach = 4.0
	best.lead = 3.0
	best.T = tdir
	return best


static func _nearest(p0: Vector2, back: Vector2, fwd: Vector2, segs: Array) -> Dictionary:
	var best := {}
	var bd := INF
	for s in segs:
		if absf(fwd.dot((s.b - s.a).normalized())) > 0.92:
			continue
		var ab: Vector2 = s.b - s.a
		var u := clampf((p0 - s.a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var q: Vector2 = s.a + ab * u
		var rel := q - p0
		var d := rel.length()
		if d < 4.0 or d > 170.0 or rel.dot(back) < d * 0.35 or d >= bd:
			continue
		bd = d
		best = s.duplicate()
		best.q = q
	return best


static func _ray(origin: Vector2, dir: Vector2, a: Vector2, b: Vector2) -> float:
	var v := b - a
	var den := dir.x * v.y - dir.y * v.x
	if absf(den) < 1e-8:
		return -1.0
	var w := a - origin
	var t := (w.x * v.y - w.y * v.x) / den
	var u := (w.x * dir.y - w.y * dir.x) / den
	if t < 0.0 or u < 0.0 or u > 1.0:
		return -1.0
	return t


static func _headings(tgt: Dictionary) -> Array:
	var h := atan2(tgt.T.x, tgt.T.y) if tgt.has("T") else atan2((tgt.b - tgt.a).x, (tgt.b - tgt.a).y)
	return [h, _wrap(h + PI)]


static func _wrap(a: float) -> float:
	return fposmod(a + PI, TAU) - PI

static func _rank(p0: Vector2, h0: float, sol: Dictionary, tgt: Dictionary, segs: Array, gear: PackedVector2Array, pave: bool) -> float:
	if not pave:
		var end: Vector2 = PushbackPath.pose(p0, h0, float(sol.side), float(sol.limit), float(sol.straight), float(sol.radius), float(sol.turn))[0]
		return 200.0 if _seg_dist(end, tgt) < float(tgt.half) + 8.0 else -_seg_dist(end, tgt)
	var paved := _Surf.prefix(p0, h0, sol, tgt, segs, gear)
	return maxf(paved, 0.0) + (1000.0 if paved >= float(sol.limit) - 0.8 else 0.0)


static func _seg_dist(p: Vector2, s: Dictionary) -> float:
	var ab: Vector2 = s.b - s.a
	var u := clampf((p - s.a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(s.a + ab * u)


## A run of collinear pieces is one strip. The arc then aims along the taxiway, not along one stub.
static func _grow(seg: Dictionary, segs: Array) -> void:
	for _i in 6:
		var dir: Vector2 = (seg.b - seg.a).normalized()
		var grew := false
		for s in segs:
			if str(s.kind) != str(seg.kind) or absf(float(s.half) - float(seg.half)) > 1.0:
				continue
			var sd: Vector2 = s.b - s.a
			if sd.length() < 0.5 or absf(sd.normalized().dot(dir)) < 0.94:
				continue
			grew = _extend(seg, s.a, s.b) or grew
		if not grew:
			return


static func _extend(seg: Dictionary, c: Vector2, d: Vector2) -> bool:
	var a: Vector2 = seg.a
	var b: Vector2 = seg.b
	if minf(c.distance_to(b), d.distance_to(b)) < 1.5:
		var far: Vector2 = c if c.distance_to(a) >= d.distance_to(a) else d
		if far.distance_to(a) > b.distance_to(a) + 0.4:
			seg.b = far
			return true
	if minf(c.distance_to(a), d.distance_to(a)) < 1.5:
		var far2: Vector2 = c if c.distance_to(b) >= d.distance_to(b) else d
		if far2.distance_to(b) > a.distance_to(b) + 0.4:
			seg.a = far2
			return true
	return false
