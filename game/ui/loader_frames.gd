class_name LoaderFrames
extends RefCounted
## The loader film's frames as shipped: the JPGs themselves (import "keep", tools/shoot_loader_films.sh), read as bytes
## and decoded on a worker (WorkerThreadPool) one frame ahead, so the main thread only uploads a decoded image. The
## lossless textures they used to import as were 484 MB for 720 frames and decoded on the main thread at 24 fps;
## the JPGs are 73 MB and the film keeps its pace while the flight scene loads.

static var _counts := {}  # dir -> number of frames (000.jpg, 001.jpg, ...)

var _task := -1
var _key := ""
var _out := {}
var _orphans: Array = []  # decodes nobody wants any more: released once done


static func path(dir: String, i: int) -> String:
	return "%s/%03d.jpg" % [dir, i]


static func count(dir: String) -> int:
	if not _counts.has(dir):
		var n := 0
		while FileAccess.file_exists(path(dir, n)):
			n += 1
		_counts[dir] = n
	return _counts[dir]


## Decode one frame on this thread (null if it cannot be read).
static func decode(file: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(file)
	if bytes.is_empty():
		return null
	var img := Image.new()
	return img if img.load_jpg_from_buffer(bytes) == OK else null


static func _decode_into(file: String, out: Dictionary) -> void:
	out.img = decode(file)


## Start decoding `file` on a worker (a different file in flight is dropped).
func prefetch(file: String) -> void:
	_drain()
	if file == _key and _task >= 0:
		return
	_drop()
	_key = file
	_out = {}
	_task = WorkerThreadPool.add_task(_decode_into.bind(file, _out), false, "loader frame")


## The decoded image of `file` once its worker is done, else null (not started, still decoding, or another file).
func take(file: String) -> Image:
	if _task < 0 or file != _key or not WorkerThreadPool.is_task_completed(_task):
		return null
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	_key = ""
	return _out.get("img")


## Wait for every decode still running (the film is leaving the tree).
func release() -> void:
	_drop()
	for t in _orphans:
		WorkerThreadPool.wait_for_task_completion(t)
	_orphans.clear()


func _drop() -> void:
	if _task >= 0:
		_orphans.append(_task)
	_task = -1
	_key = ""


func _drain() -> void:
	for i in range(_orphans.size() - 1, -1, -1):
		if WorkerThreadPool.is_task_completed(_orphans[i]):
			WorkerThreadPool.wait_for_task_completion(_orphans[i])
			_orphans.remove_at(i)
