class_name Trees
extends Node3D
## Forests from the land-class mask (tools/11_landclass.py, 1..200 = tree density). The world is split into CHUNK-metre cells;
## cells within radius of the camera get a MultiMesh of one-quad hemi-octahedral impostors (tree.gdshader; TreeAtlas bakes
## every species from 64 directions at startup), placed deterministically; species from TreeSpecies (region, height,
## WorldCover). Trees within lod_radius are real meshes (TreeLod, dither swap). TreeQuality sets the per-preset numbers.
## Generation runs on worker threads (TreeSampler reads the data files); the main thread uploads finished buffers, BUDGET per
## frame. Hidden above HIDE_AGL.

const CHUNK := 480.0
var radius := 2200.0  # graphics presets
const HIDE_AGL := 1500.0
const PX := 10.0  # land-class pixel size (m)
const BUDGET := 2  # finished chunks turned into MultiMeshes per frame
const MAX_IN_FLIGHT := 4  # chunks generating on worker threads
const MAX_TREE_H := TreeSpecies.MAX_HEIGHT  # tallest tree of any species
const COL_CACHE := 12000  # collision cells kept

@export var density_scale := 1.0:  # graphics presets scale this
	set(v):
		density_scale = v
		_col.clear()  # collision trees follow the drawn ones
		if _lod:
			_lod.density_scale = v
			_lod.clear()

## Radius (m) of the LOD0 meshes around the camera; 0 = none (Low preset).
var lod_radius := 130.0:
	set(v):
		lod_radius = v
		if _lod:
			_lod.radius = v

## Impostor atlas frame size (px) and whether three frames are blended (TreeQuality, per preset).
var atlas_px := 128
var blend_frames := true:
	set(v):
		blend_frames = v
		_mat.set_shader_parameter("blend_frames", v)
## LOD0 detail of the near meshes shrinks away towards this distance (m), where cells switch to LOD1.
var detail_radius := 60.0:
	set(v):
		detail_radius = v
		if _lod:
			_lod.detail_radius = v

## Ground cover (GroundCover child) radius and grid step, m; 0 = none.
var cover_radius := 0.0:
	set(v):
		cover_radius = v
		if _cover:
			_cover.radius = v
var cover_step := 1.6:
	set(v):
		cover_step = v
		if _cover:
			_cover.step = v

## Impostor trees cast proxy shadows within this radius (TreeShadows), m; 0 = none.
var shadow_radius := 0.0:
	set(v):
		shadow_radius = v
		if _shadows:
			_shadows.radius = v

var terrain: TerrainQuadtree:
	set(t):
		terrain = t
		if _lod:
			_lod.terrain = t
		if _cover:
			_cover.terrain = t
var _lod: TreeLod
var _cover: GroundCover
var _shadows: TreeShadows
var _atlas: TreeAtlas
var _atlas_ready := false
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
var _col := {}  # land cell Vector2i -> collision disc record, or false (no tree)


func _ready() -> void:
	TreeClear.ensure_loaded()  # before any worker reads it
	_mat.shader = preload("res://world/tree.gdshader")
	_mat.set_shader_parameter("sway_crown_m", TreeLook.SWAY_CROWN_M)
	_mat.set_shader_parameter("sway_omega", TAU / TreeLook.SWAY_PERIOD_S)
	_mat.set_shader_parameter("species_n", float(TreeSpecies.COUNT))
	_mat.set_shader_parameter("variant_n", float(TreeSpecies.VARIANTS))
	_mat.set_shader_parameter("sp_aspect", PackedFloat32Array(TreeSpecies.ASPECT))
	_mat.set_shader_parameter("blend_frames", blend_frames)
	_mesh = TreeAtlas.quad()
	_lod = TreeLod.new()
	_lod.name = "Lod"
	_lod.radius = lod_radius
	_lod.detail_radius = detail_radius
	_lod.density_scale = density_scale
	_lod.terrain = terrain
	add_child(_lod)
	_cover = GroundCover.new()
	_cover.name = "Cover"
	_cover.radius = cover_radius
	_cover.step = cover_step
	_cover.terrain = terrain
	add_child(_cover)
	_shadows = TreeShadows.new()
	_shadows.trees = self
	_shadows.radius = shadow_radius
	add_child(_shadows)
	_atlas = TreeAtlas.new()
	_atlas.baked.connect(_on_atlas)
	add_child(_atlas)
	FloatingOrigin.shifted.connect(func(_d): _reposition())


