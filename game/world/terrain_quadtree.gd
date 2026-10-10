class_name TerrainQuadtree
extends Node3D
## Chunked-LOD terrain. Quadtree roots are the coarsest data tiles; nodes split
## while the camera is closer than size * lod_k. Levels below 0 are "virtual":
## they reuse a level-0 tile's textures on a sub-rectangle so the finest node
## (MIN_LEVEL) reaches the DEM's native 30 m vertex spacing.
## A node only splits once all its children's textures are loaded (no holes).

const MIN_LEVEL := -2
const SKIRT_FRAC := 0.004
const MAX_VIRTUAL := 2

@export var lod_k := 1.6
@export var camera_path: NodePath

var cache: TerrainTileCache
var _mesh: ArrayMesh
var _shader := preload("res://world/terrain.gdshader")
var _active := {}  # Vector3i -> MeshInstance3D
var _pool: Array[MeshInstance3D] = []
var _cam_enu := Vector3.ZERO
var visible_nodes := 0


func _ready() -> void:
	cache = TerrainTileCache.new()
	_mesh = TerrainMesh.build()


func height_at(east: float, north: float) -> float:
	return cache.height_at(east, north)


func _process(_dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_cam_enu = FloatingOrigin.to_world(cam.global_position)
	cache.process()
	var top := cache.levels.size() - 1
	var wanted: Array[Vector3i] = []
	for key in cache.levels[top].tiles:
		var p: PackedStringArray = key.split("_")
		_select(top, int(p[0]), int(p[1]), wanted)
	_apply(wanted)


## The data tile a node draws from: itself if it exists, else the nearest
## ancestor (virtual levels below 0, or nodes past the data edge).
func _source(level: int, tx: int, ty: int) -> Vector3i:
	for l in range(maxi(level, 0), cache.levels.size()):
		var d := 1 << (l - level)
		var s := Vector3i(l, floori(float(tx) / d), floori(float(ty) / d))
		if cache.has_tile(s.x, s.y, s.z):
			return s
	return Vector3i(cache.levels.size() - 1, 0, 0)


func _ready_tile(level: int, tx: int, ty: int) -> bool:
	var s := _source(level, tx, ty)
	return not cache.get_tile(s.x, s.y, s.z).is_empty()


func _select(level: int, tx: int, ty: int, out: Array[Vector3i]) -> void:
	if not _ready_tile(level, tx, ty):
		return
	var size := cache.level_size(level)
	var s := _source(level, tx, ty)
	var mm := cache.min_max(s.x, s.y, s.z)
	var x0 := tx * size
	var y0 := ty * size
	var dx := maxf(maxf(x0 - _cam_enu.x, _cam_enu.x - (x0 + size)), 0.0)
	var dy := maxf(maxf(y0 - _cam_enu.y, _cam_enu.y - (y0 + size)), 0.0)
	var dz := maxf(maxf(mm.x - _cam_enu.z, _cam_enu.z - mm.y), 0.0)
	var dist := sqrt(dx * dx + dy * dy + dz * dz)
	# Stop at MAX_VIRTUAL levels below the data tile (native resolution for level 0).
	if level > MIN_LEVEL and s.x - level < MAX_VIRTUAL and dist < size * lod_k:
		var children: Array[Vector3i] = []
		var ok := true
		for c in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			var k := Vector3i(level - 1, tx * 2 + c.x, ty * 2 + c.y)
			children.append(k)
			ok = _ready_tile(k.x, k.y, k.z) and ok  # request all, even after a miss
		if ok:
			for k in children:
				_select(k.x, k.y, k.z, out)
			return
	out.append(Vector3i(level, tx, ty))


func _apply(wanted: Array[Vector3i]) -> void:
	var keep := {}
	for k in wanted:
		keep[k] = true
	for k in _active.keys():
		if not keep.has(k):
			var mi: MeshInstance3D = _active[k]
			mi.visible = false
			_pool.append(mi)
			_active.erase(k)
	for k in wanted:
		var mi: MeshInstance3D = _active.get(k)
		if mi == null:
			mi = _make_instance(k)
			_active[k] = mi
		var size := cache.level_size(k.x)
		mi.position = FloatingOrigin.to_render(Vector3(k.y * size, k.z * size, 0.0))
	visible_nodes = wanted.size()


func _make_instance(k: Vector3i) -> MeshInstance3D:
	var mi: MeshInstance3D
	if _pool.is_empty():
		mi = MeshInstance3D.new()
		mi.mesh = _mesh
		mi.material_override = ShaderMaterial.new()
		mi.material_override.shader = _shader
		add_child(mi)
	else:
		mi = _pool.pop_back()
	mi.visible = true
	var level := k.x
	var size := cache.level_size(level)
	var s := _source(level, k.y, k.z)
	var t: Dictionary = cache.get_tile(s.x, s.y, s.z)
	var d := s.x - level  # how many virtual levels below the source tile
	var span := 1 << d
	var sub := Vector2i(k.y - s.y * span, k.z - s.z * span)
	var per := cache.tile_n / span  # source texels covered by this node
	var mm := cache.min_max(s.x, s.y, s.z)
	var skirt := maxf(size * SKIRT_FRAC, 10.0)
	var m: ShaderMaterial = mi.material_override
	m.set_shader_parameter("height_tex", t.htex)
	m.set_shader_parameter("img_tex", t.itex)
	m.set_shader_parameter("texel_off", sub * per)
	m.set_shader_parameter("texel_step", per / TerrainMesh.GRID)
	m.set_shader_parameter("tile_size", size)
	m.set_shader_parameter("img_scale", 1.0 / span)
	m.set_shader_parameter("img_off", Vector2(float(sub.x) / span, 1.0 - float(sub.y) / span))
	m.set_shader_parameter("h_scale", cache.h_scale)
	m.set_shader_parameter("h_offset", cache.h_offset)
	m.set_shader_parameter("tile_n", float(cache.tile_n))
	m.set_shader_parameter("skirt_depth", skirt)
	mi.custom_aabb = AABB(Vector3(0, mm.x - skirt, -size), Vector3(size, mm.y - mm.x + skirt, size))
	return mi
