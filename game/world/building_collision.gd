class_name BuildingCollision
extends RefCounted
## Collision footprints of the OSM buildings (data/processed/buildings/<tx>_<ty>.col, written by
## tools/10_buildings.py next to the drawn meshes). Loaded around the AIRCRAFT, not the camera:
## focus() is called every physics tick and starts a worker-thread load for every level-0 tile
## within LOAD_R of the aircraft or of where it will be in LOOKAHEAD_S; load_now() reads the tile
## under a freshly placed aircraft synchronously (a few 100 ms at most), so a crash never depends on
## the picture having streamed in. Footprints of buildings drawn as landmark terminal models are left
## out (the model's own collision, Terminals, replaces them).

const CELL := 64.0  # spatial hash cell in a tile (m)
const LOAD_R := 1500.0
const KEEP_R := 6000.0
const LOOKAHEAD_S := 12.0
const EDGE := 120.0  # a footprint may overhang its tile by this much

var tile_size := TerrainTileCache.TILE_SIZE_DEFAULT
var _dir := ""
var _tiles := {}  # Vector2i -> tile Dictionary ({} = no file)
var _tasks := {}  # Vector2i -> WorkerThreadPool id (loading)
var _done: Array = []  # [key, tile] from workers
var _mutex := Mutex.new()
var _rings: Array[PackedVector2Array] = []  # landmark footprints (replaced by terminal models)
var _last := Vector2(INF, INF)


func _init(dir := "") -> void:
	_dir = dir if dir != "" else Paths.data("buildings")
	var lm = Paths.load_json("terminals/landmarks.json") if FileAccess.file_exists(Paths.data("terminals/landmarks.json")) else null
	if lm is Dictionary:
		for icao in lm:
			if FileAccess.file_exists(Paths.data("terminals/%s.glb" % icao)):
				for r in lm[icao]:
					var ring := PackedVector2Array()
					for p in r:
						ring.append(Vector2(p[0], p[1]))
					_rings.append(ring)


func tile_key(e: float, n: float) -> Vector2i:
	return Vector2i(floori(e / tile_size), floori(n / tile_size))


func loaded(e: float, n: float) -> bool:
	return _tiles.has(tile_key(e, n))


func tiles_loaded() -> int:
	return _tiles.size()


## Main thread, every physics tick: keep the collision tiles around the aircraft loaded.
func focus(e: float, n: float, ve: float, vn: float) -> void:
	poll()
	load_now(e, n)  # no-op unless the aircraft was teleported (situation load, reset) or outran the prefetch
	var here := Vector2(e, n)
	if here.distance_to(_last) < 40.0 and _tasks.is_empty():
		return
	_last = here
	var ahead := here + Vector2(ve, vn).limit_length(300.0) * LOOKAHEAD_S
	for c in [here, ahead]:
		for ty in range(floori((c.y - LOAD_R) / tile_size), floori((c.y + LOAD_R) / tile_size) + 1):
			for tx in range(floori((c.x - LOAD_R) / tile_size), floori((c.x + LOAD_R) / tile_size) + 1):
				var k := Vector2i(tx, ty)
				if not _tiles.has(k) and not _tasks.has(k):
					if FileAccess.file_exists(_path(k)):
						_tasks[k] = WorkerThreadPool.add_task(_work.bind(k))
					else:
						_tiles[k] = {}
	for k in _tiles.keys():  # drop what is far behind
		var lo := Vector2(k) * tile_size
		var d := Vector2(clampf(e, lo.x, lo.x + tile_size) - e, clampf(n, lo.y, lo.y + tile_size) - n).length()
		if d > KEEP_R:
			_tiles.erase(k)


## Main thread: take finished worker results (their tasks are released here).
func poll(already_waited := Vector2i(1 << 30, 0)) -> void:
	if _tasks.is_empty():
		return
	_mutex.lock()
	var batch := _done
	_done = []
	_mutex.unlock()
	for item in batch:
		if item[0] != already_waited:
			WorkerThreadPool.wait_for_task_completion(_tasks[item[0]])  # finished: releases it
		_tasks.erase(item[0])
		_tiles[item[0]] = item[1]


## Synchronously load the tile under (e, n) if it is not there yet (aircraft just placed).
func load_now(e: float, n: float) -> void:
	var k := tile_key(e, n)
	if _tiles.has(k):
		return
	if _tasks.has(k):  # a worker is already on it: wait for that one
		WorkerThreadPool.wait_for_task_completion(_tasks[k])
		poll(k)
		return
	_tiles[k] = parse_file(_path(k), _rings) if FileAccess.file_exists(_path(k)) else {}


## Every worker task must be waited for before the object goes away.
func wait_all() -> void:
	for id in _tasks.values():
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()
	_done.clear()


func _path(k: Vector2i) -> String:
	return _dir.path_join("%d_%d.col" % [k.x, k.y])


