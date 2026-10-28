class_name VehicleGeo
extends RefCounted
## Small mesh builder for procedural vehicles (follow-me car): lofted rounded-rectangle shells,
## chamfered boxes, extruded profiles, lathes. Every vertex carries its material in COLOR:
## rgb = linear albedo, a = kind / 10 (see K and world/follow_me.gdshader). All faces are
## described counter-clockwise about their outward normal; Godot wants clockwise, tri() flips.
## Vehicle frame: x right, y up, -z forward.

enum K { PAINT, PLASTIC, RUBBER, METAL, TAPE, SIGN, LENS_L, LENS_R, HEAD, TAIL }

var pos := PackedVector3Array()
var nrm := PackedVector3Array()
var cols := PackedColorArray()
var uvs := PackedVector2Array()
var idx := PackedInt32Array()


## Material colour: sRGB albedo plus kind (stored linear, as the shader reads it).
static func mat(c: Color, kind: int) -> Color:
	var l := c.srgb_to_linear()
	return Color(l.r, l.g, l.b, kind * 0.1)


func triangles() -> int:
	return idx.size() / 3


func vert(p: Vector3, n: Vector3, c: Color, uv := Vector2.ZERO) -> int:
	pos.append(p)
	nrm.append(n)
	cols.append(c)
	uvs.append(uv)
	return pos.size() - 1


## a, b, c counter-clockwise about the outward normal.
func tri(a: int, b: int, c: int) -> void:
	idx.append_array([a, c, b])


## Flat convex polygon; `outward` only picks the side (the point order may be either).
func poly(pts: Array, outward: Vector3, c: Color, uv_in := []) -> void:
	var nn := Vector3.ZERO
	for i in range(1, pts.size() - 1):
		nn += (pts[i] - pts[0]).cross(pts[i + 1] - pts[0])
	if nn.length() < 1e-9:
		return
	var rev := nn.dot(outward) < 0.0
	nn = nn.normalized() * (-1.0 if rev else 1.0)
	var base := pos.size()
	for i in pts.size():
		vert(pts[i], nn, c, uv_in[i] if i < uv_in.size() else Vector2.ZERO)
	for i in range(1, pts.size() - 1):
		if rev:
			tri(base, base + i + 1, base + i)
		else:
			tri(base, base + i, base + i + 1)


## Rounded rectangle ring in the xy plane at depth z, counter-clockwise seen from +z, starting at
## the bottom edge. Radii shrink to fit; nc points per corner.
static func ring(hw: float, yb: float, yt: float, rt: float, rb: float, z: float, nc := 4) -> PackedVector3Array:
	var h := yt - yb
	rt = minf(rt, minf(h * 0.45, hw * 0.9))
	rb = minf(rb, minf(h * 0.45, hw * 0.9))
	var out := PackedVector3Array()
	var corners := [
		[Vector2(hw - rb, yb + rb), rb, -90.0], [Vector2(hw - rt, yt - rt), rt, 0.0],
		[Vector2(-hw + rt, yt - rt), rt, 90.0], [Vector2(-hw + rb, yb + rb), rb, 180.0]]
	for cn in corners:
		for k in nc:
			var a := deg_to_rad(cn[2] + 90.0 * k / (nc - 1))
			var c: Vector2 = cn[0]
			out.append(Vector3(c.x + cos(a) * cn[1], c.y + sin(a) * cn[1], z))
	return out


## Surface through rings (rows, increasing z) with smooth normals.
func loft(rows: Array, c: Color) -> void:
	var m := rows.size()
	var n: int = rows[0].size()
	var base := pos.size()
	for i in m:
		var i0 := maxi(i - 1, 0)
		var i1 := mini(i + 1, m - 1)
		for j in n:
			var du: Vector3 = rows[i1][j] - rows[i0][j]
			var dv: Vector3 = rows[i][(j + 1) % n] - rows[i][(j - 1 + n) % n]
			vert(rows[i][j], dv.cross(du).normalized(), c, Vector2(float(j) / n, float(i) / (m - 1)))
	for i in m - 1:
		for j in n:
			var a := base + i * n + j
			var b := base + i * n + (j + 1) % n
			var cc := base + (i + 1) * n + (j + 1) % n
			var d := base + (i + 1) * n + j
			tri(a, b, cc)
			tri(a, cc, d)


