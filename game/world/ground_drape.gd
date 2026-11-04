class_name GroundDrape
extends RefCounted
## Meshes laid exactly on the drawn ground: runway / taxiway ribbons, stand markings, the taxi-route line.
## Each 2D triangle is cut along the terrain lattice (x = k*res, y = k*res and the cell diagonal x + y = k*res,
## see TerrainMesh) so every piece lies inside one terrain triangle; its vertices take the terrain height
## (TerrainTileCache.height_at, which interpolates the same triangles), so the overlay is coplanar with the
## finest terrain LOD and with the FDM's ground. Z-fighting is the shader's job (a view-space pull, see
## strip.gdshaderinc / ground_paint.gdshader), never a physical lift (docs/TYRE-CONTACT-PLAN.md).

const EPS := 1e-4  # m: a vertex this close to a lattice line is on it


## tris: 2D triangles (3 points each, metres from (ox, oy)); uvs: one per point. height_at: Callable(e, n) -> m.
## (ox, oy) must be a lattice point (snap()). Returns an indexed ArrayMesh, vertices (x, h - oz, -y) from the
## origin, the triangles' winding kept, normals up; null when nothing is left.
static func build(tris: PackedVector2Array, uvs: PackedVector2Array, ox: float, oy: float, oz: float,
		height_at: Callable, res: float) -> ArrayMesh:
	return to_mesh(arrays(tris, uvs, ox, oy, oz, height_at, res))


## ArrayMesh from arrays() (main thread); null for [].
static func to_mesh(arr: Array) -> ArrayMesh:
	if arr.is_empty():
		return null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


## The surface arrays of build() ([] when empty). Pure: safe on a worker thread when height_at is.
static func arrays(tris: PackedVector2Array, uvs: PackedVector2Array, ox: float, oy: float, oz: float,
		height_at: Callable, res: float) -> Array:
	var verts := PackedVector3Array()
	var tex := PackedVector2Array()
	var idx := PackedInt32Array()
	var a: Array[PackedVector2Array] = []
	var b: Array[PackedVector2Array] = []
	var pieces: Array[PackedVector2Array] = []
	for t in range(0, tris.size() - 2, 3):
		var p0 := tris[t]
		var e1 := tris[t + 1] - p0
		var e2 := tris[t + 2] - p0
		var det := e1.cross(e2)
		if absf(det) < 1e-6:
			continue
		a.clear()
		b.clear()
		pieces.clear()
		_cut(PackedVector2Array([p0, tris[t + 1], tris[t + 2]]), Vector2(1, 0), res, a)
		for p in a:
			_cut(p, Vector2(0, 1), res, b)
		for p in b:
			_cut(p, Vector2(1, 1), res, pieces)
		var u0 := uvs[t]
		var du1 := uvs[t + 1] - u0
		var du2 := uvs[t + 2] - u0
		for p in pieces:
			var base := verts.size()
			for q in p:
				var d := q - p0  # UV is affine over the source triangle: barycentric weights
				var w1 := d.cross(e2) / det
				var w2 := e1.cross(d) / det
				verts.append(Vector3(q.x, float(height_at.call(ox + q.x, oy + q.y)) - oz, -q.y))
				tex.append(u0 + du1 * w1 + du2 * w2)
			for k in range(1, p.size() - 1):
				idx.append(base)
				idx.append(base + k)
				idx.append(base + k + 1)
	if idx.is_empty():
		return []
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = tex
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


## The lattice point at or below (e, n): a drape origin that keeps the lattice lines at multiples of res.
static func snap(e: float, n: float, res: float) -> Vector2:
	return Vector2(floorf(e / res) * res, floorf(n / res) * res)


## Strip of quads along a polyline (metres from the origin), split in two triangles each, UV = (across 0..1,
## metres along) as AirportBuilder's ribbons. Appends to tris / uvs; returns the length.
static func strip(pts: Array, width: float, tris: PackedVector2Array, uvs: PackedVector2Array) -> float:
	var along := 0.0
	var prev_l := Vector2.ZERO
	var prev_r := Vector2.ZERO
	for i in pts.size():
		var p: Vector2 = pts[i]
		var dir: Vector2 = (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := Vector2(dir.y, -dir.x) * width * 0.5  # to the right of travel
		var l := p - side
		var r := p + side
		if i > 0:
			var a0 := along
			along += p.distance_to(pts[i - 1])
			# clockwise seen from above (the 3D z is -north): (l0, l1, r0), (r0, l1, r1)
			tris.append_array([prev_l, l, prev_r, prev_r, l, r])
			uvs.append_array([Vector2(0, a0), Vector2(0, along), Vector2(1, a0), Vector2(1, a0), Vector2(0, along), Vector2(1, along)])
		prev_l = l
		prev_r = r
	return along


## Cuts convex polygon poly along the lines p.dot(nrm) = k * s; appends the pieces.
static func _cut(poly: PackedVector2Array, nrm: Vector2, s: float, out: Array[PackedVector2Array]) -> void:
	var lo := INF
	var hi := -INF
	for v in poly:
		var d := v.dot(nrm)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	var k0 := floori(lo / s + EPS) + 1
	var k1 := ceili(hi / s - EPS)
	if k0 >= k1:
		out.append(poly)
		return
	var rest := poly
	for k in range(k0, k1):
		var c := k * s
		var below := PackedVector2Array()
		var above := PackedVector2Array()
		var n := rest.size()
		for i in n:
			var pa := rest[i]
			var pb := rest[(i + 1) % n]
			var da := pa.dot(nrm) - c
			var db := pb.dot(nrm) - c
			if da <= EPS:
				below.append(pa)
			if da >= -EPS:
				above.append(pa)
			if (da < -EPS and db > EPS) or (da > EPS and db < -EPS):
				var x := pa.lerp(pb, da / (da - db))
				below.append(x)
				above.append(x)
		if below.size() >= 3:
			out.append(below)
		rest = above
		if rest.size() < 3:
			return
	out.append(rest)
