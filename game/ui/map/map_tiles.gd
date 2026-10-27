class_name MapTiles
extends RefCounted
## Satellite imagery for the moving map. Tiles (terrain/img/<level>/<tx>_<ty>.dds) are read and
## decoded on worker threads and become textures on the main thread, a few per frame, so the
## frame never waits on the disk. While a tile loads, the nearest loaded coarser tile is drawn on
## a sub-rectangle of itself, so the map never shows holes (the 6 coarsest tiles are preloaded).

const MAX_UPLOADS := 3  # textures made per frame
const MAX_TEXTURES := 220
const CELL_LIMIT := 160  # most tile cells drawn per frame (a safety net, normally under 30)

var cache: TerrainTileCache
var _tex := {}  # Vector3i -> ImageTexture, or null when the file is missing (kept in use order)
var _pending := {}  # Vector3i -> true
var _done: Array = []  # [Vector3i, Image or null]
var _mutex := Mutex.new()
var _tasks: Array[int] = []


func _init(c: TerrainTileCache) -> void:
	cache = c


## Start loading the coarsest tiles so there is always imagery to fall back on.
func preload_coarse() -> void:
	var top := cache.levels.size() - 1
	for k in cache.levels[top].tiles:
		var p: PackedStringArray = k.split("_")
		_request(Vector3i(top, int(p[0]), int(p[1])))


func _request(key: Vector3i) -> void:
	if _tex.has(key) or _pending.has(key):
		return
	_pending[key] = true
	_tasks.append(WorkerThreadPool.add_task(_load.bind(key)))


func _load(key: Vector3i) -> void:
	var img: Image = null
	var path := Paths.data("terrain/img/%d/%d_%d.dds" % [key.x, key.y, key.z])
	if FileAccess.file_exists(path):
		var im := Image.new()
		if im.load_dds_from_buffer(FileAccess.get_file_as_bytes(path)) == OK:
			img = im
	_mutex.lock()
	_done.append([key, img])
	_mutex.unlock()


## Turn finished loads into textures (call once per frame). True while loads are outstanding.
func process() -> bool:
	for i in MAX_UPLOADS:
		_mutex.lock()
		var item = _done.pop_front() if not _done.is_empty() else null
		_mutex.unlock()
		if item == null:
			break
		_pending.erase(item[0])
		_tex[item[0]] = ImageTexture.create_from_image(item[1]) if item[1] != null else null
	while _tex.size() > MAX_TEXTURES:
		_tex.erase(_tex.keys()[0])
	return not _pending.is_empty()


func busy() -> bool:
	return not _pending.is_empty()


## Block until every outstanding load is a texture (screenshots, tests).
func wait_all() -> void:
	while process() or busy():
		OS.delay_msec(5)


func free_tasks() -> void:
	for t in _tasks:
		WorkerThreadPool.wait_for_task_completion(t)
	_tasks.clear()


func _have(key: Vector3i) -> Texture2D:
	var t = _tex.get(key)
	if t != null:  # keep recently used tiles at the back of the order
		_tex.erase(key)
		_tex[key] = t
	return t


## Texture to draw for a map cell: [Texture2D, source Rect2 in pixels] or [] if nothing is loaded.
func cell(level: int, tx: int, ty: int) -> Array:
	var node := Vector3i(level, tx, ty)
	var src := cache.tmeta.tex_source(level, tx, ty, TerrainMeta.HAS_IMG)
	if src == TerrainMeta.NONE:
		return []
	var t := _have(src)
	if t == null:
		_request(src)
		# nearest loaded ancestor of the wanted tile instead
		for l in range(src.x + 1, cache.levels.size()):
			var d := 1 << (l - src.x)
			var anc := Vector3i(l, floori(float(src.y) / d), floori(float(src.z) / d))
			t = _have(anc)
			if t != null:
				src = anc
				break
		if t == null:
			return []
	var r := TerrainMeta.sub_rect(node, src)
	var w := float(t.get_width())
	return [t, Rect2(r.x * w, (r.y - r.z) * w, r.z * w, r.z * w)]


## Draw imagery for the view on `ci` at one level: tiles are quads in north-up world space, drawn
## through a canvas transform that carries the view's rotation and scale.
func draw(ci: CanvasItem, view: MapView, level: int, tint: Color) -> void:
	var ts := cache.level_size(level)
	var wb := view.world_bounds()
	var x0 := floori(wb.position.x / ts)
	var x1 := floori(wb.end.x / ts)
	var y0 := floori(wb.position.y / ts)
	var y1 := floori(wb.end.y / ts)
	if (x1 - x0 + 1) * (y1 - y0 + 1) > CELL_LIMIT:
		return
	# the map is drawn in a transform that carries rotation and scale: tile space = metres from the
	# view centre (small numbers, so the imagery does not jitter far from the origin)
	ci.draw_set_transform_matrix(Transform2D(view.rot, view.size * 0.5) \
		.scaled_local(Vector2(1.0 / view.m_per_px, -1.0 / view.m_per_px)))
	var o := view.centre
	for ty in range(y0, y1 + 1):
		for tx in range(x0, x1 + 1):
			var c := cell(level, tx, ty)
			if c.is_empty():
				continue
			# a quad with texture coordinates (image row 0 = the tile's north edge; the transform
			# flips y, so north is up on screen); negative rect sizes would shift the image
			var tex: Texture2D = c[0]
			var src: Rect2 = c[1]
			var w := float(tex.get_width())
			var u0 := src.position.x / w
			var u1 := src.end.x / w
			var v0 := src.position.y / w
			var v1 := src.end.y / w
			var west := tx * ts - o.x
			var east := west + ts
			var south := ty * ts - o.y
			var north := south + ts
			ci.draw_polygon(PackedVector2Array([Vector2(west, north), Vector2(east, north), Vector2(east, south), Vector2(west, south)]),
				PackedColorArray([tint, tint, tint, tint]),
				PackedVector2Array([Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]), tex)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
