class_name TerrainQuadtree
extends Node3D
## Chunked-LOD terrain. Quadtree roots are the coarsest data tiles; nodes split while the camera is closer than
## size * lod_k. Levels below 0 are "virtual": they reuse a level-0 tile's heights on a sub-rectangle so the finest node
## (MIN_LEVEL) reaches the DEM's 30 m spacing. Heights and textures have separate sources: a tile without imagery / land
## class borrows its nearest ancestor's, so each node gets one sub-rect per source. A node only splits once all its
## children's textures are loaded (no holes).
## Cost: node records are memoised per key; the tree is re-walked only when the camera moved > RESELECT_M, a tile finished
## uploading, or RESELECT_S passed. Anti-popping: split at d < size*lod_k, merge only at d > size*lod_k*HYSTERESIS; the shader
## geomorphs each node toward its parent over [MORPH_START, 1] x the parent's split distance.
## Focus (the aircraft): nodes within FOCUS_KEEP_M always split to MIN_LEVEL and never geomorph, so the ground under the
## tyres is the FDM's ground (TerrainTileCache.height_at) from any camera; ground_focus tells the overlays (ground_lift.gdshaderinc).

const MIN_LEVEL := -2
const SKIRT_FRAC := 0.004
const MAX_VIRTUAL := 2
const HYSTERESIS := 1.15
const RESELECT_M := 25.0
const RESELECT_S := 0.5
const MAX_RECS := 40000
const MORPH_START := 0.6  # x parent split distance; must be > HYSTERESIS / 2
const ROADS_NEAR_M := 3600.0  # nodes closer than this (horizontal) get the road / river tile (TerrainRoads)
const ROADS_EVERY_S := 0.25
const FOCUS_KEEP_M := 400.0  # horizontal; ground_lift.gdshaderinc fades its lift out inside this
const NO_MORPH := Vector2(1e12, 2e12)

@export var lod_k := 1.6
@export var camera_path: NodePath
var focus: Node3D  # the aircraft (set by the flight scene); null: no focus

var cache: TerrainTileCache
var roads := TerrainRoads.new()
var _mesh: ArrayMesh
var _shader := preload("res://world/terrain.gdshader")
var _active := {}  # Vector3i -> MeshInstance3D
var _pool: Array[MeshInstance3D] = []
var _cam_enu := Vector3.ZERO
var visible_nodes := 0
var pending_tiles := 0  # finer tiles the last selection wanted but the cache has not loaded yet
var _roots: Array[Vector3i] = []
var _recs := {}  # Vector3i -> [x0, y0, x1, y1, min_h, max_h, size, src, children|null, can_split]
var _split := {}  # Vector3i -> true: nodes split at the last selection (hysteresis)
var _last_sel := Vector3(INF, INF, INF)
var _since := INF
var _is_root := {}
var _ro_bound := {}  # Vector3i -> true: node currently shows a road tile
var _ro_t := 0.0
var _focus_enu := Vector3(INF, INF, INF)
var _last_focus := Vector3(INF, INF, INF)
var _unmorphed := {}  # Vector3i -> true: active node drawn without geomorph (near the focus)


func _ready() -> void:
	cache = TerrainTileCache.new()
	_mesh = TerrainMesh.build()
	TerrainDetail.apply(_shader)
	_roots = cache.tmeta.roots()
	for r in _roots:
		_is_root[r] = true
	FloatingOrigin.shifted.connect(_on_origin_shifted)


func _exit_tree() -> void:
	if cache:
		cache.wait_all()
	roads.wait_all()


func height_at(east: float, north: float) -> float:
	return cache.height_at(east, north)


