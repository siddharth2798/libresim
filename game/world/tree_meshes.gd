class_name TreeMeshes
extends RefCounted
## Procedural LOD0 tree meshes (TreeLod draws them within ~100-150 m, tree_mesh.gdshader). One
## ArrayMesh per species in unit size: x and z in crown widths, y in tree heights, origin at the
## trunk foot; the instance transform scales them to the tree. Built from tapered trunks, low-poly
## icosphere crown lumps (about 80 triangles each, normals blended towards the crown centre so a
## crown shades as one mass) and, for palms, drooping frond strips. COLOR.rgb is the base colour with
## baked occlusion, COLOR.a the part kind the shader looks at: 0 bark, 0.5 leaves, 1 frond.
## A species is 300-600 triangles.

const BARK := Color(0.16, 0.11, 0.08)
const LEAF := [Color(0.11, 0.21, 0.07), Color(0.11, 0.21, 0.05), Color(0.17, 0.22, 0.08), Color(0.09, 0.17, 0.09)]

static var _ico: Array = []  # [unit vertices, indices]


class Part:
	extends RefCounted
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var i := PackedInt32Array()

	func vert(p: Vector3, nrm: Vector3, col: Color, t := Vector2.ZERO) -> int:
		v.append(p)
		n.append(nrm.normalized())
		c.append(col)
		uv.append(t)
		return v.size() - 1


static func build(sp: int) -> ArrayMesh:
	var b := Part.new()
	match sp:
		TreeSpecies.PALM:
			_palm(b)
		TreeSpecies.ACACIA:
			_acacia(b)
		TreeSpecies.SLIM:
			_slim(b)
		_:
			_broadleaf(b)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = b.v
	arrays[Mesh.ARRAY_NORMAL] = b.n
	arrays[Mesh.ARRAY_COLOR] = b.c
	arrays[Mesh.ARRAY_TEX_UV] = b.uv
	arrays[Mesh.ARRAY_INDEX] = b.i
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


static func triangle_count(m: ArrayMesh) -> int:
	return m.surface_get_array_index_len(0) / 3


static func _icosphere() -> Array:
	if not _ico.is_empty():
		return _ico
	var t := (1.0 + sqrt(5.0)) * 0.5
	var v: Array[Vector3] = []
	for p in [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
			Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]:
		v.append(p.normalized())
	var f := [0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1]
	var mid := {}
	var idx := PackedInt32Array()
	for k in range(0, f.size(), 3):
		var a: int = f[k]
		var b: int = f[k + 1]
		var c: int = f[k + 2]
		var ab := _mid(v, mid, a, b)
		var bc := _mid(v, mid, b, c)
		var ca := _mid(v, mid, c, a)
		idx.append_array([a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca])
	_ico = [PackedVector3Array(v), idx]
	return _ico


static func _mid(v: Array[Vector3], cache: Dictionary, a: int, b: int) -> int:
	var key := Vector2i(mini(a, b), maxi(a, b))
	if not cache.has(key):
		v.append(((v[a] + v[b]) * 0.5).normalized())
		cache[key] = v.size() - 1
	return cache[key]


## Crown lump: an ellipsoid. Normals mix the sphere normal with the direction from the crown centre.
static func _lump(b: Part, c: Vector3, r: Vector3, col: Color, crown_c: Vector3, crown_r: Vector3, y0: float, y1: float) -> void:
	var ico := _icosphere()
	var base := b.v.size()
	for u: Vector3 in ico[0]:
		var p := c + u * r
		var ns := (u / r).normalized()
		var nc := ((p - crown_c) / crown_r).normalized()
		var ao := lerpf(0.55, 1.0, clampf((p.y - y0) / maxf(y1 - y0, 0.01), 0.0, 1.0))
		b.vert(p, ns * 0.45 + nc * 0.55, Color(col.r * ao, col.g * ao, col.b * ao, 0.5), Vector2(p.x, p.z))
	for i: int in ico[1]:
		b.i.append(base + i)


