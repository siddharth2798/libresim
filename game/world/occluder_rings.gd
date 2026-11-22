class_name OccluderRings
extends RefCounted
## Wall segments (OccluderBuild.segments) to occluder triangles. Segments with about the same base and top (DY) that
## meet end to end are chained; a chain spans the heights all its walls cover. A closed chain that bounds solid building (its wall normals point away from the inside, by the model's
## own winding: the largest ring sets which way that is) is shrunk MARGIN into the building (Geometry2D.offset_polygon)
## and stood up from base + margin to top - margin: an occluder prism inside the visual walls. A closed chain whose
## inside is open (a courtyard) is left out. An open chain (a wall that does not close) is kept on the wall itself, its
## ends and top / bottom pulled in by the margin.

const MIN_W := 8.0  # m: shortest occluder wall kept (after the margin) ...
const MIN_H := 4.0  # ... and lowest
const SNAP := 20.0  # endpoints within 5 cm meet (walls share their footprint corners exactly)
const DY := 0.5  # m: walls whose base and top differ by less than this chain


## Chains [{pts: PackedVector2Array, closed, y0, y1, n0: Vector2 (normal of the first segment)}] from segments.
static func chain(segs: Array) -> Array:
	var starts := {}  # endpoint key -> segment indices starting there
	var ends := {}  # ... ending there
	for i in segs.size():
		for e in 2:
			var k := _key(segs[i][e])
			var d: Dictionary = starts if e == 0 else ends
			if not d.has(k):
				d[k] = []
			d[k].append(i)
	var used := {}
	var out := []
	for i in segs.size():
		if used.has(i):
			continue
		# walk back to the start of an open chain, so it is found whole
		var first := i
		var guard := 0
		while guard < segs.size():
			guard += 1
			var prev := -1
			for j in ends.get(_key(segs[first][0]), []):
				if j != first and not used.has(j) and _fits(segs[j], segs[first]):
					prev = j
					break
			if prev < 0 or prev == i:
				break
			first = prev
		var pts := PackedVector2Array([segs[first][0]])
		var cur := first
		var closed := false
		var y0: float = segs[first][2]
		var y1: float = segs[first][3]
		while cur >= 0 and not used.has(cur):
			used[cur] = true
			pts.append(segs[cur][1])
			var nxt := -1
			y0 = maxf(y0, segs[cur][2])
			y1 = minf(y1, segs[cur][3])
			for j in starts.get(_key(segs[cur][1]), []):
				if not _fits(segs[j], segs[cur]):
					continue
				if j == first and pts.size() > 3:
					closed = true
				elif not used.has(j):
					nxt = j
					break
			if closed:
				break
			cur = nxt
		if closed:
			pts.remove_at(pts.size() - 1)
		out.append({"pts": pts, "closed": closed, "y0": y0, "y1": y1, "n0": segs[first][4]})
	return out


static func _key(p: Vector2) -> String:
	return "%d|%d" % [roundi(p.x * SNAP), roundi(p.y * SNAP)]


## Do two walls have about the same base and top?
static func _fits(a: Array, b: Array) -> bool:
	return absf(a[2] - b[2]) < DY and absf(a[3] - b[3]) < DY


## Append occluder triangles of the chains to out = [PackedVector3Array, PackedInt32Array].
static func emit(chains: Array, margin: float, min_w: float, min_h: float, out: Array) -> void:
	var sign := _outward_sign(chains)
	for c in chains:
		var y0: float = c.y0 + margin
		var y1: float = c.y1 - margin
		if y1 - y0 < min_h:
			continue
		var pts: PackedVector2Array = c.pts
		if c.closed:
			if _solid_inside(c, sign):
				for poly in Geometry2D.offset_polygon(pts, -margin):
					if Geometry2D.is_polygon_clockwise(poly) == Geometry2D.is_polygon_clockwise(pts) and _length(poly, true) >= min_w:
						_wall(poly, true, y0, y1, out)
		else:
			var trimmed := _trim(pts, margin)
			if trimmed.size() >= 2 and _length(trimmed, false) >= min_w:
				_wall(trimmed, false, y0, y1, out)


## +1 when wall normals point out of a solid ring's polygon in this model, -1 when in (decided by the largest ring).
static func _outward_sign(chains: Array) -> float:
	var best := 0.0
	var sign := 1.0
	for c in chains:
		if c.closed:
			var a := absf(_area(c.pts))
			if a > best:
				best = a
				sign = 1.0 if _points_out(c) else -1.0
	return sign


static func _solid_inside(c: Dictionary, sign: float) -> bool:
	return (1.0 if _points_out(c) else -1.0) == sign


## Does the first segment's normal point out of the ring's polygon?
static func _points_out(c: Dictionary) -> bool:
	var pts: PackedVector2Array = c.pts
	var mid := (pts[0] + pts[1]) * 0.5
	return not Geometry2D.is_point_in_polygon(mid + (c.n0 as Vector2) * 0.05, pts)


static func _area(pts: PackedVector2Array) -> float:
	var s := 0.0
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5


static func _length(pts: PackedVector2Array, closed: bool) -> float:
	var s := 0.0
	for i in pts.size() - (0 if closed else 1):
		s += pts[i].distance_to(pts[(i + 1) % pts.size()])
	return s


## Pull both ends of an open polyline in by m along it.
static func _trim(pts: PackedVector2Array, m: float) -> PackedVector2Array:
	var p := pts.duplicate()
	for end in 2:
		var left := m
		while p.size() >= 2 and left > 0.0:
			var i := 0 if end == 0 else p.size() - 1
			var j := 1 if end == 0 else p.size() - 2
			var seg := p[i].distance_to(p[j])
			if seg > left:
				p[i] = p[i].move_toward(p[j], left)
				left = 0.0
			else:
				left -= seg
				p.remove_at(i)
	return p


## Vertical quads along the polyline (x, z) from y0 to y1.
static func _wall(pts: PackedVector2Array, closed: bool, y0: float, y1: float, out: Array) -> void:
	var verts: PackedVector3Array = out[0]
	var idx: PackedInt32Array = out[1]
	var n := pts.size()
	for i in n - (0 if closed else 1):
		var a := pts[i]
		var b := pts[(i + 1) % n]
		var k := verts.size()
		verts.append_array([Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y)])
		idx.append_array([k, k + 1, k + 2, k, k + 2, k + 3])
	out[0] = verts
	out[1] = idx
