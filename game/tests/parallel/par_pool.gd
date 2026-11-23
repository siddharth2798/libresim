extends RefCounted
## The launcher's worker processes (tests/parallel/run_parallel.gd): starts a headless, muted Godot on one job,
## reads its stdout and stderr without blocking (so a chatty worker never stalls on a full pipe), samples its memory,
## kills it at its timeout, and hands back what it printed when it ends.
## Every worker gets its own empty home under <cache>/homes/<n>: HOME, XDG_*_HOME, APPDATA and LOCALAPPDATA point
## there while it is started, so user:// (saves, options, caches) is fresh per job and never the player's own or
## another worker's. isolate = false keeps the real user folder (TEST_JOBS=1, the reference run).

const _Rss := preload("res://tests/parallel/par_rss.gd")
const HOME_VARS := ["HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "APPDATA", "LOCALAPPDATA"]

var exe := OS.get_executable_path()
var project := ProjectSettings.globalize_path("res://")
var homes := ""
var isolate := true
var running := []  # {job, pid, out, err (pipes), text, etext (chunks read), t0, peak, home}
var _n := 0
var _sampled := 0


func start(job: Dictionary) -> String:
	var args: Array = ["--headless", "--audio-driver", "Dummy", "--path", project, "res://tests/run_tests.tscn", "--"] + job.args
	_n += 1
	var home := homes.path_join(str(_n))
	var saved := {}
	if isolate:
		DirAccess.make_dir_recursive_absolute(home)
		for v in HOME_VARS:
			saved[v] = OS.get_environment(v)
			OS.set_environment(v, home if v == "HOME" else home.path_join(v.to_lower()))
	var info := OS.execute_with_pipe(exe, PackedStringArray(args), false)
	for v in saved:
		if saved[v] == "":
			OS.unset_environment(v)
		else:
			OS.set_environment(v, saved[v])
	if info.is_empty():
		return "could not start %s" % exe
	running.append({"job": job, "pid": int(info.pid), "out": info.stdio, "err": info.stderr, "text": [], "etext": [], "t0": Time.get_ticks_msec(), "peak": 0, "home": home})
	return ""


## Reads what the workers printed; returns the ones that ended: [{job, out, err, code, timed_out, ms, peak, home}].
func poll() -> Array:
	var now := Time.get_ticks_msec()
	if now - _sampled > 1000 and not running.is_empty():
		_sampled = now
		var mem := _Rss.sample(running.map(func(w): return w.pid))
		for w in running:
			w.peak = maxi(w.peak, int(mem.get(w.pid, 0)))
	var ended := []
	for w in running.duplicate():
		_drain(w)
		var alive := OS.is_process_running(w.pid)
		var late: bool = alive and now - w.t0 > int(w.job.timeout)
		if late:
			OS.kill(w.pid)
		if alive and not late:
			continue
		_drain(w)
		running.erase(w)
		ended.append({"job": w.job, "out": _join(w.text), "err": _join(w.etext),
			"code": -1 if late else OS.get_process_exit_code(w.pid), "timed_out": late, "ms": now - w.t0, "peak": w.peak,
			"home": w.home})
	return ended


func peaks_running() -> Array:
	return running.map(func(w): return int(w.job.peak))


func kill_all() -> void:
	for w in running:
		OS.kill(w.pid)


static func _drain(w: Dictionary) -> void:
	for pipe in ["out", "err"]:
		var f: FileAccess = w[pipe]
		var dst := "text" if pipe == "out" else "etext"
		for _i in 64:
			var b := f.get_buffer(1 << 16)
			if b.is_empty():
				break
			(w[dst] as Array).append(b)


static func _join(chunks: Array) -> String:
	var all := PackedByteArray()
	for c in chunks:
		all.append_array(c)
	return all.get_string_from_utf8()