func _on_atlas(albedo: Texture2D, normal: Texture2D) -> void:
	_mat.set_shader_parameter("atlas_albedo", albedo)
	_mat.set_shader_parameter("atlas_normal", normal)
	_mat.set_shader_parameter("sp_sphere", _atlas.sphere)
	_mat.set_shader_parameter("sp_half", _atlas.half)
	_mat.set_shader_parameter("frame_px", float(_atlas.frame_px))
	_atlas_ready = true
	print("TREE ATLAS %d px, %.1f MB on the GPU%s" % [_atlas.frame_px, _atlas.mem_bytes / 1048576.0, " (block-compressed)" if _atlas.compressed else ""])


func _process(dt: float) -> void:
	visible = Props.get_f("fdm/agl_m", 0.0) < HIDE_AGL or not Props.has("fdm/agl_m")
	if not _atlas.busy and (_atlas.frame_px != atlas_px or not _atlas_ready):
		_atlas.bake(atlas_px)  # first frame (after the preset is applied) and on a preset change
	if terrain == null or not visible or not _atlas_ready:
		return
	_mat.set_shader_parameter("lod_r", _lod.covered)
	_shadows.lod_r = _lod.covered
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
	var dry := TreeLook.dryness(Props.get_f("weather/day_of_year", 45.0))
	_mat.set_shader_parameter("season_dry", dry)
	_lod.season_dry = dry
	_cover.season_dry = dry
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
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # cut-out shadows would cost +6-10 ms (Ultra, trees_close)
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


## Collision: a vertical cylinder per tree (ObstacleShapes.disc, TreeSpecies.hit_radius / hit_top: 0.4 x width and 0.9 x
## height, less for palms), made lazily from the same TreeSampler.cell_tree rule as the drawn trees and cached per land cell.
## Independent of the camera and drawn chunks: works wherever the aircraft is once the land-class mask has loaded.
func near(e: float, n: float, r: float, alt_lo: float, out: Array) -> void:
	if terrain == null or alt_lo > terrain.cache.height_at(e, n) + MAX_TREE_H + r + 2.0:
		return  # nothing here reaches that high
	for cj in range(floori((n - r) / PX) - 1, floori((n + r) / PX) + 2):  # a canopy spills ~4 m past its cell
		for ci in range(floori((e - r) / PX) - 1, floori((e + r) / PX) + 2):
			var rec = _tree_cell(ci, cj)
			if rec is Dictionary:
				var lo: Vector2 = rec.lo
				var hi: Vector2 = rec.hi
				if lo.x <= e + r and hi.x >= e - r and lo.y <= n + r and hi.y >= n - r:
					out.append(rec)


func _tree_cell(ci: int, cj: int) -> Variant:
	var k := Vector2i(ci, cj)
	var rec = _col.get(k)
	if rec != null:
		return rec
	var lc := terrain.cache.landclass_at((ci + 0.5) * PX, (cj + 0.5) * PX)
	if lc < 0:
		return false  # land-class mask still loading: ask again next step
	var t := TreeSampler.cell_tree(ci, cj, lc, PX, density_scale)
	rec = false
	if not t.is_empty() and not TreeClear.blocked(t[0], t[1]):
		var g := terrain.cache.height_at(t[0], t[1])
		var sh := TreeSpecies.shape(ci, cj, t[1], g, maxi(terrain.cache.worldcover_at((ci + 0.5) * PX, (cj + 0.5) * PX), 0))
		var sp := int(sh[0])
		rec = ObstacleShapes.disc(Vector2(t[0], t[1]), TreeSpecies.hit_radius(sp, sh[3]), g - 0.3, g + TreeSpecies.hit_top(sp, sh[2]), "trees", true)
	if _col.size() > COL_CACHE:
		_col.clear()
	_col[k] = rec
	return rec


## Top of the tree canopy (m AMSL) at world (east, north) if a tree stands there, else -INF.
func tree_top_at(east: float, north: float) -> float:
	var out := []
	near(east, north, 0.0, -INF, out)
	for rec in out:
		if (rec.c as Vector2).distance_to(Vector2(east, north)) < rec.r:
			return rec.top
	return -INF