func _work(k: Vector2i) -> void:
	var t := parse_file(_path(k), _rings)
	_mutex.lock()
	_done.append([k, t])
	_mutex.unlock()


static func parse_file(path: String, rings: Array[PackedVector2Array] = []) -> Dictionary:
	var b := FileAccess.get_file_as_bytes(path).decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	if b.size() < 8 or b.slice(0, 4).get_string_from_ascii() != "COL1":
		return {}
	var count := b.decode_u32(4)
	var polys: Array[PackedVector2Array] = []
	var base := PackedFloat32Array()
	var top := PackedFloat32Array()
	var o := 8
	for i in count:
		var n := b.decode_u16(o)
		base.append(b.decode_float(o + 2))
		top.append(b.decode_float(o + 6))
		polys.append(b.slice(o + 10, o + 10 + n * 8).to_vector2_array())
		o += 10 + n * 8
	return make_tile(polys, base, top, rings)


## Index a tile: spatial hash of the footprints, minus those inside a landmark ring.
static func make_tile(polys: Array[PackedVector2Array], base: PackedFloat32Array, top: PackedFloat32Array, rings: Array[PackedVector2Array] = []) -> Dictionary:
	var los := PackedVector2Array()
	var his := PackedVector2Array()
	var means := PackedVector2Array()
	var tlo := Vector2(INF, INF)
	var thi := Vector2(-INF, -INF)
	for pts in polys:
		var lo := pts[0]
		var hi := pts[0]
		var mean := Vector2.ZERO
		for q in pts:
			lo = lo.min(q)
			hi = hi.max(q)
			mean += q
		los.append(lo)
		his.append(hi)
		means.append(mean / pts.size())
		tlo = tlo.min(lo)
		thi = thi.max(hi)
	var here: Array[PackedVector2Array] = []  # landmark rings that overlap this tile
	for ring in rings:
		var rlo := ring[0]
		var rhi := ring[0]
		for q in ring:
			rlo = rlo.min(q)
			rhi = rhi.max(q)
		if rlo.x <= thi.x and rhi.x >= tlo.x and rlo.y <= thi.y and rhi.y >= tlo.y:
			here.append(ring)
	var cells := {}
	for i in polys.size():
		var skip := false
		for ring in here:  # same centroid test as tools/10_buildings.py (mean of the vertices)
			if Geometry2D.is_point_in_polygon(means[i], ring):
				skip = true
				break
		if skip:
			continue
		for cy in range(floori(los[i].y / CELL), floori(his[i].y / CELL) + 1):
			for cx in range(floori(los[i].x / CELL), floori(his[i].x / CELL) + 1):
				var key := Vector2i(cx, cy)
				if not cells.has(key):
					cells[key] = []
				cells[key].append(i)
	return {"cells": cells, "polys": polys, "base": base, "top": top, "lo": los, "hi": his, "recs": {}}


## For tests and tools: install a tile built with make_tile.
func set_tile(k: Vector2i, tile: Dictionary) -> void:
	_tiles[k] = tile


## Appends the footprint records whose bounding box is within r of (east, north).
func near(e: float, n: float, r: float, out: Array) -> void:
	var cx0 := floori((e - r) / CELL)
	var cy0 := floori((n - r) / CELL)
	var cx1 := floori((e + r) / CELL)
	var cy1 := floori((n + r) / CELL)
	for ty in range(floori((n - r - EDGE) / tile_size), floori((n + r + EDGE) / tile_size) + 1):
		for tx in range(floori((e - r - EDGE) / tile_size), floori((e + r + EDGE) / tile_size) + 1):
			var t: Dictionary = _tiles.get(Vector2i(tx, ty), {})
			if t.is_empty():
				continue
			for cy in range(cy0, cy1 + 1):
				for cx in range(cx0, cx1 + 1):
					for i in t.cells.get(Vector2i(cx, cy), []):
						var lo: Vector2 = t.lo[i]
						var hi: Vector2 = t.hi[i]
						if lo.x > e + r or hi.x < e - r or lo.y > n + r or hi.y < n - r:
							continue
						if maxi(floori(lo.x / CELL), cx0) != cx or maxi(floori(lo.y / CELL), cy0) != cy:
							continue  # reported from the first cell it shares with the query
						var rec = t.recs.get(i)
						if rec == null:
							rec = ObstacleShapes.poly(t.polys[i], t.base[i], t.top[i], "a building", true)
							t.recs[i] = rec
						out.append(rec)


## Roof height (m AMSL) of the building containing world (east, north), else -INF.
func top_at(e: float, n: float) -> float:
	var out := []
	near(e, n, 0.0, out)
	var best := -INF
	for rec in out:
		if Geometry2D.is_point_in_polygon(Vector2(e, n), rec.poly):
			best = maxf(best, rec.top)
	return best
