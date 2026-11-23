extends RefCounted
## Turns the runner's --list output into the launcher's job queue (tests/parallel/run_parallel.gd).
##   one worker: a single job, the plain runner over every suite (the reference run, parted tests whole);
##   more: every suite once (its parted tests left out), small suites packed into batches in SUITES order (only
##   suites with a measured time; a new one runs alone), and each parted test cut into parts the queue spreads out.
## Sizes come from the timings cache (par_cache.gd) relative to this run: ideal = all the work / workers. A parted test
## gets parts of about a quarter of the ideal (at most 2 per worker, none shorter than 3 worker starts); a batch fills to a
## tenth of the ideal (at least 3 starts, never longer than the longest job). With no history the defaults below
## stand in. The queue is sorted longest first. A job's timeout is 4x its estimate plus a minute (2 min at least),
## or NEW_TIMEOUT_MS without history.
## A job: {key, label, args, suites, expect ("<path>::<test>" it must report), part ({key, k, n} or {}), est, peak,
## timeout}.

const _Sizing := preload("res://tests/parallel/par_sizing.gd")
const DEFAULT_SUITE_MS := 4000
const DEFAULT_PARTED_MS := 300000  # a parted test with no history: assume it is long, so it is cut finely
const DEFAULT_STARTUP_MS := 2000
const MIN_TIMEOUT_MS := 120000
const NEW_TIMEOUT_MS := 900000
const WHOLE_TIMEOUT_MS := 3600000


## listing: [{path, test, nargs}] in runner order (nargs -1: the suite did not load). Returns [{path, plain, parted}].
static func suites_of(listing: Array) -> Array:
	var out := []
	var at := {}
	for t in listing:
		if not at.has(t.path):
			at[t.path] = out.size()
			out.append({"path": t.path, "plain": [], "parted": []})
		if int(t.nargs) == 2:
			out[at[t.path]].parted.append(t.test)
		elif int(t.nargs) >= 0:
			out[at[t.path]].plain.append(t.test)
	return out


static func build(listing: Array, cache: Dictionary, workers: int) -> Array:
	var suites := suites_of(listing)
	var startup := int(cache.get("startup_ms", 0)) if int(cache.get("startup_ms", 0)) > 0 else DEFAULT_STARTUP_MS
	var known_peaks: Array = cache.peaks.values()
	var typical := _Sizing.typical_peak(known_peaks)
	if workers <= 1:
		return [_whole(suites, cache, startup, typical)]
	var work := 0.0
	var longest := 0.0
	for s in suites:
		if not s.plain.is_empty():
			var e := float(cache.suites.get(s.path, DEFAULT_SUITE_MS))
			work += e + startup
			longest = maxf(longest, e)
		for t in s.parted:
			work += float(cache.parted.get(_key(s.path, t), DEFAULT_PARTED_MS))
	var ideal := work / workers
	var jobs := []
	for s in suites:
		for t in s.parted:
			var key := _key(s.path, t)
			var total := float(cache.parted.get(key, DEFAULT_PARTED_MS))
			var n := clampi(ceili(total / maxf(ideal * 0.25, 3.0 * startup)), 1, 2 * workers)
			longest = maxf(longest, total / n)
			for k in n:
				var est := total / n + startup
				jobs.append({"key": "%s#%d/%d" % [key, k, n], "label": "%s %s part %d/%d" % [s.path.get_file(), t, k + 1, n],
					"args": ["--file=" + s.path, "--test=" + t, "--parts=%d/%d" % [k, n], "--mark"], "suites": [s.path],
					"expect": [key], "part": {"key": key, "k": k, "n": n}, "est": est,
					"peak": int(cache.peaks.get(key, typical)), "timeout": _timeout(est, cache.parted.has(key))})
	var target := clampf(ideal / 10.0, 3.0 * startup, maxf(longest, 3.0 * startup))
	var batch := []
	var sum := 0.0
	for s in suites:
		if s.plain.is_empty():
			continue
		var e := float(cache.suites.get(s.path, DEFAULT_SUITE_MS))
		if e >= target or not cache.suites.has(s.path):  # unknown: alone, so the next run knows its time
			jobs.append(_suite_job([s], cache, startup, typical))
			continue
		batch.append(s)
		sum += e
		if sum >= target:
			jobs.append(_suite_job(batch, cache, startup, typical))
			batch = []
			sum = 0.0
	if not batch.is_empty():
		jobs.append(_suite_job(batch, cache, startup, typical))
	jobs.sort_custom(func(a, b): return a.est > b.est)
	return jobs


static func _suite_job(batch: Array, cache: Dictionary, startup: int, typical: int) -> Dictionary:
	var paths := []
	var expect := []
	var est := float(startup)
	var peak := 0
	var known: bool = true
	for s in batch:
		paths.append(s.path)
		for t in s.plain:
			expect.append(_key(s.path, t))
		est += float(cache.suites.get(s.path, DEFAULT_SUITE_MS))
		known = known and cache.suites.has(s.path)
		peak = maxi(peak, int(cache.peaks.get(s.path, typical)))
	var label: String = paths[0].get_file() + ("" if paths.size() == 1 else " +%d more" % (paths.size() - 1))
	return {"key": ",".join(paths), "label": label, "args": ["--file=" + ",".join(paths), "--skip-parted", "--mark"],
		"suites": paths, "expect": expect, "part": {}, "est": est, "peak": peak, "timeout": _timeout(est, known)}


## TEST_JOBS=1: the plain runner over everything, as the reference command runs it.
static func _whole(suites: Array, cache: Dictionary, startup: int, typical: int) -> Dictionary:
	var expect := []
	var paths := []
	var est := float(startup)
	for s in suites:
		paths.append(s.path)
		for t in s.plain + s.parted:
			expect.append(_key(s.path, t))
		est += float(cache.suites.get(s.path, DEFAULT_SUITE_MS))
		for t in s.parted:
			est += float(cache.parted.get(_key(s.path, t), DEFAULT_PARTED_MS))
	var known: bool = not cache.suites.is_empty()
	return {"key": "all", "label": "every suite picked, one process", "args": ["--mark"], "suites": paths, "expect": expect,
		"part": {}, "est": est, "peak": typical, "timeout": maxi(_timeout(est, known), WHOLE_TIMEOUT_MS if not known else 0)}


static func _timeout(est: float, known: bool) -> int:
	return maxi(MIN_TIMEOUT_MS, int(est * 4.0) + 60000) if known else NEW_TIMEOUT_MS


static func _key(path: String, test: String) -> String:
	return "%s::%s" % [path, test]

