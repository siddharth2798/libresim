class_name PushbackSurface
extends RefCounted
## Where a pushback wheel may roll. A drawn ribbon counts. So does the apron on the stand
## side of a ribbon, the lead-in from the stand to that ribbon, and apron that is still
## closer to the stand than to any ribbon. Past the far edge, or past the end of a bend, is grass.

const MARGIN := 0.5


static func prepare(tgt: Dictionary, gear: PackedVector2Array) -> void:
	var reach := 2.0
	var leadw := 2.0
	for w in gear:
		reach = maxf(reach, w.x + 1.0)
		leadw = maxf(leadw, absf(w.y) + 1.5)
	tgt.reach = reach
	tgt.lead = leadw


## Metres of the arc that never leave a wheel further off the pavement than it was when parked.
static func prefix(p0: Vector2, h0: float, sol: Dictionary, tgt: Dictionary, segs: Array, gear: PackedVector2Array) -> float:
	var base := _parked(p0, h0, sol, tgt, segs, gear)
	var lim := float(sol.limit)
	var last := -1.0
	var s := 0.0
	while s <= lim + 0.01:
		if _worse(p0, h0, sol, s, tgt, segs, gear, base):
			return last
		last = s
		s += 1.0
	return lim


## How far a newly off wheel crosses the target strip's far edge. A wheel that was already off does not count.
static func overshoot(p0: Vector2, h0: float, sol: Dictionary, tgt: Dictionary, segs: Array, gear: PackedVector2Array) -> float:
	var base := _parked(p0, h0, sol, tgt, segs, gear)
	var pen := 0.0
	var s := 0.0
	var lim := float(sol.limit)
	while s <= lim + 0.01:
		var pose: Array = PushbackPath.pose(p0, h0, float(sol.side), s, float(sol.straight), float(sol.radius), float(sol.turn))
		var i := 0
		for w in gear:
			var q := _wheel(pose[0], pose[1], w)
			if gap(q, tgt, segs) > base[i] + 0.05:
				pen = maxf(pen, -float(tgt.half) + MARGIN - (q - tgt.a).dot(tgt.N))
			i += 1
		s += 1.0
	return pen


## Metres past the pavement. 0 when the wheel is on a ribbon, on the apron in front of one, or on the lead-in.
static func gap(p: Vector2, tgt: Dictionary, segs: Array) -> float:
	var stand: Vector2 = tgt.p0
	var inside := false
	var apron := false
	var blocked := false
	var near := 1.0e6
	var off := 1.0e6
	for s in segs:
		var ab: Vector2 = s.b - s.a
		var l2 := ab.length_squared()
		if l2 < 0.25:
			continue
		var u: float = (p - s.a).dot(ab) / l2
		var c: Vector2 = s.a + ab * clampf(u, 0.0, 1.0)
		var d := p.distance_to(c)
		var half := float(s.half)
		near = minf(near, d)
		off = minf(off, d - half)
		if d <= half:
			inside = true
			continue
		if u < 0.0 or u > 1.0:
			continue
		var n := Vector2(-ab.y, ab.x)
		if (stand - c).dot(n) < 0.0:
			n = -n
		if (p - c).dot(n) / ab.length() < -half:
			blocked = true
		else:
			apron = true
	if inside or p.distance_to(stand) + 1.0 < near:
		return 0.0
	if blocked:
		return maxf(off, 0.0)
	if apron or _lead(p, tgt):
		return 0.0
	return maxf(off, 0.0)


static func _lead(p: Vector2, tgt: Dictionary) -> bool:
	var stand: Vector2 = tgt.p0
	var goal: Vector2 = tgt.q
	var back := goal - stand
	var span := back.length()
	if span < 1.0:
		return false
	var a := stand - back * (float(tgt.reach) / span)
	var lead := goal - a
	var u := clampf((p - a).dot(lead) / lead.length_squared(), 0.0, 1.0)
	return p.distance_to(a + lead * u) <= float(tgt.lead)


static func _parked(p0: Vector2, h0: float, sol: Dictionary, tgt: Dictionary, segs: Array, gear: PackedVector2Array) -> PackedFloat32Array:
	var pose: Array = PushbackPath.pose(p0, h0, float(sol.side), 0.0, float(sol.straight), float(sol.radius), float(sol.turn))
	var out := PackedFloat32Array()
	for w in gear:
		out.append(gap(_wheel(pose[0], pose[1], w), tgt, segs))
	return out


static func _worse(p0: Vector2, h0: float, sol: Dictionary, s: float, tgt: Dictionary, segs: Array, gear: PackedVector2Array, base: PackedFloat32Array) -> bool:
	var pose: Array = PushbackPath.pose(p0, h0, float(sol.side), s, float(sol.straight), float(sol.radius), float(sol.turn))
	var i := 0
	for w in gear:
		if gap(_wheel(pose[0], pose[1], w), tgt, segs) > base[i] + 0.05:
			return true
		i += 1
	return false


static func _wheel(pos: Vector2, hdg: float, w: Vector2) -> Vector2:
	return pos + Vector2(sin(hdg), cos(hdg)) * w.x + Vector2(cos(hdg), -sin(hdg)) * w.y
