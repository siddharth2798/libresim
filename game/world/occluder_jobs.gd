class_name OccluderJobs
extends RefCounted
## Builds occluders (OccluderBuild) for loaded models on worker threads and attaches them when done: an
## OccluderInstance3D child of the model root, in the root's frame, so it moves with the model (FloatingOrigin shifts
## included). A model freed before its job finishes simply gets nothing. --no-occlusion skips them altogether.

var _jobs := {}  # key -> {"task": int, "root": WeakRef, "out": Array, "ready": bool}
var _mutex := Mutex.new()


## Start a job for root (in or out of the tree); its triangles are read now, on the calling thread.
func start(key: String, root: Node3D) -> void:
	if OcclusionRules.disabled:
		return
	stop(key)
	var faces := OccluderBuild.faces_under(root)
	var job := {"root": weakref(root), "out": [], "ready": false}
	job.task = WorkerThreadPool.add_task(func():
		var arrays := OccluderBuild.build(faces)
		_mutex.lock()
		job.out = arrays
		job.ready = true
		_mutex.unlock())
	_jobs[key] = job


## Main thread, every frame or so: attach finished occluders.
func poll() -> void:
	for key in _jobs.keys():
		var job: Dictionary = _jobs[key]
		_mutex.lock()
		var ready: bool = job.ready
		_mutex.unlock()
		if not ready:
			continue
		WorkerThreadPool.wait_for_task_completion(job.task)
		_jobs.erase(key)
		var root := job.root.get_ref() as Node3D
		var oi := OccluderBuild.instance(job.out, "Occluder")
		if root != null and oi != null:
			root.add_child(oi)


## Forget a job (its model is going); waits for a running task so nothing outlives the caller.
func stop(key: String) -> void:
	if _jobs.has(key):
		WorkerThreadPool.wait_for_task_completion(_jobs[key].task)
		_jobs.erase(key)


func stop_all() -> void:
	for key in _jobs.keys():
		stop(key)


func pending() -> int:
	return _jobs.size()
