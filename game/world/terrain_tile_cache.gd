class_name TerrainTileCache
extends RefCounted
## Loads heightmap (.r16), imagery (.dds, BC1) and land-class (.r8.gz) tiles on
## worker threads and turns them into textures on the main thread. Heights and
## textures are cached separately: a tile without imagery / land class (flags in
## TerrainMeta) shares its nearest ancestor's textures, which are loaded once.
## Also answers CPU height queries from level-0 tiles (camera clamp, FDM ground
## contact, LOS) and land-class queries (ditching, tree density).
## Tile key = Vector3i(level, tx, ty); see tools/02_dem_tiles.py for the layout.

const MAX_UPLOADS_PER_FRAME := 6
const TILE_SIZE_DEFAULT := 7680.0  # level-0 tile size (tools/common.py TILE_SIZE)
const MAX_ENTRIES := 400  # per kind (heights, textures)
const MAX_CPU := 160  # CPU-side height / land-class tiles kept for queries
const IMG_N := 768
const NONE := TerrainMeta.NONE

var tmeta: TerrainMeta
var tile_n: int
var h_scale: float
var h_offset: float
var levels: Array = []  # TerrainMeta.levels (merged base + regions)

var _h := {}  # Vector3i -> {state, htex, used}
var _t := {}  # Vector3i -> {state, itex, lctex, lcimg, used}   (texture source tiles)
var _tiles := {}  # Vector3i -> composite {htex, itex, lctex, img_src, lc_src, used, ents}
var _tasks := {}  # Vector4i(kind, level, tx, ty) -> WorkerThreadPool task id
var _done: Array = []  # [kind, key, Image a, Image b]
var _mutex := Mutex.new()
var _cpu_heights := {}  # Vector2i(tx,ty) of level 0 -> PackedByteArray
var _frame := 0
var _fallback_img: ImageTexture
var _fallback_lc: ImageTexture


func _init() -> void:
	tmeta = TerrainMeta.new()
	tile_n = tmeta.tile_n
	h_scale = tmeta.h_scale
	h_offset = tmeta.h_offset
	levels = tmeta.levels
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	img.fill(Color(0.35, 0.4, 0.3))
	_fallback_img = ImageTexture.create_from_image(img)
	var lci := Image.create(4, 4, false, Image.FORMAT_R8)
	_fallback_lc = ImageTexture.create_from_image(lci)


func level_size(level: int) -> float:
	return tmeta.level_size(level)


func has_tile(level: int, tx: int, ty: int) -> bool:
	return tmeta.has_tile(level, tx, ty)


func min_max(level: int, tx: int, ty: int) -> Vector2:
	return tmeta.min_max(level, tx, ty)


## Returns {htex, itex, lctex, img_src, lc_src} once the tile's heights and its
## (possibly borrowed) textures are ready; otherwise starts loading and returns {}.
func get_tile(level: int, tx: int, ty: int) -> Dictionary:
	var key := Vector3i(level, tx, ty)
	var c = _tiles.get(key)
	if c != null:  # fast path: ready composite; keep its entries alive
		c.used = _frame
		for e in c.ents:
			e.used = _frame
		return c
	var isrc := tmeta.tex_source(level, tx, ty, TerrainMeta.HAS_IMG)
	var lsrc := tmeta.tex_source(level, tx, ty, TerrainMeta.HAS_LC)
	var h = _request(_h, key, 0)
	var ti = _request(_t, isrc, 1) if isrc != NONE else null
	var tl = _request(_t, lsrc, 1) if lsrc != NONE else null
	if h.state != 1 or (ti != null and ti.state != 1) or (tl != null and tl.state != 1):
		return {}
	var ents := [h]
	for e in [ti, tl]:
		if e != null:
			ents.append(e)
	c = {"htex": h.htex, "itex": ti.itex if ti != null and ti.itex else _fallback_img,
		"lctex": tl.lctex if tl != null and tl.lctex else _fallback_lc,
		"img_src": isrc, "lc_src": lsrc, "used": _frame, "ents": ents}
	_tiles[key] = c
	return c


func _request(store: Dictionary, key: Vector3i, kind: int) -> Dictionary:
	var e = store.get(key)
	if e == null:
		e = {"state": 0, "used": _frame}
		store[key] = e
		var job := _load_h.bind(key) if kind == 0 else _load_t.bind(key, tmeta.flags(key.x, key.y, key.z))
		_tasks[Vector4i(kind, key.x, key.y, key.z)] = WorkerThreadPool.add_task(job)
	e.used = _frame
	return e


func _load_h(key: Vector3i) -> void:
	var p := Paths.data("terrain/h/%d/%d_%d.r16" % [key.x, key.y, key.z])
	var hb := FileAccess.get_file_as_bytes(p)
	var w := tile_n + 1
	if hb.size() != w * w * 2:  # missing / truncated: flat at 0 m rather than a hole
		push_warning("terrain: bad heightmap " + p)
		hb = PackedByteArray()
		hb.resize(w * w * 2)
		var raw := clampi(roundi(-h_offset / h_scale), 0, 65535)
		for i in w * w:
			hb.encode_u16(i * 2, raw)
	var h := Image.create_from_data(w, w, false, Image.FORMAT_RG8, hb)
	_finish([0, key, h, null])


