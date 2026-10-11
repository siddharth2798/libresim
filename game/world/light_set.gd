class_name LightSet
extends RefCounted
## A batch of light points for one MultiMesh (one material group of one airport).
## Positions are ENU metres relative to the airport anchor; the per-instance layout
## is what world/light_point.gdshaderinc reads (COLOR, CUSTOM). Built straight into
## the MultiMesh buffer: 12 floats transform + 4 colour + 4 custom per instance.

const STRIDE := 20

var anchor := Vector2.ZERO  # ENU (east, north) of the airport anchor
var buf := PackedFloat32Array()
var count := 0


func _init(anchor_enu := Vector2.ZERO) -> void:
	anchor = anchor_enu


## Add a light at ENU (e, n), height h. dir = beam direction (ENU, east/north; zero =
## omnidirectional), lobe = beam exponent (higher = narrower), spill = off-beam fraction,
## bidir = beam both ways along dir, mode = flash/PAPI code (see the shader), size = scale.
func add(e: float, n: float, h: float, col: Color, dir := Vector2.ZERO, lobe := 4.0,
		spill := 0.0, bidir := false, mode := 0.0, size := 1.0) -> void:
	var x := e - anchor.x
	var z := -(n - anchor.y)
	var lz := 0.0
	if dir != Vector2.ZERO:
		dir = dir.normalized()
		lz = (floorf(maxf(lobe, 1.0)) + clampf(spill, 0.0, 0.99)) * (-1.0 if bidir else 1.0)
	buf.append_array([1.0, 0.0, 0.0, x, 0.0, 1.0, 0.0, h, 0.0, 0.0, 1.0, z,
		col.r, col.g, col.b, size, dir.x, -dir.y, lz, mode])
	count += 1


## ENU position (east, north, up) of instance i.
func pos(i: int) -> Vector3:
	var o := i * STRIDE
	return Vector3(buf[o + 3] + anchor.x, -buf[o + 11] + anchor.y, buf[o + 7])


func color(i: int) -> Color:
	var o := i * STRIDE + 12
	return Color(buf[o], buf[o + 1], buf[o + 2])


## Beam direction (ENU) of instance i; zero for omnidirectional lights.
func beam(i: int) -> Vector2:
	var o := i * STRIDE + 16
	return Vector2(buf[o], -buf[o + 1])


func mode(i: int) -> float:
	return buf[i * STRIDE + 19]


## A MultiMeshInstance3D drawing these lights with the given material (null if empty).
func make_instance(mat: Material, name: String) -> MultiMeshInstance3D:
	if count == 0:
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = count
	mm.buffer = buf
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for i in count:
		var o := i * STRIDE
		var p := Vector3(buf[o + 3], buf[o + 7], buf[o + 11])
		lo = lo.min(p)
		hi = hi.max(p)
	var mi := MultiMeshInstance3D.new()
	mi.name = name
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(lo, hi - lo).grow(80.0)  # quads are expanded in the shader
	return mi