## Chamfered box (bevel 0 = plain), optionally rotated by `basis` about its centre.
func box(center: Vector3, size: Vector3, c: Color, bevel := 0.0, basis := Basis.IDENTITY) -> void:
	var h := size * 0.5
	var b := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.9)
	var lv := [[-h.x, -h.x + b, h.x - b, h.x], [-h.y, -h.y + b, h.y - b, h.y], [-h.z, -h.z + b, h.z - b, h.z]]
	var pt := func(i: Array) -> Vector3: return center + basis * Vector3(lv[0][i[0]], lv[1][i[1]], lv[2][i[2]])
	var dirs := [Vector3.LEFT, Vector3.RIGHT, Vector3.DOWN, Vector3.UP, Vector3.FORWARD, Vector3.BACK]
	if b <= 0.0:
		for ax in 3:
			for s in 2:
				var e := 0 if s == 0 else 3
				var o1 := (ax + 1) % 3
				var o2 := (ax + 2) % 3
				var q := []
				for uv in [[0, 0], [3, 0], [3, 3], [0, 3]]:
					var i := [0, 0, 0]
					i[ax] = e
					i[o1] = uv[0]
					i[o2] = uv[1]
					q.append(pt.call(i))
				poly(q, basis * dirs[ax * 2 + s], c)
		return
	for ax in 3:  # six inset faces
		for s in 2:
			var e := 0 if s == 0 else 3
			var o1 := (ax + 1) % 3
			var o2 := (ax + 2) % 3
			var q := []
			for uv in [[1, 1], [2, 1], [2, 2], [1, 2]]:
				var i := [0, 0, 0]
				i[ax] = e
				i[o1] = uv[0]
				i[o2] = uv[1]
				q.append(pt.call(i))
			poly(q, basis * dirs[ax * 2 + s], c)
	for t in 3:  # twelve edge strips, running along axis t
		var a := (t + 1) % 3
		var cx := (t + 2) % 3
		for sa in 2:
			for sc in 2:
				var ea := 0 if sa == 0 else 3
				var ec := 0 if sc == 0 else 3
				var ia := 1 if sa == 0 else 2
				var ic := 1 if sc == 0 else 2
				var q := []
				for spec in [[ea, ic, 1], [ea, ic, 2], [ia, ec, 2], [ia, ec, 1]]:
					var i := [0, 0, 0]
					i[a] = spec[0]
					i[cx] = spec[1]
					i[t] = spec[2]
					q.append(pt.call(i))
				var hint: Vector3 = dirs[a * 2 + sa] + dirs[cx * 2 + sc]
				poly(q, basis * hint, c)
	for sx in 2:  # eight corner triangles
		for sy in 2:
			for sz in 2:
				var ex := [0 if sx == 0 else 3, 1 if sx == 0 else 2]
				var ey := [0 if sy == 0 else 3, 1 if sy == 0 else 2]
				var ez := [0 if sz == 0 else 3, 1 if sz == 0 else 2]
				poly([pt.call([ex[0], ey[1], ez[1]]), pt.call([ex[1], ey[0], ez[1]]), pt.call([ex[1], ey[1], ez[0]])],
					basis * (dirs[sx] + dirs[2 + sy] + dirs[4 + sz]), c)


## A bar from p0 to p1 with a wx by wd cross-section (wx lateral), for pillars, struts and rails.
func strut(p0: Vector3, p1: Vector3, wx: float, wd: float, c: Color, bevel := 0.0) -> void:
	var d := (p1 - p0).normalized()
	var ax := (Vector3.RIGHT - d * d.dot(Vector3.RIGHT)).normalized()
	box((p0 + p1) * 0.5, Vector3(wx, p0.distance_to(p1), wd), c, bevel, Basis(ax, d, ax.cross(d)))


## Prism: a profile polygon in (z, y) extruded from x0 to x1 (flat shading; concave profiles are fine).
func prism_x(profile: PackedVector2Array, x0: float, x1: float, c: Color) -> void:
	var v3 := func(x: float, p: Vector2) -> Vector3: return Vector3(x, p.y, p.x)
	var tr := Geometry2D.triangulate_polygon(profile)
	for k in range(0, tr.size(), 3):
		for s in 2:
			var x := x1 if s == 0 else x0
			poly([v3.call(x, profile[tr[k]]), v3.call(x, profile[tr[k + 1]]), v3.call(x, profile[tr[k + 2]])],
				Vector3.RIGHT if s == 0 else Vector3.LEFT, c)
	var area := 0.0
	var n := profile.size()
	for i in n:
		area += profile[i].cross(profile[(i + 1) % n])
	for i in n:
		var p := profile[i]
		var q := profile[(i + 1) % n]
		var e := q - p
		var o := Vector2(e.y, -e.x) * (1.0 if area > 0.0 else -1.0)
		poly([v3.call(x0, p), v3.call(x1, p), v3.call(x1, q), v3.call(x0, q)], Vector3(0.0, o.y, o.x), c)


## Surface of revolution about the x axis. profile = (x, r) points; the normal is the tangent turned
## +90 degrees in the (x, r) plane (a tread running +x faces outward). basis rotates the whole thing.
func lathe_x(profile: PackedVector2Array, center: Vector3, segs: int, c: Color, basis := Basis.IDENTITY) -> void:
	var m := profile.size()
	var base := pos.size()
	for i in m:
		var t := profile[mini(i + 1, m - 1)] - profile[maxi(i - 1, 0)]
		var n2 := Vector2(-t.y, t.x).normalized()
		for k in segs + 1:
			var a := TAU * k / segs
			var ca := cos(a)
			var sa := sin(a)
			vert(center + basis * Vector3(profile[i].x, profile[i].y * ca, profile[i].y * sa),
				(basis * Vector3(n2.x, n2.y * ca, n2.y * sa)).normalized(), c, Vector2(float(k) / segs, float(i) / maxi(m - 1, 1)))
	for i in m - 1:
		for k in segs:
			var a := base + i * (segs + 1) + k
			var b := a + 1
			var d := a + segs + 1
			var e := d + 1
			# a quad winds either way depending on the profile direction: test against the normal
			var geo := (pos[b] - pos[a]).cross(pos[d] - pos[a])
			if geo.dot(nrm[a] + nrm[b] + nrm[d] + nrm[e]) >= 0.0:
				tri(a, b, e)
				tri(a, e, d)
			else:
				tri(a, e, b)
				tri(a, d, e)


func to_arrays() -> Array:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


## Adds this geometry as one surface of `mesh` (nothing if empty).
func commit(mesh: ArrayMesh, material: Material) -> void:
	if pos.is_empty():
		return
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, to_arrays())
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)
