class_name SolidGrid
extends RefCounted
## Turns a triangle soup (a landmark terminal model) into a collision raster, an
## ObstacleShapes.grid record: for each 2 m cell the interval of heights the model occupies.
## Paving at ground level is not solid. A cell whose lowest surface is within low_fill (LOW_FILL by
## default) of the ground is solid from the ground up (walls, low roofs); higher up it keeps its own
## interval, so an 8 m canopy leaves room to taxi underneath. Pure function of its input: runs on a worker thread.

const CELL := 2.0
const PAVEMENT := 0.8  # surfaces this close to the ground are paving
const LOW_FILL := 6.0


## verts: 3 per triangle, ENU metres (east, north, up). ground: the model's ground height (m AMSL).
static func build(verts: PackedVector3Array, ground: float, label: String, low_fill := LOW_FILL) -> Dictionary:
	if verts.size() < 3:
		return {}
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for v in verts:
		lo = lo.min(Vector2(v.x, v.y))
		hi = hi.max(Vector2(v.x, v.y))
	var nx := int(ceil((hi.x - lo.x) / CELL)) + 1
	var ny := int(ceil((hi.y - lo.y) / CELL)) + 1
	var zmin := PackedFloat32Array()
	var zmax := PackedFloat32Array()
	zmin.resize(nx * ny)
	zmax.resize(nx * ny)
	zmin.fill(INF)
	zmax.fill(-INF)
	for t in range(0, verts.size() - 2, 3):
		var a := verts[t]
		var ab := verts[t + 1] - a
		var ac := verts[t + 2] - a
		var steps := maxi(int(ceil(maxf(ab.length(), maxf(ac.length(), (ab - ac).length())) / (CELL * 0.7))), 1)
		for i in steps + 1:
			for j in steps + 1 - i:
				var p := a + ab * (float(i) / steps) + ac * (float(j) / steps)
				if p.z < ground + PAVEMENT:
					continue
				var k := int((p.y - lo.y) / CELL) * nx + int((p.x - lo.x) / CELL)
				zmin[k] = minf(zmin[k], p.z)
				zmax[k] = maxf(zmax[k], p.z)
	for k in zmin.size():
		if zmax[k] > -INF and zmin[k] < ground + low_fill:
			zmin[k] = ground
	return ObstacleShapes.grid(lo, CELL, nx, ny, zmin, zmax, label)
