class_name CorridorBook
extends RefCounted
## Which airports of the flight have their corridors (OpsCorridors) in ObstacleRegistry, registered lazily: planning
## the pushback swing of every stand of every airport took about 3 s of the load (VABB alone over 1 s). AirportOps
## sets the book up and asks for the start airport; then, once a second (and at once after a jump of the aircraft):
##   aircraft within SYNC_M of an airport  -> registered now, on this thread (it may be on that airport's pavement);
##   aircraft or camera within LAZY_M      -> planned on a worker (WorkerThreadPool), the boxes added when it is done.
## Whoever needs an airport's corridors calls ensure() (AirportOps before it dresses an airport) or is_ready() /
## request() (RunwayLights waits with an airport's floodlight masts). Positions are world ENU (east, north): the
## floating origin never moves an airport. Corridors stay registered until reset() (the flight scene leaves).

const SYNC_M := 2000.0
const LAZY_M := 15000.0

static var _sites := {}  # icao -> {"ops": Dictionary, "runways": Array, "rect": Rect2 (world ENU)}
static var _ready := {}  # icao -> true: boxes in the registry
static var _jobs := {}  # icao -> {"task": int, "out": Dictionary}: planned on a worker
static var _orphans: Array = []  # worker tasks of a book that was reset: waited for (released) once done
static var _def: AircraftDef  # the aircraft the corridors are sized for


## ops: airport_ops.json; runways: icao -> its runways.json entries. Every airport in either is a site.
static func setup(ops: Dictionary, runways: Dictionary, def: AircraftDef = null) -> void:
	reset()
	_def = def
	for icao in ops.keys() + runways.keys():
		if _sites.has(icao):
			continue
		var a: Dictionary = ops.get(icao, {})
		var rws: Array = runways.get(icao, [])
		_sites[icao] = {"ops": a, "runways": rws, "rect": _extent(a, rws)}


## Forget every site; the registered corridors leave the registry. A plan still running is left to finish.
static func reset() -> void:
	for icao in _jobs:
		_orphans.append(_jobs[icao].task)
	_jobs.clear()
	for icao in _ready:
		OpsCorridors.unregister(icao)
	_ready.clear()
	_sites.clear()
	_drain()


static func has_site(icao: String) -> bool:
	return _sites.has(icao)


## True once the airport's corridors are in, and for an airport the book does not know (nothing to wait for).
static func is_ready(icao: String) -> bool:
	return _ready.has(icao) or not _sites.has(icao)


static func registered() -> Array:
	return _ready.keys()


static func pending() -> Array:
	return _jobs.keys()


## The airport's corridors, now: waits for its worker if one is planning it, else plans it on this thread.
static func ensure(icao: String) -> void:
	if is_ready(icao):
		return
	if _jobs.has(icao):
		WorkerThreadPool.wait_for_task_completion(_jobs[icao].task)
		_finish(icao)
		return
	OpsCorridors.unregister(icao)
	CorridorPlan.insert(icao, CorridorPlan.compute(_job(icao)))
	_ready[icao] = true


## Plan the airport on a worker (nothing if it is in or already being planned).
static func request(icao: String) -> void:
	if is_ready(icao) or _jobs.has(icao):
		return
	var out := {}
	var task := WorkerThreadPool.add_task(CorridorPlan.compute_into.bind(_job(icao), out), false, "corridors " + icao)
	_jobs[icao] = {"task": task, "out": out}


## Every frame: plans that are done go into the registry.
static func poll() -> void:
	for icao in _jobs.keys():
		if WorkerThreadPool.is_task_completed(_jobs[icao].task):
			WorkerThreadPool.wait_for_task_completion(_jobs[icao].task)
			_finish(icao)
	_drain()


## sync_at: the aircraft (world ENU east, north); near: more points (the camera) that only start plans on a worker.
static func update(sync_at: Variant, near: Array = []) -> void:
	for icao in _sites:
		if _ready.has(icao):
			continue
		var r: Rect2 = _sites[icao].rect
		if sync_at is Vector2 and dist(r, sync_at) < SYNC_M:
			ensure(icao)
			continue
		var d := dist(r, sync_at) if sync_at is Vector2 else INF
		for p in near:
			d = minf(d, dist(r, p))
		if d < LAZY_M:
			request(icao)


## Distance (m) from p to the airport's extent (0 inside it).
static func dist(r: Rect2, p: Vector2) -> float:
	return Vector2(maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0), maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)).length()


## The nearest site to p ("" if there is none).
static func nearest(p: Vector2) -> String:
	var best := ""
	var bd := INF
	for icao in _sites:
		var d := dist(_sites[icao].rect, p)
		if d < bd:
			bd = d
			best = icao
	return best


static func _job(icao: String) -> Dictionary:
	var s: Dictionary = _sites[icao]
	return CorridorPlan.job(icao, s.ops, s.runways, _def)


static func _finish(icao: String) -> void:
	var out: Dictionary = _jobs[icao].out
	_jobs.erase(icao)
	OpsCorridors.unregister(icao)
	CorridorPlan.insert(icao, out.get("boxes", PackedFloat64Array()))
	_ready[icao] = true


static func _drain() -> void:
	for i in range(_orphans.size() - 1, -1, -1):
		if WorkerThreadPool.is_task_completed(_orphans[i]):
			WorkerThreadPool.wait_for_task_completion(_orphans[i])
			_orphans.remove_at(i)


## World ENU box around the stands, taxi nodes and runway ends.
static func _extent(ops: Dictionary, runways: Array) -> Rect2:
	var pts := PackedVector2Array()
	for s in ops.get("stands", []):
		pts.append(Vector2(s.x, s.y))
	for n in ops.get("taxi", {}).get("nodes", {}).values():
		pts.append(Vector2(n[0], n[1]))
	for r in runways:
		for e in r.ends:
			pts.append(Vector2(e.x, e.y))
	if pts.is_empty():
		return Rect2(Vector2(INF, INF), Vector2.ZERO)
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r
