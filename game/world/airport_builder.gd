class_name AirportBuilder
extends Node3D
## Builds runway and taxiway surfaces from data/processed/runways.json
## (tools/09_runways.py). Each surface is a strip mesh draped on the terrain triangles (GroundDrape: at the
## FDM's ground height, no lift; the shaders win the depth test), anchored at a lattice point near its first
## point and re-positioned when the floating origin shifts. The meshes are cut on a worker thread (~1 s for
## every airport, with its own height cache) and appear as they finish; data is there at once.


var terrain: TerrainQuadtree
var data: Dictionary
var _items: Array = []  # [MeshInstance3D, anchor ENU Vector3]
var _jobs: Array = []  # [pts Array[Vector2], width, kind (0 runway, 1 taxiway, 2 lead-on), length]
var _done: Array = []  # [job, arrays, anchor] from the worker
var _mutex := Mutex.new()
var _task := -1
var _shader := preload("res://world/runway.gdshader")
var _taxi_shader := preload("res://world/taxiway.gdshader")  # fades out when a few px wide
var _lead_shader := preload("res://world/lead_on.gdshader")  # yellow line only, drawn over a runway


## wait: cut the meshes now, on this thread (tests); else on a worker, added by _process.
func build(t: TerrainQuadtree, wait := false) -> void:
	terrain = t
	data = Paths.load_json("runways.json")
	if data == null:
		return
	for r in data.runways:
		var a: Dictionary = r.ends[0]
		var b: Dictionary = r.ends[1]
		_jobs.append([[Vector2(a.x, a.y), Vector2(b.x, b.y)], float(r.width), 0, float(r.length)])
	for tw in data.taxiways:
		var pts: Array[Vector2] = []
		for p in tw.pts:
			pts.append(Vector2(p[0], p[1]))
		_jobs.append([pts, minf(tw.width, 23.0), 1, 0.0])
	_lead_ons()
	FloatingOrigin.shifted.connect(func(_d): _reposition())
	if wait:
		_work(t.cache)
		_flush()
	else:
		_task = WorkerThreadPool.add_task(_work.bind(TerrainTileCache.new()))


## True while the runway and taxiway meshes are still being cut.
func busy() -> bool:
	return _task >= 0


## 0..1 of those meshes on the scene. Stays short of 1 until the worker has finished.
func progress() -> float:
	if _task < 0:
		return 1.0
	if _jobs.is_empty():
		return 0.0
	return clampf(float(_items.size()) / float(_jobs.size()), 0.0, 0.99)


func _process(_dt: float) -> void:
	if _task >= 0:
		_flush()
		if WorkerThreadPool.is_task_completed(_task):
			WorkerThreadPool.wait_for_task_completion(_task)
			_task = -1
			_flush()


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## Worker: drapes every job on the terrain of cache (used by this thread only).
func _work(cache: TerrainTileCache) -> void:
	var res := cache.tmeta.tile_size_m / cache.tile_n
	for j in _jobs:
		var pts: Array = j[0]
		if pts.size() < 2:
			continue
		var o := GroundDrape.snap(pts[0].x, pts[0].y, res)
		var anchor := Vector3(o.x, o.y, cache.height_at(pts[0].x, pts[0].y))
		var local: Array = []
		for p in pts:
			local.append(Vector2(p.x - o.x, p.y - o.y))
		var tris := PackedVector2Array()
		var uvs := PackedVector2Array()
		var along := GroundDrape.strip(local, j[1], tris, uvs)
		var arr := GroundDrape.arrays(tris, uvs, anchor.x, anchor.y, anchor.z, cache.height_at, res)
		if not arr.is_empty():
			_mutex.lock()
			_done.append([j, arr, anchor, along])
			_mutex.unlock()


## Main thread: meshes for the finished jobs.
func _flush() -> void:
	_mutex.lock()
	var batch := _done
	_done = []
	_mutex.unlock()
	for d in batch:
		var j: Array = d[0]
		var kind: int = j[2]
		var mat := ShaderMaterial.new()
		mat.shader = [_shader, _taxi_shader, _lead_shader][kind]
		mat.set_shader_parameter("is_runway", kind == 0)
		mat.set_shader_parameter("length_m", d[3] if kind != 0 else j[3])
		mat.set_shader_parameter("width_m", j[1])
		var mi := MeshInstance3D.new()
		mi.mesh = GroundDrape.to_mesh(d[1])
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.position = FloatingOrigin.to_render(d[2])
		_items.append([mi, d[2]])


## OSM taxiways end on the runway centre line, but the runway surface hides that last stretch: draw
## the yellow lead-on line over the runway (the part of each taxiway inside a runway strip).
func _lead_ons() -> void:
	for r in data.runways:
		var a := Vector2(r.ends[0].x, r.ends[0].y)
		var b := Vector2(r.ends[1].x, r.ends[1].y)
		var u := (b - a).normalized()
		var hw := float(r.width) * 0.5
		var length := a.distance_to(b)
		for tw in data.taxiways:
			var run: Array[Vector2] = []
			var prev := Vector2.INF
			for p in tw.pts:
				var v := Vector2(p[0], p[1])
				var along := (v - a).dot(u)
				if absf((v - a).cross(u)) < hw + 0.5 and along > -2.0 and along < length + 2.0:
					if run.is_empty() and prev != Vector2.INF:
						run.append(prev)  # the last point outside: the line enters the runway from there
					run.append(v)
				elif not run.is_empty():
					run.append(v)  # first point past the strip: the line crosses it
					break
				prev = v
			if run.size() >= 2:
				_jobs.append([run, 1.0, 2, 0.0])


func _reposition() -> void:
	for it in _items:
		(it[0] as MeshInstance3D).position = FloatingOrigin.to_render(it[1])


## Start position on a runway: returns {pos: Vector2 ENU, heading_deg} or {}.
func runway_start(airport: String, ident: String) -> Dictionary:
	if data == null:
		return {}
	var rwys: Array = data.runways.filter(func(r): return r.airport == airport)
	rwys.sort_custom(func(a, b): return a.length > b.length)  # default: longest runway
	for r in rwys:
		for i in 2:
			var e: Dictionary = r.ends[i]
			if ident == "" or e.ident == ident:
				var hd := deg_to_rad(float(e.heading_true))
				var fwd := Vector2(sin(hd), cos(hd))
				var p := Vector2(e.x, e.y) + fwd * 25.0
				return {"pos": p, "heading_deg": float(e.heading_true), "ident": e.ident}
	return {}
