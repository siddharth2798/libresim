class_name JetwayLinks
extends RefCounted
## The fixed parts of the jet-bridge networks (airport_ops.json "jetlinks", tools/jetway_net.py): enclosed walkways on
## columns from the terminal wall to the rotundas of the movable bridges (JetwayRig), at the bridges' floor height.
## One mesh per airport: a box corridor per link (light cladding, a dark glazed band along both sides), its floor at
## ground + JetwayPose.FLOOR_Y at each end; an end at a rotunda stops inside the rotunda's room, an end at the
## building already runs INSET_M into it (the pipeline did that). Drawn only (no collision: they hang 3.6 m up,
## beside the buildings).

const HALF_W := 1.25  # the rotunda's fixed stub is 2.2 m wide, so it disappears inside
const BASE := -0.22  # underside below the floor
const ROOF := 2.6  # roof above the floor (the stub's roof is at 2.55)
const GLASS := [0.75, 1.85]  # glazed band above the floor
const COLUMN_EVERY := 18.0
const COL_HALF := 0.3
const ROT_STOP := 1.3  # a link stops this far short of a rotunda column (inside its 1.44 m room)

static var _body: StandardMaterial3D
static var _glass: StandardMaterial3D


## links: [{a: [e, n], b: [e, n]}]; h: Callable(e, n) -> ground (m); rots: rotunda positions (ENU Vector2).
## Returns a MeshInstance3D in the frame of AirportOps' root (x east, y height, z -north), or null.
static func build(links: Array, h: Callable, rots: Array) -> MeshInstance3D:
	if links.is_empty():
		return null
	var body := SurfaceTool.new()
	var glass := SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	for l in links:
		var a := Vector2(l.a[0], l.a[1])
		var b := Vector2(l.b[0], l.b[1])
		if a.distance_to(b) < 0.5:
			continue
		var d := (b - a).normalized()
		for r in rots:
			if (r as Vector2).distance_to(a) < 0.5:
				a += d * ROT_STOP
			if (r as Vector2).distance_to(b) < 0.5:
				b -= d * ROT_STOP
		if a.distance_to(b) < 0.3:
			continue
		var fa := float(h.call(a.x, a.y)) + JetwayPose.FLOOR_Y
		var fb := float(h.call(b.x, b.y)) + JetwayPose.FLOOR_Y
		_corridor(body, glass, a, b, fa, fb)
		var n := int(a.distance_to(b) / COLUMN_EVERY)
		for i in n:
			var t := float(i + 1) / (n + 1)
			var c := a.lerp(b, t)
			_box(body, c, d, COL_HALF, COL_HALF, float(h.call(c.x, c.y)) - 0.3, lerpf(fa, fb, t) + BASE)
	var mesh := ArrayMesh.new()
	for st in [body, glass]:
		(st as SurfaceTool).index()
		(st as SurfaceTool).commit(mesh)
	_materials()
	mesh.surface_set_material(0, _body)
	if mesh.get_surface_count() > 1:
		mesh.surface_set_material(1, _glass)
	var mi := MeshInstance3D.new()
	mi.name = "JetwayLinks"
	mi.mesh = mesh
	return mi


static func _materials() -> void:
	if _body:
		return
	_body = StandardMaterial3D.new()
	_body.albedo_color = Color(0.78, 0.79, 0.8)
	_body.roughness = 0.55
	_body.metallic = 0.25
	_body.cull_mode = BaseMaterial3D.CULL_DISABLED  # winding-agnostic: thin boxes, normals set per face
	_glass = StandardMaterial3D.new()
	_glass.albedo_color = Color(0.3, 0.36, 0.42)
	_glass.roughness = 0.25
	_glass.metallic = 0.3
	_glass.cull_mode = BaseMaterial3D.CULL_DISABLED


static func _v(p: Vector2, up: float) -> Vector3:
	return Vector3(p.x, up, -p.y)


## A quad p0 p1 p2 p3 (counter-clockwise seen from outside) with its normal.
static func _quad(st: SurfaceTool, q: Array, n: Vector3) -> void:
	st.set_normal(n)
	for i in [0, 1, 2, 0, 2, 3]:
		st.add_vertex(q[i])


static func _corridor(body: SurfaceTool, glass: SurfaceTool, a: Vector2, b: Vector2, fa: float, fb: float) -> void:
	var d := (b - a).normalized()
	var r := Vector2(d.y, -d.x) * HALF_W  # to the right of a -> b
	var nr := Vector3(r.x, 0.0, -r.y).normalized()
	var nd := Vector3(d.x, 0.0, -d.y)
	var lo_a := fa + BASE
	var lo_b := fb + BASE
	var hi_a := fa + ROOF
	var hi_b := fb + ROOF
	var ar := a + r
	var al := a - r
	var br := b + r
	var bl := b - r
	_quad(body, [_v(ar, lo_a), _v(br, lo_b), _v(br, hi_b), _v(ar, hi_a)], nr)  # right wall
	_quad(body, [_v(bl, lo_b), _v(al, lo_a), _v(al, hi_a), _v(bl, hi_b)], -nr)  # left wall
	_quad(body, [_v(al, hi_a), _v(ar, hi_a), _v(br, hi_b), _v(bl, hi_b)], Vector3.UP)  # roof
	_quad(body, [_v(al, lo_a), _v(bl, lo_b), _v(br, lo_b), _v(ar, lo_a)], Vector3.DOWN)  # underside
	_quad(body, [_v(al, lo_a), _v(ar, lo_a), _v(ar, hi_a), _v(al, hi_a)], -nd)  # end caps
	_quad(body, [_v(br, lo_b), _v(bl, lo_b), _v(bl, hi_b), _v(br, hi_b)], nd)
	var off := r.normalized() * 0.03  # the glazing stands just proud of the cladding
	var g0: float = GLASS[0]
	var g1: float = GLASS[1]
	_quad(glass, [_v(ar + off, fa + g0), _v(br + off, fb + g0), _v(br + off, fb + g1), _v(ar + off, fa + g1)], nr)
	_quad(glass, [_v(bl - off, fb + g0), _v(al - off, fa + g0), _v(al - off, fa + g1), _v(bl - off, fb + g1)], -nr)


## An upright box (column) centred on c, aligned with d, from height lo to hi.
static func _box(st: SurfaceTool, c: Vector2, d: Vector2, ha: float, hc: float, lo: float, hi: float) -> void:
	if hi <= lo:
		return
	var f := d * ha
	var s := Vector2(d.y, -d.x) * hc
	var p := [c + f + s, c - f + s, c - f - s, c + f - s]  # clockwise seen from above (ENU)
	for i in 4:
		var p0: Vector2 = p[i]
		var p1: Vector2 = p[(i + 1) % 4]
		var e := (p1 - p0)
		var n := Vector3(-e.y, 0.0, -e.x).normalized()  # outward: ENU left of the clockwise edge
		_quad(st, [_v(p1, lo), _v(p0, lo), _v(p0, hi), _v(p1, hi)], n)
