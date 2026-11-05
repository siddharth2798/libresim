class_name TerrainRoads
extends RefCounted
## Lazy cache of the road / river signed-distance tiles (tools/20_roads_rivers.py -> terrain/ro/0/<tx>_<ty>.png, 1920^2 LA8, one
## per level-0 tile). Only the few tiles around the camera are resident (the shader draws ribbons within ~3.3 km), so this sits
## beside TerrainTileCache. PNGs decode on worker threads; textures are created on the main thread, one per frame. Idle tiles are
## dropped after EVICT_MS (materials keep their own reference while bound).
## The airport pavement mask of the same tile (tools/27_pavement.py -> terrain/pv/0/<tx>_<ty>.png, RGBA8, same lattice) loads
## with it when there is one: pavement(tx, ty).

const EVICT_MS := 20000
const MAX_UPLOADS_PER_FRAME := 1

var _tiles := {}  # Vector2i -> {state: 0 loading | 1 ready | 2 no data, tex, pv (pavement or null), used}
var _tasks := {}  # Vector2i -> WorkerThreadPool task id
var _done: Array = []  # [Vector2i, Image or null, pavement Image or null]
var _mutex := Mutex.new()
var _frame := 0
var _now := 0


## The tile's texture once loaded, else null (and the load is started). A tile with no data stays null.
func texture(tx: int, ty: int) -> Texture2D:
	var key := Vector2i(tx, ty)
	var e = _tiles.get(key)
	if e == null:
		e = {"state": 0, "tex": null, "pv": null, "used": _now}
		_tiles[key] = e
		_tasks[key] = WorkerThreadPool.add_task(_load.bind(key))
	e.used = _now
	return e.tex if e.state == 1 else null


## The tile's pavement mask once the tile is loaded, null when it has none (or is not loaded yet).
func pavement(tx: int, ty: int) -> Texture2D:
	var e = _tiles.get(Vector2i(tx, ty))
	return e.pv if e != null and e.state == 1 else null


func has_data(tx: int, ty: int) -> bool:
	var e = _tiles.get(Vector2i(tx, ty))
	return e != null and e.state == 1


func is_settled(tx: int, ty: int) -> bool:
	var e = _tiles.get(Vector2i(tx, ty))
	return e != null and e.state != 0


func _load(key: Vector2i) -> void:
	var img := _png("terrain/ro/0/%d_%d.png" % [key.x, key.y])
	var pv := _png("terrain/pv/0/%d_%d.png" % [key.x, key.y]) if img != null else null
	_mutex.lock()
	_done.append([key, img, pv])
	_mutex.unlock()


static func _png(rel: String) -> Image:
	var p := Paths.data(rel)
	if not FileAccess.file_exists(p):
		return null
	var img := Image.new()
	return img if img.load_png_from_buffer(FileAccess.get_file_as_bytes(p)) == OK else null


## Once per frame from the main thread.
func process() -> void:
	_frame += 1
	_now = Time.get_ticks_msec()
	_mutex.lock()
	var n := mini(_done.size(), MAX_UPLOADS_PER_FRAME)
	var batch := _done.slice(0, n)
	_done = _done.slice(n)
	_mutex.unlock()
	for item in batch:
		var key: Vector2i = item[0]
		if _tasks.has(key):
			WorkerThreadPool.wait_for_task_completion(_tasks[key])
			_tasks.erase(key)
		var e = _tiles[key]
		if item[1] != null:
			e.tex = ImageTexture.create_from_image(item[1])
			e.pv = ImageTexture.create_from_image(item[2]) if item[2] != null else null
			e.state = 1
		else:
			e.state = 2
	if _frame % 120 == 0:
		for key in _tiles.keys():
			var e = _tiles[key]
			if e.state != 0 and _now - e.used > EVICT_MS:
				_tiles.erase(key)


func wait_all() -> void:
	for id in _tasks.values():
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()
