extends SceneTree
## Parallel test launcher: runs every suite of tests/run_tests.gd SUITES over several headless, muted Godot workers
## and merges what they report into one summary and exit code (0 only when every test passed and no worker printed a
## SCRIPT ERROR, crashed or timed out).
##   godot --headless --audio-driver Dummy --path game -s res://tests/parallel/run_parallel.gd [-- --jobs=N] [--suite=a,b]
##   (tools/test_all.sh does this; TEST_JOBS=N in the environment works like --jobs=N; --suite= / --file= run only
##   those suites, as in run_tests)
## 1. A worker lists every suite and test (run_tests --list); a suite that does not load fails the run.
## 2. par_sizing.gd picks the worker count from this machine (cores, free memory, jobs); par_plan.gd cuts the work
##    into jobs from the timings cache (par_cache.gd), longest first; parted tests are split into parts.
## 3. par_pool.gd keeps that many workers busy, each job in a fresh process with its own empty user folder; a job
##    starts only when the memory budget holds it; a job past its timeout is killed and reported.
## 4. par_merge.gd checks every listed test reported once (a parted test once, from all its parts), leak_check passed
##    in every worker, then prints the FAILs, SCRIPT ERRORs and crashes, and "passed/total passed" as the single run does.
## Logs of every job: <repo>/.cache/tests/logs/. TEST_JOBS=1 runs the plain single process (the reference run).

const _Pool := preload("res://tests/parallel/par_pool.gd")
const _Plan := preload("res://tests/parallel/par_plan.gd")
const _Sizing := preload("res://tests/parallel/par_sizing.gd")
const _Merge := preload("res://tests/parallel/par_merge.gd")
const _Cache := preload("res://tests/parallel/par_cache.gd")
const LIST_TIMEOUT_MS := 300000

var _pool := _Pool.new()
var _cache := {}
var _queue := []
var _done := []
var _expect := []
var _parted := {}  # "<path>::<test>" of the tests that take parts
var _problems := []
var _workers := 1
var _budget := -1
var _override := 0
var _pick := []  # --suite= / --file=: run only those suites (as run_tests does)
var _jobs := 0
var _planned := false
var _t0 := 0
var _quit := -1


func _initialize() -> void:
	Engine.max_fps = 30  # the launcher only polls pipes; leave the cores to the workers
	_t0 = Time.get_ticks_msec()
	_override = int(OS.get_environment("TEST_JOBS")) if OS.get_environment("TEST_JOBS").is_valid_int() else 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--jobs="):
			_override = int(a.substr(7))
		if a.begins_with("--suite=") or a.begins_with("--file="):
			_pick.append(a)
	_cache = _Cache.read()
	_wipe(_Cache.dir().path_join("homes"))
	_wipe(_Cache.dir().path_join("logs"))
	DirAccess.make_dir_recursive_absolute(_Cache.dir().path_join("logs"))
	_pool.homes = _Cache.dir().path_join("homes")
	var err := _pool.start({"key": "list", "label": "listing the suites", "args": ["--list"] + _pick, "timeout": LIST_TIMEOUT_MS,
		"peak": 0, "est": 0})
	if err != "":
		print("test launcher: " + err)
		_quit = 2


func _process(_delta: float) -> bool:
	if _quit >= 0:
		quit(_quit)
		return false
	for e in _pool.poll():
		if e.job.key == "list":
			_plan(e)
		else:
			_ended(e)
	if _quit < 0 and not _queue.is_empty():
		_fill()
	if _quit < 0 and _planned and _queue.is_empty() and _pool.running.is_empty():
		_finish()
	return false


