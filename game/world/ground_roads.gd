class_name GroundRoads
extends RefCounted
## Is a ground point on a road, track or river ribbon? For GroundCover (no grass on roads). Reads the same 4 m signed-
## distance tiles the terrain shader draws (tools/20_roads_rivers.py -> terrain/ro/0/<tx>_<ty>.png, LA8: L = metres from
## the ribbon edge as byte * 0.16 - 6, negative inside; A = class, 0 none). A tile is decoded on a worker thread the
## first time a point in it is asked about; until then on() answers -1 (unknown). Only KEEP tiles stay in memory.

const KEEP := 2
const MARGIN_M := 1.0  # keep plants this far off the ribbon edge

var tile_m := 7680.0
var _tiles := {}  # Vector2i -> Image (LA8) or null (no roads there)
var _loading := {}  # shared with the tasks
var _tasks := {}
var _mutex := Mutex.new()


## 1 on a ribbon, 0 off it, -1 while the tile is still loading.
func on(e: float, n: float) -> int:
	var key := Vector2i(floori(e / tile_m), floori(n / tile_m))
	if not _tiles.has(key):
		_poll(key)
		if not _tiles.has(key):
			return -1
	var img: Image = _tiles[key]
	if img == null:
		return 0
	var rn := img.get_width()
	var res := tile_m / rn
	var px := clampi(int((e - key.x * tile_m) / res), 0, rn - 1)
	var py := clampi(rn - 1 - int((n - key.y * tile_m) / res), 0, img.get_height() - 1)
	var c := img.get_pixel(px, py)
	return 1 if c.a > 0.002 and c.r * 40.8 - 6.0 < MARGIN_M else 0


func finish() -> void:
	for k in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[k])
	_tasks.clear()


func _poll(key: Vector2i) -> void:
	_mutex.lock()
	var ready := _loading.has(key)
	var img: Image = _loading.get(key)
	_loading.erase(key)
	_mutex.unlock()
	if ready:
		WorkerThreadPool.wait_for_task_completion(_tasks[key])
		_tasks.erase(key)
		if _tiles.size() >= KEEP:
			_tiles.clear()
		_tiles[key] = img
		return
	if _tasks.has(key):
		return
	var path := Paths.data("terrain/ro/0/%d_%d.png" % [key.x, key.y])
	if not FileAccess.file_exists(path):
		_tiles[key] = null
		return
	var out := _loading
	var m := _mutex
	_tasks[key] = WorkerThreadPool.add_task(func() -> void:
		var im := Image.new()
		var ok := im.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK
		m.lock()
		out[key] = im if ok else null
		m.unlock())
