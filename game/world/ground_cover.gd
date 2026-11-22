class_name GroundCover
extends Node3D
## Grass, ferns and bushes near the camera (docs/GRAPHICS-PLAN.md G8). The world is split into CELL-metre cells; cells
## within `radius` of the camera get one MultiMesh per kind (GroundCoverMeshes) with a plant on each grid point of
## `step` metres that GroundCoverRules picks from the WorldCover class and land class, skipping roads and rivers
## (GroundRoads), paved ground (runway and taxiway ribbons and the apron mask, GroundSurface; TreeClear) and water. Cells are placed in world (ENU) terms and
## moved with the floating origin, instance transforms are relative to the cell, and the sway phase comes from each
## plant's seed, so nothing moves or swims at an origin shift. One cell is built per frame on the main thread
## (step 1.6 m: 225 grid points). Plants shrink away between 0.45 and 1.0 x radius (no pop) and the layer is off when
## the camera is higher than OFF_AGL. radius / step per preset (TreeQuality): Low none, Medium 18 m, High and up 40-65 m.

const CELL := 24.0
const OFF_AGL := 120.0
const MAX_TRIES := 6  # a cell whose masks never load is given up as empty

var terrain: TerrainQuadtree
var radius := 0.0:  # m, 0 = off
	set(v):
		radius = v
		_mat.set_shader_parameter("cover_r", v)
var step := 1.6:  # m between grid points
	set(v):
		if v != step:
			step = v
			clear()
var season_dry := 0.0:
	set(v):
		season_dry = v
		_mat.set_shader_parameter("season_dry", v)

var surface := GroundSurface.new()
var roads := GroundRoads.new()
var _mat := ShaderMaterial.new()
var _cells := {}  # Vector2i -> Array of MultiMeshInstance3D
var _tries := {}
var _queue: Array[Vector2i] = []
var _timer := 0.0
var _cam_w := Vector2.ZERO
var _wait_pv := false  # the last cell waited for its apron-mask tile (not a failed try)


func _ready() -> void:
	_mat.shader = preload("res://world/ground_cover.gdshader")
	_mat.set_shader_parameter("leaf_tex", preload("res://world/textures/trees/leaf_cards.png"))
	_mat.set_shader_parameter("cover_r", radius)
	var rw = Paths.load_json("runways.json")
	if rw is Dictionary:
		surface.setup(rw)
	elif rw is Array:
		surface.setup({"runways": rw})
	FloatingOrigin.shifted.connect(func(_d): _reposition())


func _exit_tree() -> void:
	surface.finish()
	roads.finish()


func _process(dt: float) -> void:
	if terrain == null or radius <= 0.0:
		if not _cells.is_empty():
			clear()
		return
	if not _queue.is_empty():
		var k: Vector2i = _queue.pop_front()
		if not _cells.has(k) and not _build_cell(k):
			_tries[k] = _tries.get(k, 0) + (0 if _wait_pv else 1)
			if _tries[k] < MAX_TRIES:
				_queue.append(k)
			else:
				_cells[k] = []
	_timer -= dt
	if _timer > 0.0:
		return
	_timer = 0.25
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var w := FloatingOrigin.to_world(cam.global_position)
	_cam_w = Vector2(w.x, w.y)
	visible = w.z - terrain.cache.height_at(w.x, w.y) < OFF_AGL
	if not visible:
		return
	var want := wanted(_cam_w, radius)
	for k in want:
		if not _cells.has(k) and not _queue.has(k):
			_queue.append(k)
	for k in _cells.keys():
		if not want.has(k) and cell_distance(_cam_w, k) > radius + CELL:
			for mi in _cells[k]:
				mi.queue_free()
			_cells.erase(k)
	_queue = _queue.filter(func(k): return want.has(k))
	_queue.sort_custom(func(a, b): return cell_distance(_cam_w, a) < cell_distance(_cam_w, b))


