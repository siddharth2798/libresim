class_name Buildings
extends Node3D
## Streams 3D OSM buildings (data/processed/buildings/<tx>_<ty>.bin, tools/10_buildings.py)
## for the level-0 terrain tiles within radius of the camera. Meshes are built on
## worker threads straight from the file bytes (no per-vertex script loops).
## Hidden above HIDE_AGL to save GPU when flying high (they'd be sub-pixel anyway).

var radius := 9000.0  # graphics presets
const HIDE_AGL := 2500.0
const MAX_LOADS := 2  # tiles finished per frame

var _tiles := {}  # Vector2i -> MeshInstance3D (or null while loading)
var _done: Array = []
var _mutex := Mutex.new()
var _mat := ShaderMaterial.new()
var _timer := 0.0
var _dir := ""
const CELL := 64.0
var _col := {}  # Vector2i tile -> {"cells": {Vector2i: [idx...]}, "polys": [PackedVector2Array], "base": [], "top": []}


func _ready() -> void:
	_mat.shader = preload("res://world/building.gdshader")
	_dir = Paths.data("buildings")
	FloatingOrigin.shifted.connect(func(_d): _reposition())


func _process(dt: float) -> void:
	_mutex.lock()
	var batch := _done.slice(0, MAX_LOADS)
	_done = _done.slice(MAX_LOADS)
	_mutex.unlock()
	for item in batch:
		_add(item[0], item[1])
		if not item[2].is_empty():
			_col[item[0]] = item[2]
	_mat.set_shader_parameter("night", clampf((2.0 - Props.get_f("environment/sun_elev_deg", 30.0)) / 8.0, 0.0, 1.0))
	visible = Props.get_f("fdm/agl_m", 0.0) < HIDE_AGL or not Props.has("fdm/agl_m")
	_timer -= dt
	if _timer > 0.0:
		return
	_timer = 0.5
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var w := FloatingOrigin.to_world(cam.global_position)
	var s := TerrainTileCache.TILE_SIZE_DEFAULT
	var want := {}
	var r := int(ceil(radius / s))
	var c := Vector2i(floori(w.x / s), floori(w.y / s))
	for j in range(-r, r + 1):
		for i in range(-r, r + 1):
			var k := c + Vector2i(i, j)
			var d := Vector2(w.x, w.y).distance_to(Vector2((k.x + 0.5) * s, (k.y + 0.5) * s)) - s * 0.71
			if d < radius:
				want[k] = true
	for k in want:
		if not _tiles.has(k) and FileAccess.file_exists(_path(k)):
			_tiles[k] = null
			WorkerThreadPool.add_task(_load.bind(k))
	for k in _tiles.keys():
		if not want.has(k) and _tiles[k] != null:
			_col.erase(k)
			_tiles[k].queue_free()
			_tiles.erase(k)


func _path(k: Vector2i) -> String:
	return _dir.path_join("%d_%d.bin" % [k.x, k.y])


func _load(k: Vector2i) -> void:
	var raw := FileAccess.get_file_as_bytes(_path(k))
	var b := raw.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	if b.size() < 12 or b.slice(0, 4).get_string_from_ascii() != "BLD1":
		return
	var nv := b.decode_u32(4)
	var ni := b.decode_u32(8)
	var o := 12
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = b.slice(o, o + nv * 12).to_vector3_array()
	o += nv * 12
	arrays[Mesh.ARRAY_CUSTOM0] = b.slice(o, o + nv * 4)
	o += nv * 4
	arrays[Mesh.ARRAY_INDEX] = b.slice(o, o + ni * 4).to_int32_array()
	var mesh := ArrayMesh.new()
	var fmt := Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
	var col := _load_collision(k)
	_mutex.lock()
	_done.append([k, mesh, col])
	_mutex.unlock()


func _load_collision(k: Vector2i) -> Dictionary:
	var p := _dir.path_join("%d_%d.col" % [k.x, k.y])
	if not FileAccess.file_exists(p):
		return {}
	var b := FileAccess.get_file_as_bytes(p).decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	if b.size() < 8 or b.slice(0, 4).get_string_from_ascii() != "COL1":
		return {}
	var count := b.decode_u32(4)
	var o := 8
	var polys: Array = []
	var base := PackedFloat32Array()
	var top := PackedFloat32Array()
	var cells := {}
	for i in count:
		var n := b.decode_u16(o)
		base.append(b.decode_float(o + 2))
		top.append(b.decode_float(o + 6))
		var pts := b.slice(o + 10, o + 10 + n * 8).to_vector2_array()
		o += 10 + n * 8
		polys.append(pts)
		var lo := pts[0]
		var hi := pts[0]
		for q in pts:
			lo = lo.min(q)
			hi = hi.max(q)
		for cy in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
			for cx in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
				var key := Vector2i(cx, cy)
				if not cells.has(key):
					cells[key] = []
				cells[key].append(i)
	return {"cells": cells, "polys": polys, "base": base, "top": top}


## Roof height (m AMSL) of the building containing world (east, north), else -INF.
func building_top_at(east: float, north: float) -> float:
	var s := TerrainTileCache.TILE_SIZE_DEFAULT
	var t: Dictionary = _col.get(Vector2i(floori(east / s), floori(north / s)), {})
	if t.is_empty():
		return -INF
	var ids: Array = t.cells.get(Vector2i(floori(east / CELL), floori(north / CELL)), [])
	var p := Vector2(east, north)
	for i in ids:
		if Geometry2D.is_point_in_polygon(p, t.polys[i]):
			return t.top[i]
	return -INF


func _add(k: Vector2i, mesh: ArrayMesh) -> void:
	if not _tiles.has(k):
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.set_meta("tile", k)
	add_child(mi)
	_tiles[k] = mi
	_place(mi, k)


func _place(mi: MeshInstance3D, k: Vector2i) -> void:
	var s := TerrainTileCache.TILE_SIZE_DEFAULT
	var p := FloatingOrigin.to_render(Vector3(k.x * s, k.y * s, 0.0))
	mi.position = p


func _reposition() -> void:
	for k in _tiles:
		if _tiles[k] != null:
			_place(_tiles[k], k)
