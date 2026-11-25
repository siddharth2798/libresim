class_name AirportStream
extends RefCounted
## AirportBuilder's worker: cuts one airport group at a time (AirportCut) with its own terrain height cache, so the
## main thread never waits. start(i), then poll() each frame until it returns the result.

var inflight := -1  # the group being cut, -1 when idle
var _groups: Array
var _task := -1
var _mutex := Mutex.new()
var _result := []
var _cache: TerrainTileCache


func _init(groups: Array) -> void:
	_groups = groups


func start(i: int) -> void:
	if _cache == null:
		_cache = TerrainTileCache.new()
	inflight = i
	_task = WorkerThreadPool.add_task(_cut.bind(i))


func _cut(i: int) -> void:
	var res := AirportCut.cut(_groups[i], _cache)
	_mutex.lock()
	_result = [i, res]
	_mutex.unlock()


## [group, cut] once the running cut has finished (then idle again), else [].
func poll() -> Array:
	if _task < 0 or not WorkerThreadPool.is_task_completed(_task):
		return []
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	inflight = -1
	_mutex.lock()
	var r := _result
	_result = []
	_mutex.unlock()
	return r


func stop() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		inflight = -1