## The --list worker ended: build the expectation, size the workers, plan the queue.
func _plan(e: Dictionary) -> void:
	var listing := []
	var ended := false
	for ln in e.out.split("\n"):
		var f: PackedStringArray = str(ln).strip_edges().split(" ")
		if f.size() == 4 and f[0] == "LIST":
			listing.append({"path": f[1], "test": f[2], "nargs": int(f[3])})
			if int(f[3]) < 0:
				_problems.append("%s: the suite did not load (see %s)" % [f[1], _log_path("list")])
			else:
				_expect.append("%s::%s" % [f[1], f[2]])
			if int(f[3]) == 2:
				_parted["%s::%s" % [f[1], f[2]]] = true
		ended = ended or ln.begins_with("LIST_END")
	_save_log("list", e)
	if not ended or e.timed_out:
		print("test launcher: the listing worker failed (exit %d); see %s" % [e.code, _log_path("list")])
		_quit = 2
		return
	var m := _Sizing.machine()
	var typical := _Sizing.typical_peak(_cache.peaks.values())
	var upper := _Plan.suites_of(listing).size() * 2
	var size := _Sizing.workers(m.cores, m.available, typical, upper, _override)
	_queue = _Plan.build(listing, _cache, size.workers)
	var again := _Sizing.workers(m.cores, m.available, _Sizing.typical_peak(_queue.map(func(j): return int(j.peak))),
		_queue.size(), _override)  # the typical worker is the typical job of this queue, not of a suite
	if again.workers != size.workers:
		_queue = _Plan.build(listing, _cache, again.workers)
	size = again
	if _queue.size() == 1 and _queue[0].key == "all":
		_queue[0].args += _pick
	_workers = mini(size.workers, _queue.size())
	_budget = size.budget
	_jobs = _queue.size()
	_planned = true
	_pool.isolate = _override != 1
	var hint := "timings from %d earlier suite runs" % _cache.suites.size() if not _cache.suites.is_empty() else "no timings yet, using defaults"
	print("libresim tests: %d tests in %d suites, %d jobs on %d workers (%s); %s" % [_expect.size(), _Plan.suites_of(listing).size(),
		_jobs, _workers, size.why, hint])
	var missing := _check_queue(listing)
	if missing != "":
		_problems.append(missing)


## Every suite and every listed test must be in exactly one job (a parted test in all its parts).
func _check_queue(listing: Array) -> String:
	var have := {}
	for j in _queue:
		for k in j.expect:
			have[k] = int(have.get(k, 0)) + (1 if j.part.is_empty() else 0)
			if not j.part.is_empty():
				have[k] = 1
	var lost := _expect.filter(func(k): return int(have.get(k, 0)) != 1)
	return "" if lost.is_empty() else "the queue would skip or repeat %d tests: %s" % [lost.size(), ", ".join(lost.slice(0, 8))]


## Start jobs while there is a free worker and the memory budget holds the next one (longest first).
func _fill() -> void:
	while _pool.running.size() < _workers and not _queue.is_empty():
		var pick := -1
		for i in _queue.size():
			if _Sizing.fits(_pool.peaks_running(), int(_queue[i].peak), _budget):
				pick = i
				break
		if pick < 0:
			return
		var job: Dictionary = _queue.pop_at(pick)
		var err := _pool.start(job)
		if err != "":
			_problems.append("%s: %s" % [job.label, err])


func _ended(e: Dictionary) -> void:
	e.parsed = _Merge.parse(e.out, e.err)
	_done.append(e)
	_save_log(e.job.key, e)
	var fails := 0
	for k in e.parsed.results:
		fails += 0 if e.parsed.results[k].ok else 1
	var state := "TIMEOUT" if e.timed_out else ("CRASH" if e.parsed.summary == "" else ("FAIL" if fails > 0 else "ok"))
	print("  [%3d/%d] %6.1f s  %-7s %s  (%d tests%s)" % [_done.size(), _jobs, e.ms / 1000.0, state, e.job.label,
		e.parsed.results.size(), ", %d failed" % fails if fails > 0 else ""])
	if state == "ok":
		_wipe(e.home)  # a failed job's user folder stays for a look, until the next run