## Tapered tube along points (rings of `sides`), bark coloured.
static func _tube(b: Part, pts: Array, radii: Array, sides: int, col: Color, rings := false) -> void:
	var base := b.v.size()
	for k in pts.size():
		var p: Vector3 = pts[k]
		var dir: Vector3 = (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized()
		var side := dir.cross(Vector3.RIGHT if absf(dir.x) < 0.9 else Vector3.FORWARD).normalized()
		var up := dir.cross(side)
		var shade := 0.8 + (0.2 if rings and k % 2 == 0 else 0.0)
		for s in sides:
			var a := TAU * s / sides
			var d := side * cos(a) + up * sin(a)
			b.vert(p + d * radii[k], d, Color(col.r * shade, col.g * shade, col.b * shade, 0.0))
	for k in pts.size() - 1:
		for s in sides:
			var s2 := (s + 1) % sides
			var a0 := base + k * sides + s
			var a1 := base + k * sides + s2
			var b0 := a0 + sides
			var b1 := a1 + sides
			b.i.append_array([a0, b0, a1, a1, b0, b1])


static func _broadleaf(b: Part) -> void:
	_tube(b, [Vector3(0, 0, 0), Vector3(0.01, 0.17, 0.0), Vector3(0, 0.36, 0)], [0.028, 0.02, 0.014], 6, BARK)
	var cc := Vector3(0, 0.63, 0)
	var cr := Vector3(0.5, 0.36, 0.5)
	var col: Color = LEAF[0]
	_lump(b, Vector3(0, 0.64, 0), Vector3(0.36, 0.3, 0.36), col, cc, cr, 0.3, 0.98)
	for k in 5:
		var a := TAU * (k + 0.3) / 5.0
		_lump(b, Vector3(cos(a) * 0.18, 0.54 + 0.07 * (k % 2), sin(a) * 0.18), Vector3(0.27, 0.22, 0.27), col, cc, cr, 0.3, 0.98)
	_lump(b, Vector3(0.02, 0.8, -0.02), Vector3(0.24, 0.17, 0.24), col, cc, cr, 0.3, 0.98)


static func _acacia(b: Part) -> void:
	var col: Color = LEAF[2]
	_tube(b, [Vector3(0, 0, 0), Vector3(0.015, 0.2, 0), Vector3(0, 0.38, 0)], [0.032, 0.026, 0.022], 6, BARK)
	_tube(b, [Vector3(0, 0.38, 0), Vector3(-0.1, 0.5, 0.02), Vector3(-0.2, 0.62, 0.05)], [0.02, 0.015, 0.011], 5, BARK)
	_tube(b, [Vector3(0, 0.38, 0), Vector3(0.1, 0.5, -0.02), Vector3(0.22, 0.66, -0.04)], [0.02, 0.015, 0.011], 5, BARK)
	var cc := Vector3(0, 0.7, 0)
	var cr := Vector3(0.6, 0.2, 0.6)
	_lump(b, Vector3(-0.2, 0.68, 0.02), Vector3(0.3, 0.1, 0.28), col, cc, cr, 0.55, 0.85)
	_lump(b, Vector3(0.22, 0.72, -0.05), Vector3(0.28, 0.1, 0.26), col, cc, cr, 0.55, 0.85)
	_lump(b, Vector3(0.0, 0.76, 0.0), Vector3(0.32, 0.11, 0.3), col, cc, cr, 0.55, 0.85)
	_lump(b, Vector3(0.05, 0.64, 0.18), Vector3(0.24, 0.08, 0.22), col, cc, cr, 0.55, 0.85)


static func _slim(b: Part) -> void:
	var col: Color = LEAF[3]
	_tube(b, [Vector3(0, 0, 0), Vector3(0, 0.25, 0), Vector3(0, 0.5, 0)], [0.04, 0.032, 0.025], 6, BARK)
	var cc := Vector3(0, 0.66, 0)
	var cr := Vector3(0.5, 0.4, 0.5)
	for L in [[0.4, 0.44, 0.24], [0.56, 0.42, 0.22], [0.72, 0.36, 0.2], [0.86, 0.26, 0.16], [0.95, 0.14, 0.1]]:
		_lump(b, Vector3(0.0, L[0], 0.0), Vector3(L[1], L[2], L[1]), col, cc, cr, 0.3, 1.0)


static func _palm(b: Part) -> void:
	var top := Vector3(0.03, 0.87, 0.015)
	_tube(b, [Vector3(0, 0, 0), Vector3(0.006, 0.3, 0.004), Vector3(0.016, 0.6, 0.01), top], [0.03, 0.021, 0.016, 0.014], 6, Color(0.12, 0.11, 0.095), true)
	var col: Color = LEAF[1]
	var n := 11
	for k in n:
		var a := TAU * (k + 0.35 * sin(k * 2.7)) / n
		var dir := Vector3(cos(a), 0, sin(a))
		var length := 0.5 + 0.08 * sin(k * 1.9)
		var rise := 0.05 + 0.03 * sin(k * 3.1)
		_frond(b, top + dir * 0.01, dir, length, rise, 0.17, col)
	_lump(b, top + Vector3(0, -0.015, 0), Vector3(0.05, 0.025, 0.05), Color(0.2, 0.15, 0.06), top, Vector3(0.1, 0.1, 0.1), 0.8, 0.9)


## Frond: a strip of 5 segments along a drooping arc, tapering to the tip (UV x across, y along).
static func _frond(b: Part, o: Vector3, dir: Vector3, length: float, rise: float, width: float, col: Color) -> void:
	var side := dir.cross(Vector3.UP).normalized()
	var base := b.v.size()
	var segs := 5
	for s in segs + 1:
		var t := float(s) / segs
		var p := o + dir * length * t + Vector3(0, rise * t * 2.0 - rise * 3.4 * t * t, 0)
		var w := width * 0.5 * sin(PI * (0.08 + 0.92 * minf(t * 1.0, 1.0))) * (1.0 - 0.3 * t)
		var shade := lerpf(0.6, 1.0, t)
		var c := Color(col.r * shade, col.g * shade, col.b * shade, 1.0)
		var n := (Vector3.UP * 0.8 + dir * 0.3).normalized()
		b.vert(p - side * w, n, c, Vector2(0.0, t))
		b.vert(p + side * w, n, c, Vector2(1.0, t))
	for s in segs:
		var i := base + s * 2
		b.i.append_array([i, i + 2, i + 1, i + 1, i + 2, i + 3])
