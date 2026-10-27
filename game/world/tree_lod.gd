class_name TreeLod
extends Node3D
## LOD0 trees: real low-poly meshes (TreeMeshes, tree_mesh.gdshader) for the trees within `radius`
## metres of the camera, which cast and receive sun shadows. Beyond that the billboards of Trees draw
## the same trees (same TreeSampler.cell_tree / TreeSpecies rules, same tint and yaw), and the swap is
## a dither over lod_band metres: `covered` tells Trees how far the built cells reach, so a tree is
## never dropped from both. Cells of CELL metres are built on the main thread, one per frame, from
## the same land-class and height lookups as the collisions. Off when the camera is above HIDE_AGL and on the Low preset
## (radius 0).

const CELL := 80.0
const PX := 10.0
const HIDE_AGL := 450.0
const MAX_TRIES := 3  # a cell whose land-class mask never loads is given up as empty

var terrain: TerrainQuadtree
var radius := 130.0  # graphics presets
var density_scale := 1.0
var covered := 0.0  # metres around the camera whose trees all exist as meshes

var _meshes: Array[ArrayMesh] = []
var _mat := ShaderMaterial.new()
var _cells := {}  # Vector2i -> Array of MultiMeshInstance3D (empty: no trees there)
var _tries := {}
var _queue: Array[Vector2i] = []
var _timer := 0.0
var _cam_w := Vector2.ZERO
var _low_enough := true  # the camera is below HIDE_AGL above the ground


func _ready() -> void:
	_mat.shader = preload("res://world/tree_mesh.gdshader")
	for sp in TreeSpecies.COUNT:
		_meshes.append(TreeMeshes.build(sp))
	FloatingOrigin.shifted.connect(func(_d): _reposition())


func _process(dt: float) -> void:
	if terrain == null or radius <= 0.0 or not _low_enough:
		if not _cells.is_empty():
			clear()
		covered = 0.0
		_mat.set_shader_parameter("lod_r", 0.0)
		if terrain == null or radius <= 0.0:
			return
	if not _queue.is_empty():
		var k: Vector2i = _queue.pop_front()
		if not _cells.has(k) and not _build_cell(k):
			_tries[k] = _tries.get(k, 0) + 1
			if _tries[k] >= MAX_TRIES:
				_cells[k] = []
	_timer -= dt
	if _timer > 0.0:
		return
	_timer = 0.2
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var w := FloatingOrigin.to_world(cam.global_position)
	_cam_w = Vector2(w.x, w.y)
	_low_enough = w.z - terrain.cache.height_at(w.x, w.y) < HIDE_AGL
	if not _low_enough:
		return
	_refresh()
	_mat.set_shader_parameter("lod_r", covered)


## Drop every cell (the preset or altitude says LOD0 is off).
func clear() -> void:
	for k in _cells:
		for mi in _cells[k]:
			mi.queue_free()
	_cells.clear()
	_queue.clear()
	_tries.clear()


func _refresh() -> void:
	var r := int(ceil((radius + CELL) / CELL))
	var c := Vector2i(floori(_cam_w.x / CELL), floori(_cam_w.y / CELL))
	var reach := radius
	var want := {}
	for j in range(-r, r + 1):
		for i in range(-r, r + 1):
			var k := c + Vector2i(i, j)
			var d := _cam_w.distance_to((Vector2(k) + Vector2(0.5, 0.5)) * CELL) - CELL * 0.71
			if d < radius:
				want[k] = true
				if not _cells.has(k):
					reach = minf(reach, maxf(d, 0.0))
					if not _queue.has(k):
						_queue.append(k)
	for k in _cells.keys():
		if not want.has(k) and _cam_w.distance_to((Vector2(k) + Vector2(0.5, 0.5)) * CELL) > radius + CELL * 1.6:
			for mi in _cells[k]:
				mi.queue_free()
			_cells.erase(k)
	_queue = _queue.filter(func(k): return want.has(k))
	_queue.sort_custom(func(a, b): return (Vector2(a) * CELL).distance_to(_cam_w) < (Vector2(b) * CELL).distance_to(_cam_w))
	covered = reach


func _build_cell(k: Vector2i) -> bool:
	var n := int(CELL / PX)
	var ci0 := floori(k.x * CELL / PX)
	var cj0 := floori(k.y * CELL / PX)
	var bufs: Array[PackedFloat32Array] = []
	bufs.resize(TreeSpecies.COUNT)
	for j in n:
		for i in n:
			var ci := ci0 + i
			var cj := cj0 + j
			var lc := terrain.cache.landclass_at((ci + 0.5) * PX, (cj + 0.5) * PX)
			if lc < 0:
				return false  # land-class mask still loading
			var t := TreeSampler.cell_tree(ci, cj, lc, PX, density_scale)
			if t.is_empty():
				continue
			var g := terrain.cache.height_at(t[0], t[1])
			var sh := TreeSpecies.shape(ci, cj, t[1], g)
			var b := Basis(Vector3.UP, TreeSampler.hash3(ci, cj, 6) * TAU).scaled(Vector3(sh[3], sh[2], sh[3]))
			bufs[int(sh[0])].append_array([b.x.x, b.y.x, b.z.x, t[0] - k.x * CELL,
				b.x.y, b.y.y, b.z.y, g - 0.3,
				b.x.z, b.y.z, b.z.z, -(t[1] - k.y * CELL),
				TreeSampler.hash3(ci, cj, 7), sh[0] * TreeSpecies.VARIANTS + sh[1], TreeSampler.hash3(ci, cj, 9), TreeSampler.hash3(ci, cj, 10)])
	var made := []
	for sp in TreeSpecies.COUNT:
		if bufs[sp].is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = _meshes[sp]
		mm.instance_count = bufs[sp].size() / 16
		mm.buffer = bufs[sp]
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.set_meta("cell", k)
		add_child(mi)
		_place(mi, k)
		made.append(mi)
	_cells[k] = made
	return true


func instance_count() -> int:
	var total := 0
	for k in _cells:
		for mi in _cells[k]:
			total += mi.multimesh.instance_count
	return total


func _place(mi: Node3D, k: Vector2i) -> void:
	mi.position = FloatingOrigin.to_render(Vector3(k.x * CELL, k.y * CELL, 0.0))


func _reposition() -> void:
	for k in _cells:
		for mi in _cells[k]:
			_place(mi, k)
