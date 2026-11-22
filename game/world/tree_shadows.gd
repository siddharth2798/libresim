class_name TreeShadows
extends Node
## Real sun shadows for the impostor trees (which cast none) on High and up (docs/GRAPHICS-PLAN.md G8): each impostor
## chunk of Trees within `radius` gets a child MultiMesh with the same instance buffer and a 28-triangle opaque proxy
## (an icosahedron crown on a 4-sided trunk; tree_shadow.gdshader shapes the crown per species), drawn in the shadow
## pass only. Opaque proxies skip the alpha test that made the old impostor shadows cost +9-10 ms at Ultra. Trees within
## the near-mesh radius (they cast their own) and beyond `radius` collapse to nothing in the vertex shader, so the
## shadows fade in and out per tree; chunks are only the unit of work. Being children of the chunk, proxies move with it
## at a floating-origin shift. Beyond `radius` the terrain canopy shade takes over (canopy_start).

const PROXY := "ShadowProxy"

var trees: Node  # Trees
var radius := 0.0:  # m, 0 = off (Low, Medium)
	set(v):
		radius = v
		_mat.set_shader_parameter("shadow_r", v)
var lod_r := 0.0:
	set(v):
		lod_r = v
		_mat.set_shader_parameter("lod_r", v)

var _mat := ShaderMaterial.new()
var _mesh: ArrayMesh
var _timer := 0.0


func _ready() -> void:
	_mat.shader = preload("res://world/tree_shadow.gdshader")
	_mat.set_shader_parameter("variant_n", float(TreeSpecies.VARIANTS))
	_mesh = proxy_mesh()


func _process(dt: float) -> void:
	_timer -= dt
	if _timer > 0.0 or trees == null:
		return
	_timer = 0.5
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var w := FloatingOrigin.to_world(cam.global_position)
	for k in trees._chunks:
		var mi = trees._chunks[k]
		if mi == null:
			continue
		var has := (mi as Node).has_node(PROXY)
		var want := radius > 0.0 and in_range(Vector2(w.x, w.y), k, radius)
		if want and not has:
			_add(mi)
		elif has and not want:
			mi.get_node(PROXY).queue_free()


## True if any of chunk k (Trees.CHUNK metres) is within r of world point w.
static func in_range(w: Vector2, k: Vector2i, r: float) -> bool:
	var lo := Vector2(k) * Trees.CHUNK
	return w.distance_to(w.clamp(lo, lo + Vector2(Trees.CHUNK, Trees.CHUNK))) < r


func _add(mi: MultiMeshInstance3D) -> void:
	if mi.multimesh.instance_count == 0:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _mesh
	mm.instance_count = mi.multimesh.instance_count
	mm.buffer = mi.multimesh.buffer
	var p := MultiMeshInstance3D.new()
	p.name = PROXY
	p.multimesh = mm
	p.material_override = _mat
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	mi.add_child(p)


## Unit-tree proxy: trunk prism (UV.x 0) and an icosahedron crown (UV.x 1, unit radius around the origin; the shader
## moves it to the species' crown centre and size).
static func proxy_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := 0.025
	var ring := [Vector3(r, 0, 0), Vector3(0, 0, r), Vector3(-r, 0, 0), Vector3(0, 0, -r)]
	for k in 4:
		var a: Vector3 = ring[k]
		var b: Vector3 = ring[(k + 1) % 4]
		for p in [a, b + Vector3(0, 0.5, 0), b, a, a + Vector3(0, 0.5, 0), b + Vector3(0, 0.5, 0)]:
			st.set_uv(Vector2.ZERO)
			st.add_vertex(p)
	var t := (1.0 + sqrt(5.0)) * 0.5
	var v := [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
		Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var f := [0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1]
	for i in f:
		st.set_uv(Vector2(1, 0))
		st.add_vertex((v[i] as Vector3).normalized())
	var m := st.commit()
	m.custom_aabb = AABB(Vector3(-1.0, -0.1, -1.0), Vector3(2.0, 1.3, 2.0))
	return m
