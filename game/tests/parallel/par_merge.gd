extends RefCounted
## Reads the test workers' output and merges it into one result (tests/parallel/run_parallel.gd).
## parse(): one worker's stdout + stderr -> what it reported, by suite (the runner's --mark lines say which suite).
## merge(): every job against the --list expectation: each listed test must report exactly as the single run would.
## A parted test is one test: it passes when every part passes and the parts' "covered" counts add up to the whole
## set. leak_check is one test too: it passes when it passed in every worker. A listed test no worker reported fails
## as "not run" (with its job's crash or timeout), so nothing can be skipped silently.

## The line a parted test prints for each part: "part k/n covered A of B <cases>, C of D <checked>" (C of D: how many of
## them it actually checked, of the whole set). The parts' A and C must add up to B and D, or the test fails.
const SHARD_RE := "part (\\d+)/(\\d+) covered (\\d+) of (\\d+) [^,]*, (\\d+) of (\\d+)"


## Returns {results: {"<path>::<test>": {"ok", "msg", "ms"}}, suite_ms: {path: ms}, summary ("p/t passed" or ""),
## leak ({"ok", "msg"} or {}), errors: [SCRIPT ERROR / Parse Error lines], engine: [ERROR: / WARNING: lines],
## shards: [{part, parts, covered, total, checked, all}]}.
static func parse(out_text: String, err_text: String) -> Dictionary:
	var r := {"results": {}, "suite_ms": {}, "summary": "", "leak": {}, "errors": [], "engine": [], "shards": []}
	var suite := ""
	var shard := RegEx.create_from_string(SHARD_RE)
	for ln in (out_text + "\n" + err_text).split("\n"):
		var s := ln.strip_edges()
		if s.begins_with("SUITE_END "):
			var f := s.split(" ")
			r.suite_ms[f[1]] = int(f[2]) if f.size() > 2 else 0
		elif s.begins_with("SUITE "):
			suite = s.substr(6)
		elif s.begins_with("PASS  leak_check"):
			r.leak = {"ok": true, "msg": s.substr(6)}
		elif s.begins_with("FAIL  leak_check"):
			r.leak = {"ok": false, "msg": s.substr(6)}
		elif s.begins_with("PASS  "):
			var name := s.substr(6).get_slice("  (", 0)
			var ms := int(s.get_slice("(", s.get_slice_count("(") - 1).to_int())
			r.results["%s::%s" % [suite, name]] = {"ok": true, "msg": "", "ms": ms}
		elif s.begins_with("FAIL  "):
			var body := s.substr(6)
			r.results["%s::%s" % [suite, body.get_slice(":", 0)]] = {"ok": false, "msg": body.substr(body.find(":") + 1).strip_edges(), "ms": 0}
		elif s.contains("SCRIPT ERROR") or s.contains("Parse Error"):
			r.errors.append(s)
		elif s.begins_with("ERROR:") or s.begins_with("WARNING:"):
			r.engine.append(s)
		elif s.ends_with(" passed") and s.contains("/"):
			r.summary = s
		var m := shard.search(s)
		if m != null:
			r.shards.append({"part": int(m.get_string(1)), "parts": int(m.get_string(2)), "covered": int(m.get_string(3)),
				"total": int(m.get_string(4)), "checked": int(m.get_string(5)), "all": int(m.get_string(6))})
	return r


