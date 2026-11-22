class_name GroundSurface
extends RefCounted
## Is a ground point paved? For the ground effects (world/ground_fx.gd): dust only off the pavement, full wheel
## spray on it. Paved = on a runway or taxiway ribbon (runways.json, exact) or inside the airport pavement mask
## (terrain/pv tiles from tools/27_pavement.py: aprons, stands, runway and taxiway shoulders; red = edge distance,
## negative inside, as terrain_pavement.gdshaderinc reads it). A mask tile is read on a worker thread the first time
## a point in it is asked about. Until it has arrived, a point near a runway counts as paved: no dust for a second on
## grass is better than a puff of dust on an apron. Every runway in the data is asphalt or concrete, so grass and dirt
## are the ground beside the pavement.

const KEEP_EVERY := 2  # the 4 m mask (tools/pavement_raster.py) is kept at 8 m: 3.7 MB a tile instead of 15
const CELL := 250.0  # m: ribbon index cell
const NEAR_RUNWAY := 1500.0  # m: "probably paved" while the mask tile is loading

var tile_m := 7680.0  # level-0 tile edge (TerrainMeta.tile_size_m)
var fixed := -1  # tests and debug scenes: 1 = everything paved, 0 = nothing paved, -1 = look it up
var _cells := {}  # Vector2i -> [[a, b, half width]]
var _runway_mid: Array = []  # Vector2 per runway
var _tiles := {}  # Vector2i -> Image, or null when there is no mask for that tile
var _loading := {}  # shared with the loader tasks: Vector2i -> Image (or null) once read
var _mutex := Mutex.new()
var _tasks := {}  # Vector2i -> WorkerThreadPool task id


## data: runways.json ({runways, taxiways}); tile: TerrainMeta.tile_size_m.
func setup(data: Dictionary, tile := 7680.0) -> void:
	tile_m = tile
	for r in data.get("runways", []):
		var a := Vector2(r.ends[0].x, r.ends[0].y)
		var b := Vector2(r.ends[1].x, r.ends[1].y)
		_add(a, b, float(r.width) * 0.5)
		_runway_mid.append((a + b) * 0.5)
	for tw in data.get("taxiways", []):
		for i in tw.pts.size() - 1:
			_add(Vector2(tw.pts[i][0], tw.pts[i][1]), Vector2(tw.pts[i + 1][0], tw.pts[i + 1][1]), minf(float(tw.width), 23.0) * 0.5)


func paved(e: float, n: float) -> bool:
	if fixed >= 0:
		return fixed == 1
	var p := Vector2(e, n)
	for s in _cells.get(Vector2i(floori(e / CELL), floori(n / CELL)), []):
		if Geometry2D.get_closest_point_to_segment(p, s[0], s[1]).distance_to(p) <= s[2]:
			return true
	var key := Vector2i(floori(e / tile_m), floori(n / tile_m))
	if not _tiles.has(key):
		_poll(key)
		if not _tiles.has(key):
			return near_runway(p)
	var img: Image = _tiles[key]
	if img == null:
		return false
	var rn := img.get_width()
	var res := tile_m / rn
	var px := clampi(int((e - key.x * tile_m) / res), 0, rn - 1)
	var py := clampi(rn - 1 - int((n - key.y * tile_m) / res), 0, img.get_height() - 1)
	return img.get_pixel(px, py).r * 16.0 - 8.0 < 0.0


func near_runway(p: Vector2) -> bool:
	for m in _runway_mid:
		if p.distance_to(m) < NEAR_RUNWAY:
			return true
	return false


## Waits for the loaders (call before freeing).
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
		if _tiles.size() >= 2:
			_tiles.clear()  # keep only the tiles under the aircraft
		_tiles[key] = img
		return
	if _tasks.has(key):
		return
	var path := Paths.data("terrain/pv/0/%d_%d.png" % [key.x, key.y])
	if not FileAccess.file_exists(path):
		_tiles[key] = null
		return
	var out := _loading
	var m := _mutex
	_tasks[key] = WorkerThreadPool.add_task(func() -> void:
		var im := Image.new()
		var ok := im.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK
		if ok:
			im.resize(im.get_width() / KEEP_EVERY, im.get_height() / KEEP_EVERY, Image.INTERPOLATE_NEAREST)
		m.lock()
		out[key] = im if ok else null
		m.unlock())


func _add(a: Vector2, b: Vector2, hw: float) -> void:
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * hw
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * hw
	for cy in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
		for cx in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
			var k := Vector2i(cx, cy)
			if not _cells.has(k):
				_cells[k] = []
			_cells[k].append([a, b, hw])
