extends RefCounted
## The parallel test launcher (tests/parallel/): worker sizing, the job queue, merging the workers' output.
## The queue must hold every suite of run_tests.gd SUITES and every test in it exactly once, or the launcher would
## skip tests silently.

const Sizing := preload("res://tests/parallel/par_sizing.gd")
const Plan := preload("res://tests/parallel/par_plan.gd")
const Merge := preload("res://tests/parallel/par_merge.gd")
const Cache := preload("res://tests/parallel/par_cache.gd")
const Rss := preload("res://tests/parallel/par_rss.gd")
const Runner := preload("res://tests/run_tests.gd")
const GB := 1024 * 1024 * 1024


func test_workers_follow_the_machine_not_a_constant() -> String:
	var bad := []
	var c := func(cores, avail, peak, jobs, over, want):
		var w: int = Sizing.workers(cores, avail, peak, jobs, over).workers
		if w != want:
			bad.append("%d cores %.1f GB peak %.2f GB %d jobs TEST_JOBS=%d -> %d, want %d" % [cores, float(avail) / GB, float(peak) / GB, jobs, over, w, want])
	c.call(10, 16 * GB, GB / 4, 100, 0, 9)  # one core left free
	c.call(2, 8 * GB, GB / 4, 100, 0, 1)  # 2-core CI box
	c.call(1, 8 * GB, GB / 4, 100, 0, 1)
	c.call(8, 3 * GB, GB, 100, 0, 2)  # 8 GB laptop with 3 GB free: memory caps it
	c.call(64, 256 * GB, GB / 4, 100, 0, 63)
	c.call(64, 256 * GB, GB / 4, 5, 0, 5)  # never more workers than jobs
	c.call(10, -1, GB, 100, 0, 9)  # memory unknown: cores only
	c.call(10, GB / 4, GB, 100, 0, 1)  # almost no memory: still one
	c.call(10, 16 * GB, GB / 4, 100, 1, 1)  # TEST_JOBS=1
	c.call(4, 16 * GB, GB / 4, 100, 12, 12)  # TEST_JOBS wins over the cores
	return "; ".join(bad)


func test_memory_budget_gates_heavy_jobs() -> String:
	if not Sizing.fits([], 10 * GB, GB):
		return "a job must start when nothing runs, however big"
	if Sizing.fits([GB, GB], GB, 2 * GB):
		return "three 1 GB jobs fit a 2 GB budget"
	if not Sizing.fits([GB / 2], GB, 2 * GB) or not Sizing.fits([GB, GB, GB], GB, -1):
		return "fitting jobs refused"
	if Sizing.typical_peak([]) != Sizing.DEFAULT_PEAK or Sizing.typical_peak([1, 2, 3, 4]) != 4:
		return "typical peak %d / %d" % [Sizing.typical_peak([]), Sizing.typical_peak([1, 2, 3, 4])]
	return ""


func test_queue_holds_every_suite_and_test_once() -> String:
	var listing := _listing()
	if listing.is_empty():
		return "no suites listed"
	var want := {}
	for t in listing:
		want["%s::%s" % [t.path, t.test]] = true
	var hist := Cache.empty()
	for t in listing:
		hist.suites[t.path] = 300 + (t.path.length() * 37) % 9000  # some history so small suites are batched
	for cache in [Cache.empty(), hist]:
		for workers in [1, 2, 3, 9, 64]:
			var err := _covers(Plan.build(listing, cache, workers), want, listing, workers)
			if err != "":
				return "%d workers, %s: %s" % [workers, "history" if not cache.suites.is_empty() else "no history", err]
	return ""


func test_queue_runs_longest_first_and_cuts_parted_tests() -> String:
	var listing := [{"path": "a.gd", "test": "test_a", "nargs": 0}, {"path": "b.gd", "test": "test_b", "nargs": 0},
		{"path": "b.gd", "test": "test_big", "nargs": 2}, {"path": "c.gd", "test": "test_c", "nargs": 0}]
	var cache := Cache.empty()
	cache.suites = {"a.gd": 1000, "b.gd": 60000, "c.gd": 1500}
	cache.parted = {"b.gd::test_big": 400000}
	cache.startup_ms = 1000
	var jobs := Plan.build(listing, cache, 8)
	for i in jobs.size() - 1:
		if jobs[i].est < jobs[i + 1].est:
			return "not longest first: %s" % jobs.map(func(j): return j.label)
	var parts := jobs.filter(func(j): return not j.part.is_empty())
	if parts.size() < 2 or parts.size() > 16 or "--skip-parted" in parts[0].args:
		return "parted test in %d parts" % parts.size()
	if jobs.size() != parts.size() + 2:  # b alone (long), a and c batched together
		return "jobs %s" % jobs.map(func(j): return j.label)
	if Plan.build(listing, cache, 1).size() != 1 or Plan.build(listing, cache, 1)[0].args != ["--mark"]:
		return "one worker must run the plain single process"
	return ""