## expect: every "<path>::<test>" the listing promised. done: [{job, parsed, code, timed_out, ms}].
## Returns {passed, total, fails: [line], errors: [line], problems: [line], coverage: [line], ok}.
static func merge(expect: Array, done: Array) -> Dictionary:
	var res := {}  # key -> {"ok", "msgs": []}
	var part_ok := {}  # parted key -> {"parts": n, "seen": {k: true}, "covered", "total", "checked", "all"}
	var leak_ok := true
	var leak_msgs := []
	var errors := []
	var problems := []
	var trouble := {}  # test key -> CRASH / TIMEOUT of the worker that should have run it
	for d in done:
		var job: Dictionary = d.job
		var p: Dictionary = d.parsed
		var why := _job_trouble(d)
		if why != "":
			problems.append("%s: %s" % [job.label, why])
			for k in job.get("expect", []):
				trouble[k] = why.get_slice(":", 0)
		for e in p.errors:
			errors.append("%s  [%s]" % [e, job.label])
		if p.leak.is_empty():
			leak_ok = false
			leak_msgs.append("%s: no leak_check (%s)" % [job.label, why if why != "" else "worker ended early"])
		elif not p.leak.ok:
			leak_ok = false
			leak_msgs.append("%s: %s" % [job.label, p.leak.msg])
		for key in p.results:
			var r: Dictionary = p.results[key]
			var k: String = key
			if not res.has(k):
				res[k] = {"ok": true, "msgs": []}
			res[k].ok = res[k].ok and r.ok
			if not r.ok:
				res[k].msgs.append(r.msg if job.part.is_empty() else "part %d/%d: %s" % [job.part.k + 1, job.part.n, r.msg])
		if not job.part.is_empty():
			var pk: String = job.part.key
			if not part_ok.has(pk):
				part_ok[pk] = {"parts": job.part.n, "seen": {}, "covered": 0, "total": -1, "checked": 0, "all": -1}
			if p.results.has(pk):
				part_ok[pk].seen[job.part.k] = true
			for sh in p.shards:
				part_ok[pk].covered += sh.covered
				part_ok[pk].checked += sh.checked
				part_ok[pk].total = sh.total
				part_ok[pk].all = sh.all
	var coverage := []
	for pk in part_ok:
		var c: Dictionary = part_ok[pk]
		var whole: bool = c.seen.size() == c.parts and c.covered == c.total and c.checked == c.all
		coverage.append("%s: %d of %d parts reported; %d of %d stand-aircraft pairs covered, %d of %d with a strip checked%s"
			% [pk.get_slice("::", 1), c.seen.size(), c.parts, c.covered, c.total, c.checked, c.all, "" if whole else "  MISMATCH"])
		if not whole and res.has(pk):
			res[pk].ok = false
			res[pk].msgs.append("the parts did not cover every stand once (%d of %d pairs, %d of %d parts)" % [c.covered, c.total, c.seen.size(), c.parts])
	var fails := []
	var passed := 0
	for key in expect:
		if not res.has(key):
			var why: String = "its worker ended in a %s" % trouble[key] if trouble.has(key) else "no worker reported it"
			fails.append("  FAIL  %s: not run (%s)  [%s]" % [key.get_slice("::", 1), why, key.get_slice("::", 0).get_file()])
		elif res[key].ok:
			passed += 1
		else:
			fails.append("  FAIL  %s: %s  [%s]" % [key.get_slice("::", 1), "; ".join(res[key].msgs), key.get_slice("::", 0).get_file()])
	for key in res:
		if not key in expect:
			problems.append("reported a test the listing did not have: %s" % key)
	if leak_ok:
		passed += 1
	else:
		fails.append("  FAIL  leak_check: %s" % "; ".join(leak_msgs))
	var total := expect.size() + 1
	return {"passed": passed, "total": total, "fails": fails, "errors": errors, "problems": problems, "coverage": coverage,
		"ok": passed == total and errors.is_empty() and problems.is_empty()}


## "" for a worker that ended normally; otherwise why it did not (timeout, crash, no summary line).
static func _job_trouble(d: Dictionary) -> String:
	if d.timed_out:
		return "TIMEOUT: killed after %.0f s (its limit; history said about %.0f s)" % [d.ms / 1000.0, d.job.est / 1000.0]
	if d.parsed.summary == "":
		return "CRASH: the worker exited with code %d before its summary line" % d.code
	if d.code != 0 and d.code != 1:
		return "CRASH: the worker exited with code %d" % d.code
	return ""
