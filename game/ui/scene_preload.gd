class_name ScenePreload
extends RefCounted
## The flight scene and the chosen aircraft's models load in the background (ResourceLoader.load_threaded_request)
## from the moment the Free flight setup opens or an aircraft is picked, so "Fly" does not freeze the loader film
## while they load. BusyOverlay waits for them with the film playing, then changes scene with the loaded PackedScene;
## AircraftModel and Cockpit take their glbs from here. Anything not preloaded, or that failed, loads the normal way.
##   begin(id)   start (or keep) the loads for aircraft `id`; another aircraft's loads are dropped.
##   take(path)  the loaded resource (waits if its load is still running), or null: the caller then load()s it.

const FLIGHT := "res://world/flight.tscn"
const MODEL_FILES := ["exterior", "interior", "door_model"]  # aircraft.json "files" a flight loads as scenes

static var enabled := DisplayServer.get_name() != "headless"  # tests switch it on; headless runs load straight
static var _paths := {}  # path -> true: requested and not taken yet
static var _aircraft := ""


## Start loading the flight scene and aircraft `id`'s models (nothing new if they are already loading).
static func begin(id: String) -> void:
	if not enabled:
		return
	if id != _aircraft:
		_drop_models()
		_aircraft = id
	_request(FLIGHT)
	var def := AircraftDef.load_def(id) if id != "" else null
	if def == null:
		return
	for f in MODEL_FILES:
		if def.has_file(f):
			_request(def.path(f))


## Everything begin() asked for that is still loading.
static func busy() -> bool:
	for p in _paths:
		if ResourceLoader.load_threaded_get_status(p) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return true
	return false


## 0..1 over everything begin() asked for (for a status line).
static func progress() -> float:
	if _paths.is_empty():
		return 1.0
	var sum := 0.0
	for p in _paths:
		var pr := []
		var st := ResourceLoader.load_threaded_get_status(p, pr)
		sum += 1.0 if st != ResourceLoader.THREAD_LOAD_IN_PROGRESS else (float(pr[0]) if not pr.is_empty() else 0.0)
	return sum / _paths.size()


static func requested(path: String) -> bool:
	return _paths.has(path)


## The preloaded resource at `path`, or null (not preloaded, or its load failed). A load still running is waited for.
static func take(path: String) -> Resource:
	if not _paths.has(path):
		return null
	_paths.erase(path)
	var st := ResourceLoader.load_threaded_get_status(path)
	if st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE or st == ResourceLoader.THREAD_LOAD_FAILED:
		if st == ResourceLoader.THREAD_LOAD_FAILED:
			ResourceLoader.load_threaded_get(path)  # releases the failed request
		return null
	return ResourceLoader.load_threaded_get(path)


## The scene at `path`: the preloaded one if there is one, else loaded now (the normal load).
static func scene(path: String) -> PackedScene:
	var r := take(path)
	return (r if r != null else load(path)) as PackedScene


## Drop every preload that was not taken (the menu is back, a test is done). Their loads finish and are released.
static func clear() -> void:
	_drop_models()
	_drop(FLIGHT)
	_aircraft = ""


static func _request(path: String) -> void:
	if _paths.has(path) or not ResourceLoader.exists(path):
		return
	if ResourceLoader.load_threaded_request(path, "", true) == OK:
		_paths[path] = true


static func _drop_models() -> void:
	for p in _paths.keys():
		if p != FLIGHT:
			_drop(p)


## A request nobody will take: load_threaded_get frees it (waiting for it if it is still loading would block, so a
## running one is fetched on a later frame).
static func _drop(path: String) -> void:
	if not _paths.has(path):
		return
	_paths.erase(path)
	if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		_late_drop.call_deferred(path)
	else:
		ResourceLoader.load_threaded_get(path)


static func _late_drop(path: String) -> void:
	if _paths.has(path):
		return  # asked for again meanwhile: it is wanted after all
	if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			tree.create_timer(0.2).timeout.connect(_late_drop.bind(path))
		return
	if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		ResourceLoader.load_threaded_get(path)
