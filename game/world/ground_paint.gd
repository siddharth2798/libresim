class_name GroundPaint
extends RefCounted
## Painted lines on the ground (AirportOps stand lead-in lines and stop bars, the GroundOps taxi-route line):
## strips draped on the terrain triangles at the FDM's ground height (GroundDrape) with a depth-pull shader
## (ground_paint.gdshader). They used to be boxes / quads 18-25 cm above the ground, so a nose wheel rolling
## along the line sank into it (docs/TYRE-CONTACT-PLAN.md).

const PULL_STAND := 0.998  # over the apron, taxiway and runway ribbons (as a lead-on line)
const PULL_ROUTE := 0.9975  # over stand paint too
static var _mats := {}  # [Color, pull] -> ShaderMaterial
static var _shader: Shader


static func material(color: Color, pull: float) -> ShaderMaterial:
	var k := [color, pull]
	if not _mats.has(k):
		if _shader == null:
			_shader = load("res://world/ground_paint.gdshader")
		var m := ShaderMaterial.new()
		m.shader = _shader
		m.set_shader_parameter("color", color)
		m.set_shader_parameter("pull", pull)
		_mats[k] = m
	return _mats[k]


## A strip of width along pts (world ENU Vector2, a polyline) on the ground. The node's position is the
## drape origin in ENU (east, north, up); the caller puts it in render / parent space (see enu_origin).
## res: the terrain lattice (TerrainMeta tile_size_m / tile_n).
static func strip(pts: Array, width: float, height_at: Callable, mat: Material, res := 30.0) -> MeshInstance3D:
	if pts.size() < 2:
		return null

	var o := GroundDrape.snap(pts[0].x, pts[0].y, res)
	var oz: float = height_at.call(pts[0].x, pts[0].y)
	var local: Array = []
	for p in pts:
		local.append(Vector2(p.x - o.x, p.y - o.y))
	var tris := PackedVector2Array()
	var uvs := PackedVector2Array()
	GroundDrape.strip(local, width, tris, uvs)
	var mesh := GroundDrape.build(tris, uvs, o.x, o.y, oz, height_at, res)
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("enu_origin", Vector3(o.x, o.y, oz))
	return mi


## The ENU drape origin of a strip() node.
static func enu_origin(mi: MeshInstance3D) -> Vector3:
	return mi.get_meta("enu_origin", Vector3.ZERO)