func _process(dt: float) -> void:
	RenderingServer.global_shader_parameter_set("terrain_bump_amp", TerrainBump.peak_m(Graphics.preset))
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_cam_enu = FloatingOrigin.to_world(cam.global_position)
	RenderingServer.global_shader_parameter_set("terrain_eye", cam.global_position)
	var fp := Vector3(1e9, 0.0, 1e9)
	_focus_enu = Vector3(INF, INF, INF)
	if is_instance_valid(focus) and focus.is_inside_tree():
		fp = focus.global_position
		_focus_enu = FloatingOrigin.to_world(fp)
	RenderingServer.global_shader_parameter_set("ground_focus", fp)
	var uploads := cache.process()
	roads.process()
	_ro_t += dt
	if _ro_t >= ROADS_EVERY_S:
		_ro_t = 0.0
		_update_roads()
	_since += dt
	var focus_moved := is_finite(_focus_enu.x) and not (_focus_enu.distance_to(_last_focus) < RESELECT_M)
	if uploads == 0 and _since < RESELECT_S and _cam_enu.distance_to(_last_sel) < RESELECT_M and not focus_moved:
		return
	_since = 0.0
	_last_sel = _cam_enu
	_last_focus = _focus_enu
	if _recs.size() > MAX_RECS:
		_recs.clear()  # memo only; rebuilt on demand
	var wanted: Array[Vector3i] = []
	var split := {}
	pending_tiles = 0
	for r in _roots:
		if _ready_tile(r):
			_select(r, wanted, split)
	_split = split
	_apply(wanted)


func _rec(k: Vector3i) -> Array:
	var r = _recs.get(k)
	if r != null:
		return r
	var size := cache.level_size(k.x)
	var s := cache.tmeta.height_source(k.x, k.y, k.z)
	if s == TerrainMeta.NONE:
		s = _roots[0]
	var mm := cache.min_max(s.x, s.y, s.z)
	# stop at MAX_VIRTUAL levels below the data tile (native resolution for level 0)
	var can := k.x > MIN_LEVEL and s.x - k.x < MAX_VIRTUAL
	r = [k.y * size, k.z * size, (k.y + 1) * size, (k.z + 1) * size, mm.x, mm.y, size, s, null, can]
	_recs[k] = r
	return r


func _children(k: Vector3i, r: Array) -> Array:
	if r[8] == null:
		r[8] = [Vector3i(k.x - 1, k.y * 2, k.z * 2), Vector3i(k.x - 1, k.y * 2 + 1, k.z * 2),
			Vector3i(k.x - 1, k.y * 2, k.z * 2 + 1), Vector3i(k.x - 1, k.y * 2 + 1, k.z * 2 + 1)]
	return r[8]


func _ready_tile(k: Vector3i) -> bool:
	var s: Vector3i = _rec(k)[7]
	return not cache.get_tile(s.x, s.y, s.z).is_empty()


## k is known to be ready (checked by the caller).
func _select(k: Vector3i, out: Array[Vector3i], split: Dictionary) -> void:
	var r := _rec(k)
	if r[9]:
		var dx := maxf(maxf(r[0] - _cam_enu.x, _cam_enu.x - r[2]), 0.0)
		var dy := maxf(maxf(r[1] - _cam_enu.y, _cam_enu.y - r[3]), 0.0)
		var dz := maxf(maxf(r[4] - _cam_enu.z, _cam_enu.z - r[5]), 0.0)
		var limit: float = r[6] * lod_k * (HYSTERESIS if _split.has(k) else 1.0)
		if dx * dx + dy * dy + dz * dz < limit * limit or _near_focus(r):
			var kids := _children(k, r)
			var ok := true
			for c in kids:
				var got := _ready_tile(c)  # request all, even after a miss
				if not got:
					pending_tiles += 1
				ok = got and ok
			if ok:
				split[k] = true
				for c in kids:
					_select(c, out, split)
				return
	out.append(k)


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
			_ro_bound.erase(k)
			_unmorphed.erase(k)
			_unbind_roads(mi.material_override)
	for k in wanted:
		if not _active.has(k):
			var mi := _make_instance(k)
			_active[k] = mi
			_place(k, mi)
		elif _unmorphed.has(k) != _near_focus(_rec(k)):
			_set_morph(k, _active[k].material_override)
	visible_nodes = wanted.size()


## Node record r within FOCUS_KEEP_M (horizontally) of the focus.
func _near_focus(r: Array) -> bool:
	if not is_finite(_focus_enu.x):
		return false
	var dx := maxf(maxf(r[0] - _focus_enu.x, _focus_enu.x - r[2]), 0.0)
	var dy := maxf(maxf(r[1] - _focus_enu.y, _focus_enu.y - r[3]), 0.0)
	return dx * dx + dy * dy < FOCUS_KEEP_M * FOCUS_KEEP_M


