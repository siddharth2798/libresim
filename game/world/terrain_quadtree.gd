class_name TerrainQuadtree
extends Node3D
## Chunked-LOD terrain. Quadtree roots are the coarsest data tiles; nodes split
## while the camera is closer than size * lod_k. Levels below 0 are "virtual":
## they reuse a level-0 tile's heights on a sub-rectangle so the finest node
## (MIN_LEVEL) reaches the DEM's native 30 m vertex spacing. Heights and textures
## have separate sources: a tile without imagery / land class (region packs)
## borrows its nearest ancestor's, so each node gets one sub-rect per source.
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
var _roots: Array[Vector3i] = []


func _ready() -> void:
	cache = TerrainTileCache.new()
	_mesh = TerrainMesh.build()
	_roots = cache.tmeta.roots()


func height_at(east: float, north: float) -> float:
	return cache.height_at(east, north)


func _process(_dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_cam_enu = FloatingOrigin.to_world(cam.global_position)
	cache.process()
	var wanted: Array[Vector3i] = []
	for r in _roots:
		_select(r.x, r.y, r.z, wanted)
	_apply(wanted)


## The data tile a node takes heights from: itself if it exists, else the nearest
## ancestor (virtual levels below 0, or nodes past the data edge).
func _source(level: int, tx: int, ty: int) -> Vector3i:
	var s := cache.tmeta.height_source(level, tx, ty)
	return s if s != TerrainMeta.NONE else _roots[0]


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
	var per := cache.tile_n / span  # source heightmap texels covered by this node
	var ir := TerrainMeta.sub_rect(k, t.img_src)  # imagery may come from a coarser tile
	var lr := TerrainMeta.sub_rect(k, t.lc_src)
	var mm := cache.min_max(s.x, s.y, s.z)
	var skirt := maxf(size * SKIRT_FRAC, 10.0)
	var m: ShaderMaterial = mi.material_override
	m.set_shader_parameter("height_tex", t.htex)
	m.set_shader_parameter("img_tex", t.itex)
	m.set_shader_parameter("lc_tex", t.lctex)
	m.set_shader_parameter("texel_off", sub * per)
	m.set_shader_parameter("texel_step", per / TerrainMesh.GRID)
	m.set_shader_parameter("tile_size", size)
	m.set_shader_parameter("img_scale", ir.z)
	m.set_shader_parameter("img_off", Vector2(ir.x, ir.y))
	m.set_shader_parameter("lc_scale", lr.z)
	m.set_shader_parameter("lc_off", Vector2(lr.x, lr.y))
	m.set_shader_parameter("h_scale", cache.h_scale)
	m.set_shader_parameter("h_offset", cache.h_offset)
	m.set_shader_parameter("tile_n", float(cache.tile_n))
	m.set_shader_parameter("skirt_depth", skirt)
	mi.custom_aabb = AABB(Vector3(0, mm.x - skirt, -size), Vector3(size, mm.y - mm.x + skirt, size))
	return mi