## Cells (Vector2i -> true) with any point within r of world point w.
static func wanted(w: Vector2, r: float) -> Dictionary:
	var out := {}
	var c := Vector2i(floori(w.x / CELL), floori(w.y / CELL))
	var n := int(ceil(r / CELL)) + 1
	for j in range(-n, n + 1):
		for i in range(-n, n + 1):
			var k := c + Vector2i(i, j)
			if cell_distance(w, k) < r:
				out[k] = true
	return out


static func cell_distance(w: Vector2, k: Vector2i) -> float:
	var lo := Vector2(k) * CELL
	return w.distance_to(w.clamp(lo, lo + Vector2(CELL, CELL)))


func clear() -> void:
	for k in _cells:
		for mi in _cells[k]:
			mi.queue_free()
	_cells.clear()
	_tries.clear()
	_queue.clear()


## MultiMesh buffers (12 xform + 4 custom floats per plant, relative to the cell's SW corner) per kind; [] while a
## mask or the pavement tile under the cell is still loading.
func cell_buffers(k: Vector2i) -> Array:
	var cache := terrain.cache
	var tkey := Vector2i(floori((k.x + 0.5) * CELL / surface.tile_m), floori((k.y + 0.5) * CELL / surface.tile_m))
	surface.paved((k.x + 0.5) * CELL, (k.y + 0.5) * CELL)  # starts loading the apron mask of the tile
	_wait_pv = surface.fixed < 0 and not surface._tiles.has(tkey) and surface.near_runway((Vector2(k) + Vector2(0.5, 0.5)) * CELL)
	_wait_pv = _wait_pv or roads.on((k.x + 0.5) * CELL, (k.y + 0.5) * CELL) < 0  # road tile still decoding
	if _wait_pv:
		return []
	var b0 := PackedFloat32Array()  # one buffer per kind (packed arrays are values: no Array of them to append into)
	var b1 := PackedFloat32Array()
	var b2 := PackedFloat32Array()
	var n := int(round(CELL / step))
	var i0 := floori(k.x * CELL / step)
	var j0 := floori(k.y * CELL / step)
	for j in n:
		for i in n:
			var p := GroundCoverRules.point(i0 + i, j0 + j, step)
			var lc := cache.landclass_at(p.x, p.y)
			if lc < 0:
				return []
			var g := cache.height_at(p.x, p.y)
			var kind := GroundCoverRules.pick(i0 + i, j0 + j, lc, maxi(cache.worldcover_at(p.x, p.y), 0), g)
			if kind.x < 0 or TreeClear.blocked(p.x, p.y) or roads.on(p.x, p.y) != 0 or surface.paved(p.x, p.y):
				continue
			var h := GroundCoverRules.height(i0 + i, j0 + j, kind)
			var b := Basis(Vector3.UP, GroundCoverRules.hash3(i0 + i, j0 + j, 25) * TAU).scaled(Vector3(h, h, h))
			var rec := PackedFloat32Array([b.x.x, b.y.x, b.z.x, p.x - k.x * CELL,
				b.x.y, b.y.y, b.z.y, g - 0.05,
				b.x.z, b.y.z, b.z.z, -(p.y - k.y * CELL),
				GroundCoverRules.hash3(i0 + i, j0 + j, 26), float(kind.x), float(kind.y), GroundCoverRules.hash3(i0 + i, j0 + j, 27)])
			match kind.x:
				0:
					b0.append_array(rec)
				1:
					b1.append_array(rec)
				_:
					b2.append_array(rec)
	return [b0, b1, b2]


func _build_cell(k: Vector2i) -> bool:
	var bufs := cell_buffers(k)
	if bufs.is_empty():
		return false
	var made := []
	for m in GroundCoverRules.MESHES:
		var buf: PackedFloat32Array = bufs[m]
		if buf.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = GroundCoverMeshes.get_mesh(m)
		mm.instance_count = buf.size() / 16
		mm.buffer = buf
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = _mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
