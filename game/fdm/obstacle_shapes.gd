class_name ObstacleShapes
extends RefCounted
## Obstacle records and the segment-vs-solid test used by ObstacleCollision.
## A record is a Dictionary, positions are ENU metres (east, north, up AMSL):
##   common: id (unique), k (DISC / POLY / GRID), label ("trees", "a building", ...), base, top, lo, hi (Vector2 bbox),
##           soft (OSM buildings and trees: forgiven while the CG is inside a taxiway / runway corridor)
##   DISC:   c (Vector2 centre), r        a vertical cylinder (a tree canopy, a mast)
##   POLY:   poly (PackedVector2Array)    a vertical prism (building, vehicle, jetway box)
##   GRID:   o (Vector2 SW corner), cell, nx, ny, zmin, zmax (row-major, PackedFloat32Array)
##           a height-interval raster (a terminal model: walls, roofs and canopies)

const DISC := 0
const POLY := 1
const GRID := 2
static var _next_id := 0


static func _id() -> int:
	_next_id += 1
	return _next_id


static func disc(c: Vector2, r: float, base: float, top: float, label: String, soft := false) -> Dictionary:
	return {"id": _id(), "k": DISC, "label": label, "base": base, "top": top, "c": c, "r": r, "soft": soft,
		"lo": c - Vector2(r, r), "hi": c + Vector2(r, r)}


static func poly(pts: PackedVector2Array, base: float, top: float, label: String, soft := false) -> Dictionary:
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	return {"id": _id(), "k": POLY, "label": label, "base": base, "top": top, "poly": pts, "lo": lo, "hi": hi, "soft": soft}


## Oriented rectangle: centre, half sizes along / across heading (rad, compass: 0 = north).
static func box(c: Vector2, half_along: float, half_across: float, heading: float, base: float, top: float, label: String) -> Dictionary:
	var f := Vector2(sin(heading), cos(heading))
	var s := Vector2(f.y, -f.x)
	var pts := PackedVector2Array([c + f * half_along + s * half_across, c + f * half_along - s * half_across,
		c - f * half_along - s * half_across, c - f * half_along + s * half_across])
	return poly(pts, base, top, label)


## zmin / zmax: per-cell solid interval, INF / -INF where the cell is empty.
static func grid(o: Vector2, cell: float, nx: int, ny: int, zmin: PackedFloat32Array, zmax: PackedFloat32Array, label: String) -> Dictionary:
	var lo := 1e30
	var hi := -1e30
	for i in zmax.size():
		if zmax[i] > -1e29:
			lo = minf(lo, zmin[i])
			hi = maxf(hi, zmax[i])
	return {"id": _id(), "k": GRID, "label": label, "base": lo, "top": hi, "o": o, "cell": cell, "nx": nx, "ny": ny,
		"zmin": zmin, "zmax": zmax, "lo": o, "hi": o + Vector2(nx, ny) * cell, "soft": false}


## Does the segment p -> q touch the solid? (Zero-thickness segment against a solid.)
static func segment_hits(p: Vector3, q: Vector3, o: Dictionary) -> bool:
	var lo: Vector2 = o.lo
	var hi: Vector2 = o.hi
	if maxf(p.x, q.x) < lo.x or minf(p.x, q.x) > hi.x or maxf(p.y, q.y) < lo.y or minf(p.y, q.y) > hi.y:
		return false
	var t0 := 0.0
	var t1 := 1.0
	var dz := q.z - p.z
	if absf(dz) < 1e-9:
		if p.z < o.base or p.z > o.top:
			return false
	else:
		var ta: float = (o.base - p.z) / dz
		var tb: float = (o.top - p.z) / dz
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 > t1:
			return false
	var a := Vector2(lerpf(p.x, q.x, t0), lerpf(p.y, q.y, t0))
	var b := Vector2(lerpf(p.x, q.x, t1), lerpf(p.y, q.y, t1))
	match o.k:
		DISC:
			return Geometry2D.get_closest_point_to_segment(o.c, a, b).distance_squared_to(o.c) < o.r * o.r
		POLY:
			var poly: PackedVector2Array = o.poly
			if Geometry2D.is_point_in_polygon(a, poly) or Geometry2D.is_point_in_polygon(b, poly):
				return true
			return a.distance_squared_to(b) > 1e-8 and not Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([a, b]), poly).is_empty()
		_:
			return _grid_hits(p, q, t0, t1, o)


static func _grid_hits(p: Vector3, q: Vector3, t0: float, t1: float, o: Dictionary) -> bool:
	var cell: float = o.cell
	var org: Vector2 = o.o
	var len := Vector2(q.x - p.x, q.y - p.y).length() * (t1 - t0)
	var n := maxi(int(ceil(len / (cell * 0.5))), 1)
	var nx: int = o.nx
	var ny: int = o.ny
	var zmin: PackedFloat32Array = o.zmin
	var zmax: PackedFloat32Array = o.zmax
	for i in n + 1:
		var t := lerpf(t0, t1, float(i) / n)
		var ix := floori((lerpf(p.x, q.x, t) - org.x) / cell)
		var iy := floori((lerpf(p.y, q.y, t) - org.y) / cell)
		if ix < 0 or iy < 0 or ix >= nx or iy >= ny:
			continue
		var z := lerpf(p.z, q.z, t)
		var k := iy * nx + ix
		if z >= zmin[k] and z <= zmax[k]:
			return true
	return false
