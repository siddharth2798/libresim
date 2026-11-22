class_name RunwayBakes
extends RefCounted
## Lazy per-runway bakes for AirportBuilder (RunwayBake, world/runway_v2.gdshader `bake_tex`): runways within NEAR_M
## of the camera are baked one at a time, nearest first, without a hitch (the pass is drawn with a normal frame, read
## back on the next, its mipmaps built on a worker thread); runways beyond FAR_M give their texture back, so memory
## stays bounded (~10 MB a long runway). Until a bake is ready a runway draws runway_v2's cheap unbaked look; the
## bake then fades in over FADE_S (bake_mix), so nothing pops. Headless nothing is baked.

const NEAR_M := 15000.0
const FAR_M := 20000.0
const FADE_S := 1.0

var _host: Node
var _items: Array = []  # {mat, r, u, enu (Vector2 midpoint), tex, mix}
var _job := {}  # the pass being drawn: {item, pass, frames}
var _mips := {}  # mipmaps being built: {item, img, task}


func _init(host: Node) -> void:
	_host = host


## A runway's material to bake (u: its RunwayMarkings.uniforms).
func add(mat: ShaderMaterial, r: Dictionary, u: Dictionary) -> void:
	var a := Vector2(r.ends[0].x, r.ends[0].y)
	var b := Vector2(r.ends[1].x, r.ends[1].y)
	_items.append({"mat": mat, "r": r, "u": u, "enu": (a + b) * 0.5, "tex": null, "mix": 0.0})


## Runways holding a bake now.
func baked_count() -> int:
	return _items.filter(func(it): return it.tex != null).size()


## What to do this frame: {bake: index of the nearest unbaked runway within NEAR_M (-1 none or one is in progress),
## free: indices of baked runways beyond FAR_M}. dists: metres from the camera; baked: has a texture; busy: a bake
## is in progress.
static func plan(dists: Array, baked: Array, busy: bool) -> Dictionary:
	var best := -1
	var free := []
	for i in dists.size():
		if baked[i]:
			if dists[i] > FAR_M:
				free.append(i)
		elif not busy and dists[i] < NEAR_M and (best < 0 or dists[i] < dists[best]):
			best = i
	return {"bake": best, "free": free}


## Once a frame. cam: camera position (ENU metres).
func step(cam: Vector2, dt: float) -> void:
	for it in _items:  # fade finished bakes in
		if it.tex != null and it.mix < 1.0:
			it.mix = minf(it.mix + dt / FADE_S, 1.0)
			it.mat.set_shader_parameter("bake_mix", it.mix)
	if not _job.is_empty():
		_job.frames += 1
		if _job.frames >= 2:  # drawn with the previous frame
			var img := RunwayBake.read(_job.pass)
			if img != null:
				_mips = {"item": _job.item, "img": img, "task": WorkerThreadPool.add_task(img.generate_mipmaps)}
			_job = {}
	if not _mips.is_empty() and WorkerThreadPool.is_task_completed(_mips.task):
		WorkerThreadPool.wait_for_task_completion(_mips.task)
		var it: Dictionary = _mips.item
		it.tex = ImageTexture.create_from_image(_mips.img)
		it.mix = 0.0
		it.mat.set_shader_parameter("bake_tex", it.tex)
		_mips = {}
	var dists := []
	var baked := []
	for it in _items:
		dists.append(cam.distance_to(it.enu))
		baked.append(it.tex != null)
	var p := plan(dists, baked, not _job.is_empty() or not _mips.is_empty())
	for i in p.free:
		var it: Dictionary = _items[i]
		it.tex = null
		it.mix = 0.0
		it.mat.set_shader_parameter("bake_mix", 0.0)
		it.mat.set_shader_parameter("bake_tex", null)
	if p.bake >= 0:
		var it: Dictionary = _items[p.bake]
		var job := RunwayBake.begin(it.r, it.u, _host)
		if not job.is_empty():
			_job = {"item": it, "pass": job, "frames": 0}


## Drops a pass in progress (the builder leaves the tree).
func stop() -> void:
	RunwayBake.cancel(_job.get("pass", {}))
	_job = {}
	if not _mips.is_empty():
		WorkerThreadPool.wait_for_task_completion(_mips.task)
		_mips = {}