func _finish() -> void:
	var r := _Merge.merge(_expect, _done)
	var engine := {}
	for d in _done:
		for ln in d.parsed.engine:
			engine[ln] = int(engine.get(ln, 0)) + 1
	print("")
	for c in r.coverage:
		print("  parted  " + c)
	if not engine.is_empty():
		print("engine messages (the single run prints them too):")
		for ln in engine:
			print("  %s%s" % [ln, "  (x%d)" % engine[ln] if engine[ln] > 1 else ""])
	for ln in r.errors:
		print(ln)
	for ln in _problems + r.problems:
		print("  PROBLEM  " + ln)
	for ln in r.fails:
		print(ln)
	var ok: bool = r.ok and _problems.is_empty()
	print("%d/%d passed" % [r.passed, r.total])
	print("%s in %.1f s on %d workers; %d SCRIPT ERROR lines; logs in %s" % ["all passed" if ok else "FAILED",
		(Time.get_ticks_msec() - _t0) / 1000.0, _workers, r.errors.size(), _Cache.dir().path_join("logs")])
	_learn()
	_quit = 0 if ok else 1


## Folds this run's timings and memory peaks into the cache for the next run's plan.
func _learn() -> void:
	var parted := {}  # key -> {"ms", "parts": {k: true}, "n", "peak"}
	var overheads := []
	for d in _done:
		if d.timed_out or d.parsed.summary == "":
			continue
		var p: Dictionary = d.parsed
		var sum := 0
		for path in p.suite_ms:
			sum += int(p.suite_ms[path])
		overheads.append(d.ms - sum)
		if not d.job.part.is_empty():
			var pk: String = d.job.part.key
			if not parted.has(pk):
				parted[pk] = {"ms": 0, "parts": {}, "n": d.job.part.n, "peak": 0}
			parted[pk].ms += sum
			parted[pk].parts[d.job.part.k] = true
			parted[pk].peak = maxi(parted[pk].peak, d.peak)
			continue
		for path in p.suite_ms:
			var ms := int(p.suite_ms[path])
			for key in p.results:  # one process over everything (TEST_JOBS=1): a parted test ran whole in its suite
				if _parted.has(key) and key.begins_with(path + "::"):
					ms -= int(p.results[key].ms)
					_Cache.blend(_cache.parted, key, int(p.results[key].ms))
			_Cache.blend(_cache.suites, path, maxi(ms, 1))
			if d.peak > 0 and p.suite_ms.size() == 1:
				_Cache.blend_peak(_cache.peaks, path, d.peak)
			elif d.peak > 0:  # a batch's peak only bounds each of its suites from above: keep the tightest bound
				_cache.peaks[path] = mini(int(_cache.peaks.get(path, d.peak)), d.peak)
	for pk in parted:
		if parted[pk].parts.size() == parted[pk].n:
			_Cache.blend(_cache.parted, pk, parted[pk].ms)
			if parted[pk].peak > 0:
				_Cache.blend_peak(_cache.peaks, pk, parted[pk].peak)
	if not overheads.is_empty():
		overheads.sort()
		_Cache.blend(_cache, "startup_ms", maxi(int(overheads[overheads.size() / 2]), 1))
	_Cache.write(_cache)


func _save_log(key: String, e: Dictionary) -> void:
	var f := FileAccess.open(_log_path(key), FileAccess.WRITE)
	if f != null:
		f.store_string("exit %d, %d ms, peak %d bytes, timed out %s\n--- stdout\n%s\n--- stderr\n%s\n" % [e.code, e.ms,
			e.peak, e.timed_out, e.out, e.err])


func _log_path(key: String) -> String:
	var name := key.replace("res://tests/", "").replace("/", "_").replace(":", "_").replace(",", "+").replace("#", "_")
	return _Cache.dir().path_join("logs").path_join(name.left(120) + ".log")


## Deletes a folder and everything in it (the launcher's own homes and logs under .cache/tests only).
static func _wipe(p: String) -> void:
	var d := DirAccess.open(p)
	if d == null:
		return
	d.include_hidden = true
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_wipe(p.path_join(sub))
	DirAccess.remove_absolute(p)