func test_merge_reports_failures_crashes_and_skipped_tests() -> String:
	var out := "SUITE s.gd\n  PASS  test_a  (5 ms)\n  FAIL  test_b: boom: detail\nSUITE_END s.gd 40\n  PASS  leak_check: ok\n1/3 passed\n"
	var p := Merge.parse(out, "SCRIPT ERROR: oops\nWARNING: fine\n")
	if p.results.size() != 2 or p.results["s.gd::test_b"].msg != "boom: detail" or p.errors.size() != 1 or p.engine.size() != 1 or p.suite_ms["s.gd"] != 40:
		return "parse %s" % p
	var job := {"label": "s.gd", "part": {}, "est": 1000}
	var ok := Merge.merge(["s.gd::test_a"], [{"job": job, "parsed": Merge.parse(out.replace("  FAIL  test_b: boom: detail\n", ""), ""), "code": 0, "timed_out": false, "ms": 50}])
	if not ok.ok or ok.passed != 2 or ok.total != 2:
		return "clean merge %s" % ok
	var r := Merge.merge(["s.gd::test_a", "s.gd::test_b", "s.gd::test_c"], [{"job": job, "parsed": p, "code": 1, "timed_out": false, "ms": 50}])
	if r.ok or r.passed != 2 or r.fails.size() != 2 or not str(r.fails).contains("not run") or r.errors.size() != 1:
		return "merge %s" % r
	var crash := Merge.merge(["s.gd::test_a"], [{"job": job, "parsed": Merge.parse("SUITE s.gd\n", ""), "code": 139, "timed_out": false, "ms": 50}])
	if crash.ok or not str(crash.problems).contains("CRASH") or not str(crash.fails).contains("leak_check"):
		return "crash %s" % crash
	var hang := Merge.merge(["s.gd::test_a"], [{"job": job, "parsed": Merge.parse("", ""), "code": -1, "timed_out": true, "ms": 9000}])
	if hang.ok or not str(hang.problems).contains("TIMEOUT"):
		return "timeout %s" % hang
	return ""


func test_merge_joins_the_parts_of_a_parted_test() -> String:
	var key := "p.gd::test_all"
	var line := "    pushback every stand: part %d/2 covered %d of 10 stand-aircraft pairs, %d of 6 with a strip behind\n"
	var done := []
	for k in 2:
		var out := "SUITE p.gd\n" + line % [k, 5, 3] + "  PASS  test_all  (9 ms)\nSUITE_END p.gd 9\n  PASS  leak_check: ok\n1/2 passed\n"
		done.append({"job": {"label": "part", "part": {"key": key, "k": k, "n": 2}, "est": 9}, "parsed": Merge.parse(out, ""), "code": 0, "timed_out": false, "ms": 9})
	var r := Merge.merge([key], done)
	if not r.ok or r.total != 2 or r.passed != 2:
		return "two parts %s" % r
	var lost := Merge.merge([key], done.slice(0, 1))
	if lost.ok or not str(lost.coverage).contains("MISMATCH"):
		return "one part of two passed as the whole test: %s" % lost
	return ""


func test_memory_samples_parse_on_each_os() -> String:
	var ps := Rss.parse_ps(" 101 204800\n 102  1024\n 999 5\n", [101, 102])
	var tl := Rss.parse_tasklist("\"Godot.exe\",\"101\",\"Console\",\"1\",\"204,800 K\"\n\"x.exe\",\"7\",\"Console\",\"1\",\"5 K\"", [101])
	if ps.get(101) != 204800 * 1024 or ps.get(102) != 1024 * 1024 or ps.has(999) or tl.get(101) != 204800 * 1024 or tl.has(7):
		return "ps %s tasklist %s" % [ps, tl]
	return ""


## Suites run in another order (or alone) under the launcher, so a test must put back what it changed. The exhaust
## plume test used to put an engine property that was never set back as null, and a later Props.get_b on it raised a
## SCRIPT ERROR in whichever suite came next.
func test_post_fx_puts_unset_engine_properties_back_unset() -> String:
	var keys := []
	for i in 8:
		keys.append_array(["engines/%d/running" % (i + 1), "engines/%d/egt_k" % (i + 1)])
	var before := {}
	for k in keys:
		if Props.has(k):
			before[k] = Props.get_v(k)
		Props._p.erase(k)
	var suite: Node = load("res://tests/test_post_fx.gd").new()
	(Engine.get_main_loop() as SceneTree).root.add_child(suite)
	var err: String = suite.test_post_fx_exhaust_plumes_follow_engines()
	suite.teardown()
	suite.free()
	var left := keys.filter(func(k): return Props.has(k))
	for k in keys:
		Props._p.erase(k)
		if before.has(k):
			Props.set_v(k, before[k])
	if err != "":
		return err
	return "" if left.is_empty() else "left behind: %s" % ", ".join(left.map(func(k): return "%s=%s" % [k, Props.get_v(k)]))


## What run_tests --list reports, read here from the same SUITES.
static func _listing() -> Array:
	var out := []
	for path in Runner.SUITES:
		var scr = load(path) if ResourceLoader.exists(path) else null
		if not scr is Script:
			out.append({"path": path, "test": "-", "nargs": -1})
			continue
		for m in (scr as Script).get_script_method_list():
			if str(m.name).begins_with("test_"):
				out.append({"path": path, "test": m.name, "nargs": m.args.size()})
	return out


static func _covers(jobs: Array, want: Dictionary, listing: Array, workers: int) -> String:
	var seen := {}
	var suites := {}
	var parts := {}
	for j in jobs:
		for s in j.suites:
			suites[s] = true
		for k in j.expect:
			if j.part.is_empty():
				seen[k] = int(seen.get(k, 0)) + 1
			else:
				parts[k] = (parts.get(k, []) as Array) + [j.part.k]
				seen[k] = 1
	for k in parts:
		var ks: Array = parts[k]
		ks.sort()
		if ks != range(ks.size()) or (workers == 1 and ks.size() != 1):
			return "parts of %s: %s" % [k, ks]
	for t in listing:
		if not suites.has(t.path):
			return "suite skipped: %s" % t.path
	for k in want:
		if int(seen.get(k, 0)) != 1:
			return "%s in %d jobs" % [k, int(seen.get(k, 0))]
	return "" if seen.size() == want.size() else "%d tests queued, %d listed" % [seen.size(), want.size()]
