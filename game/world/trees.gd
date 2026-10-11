class_name Trees
extends Node3D
## Forests from the land-class mask (tools/11_landclass.py, 1..200 = tree density).
## The world is split into CHUNK-metre cells; cells within radius of the camera get
## a MultiMesh of crossed-quad trees, placed deterministically (same trees every time).
## Generation runs on worker threads (TreeSampler reads the data files itself); the main
## thread only uploads finished buffers, BUDGET per frame. Hidden above HIDE_AGL.

const CHUNK := 480.0
var radius := 2200.0  # graphics presets
const HIDE_AGL := 1500.0
const PX := 10.0  # land-class pixel size (m)
const BUDGET := 2  # finished chunks turned into MultiMeshes per frame
const MAX_IN_FLIGHT := 4  # chunks generating on worker threads

@export var density_scale := 1.0  # graphics presets scale this

var terrain: TerrainQuadtree
var _chunks := {}  # Vector2i -> MultiMeshInstance3D (or null = mask not loaded yet)
var _queue: Array[Vector2i] = []
var _mesh: ArrayMesh
var _mat := ShaderMaterial.new()
var _timer := 0.0
var _sampler: TreeSampler
var _mutex := Mutex.new()
var _done: Array = []  # [chunk key, PackedFloat32Array] from workers
var _in_flight := 0
var _flying := {}  # chunk key -> WorkerThreadPool task id while generating


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
	_mutex.lock()
	var done := _done.slice(0, BUDGET)
	_done = _done.slice(BUDGET)
	_mutex.unlock()
	for d in done:
		_in_flight -= 1
		WorkerThreadPool.wait_for_task_completion(_flying[d[0]])  # finished: just releases it
		_flying.erase(d[0])
		_finish_chunk(d[0], d[1])
	while _in_flight < MAX_IN_FLIGHT and not _queue.is_empty():
		var k: Vector2i = _queue.pop_front()
		if _chunks.has(k) and _chunks[k] == null and not _flying.has(k):
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
	var r := int(ceil(radius / CHUNK))
	var want := {}
	for j in range(-r, r + 1):
		for i in range(-r, r + 1):
			var k := c + Vector2i(i, j)
			if Vector2(w.x, w.y).distance_to((Vector2(k) + Vector2(0.5, 0.5)) * CHUNK) < radius + CHUNK * 0.7:
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
	return TreeSampler.hash3(x, y, k)


## Main thread: look up the chunk's land-class source tile, then generate on a worker.
func _build(k: Vector2i) -> void:
	if _sampler == null:
		_sampler = TreeSampler.new(terrain.cache)
	var tm := terrain.cache.tmeta
	var src := tm.tex_source(0, floori(k.x * CHUNK / tm.tile_size_m), floori(k.y * CHUNK / tm.tile_size_m), TerrainMeta.HAS_LC)
	if src == TerrainMeta.NONE:
		_finish_chunk(k, PackedFloat32Array())
		return
	_in_flight += 1
	_flying[k] = WorkerThreadPool.add_task(_work.bind(k, src, tm.level_size(src.x), density_scale))


## Worker thread.
func _work(k: Vector2i, src: Vector3i, src_size: float, density: float) -> void:
	var buf := _sampler.build(k.x * CHUNK, k.y * CHUNK, CHUNK, PX, src, src_size, density)
	_mutex.lock()
	_done.append([k, buf])
	_mutex.unlock()


## Every WorkerThreadPool task must be waited for; never free the node under a running task.
func _exit_tree() -> void:
	for id in _flying.values():
		WorkerThreadPool.wait_for_task_completion(id)
	_flying.clear()


## Main thread: turn a finished worker buffer into a MultiMeshInstance3D (one buffer upload).
func _finish_chunk(k: Vector2i, buf: PackedFloat32Array) -> void:
	if not _chunks.has(k) or _chunks[k] != null:
		return  # dropped (out of range) while generating
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _mesh
	mm.instance_count = buf.size() / 16
	if buf.size() > 0:
		mm.buffer = buf
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


## Top of the tree canopy (m AMSL) at world (east, north) if a tree stands there, else -INF.
## Mirrors _build's placement (same hashes), using the canopy radius.
func tree_top_at(east: float, north: float) -> float:
	if terrain == null:
		return -INF
	var gi0 := int(east / PX)
	var gj0 := int(north / PX)
	for dj in [-1, 0, 1]:
		for di in [-1, 0, 1]:
			var gi: int = gi0 + di
			var gj: int = gj0 + dj
			var e := (gi + 0.5) * PX
			var n := (gj + 0.5) * PX
			var lc := terrain.cache.landclass_at(e, n)
			if lc <= 0 or lc == 255 or _hash(gi, gj, 1) > lc / 200.0 * 0.8 * density_scale:
				continue
			var px := e + (_hash(gi, gj, 2) - 0.5) * PX * 0.8
			var py := n + (_hash(gi, gj, 3) - 0.5) * PX * 0.8
			var height := lerpf(6.0, 15.0, _hash(gi, gj, 4))
			var radius := height * lerpf(0.55, 0.85, _hash(gi, gj, 5)) * 0.4
			if Vector2(px, py).distance_to(Vector2(east, north)) < radius:
				return terrain.cache.height_at(px, py) + height * 0.9
	return -INF
