class_name TerrainTileCache
extends RefCounted
## Loads heightmap (.r16) + imagery (.dds, BC1) tiles on worker threads and turns them
## into textures on the main thread. Also answers CPU height queries from level-0
## tiles (used by camera clamp, FDM ground contact, LOS checks).
## Tile key = Vector3i(level, tx, ty); see tools/02_dem_tiles.py for the layout.

const MAX_UPLOADS_PER_FRAME := 6
const TILE_SIZE_DEFAULT := 7680.0  # level-0 tile size (tools/common.py TILE_SIZE)
const MAX_ENTRIES := 400

var meta: Dictionary
var tile_n: int
var h_scale: float
var h_offset: float
var levels: Array = []  # [{size_m, tiles: {"tx_ty": [min,max]}}]

var _entries := {}  # Vector3i -> {state, htex, itex, used}
var _done: Array = []  # [key, Image h, Image img]
var _mutex := Mutex.new()
var _cpu_heights := {}  # Vector2i(tx,ty) of level 0 -> PackedByteArray
var _frame := 0
var _fallback_img: ImageTexture


func _init() -> void:
	meta = Paths.load_json("terrain/meta.json")
	tile_n = int(meta.tile_n)
	h_scale = meta.h_scale
	h_offset = meta.h_offset
	levels = meta.levels
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	img.fill(Color(0.35, 0.4, 0.3))
	_fallback_img = ImageTexture.create_from_image(img)


func level_size(level: int) -> float:
	return float(meta.tile_size_m) * pow(2.0, level)


func has_tile(level: int, tx: int, ty: int) -> bool:
	return level >= 0 and level < levels.size() and levels[level].tiles.has("%d_%d" % [tx, ty])


func min_max(level: int, tx: int, ty: int) -> Vector2:
	var mm = levels[level].tiles.get("%d_%d" % [tx, ty], [0.0, 0.0])
	return Vector2(mm[0], mm[1])


## Returns {htex, itex} when ready, otherwise starts loading and returns {}.
func get_tile(level: int, tx: int, ty: int) -> Dictionary:
	var key := Vector3i(level, tx, ty)
	var e = _entries.get(key)
	if e == null:
		_entries[key] = {"state": 0, "used": _frame}
		WorkerThreadPool.add_task(_load.bind(key))
		return {}
	e.used = _frame
	return e if e.state == 1 else {}


func _load(key: Vector3i) -> void:
	var base := "terrain/%s/%d/%d_%d"
	var hb := FileAccess.get_file_as_bytes(Paths.data(base % ["h", key.x, key.y, key.z] + ".r16"))
	var h := Image.create_from_data(tile_n + 1, tile_n + 1, false, Image.FORMAT_RG8, hb)
	var img: Image = null
	var dds := Paths.data(base % ["img", key.x, key.y, key.z] + ".dds")
	if FileAccess.file_exists(dds):
		img = Image.new()
		if img.load_dds_from_buffer(FileAccess.get_file_as_bytes(dds)) != OK:
			img = null
	_mutex.lock()
	_done.append([key, h, img])
	_mutex.unlock()


## Call once per frame from the main thread.
func process() -> void:
	_frame += 1
	_mutex.lock()
	var n := mini(_done.size(), MAX_UPLOADS_PER_FRAME)
	var batch := _done.slice(0, n)
	_done = _done.slice(n)
	_mutex.unlock()
	for item in batch:
		var e = _entries.get(item[0])
		if e == null:
			continue
		e.htex = ImageTexture.create_from_image(item[1])
		e.itex = ImageTexture.create_from_image(item[2]) if item[2] else _fallback_img
		e.state = 1
	if _entries.size() > MAX_ENTRIES and _frame % 60 == 0:
		_evict()


func _evict() -> void:
	var keys := _entries.keys()
	keys.sort_custom(func(a, b): return _entries[a].used < _entries[b].used)
	for i in range(_entries.size() - MAX_ENTRIES * 3 / 4):
		var e = _entries[keys[i]]
		if e.state == 1 and _frame - e.used > 120:
			_entries.erase(keys[i])


## Terrain height (m) at world ENU (east, north), bilinear on level-0 samples.
func height_at(east: float, north: float) -> float:
	var size: float = meta.tile_size_m
	var tx := floori(east / size)
	var ty := floori(north / size)
	var tk := Vector2i(tx, ty)
	var b: PackedByteArray = _cpu_heights.get(tk, PackedByteArray())
	if b.is_empty():
		if not has_tile(0, tx, ty):
			return 0.0
		b = FileAccess.get_file_as_bytes(Paths.data("terrain/h/0/%d_%d.r16" % [tx, ty]))
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
