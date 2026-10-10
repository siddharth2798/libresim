class_name Trees
extends Node3D
## Forests from the land-class mask (tools/11_landclass.py, 1..200 = tree density).
## The world is split into CHUNK-metre cells; cells within RADIUS of the camera get
## a MultiMesh of crossed-quad trees, placed deterministically (same trees every time).
## Generation runs on the main thread with a per-frame budget (it reads the terrain
## height cache, which is not thread-safe). Hidden above HIDE_AGL.

const CHUNK := 480.0
const RADIUS := 2200.0
const HIDE_AGL := 1500.0
const PX := 10.0  # land-class pixel size (m)
const BUDGET := 2  # chunks generated per frame

@export var density_scale := 1.0  # graphics presets scale this

var terrain: TerrainQuadtree
var _chunks := {}  # Vector2i -> MultiMeshInstance3D (or null = mask not loaded yet)
var _queue: Array[Vector2i] = []
var _mesh: ArrayMesh
var _mat := ShaderMaterial.new()
var _timer := 0.0


func _ready() -> void:
	_mat.shader = preload("res://world/tree.gdshader")
	_mesh = _crossed_quads()
	FloatingOrigin.shifted.connect(func(_d): _reposition())


static func _crossed_quads() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 2:
		var a := Vector3(0.5, 0, 0) if k == 0 else Vector3(0, 0, 0.5)
		var v := [-a, a, a + Vector3.UP, -a + Vector3.UP]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_uv(uv[i])
			st.set_normal(Vector3.UP)
			st.add_vertex(v[i])
	return st.commit()


func _process(dt: float) -> void:
	visible = Props.get_f("fdm/agl_m", 0.0) < HIDE_AGL or not Props.has("fdm/agl_m")
	if terrain == null or not visible:
		return
	for i in BUDGET:
		if _queue.is_empty():
			break
		var k: Vector2i = _queue.pop_front()
		if _chunks.has(k) and _chunks[k] == null:
			_build(k)
	_timer -= dt
	if _timer > 0.0:
		return
	_timer = 0.4
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var w := FloatingOrigin.to_world(cam.global_position)
	var c := Vector2i(floori(w.x / CHUNK), floori(w.y / CHUNK))
	var r := int(ceil(RADIUS / CHUNK))
	var want := {}
	for j in range(-r, r + 1):
		for i in range(-r, r + 1):
			var k := c + Vector2i(i, j)
			if Vector2(w.x, w.y).distance_to((Vector2(k) + Vector2(0.5, 0.5)) * CHUNK) < RADIUS + CHUNK * 0.7:
				want[k] = true
				if not _chunks.has(k):
					_chunks[k] = null
					_queue.append(k)
	for k in _chunks.keys():
		if not want.has(k):
			if _chunks[k] != null:
				_chunks[k].queue_free()
			_chunks.erase(k)
	# nearest chunks first
	_queue.sort_custom(func(a, b): return (Vector2(a) * CHUNK).distance_to(Vector2(w.x, w.y)) < (Vector2(b) * CHUNK).distance_to(Vector2(w.x, w.y)))


func _hash(x: int, y: int, k: int) -> float:
	return float(posmod((x * 73856093) ^ (y * 19349663) ^ (k * 83492791), 100003)) / 100003.0


func _build(k: Vector2i) -> void:
	var cache := terrain.cache
	var x0 := k.x * CHUNK
	var y0 := k.y * CHUNK
	var n := int(CHUNK / PX)
	var xf: Array[Transform3D] = []
	var cd: Array[Color] = []
	for j in n:
		for i in n:
			var e := x0 + (i + 0.5) * PX
			var no := y0 + (j + 0.5) * PX
			var lc := cache.landclass_at(e, no)
			if lc < 0:
				_queue.append(k)  # mask not loaded yet: retry later
				return
			if lc == 0 or lc == 255:
				continue
			var gi := int(e / PX)
			var gj := int(no / PX)
			if _hash(gi, gj, 1) > lc / 200.0 * 0.8 * density_scale:
				continue
			var px := e + (_hash(gi, gj, 2) - 0.5) * PX * 0.8
			var py := no + (_hash(gi, gj, 3) - 0.5) * PX * 0.8
			var h := cache.height_at(px, py)
			var height := lerpf(6.0, 15.0, _hash(gi, gj, 4))
			var width := height * lerpf(0.55, 0.85, _hash(gi, gj, 5))
			var b := Basis(Vector3.UP, _hash(gi, gj, 6) * TAU).scaled(Vector3(width, height, width))
			xf.append(Transform3D(b, Vector3(px - x0, h - 0.3, -(py - y0))))
			cd.append(Color(_hash(gi, gj, 7), _hash(gi, gj, 8), _hash(gi, gj, 9), _hash(gi, gj, 10)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_custom_data(i, cd[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("chunk", k)
	add_child(mi)
	_chunks[k] = mi
	_place(mi, k)


func _place(mi: Node3D, k: Vector2i) -> void:
	mi.position = FloatingOrigin.to_render(Vector3(k.x * CHUNK, k.y * CHUNK, 0.0))


func _reposition() -> void:
	for k in _chunks:
		if _chunks[k] != null:
			_place(_chunks[k], k)
