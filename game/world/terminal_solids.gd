class_name TerminalSolids
extends RefCounted
## Collision for a landmark terminal model (Terminals): when the model loads, its triangles go to
## a worker thread (SolidGrid.build, tens of thousands of samples) and the finished raster is
## registered in ObstacleRegistry under "terminal:<ICAO>"; unloading the model removes it.
## What the pilot sees is what stops the aircraft; the OSM footprints behind the model are
## dropped from the building collision (BuildingCollision).

const LABEL := "the terminal"

var _jobs := {}  # icao -> {"task": int, "ready": bool, "rec": Dictionary}
var _mutex := Mutex.new()


## Main thread. root: the model's scene root (identity transform), origin: ENU (east, north, ground m).
func start(icao: String, root: Node3D, origin: Vector3) -> void:
	stop(icao)
	var verts := PackedVector3Array()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var t := Transform3D.IDENTITY  # mesh -> model root
		var nd: Node = m
		while nd != root and nd is Node3D:
			t = (nd as Node3D).transform * t
			nd = nd.get_parent()
		for v in m.mesh.get_faces():
			var g: Vector3 = t * v  # glTF axes: x east, y up, z -north
			verts.append(Vector3(origin.x + g.x, origin.y - g.z, origin.z + g.y))
	var job := {"ready": false, "rec": {}}
	job.task = WorkerThreadPool.add_task(func():
		var rec := SolidGrid.build(verts, origin.z, LABEL)
		_mutex.lock()
		job.rec = rec
		job.ready = true
		_mutex.unlock())
	_jobs[icao] = job


## Main thread: register rasters that finished.
func poll() -> void:
	for icao in _jobs:
		var job: Dictionary = _jobs[icao]
		_mutex.lock()
		var ready: bool = job.ready
		_mutex.unlock()
		if ready and not job.has("done"):
			WorkerThreadPool.wait_for_task_completion(job.task)
			job.done = true
			if not job.rec.is_empty():
				ObstacleRegistry.add("terminal:" + icao, job.rec)


func stop(icao: String) -> void:
	if _jobs.has(icao):
		if not _jobs[icao].has("done"):
			WorkerThreadPool.wait_for_task_completion(_jobs[icao].task)
		_jobs.erase(icao)
	ObstacleRegistry.remove_group("terminal:" + icao)


func stop_all() -> void:
	for icao in _jobs.keys():
		stop(icao)