func _load_t(key: Vector3i, fl: int) -> void:
	var base := "terrain/%s/%d/%d_%d"
	var img: Image = null
	var dds := Paths.data(base % ["img", key.x, key.y, key.z] + ".dds")
	if fl & TerrainMeta.HAS_IMG and FileAccess.file_exists(dds):
		img = Image.new()
		if img.load_dds_from_buffer(FileAccess.get_file_as_bytes(dds)) != OK:
			img = null
	var lc: Image = null
	var lcp := Paths.data(base % ["lc", key.x, key.y, key.z] + ".r8.gz")
	if fl & TerrainMeta.HAS_LC and FileAccess.file_exists(lcp):
		var lb := FileAccess.get_file_as_bytes(lcp).decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
		if lb.size() == IMG_N * IMG_N:
			lc = Image.create_from_data(IMG_N, IMG_N, false, Image.FORMAT_R8, lb)
	_finish([1, key, img, lc])


func _finish(item: Array) -> void:
	_mutex.lock()
	_done.append(item)
	_mutex.unlock()


## Call once per frame from the main thread. Returns the number of tiles uploaded.
func process() -> int:
	_frame += 1
	_mutex.lock()
	var n := mini(_done.size(), MAX_UPLOADS_PER_FRAME)
	var batch := _done.slice(0, n)
	_done = _done.slice(n)
	_mutex.unlock()
	for item in batch:
		var key: Vector3i = item[1]
		var tk := Vector4i(item[0], key.x, key.y, key.z)
		if _tasks.has(tk):
			WorkerThreadPool.wait_for_task_completion(_tasks[tk])  # finished: releases it
			_tasks.erase(tk)
		var e = (_h if item[0] == 0 else _t).get(key)
		if item[0] == 0:
			e.htex = ImageTexture.create_from_image(item[2])
		else:
			e.itex = ImageTexture.create_from_image(item[2]) if item[2] else null
			e.lctex = ImageTexture.create_from_image(item[3]) if item[3] else null
			e.lcimg = item[3]  # CPU copy for landclass_at()
		e.state = 1
	if _frame % 60 == 0:
		for store in [_h, _t, _tiles]:
			if store.size() > MAX_ENTRIES:
				_evict(store)
	return batch.size()


## Drops the least recently used ready entries not touched for 120 frames.
## Composites (_tiles) hold their own texture refs, so dropping an entry
## under a live composite is safe; the composite touches its entries anyway.
func _evict(store: Dictionary) -> void:
	var keys := store.keys()
	keys.sort_custom(func(a, b): return store[a].used < store[b].used)
	for i in range(store.size() - MAX_ENTRIES * 3 / 4):
		var e = store[keys[i]]
		if e.get("state", 1) == 1 and _frame - e.used > 120:
			store.erase(keys[i])


## Blocks until every queued load has finished (call before the cache is freed).
func wait_all() -> void:
	for id in _tasks.values():
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()


static func _cap(d: Dictionary) -> void:
	while d.size() >= MAX_CPU:
		d.erase(d.keys()[0])  # oldest inserted


## Terrain height (m) at world ENU (east, north), bilinear on level-0 samples.
func height_at(east: float, north: float) -> float:
	var size: float = tmeta.tile_size_m
	var tx := floori(east / size)
	var ty := floori(north / size)
	var tk := Vector2i(tx, ty)
	var b: PackedByteArray = _cpu_heights.get(tk, PackedByteArray())
	if b.is_empty():
		if not has_tile(0, tx, ty):
			return 0.0
		b = FileAccess.get_file_as_bytes(Paths.data("terrain/h/0/%d_%d.r16" % [tx, ty]))
		if b.size() != (tile_n + 1) * (tile_n + 1) * 2:
			return 0.0
		_cap(_cpu_heights)
		_cpu_heights[tk] = b
	var res := size / tile_n
	var fx := (east - tx * size) / res
	var fy := (north - ty * size) / res
	var i := clampi(floori(fx), 0, tile_n - 1)
	var j := clampi(floori(fy), 0, tile_n - 1)
	var u := fx - i
	var v := fy - j
	var w := tile_n + 1
	var h00 := b.decode_u16((j * w + i) * 2)
	var h10 := b.decode_u16((j * w + i + 1) * 2)
	var h01 := b.decode_u16(((j + 1) * w + i) * 2)
	var h11 := b.decode_u16(((j + 1) * w + i + 1) * 2)
	var hv := lerpf(lerpf(h00, h10, u), lerpf(h01, h11, u), v)
	return hv * h_scale + h_offset


static func key_level(k: Vector3i) -> int:
	return k.x


## Land-class value (0 other, 1..200 tree density, 255 water) at world (east, north),
## from the finest tile that has a land-class mask there (level 0, else the nearest
## ancestor). -1 while that mask is still loading; 0 where no tile has one.
func landclass_at(east: float, north: float) -> int:
	var size: float = tmeta.tile_size_m
	var src := tmeta.tex_source(0, floori(east / size), floori(north / size), TerrainMeta.HAS_LC)
	if src == NONE:
		return 0
	var e := _request(_t, src, 1)
	if e.state != 1:
		return -1
	var img: Image = e.lcimg
	if img == null:
		return 0
	var ss := tmeta.level_size(src.x)
	var px := clampi(int((east - src.y * ss) / ss * IMG_N), 0, IMG_N - 1)
	var py := clampi(int((1.0 - (north - src.z * ss) / ss) * IMG_N), 0, IMG_N - 1)
	return int(img.get_pixel(px, py).r * 255.0 + 0.5)