## Geomorph toward the parent over the tail of the parent's split range (vertex distance >= box distance, so
## a node is fully morphed whenever its parent splits or merges); none for roots and nodes near the focus.
func _set_morph(k: Vector3i, m: ShaderMaterial) -> void:
	var size := cache.level_size(k.x)
	var par_split := 2.0 * size * lod_k
	var morph := Vector2(par_split * MORPH_START, par_split)
	_unmorphed.erase(k)
	if _near_focus(_rec(k)):
		_unmorphed[k] = true
		morph = NO_MORPH
	elif _is_root.has(k):
		morph = NO_MORPH
	m.set_shader_parameter("morph_range", morph)


## Binds the level-0 road / river tile to active nodes within ROADS_NEAR_M of the camera (levels <= 0
## only: coarser nodes are never that close), unbinds it again when they are further away.
func _update_roads() -> void:
	for k in _active:
		_bind_roads(k, _active[k].material_override)


func _bind_roads(k: Vector3i, m: ShaderMaterial) -> void:
	if k.x > 0:
		return
	var r := _rec(k)
	var dx := maxf(maxf(r[0] - _cam_enu.x, _cam_enu.x - r[2]), 0.0)
	var dy := maxf(maxf(r[1] - _cam_enu.y, _cam_enu.y - r[3]), 0.0)
	if dx * dx + dy * dy > ROADS_NEAR_M * ROADS_NEAR_M:
		if _ro_bound.erase(k):
			_unbind_roads(m)
		return
	if _ro_bound.has(k):
		return
	var tx := k.y >> -k.x
	var ty := k.z >> -k.x
	var tex := roads.texture(tx, ty)
	if tex != null:
		m.set_shader_parameter("ro_tex", tex)
		m.set_shader_parameter("ro_rect", TerrainMeta.sub_rect(k, Vector3i(0, tx, ty)))
		m.set_shader_parameter("ro_on", 1.0)
		var pv := roads.pavement(tx, ty)  # airport pavement mask, same lattice (terrain_pavement.gdshaderinc)
		m.set_shader_parameter("pv_tex", pv)
		m.set_shader_parameter("pv_on", 1.0 if pv != null else 0.0)
		_ro_bound[k] = true


func _unbind_roads(m: ShaderMaterial) -> void:
	for p in ["ro_on", "pv_on", "ro_tex", "pv_tex"]:
		m.set_shader_parameter(p, 0.0 if p.ends_with("_on") else null)


func _place(k: Vector3i, mi: MeshInstance3D) -> void:
	var r := _rec(k)
	mi.position = FloatingOrigin.to_render_d(r[0], r[1], 0.0)


func _on_origin_shifted(_d: Vector3) -> void:
	for k in _active:
		_place(k, _active[k])


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
	var r := _rec(k)
	var size: float = r[6]
	var s: Vector3i = r[7]
	var t: Dictionary = cache.get_tile(s.x, s.y, s.z)
	var span := 1 << (s.x - k.x)  # 2^(virtual levels below the source tile)
	var sub := Vector2i(k.y - s.y * span, k.z - s.z * span)
	var per := cache.tile_n / span  # source heightmap texels covered by this node
	var ir := TerrainMeta.sub_rect(k, t.img_src)  # imagery may come from a coarser tile
	var lr := TerrainMeta.sub_rect(k, t.lc_src)
	var skirt := maxf(size * SKIRT_FRAC, 10.0)
	var m: ShaderMaterial = mi.material_override
	m.set_shader_parameter("height_tex", t.htex)
	m.set_shader_parameter("img_tex", t.itex)
	m.set_shader_parameter("lc_tex", t.lctex)
	m.set_shader_parameter("wc_tex", t.wctex)  # WorldCover class: same source tile, so same lc_off / lc_scale
	m.set_shader_parameter("sd_tex", t.sdtex)  # shore distance / openness, same source tile as lc
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
	_set_morph(k, m)
	_bind_roads(k, m)
	mi.custom_aabb = AABB(Vector3(0, r[4] - skirt, -size), Vector3(size, r[5] - r[4] + skirt, size))
	return mi
