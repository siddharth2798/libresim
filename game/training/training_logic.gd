class_name TrainingLogic
extends RefCounted
## Training lesson engine (data in training/lessons.json). No nodes: feed it a snapshot of
## the flight (dict of metrics) each frame and it advances through the lesson's steps,
## raises coach warnings, tracks the numbers used for grading, and scores the result.

const PATH := "res://training/lessons.json"
const SAVE := "user://training.json"
const WARN_COOLDOWN := 5.0
const ABORT_GRACE := 1.5  # s after a (re)start before the lesson can end early: Props still hold the last frame


static func load_lessons() -> Array:
	var j = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return j.lessons if j is Dictionary else []


## Does this lesson suit the aircraft? A lesson's optional "aircraft" list names the aircraft ids it is
## written for (V-speeds, fuel, procedures); no list = any aircraft.
static func suits(lesson: Dictionary, aircraft_id: String) -> bool:
	var list: Array = lesson.get("aircraft", [])
	return list.is_empty() or aircraft_id in list


## The lessons written for this aircraft, in order.
static func lessons_for(aircraft_id: String) -> Array:
	return load_lessons().filter(func(l): return suits(l, aircraft_id))


## Start a lesson (Session.begin_lesson). If the current aircraft is not one it is written for, the
## flight is set up with the first aircraft it lists; end_lesson() restores the pilot's own choice.
static func begin(lesson: Dictionary, assist: String) -> void:
	var setup: Dictionary = lesson.setup
	var current := str(setup.get("aircraft", Session.setup.get("aircraft", AircraftDef.DEFAULT_ID)))
	if not suits(lesson, current):  # decided first: the airborne defaults the lesson leaves open follow that aircraft
		setup = setup.duplicate()
		setup.aircraft = str(lesson.aircraft[0])
	Session.begin_lesson(lesson.id, setup, assist)


static func find(id: String) -> Dictionary:
	for l in load_lessons():
		if l.id == id:
			return l
	return {}


static func new_run(lesson: Dictionary) -> Dictionary:
	return {"lesson": lesson, "step": 0, "s0": {}, "started": false, "held": 0.0, "rec": {}, "trk": {},
		"cool": {}, "t": 0.0, "step_t": 0.0, "done": false, "later": {}, "abort_t": {}, "aborted": {}}


## Metric value: plain from the snapshot, or "d_<metric>" = change since the step began
## (headings wrap to +/-180).
static func value(snap: Dictionary, s0: Dictionary, name: String) -> float:
	if name.begins_with("d_"):
		var m := name.substr(2)
		var cur := float(snap.get(m, 0.0))
		var d := cur - float(s0.get(m, cur))
		return wrapf(d, -180.0, 180.0) if m == "hdg" else d
	return float(snap.get(name, 0.0))


static func test(cond: Array, snap: Dictionary, s0: Dictionary) -> bool:
	var v := value(snap, s0, cond[0])
	var a = cond[2]
	match str(cond[1]):
		">=": return v >= float(a)
		"<=": return v <= float(a)
		">": return v > float(a)
		"<": return v < float(a)
		"==": return absf(v - float(a)) < 0.5
		"abs<": return absf(v) < float(a)
		"abs>": return absf(v) > float(a)
		"between": return v >= float(a[0]) and v <= float(a[1])
	return false


static func all(conds: Array, snap: Dictionary, s0: Dictionary) -> bool:
	for c in conds:
		if not test(c, snap, s0):
			return false
	return true


## Advance one frame. Returns {say: [[text, level]], completed: step index or -1 (the last step
## finished this frame), skipped: [indices ticked off because a later step was already met],
## finished: bool, aborted: {} or the info of abort() when the lesson ended early}.
## Steps are in order, but a step flagged "any_order" also counts when its conditions hold while
## an earlier step is current (the earlier ones are ticked off). Lesson "abort" rules
## ({steps: [first, last], when, for s, reason, tip}) end a lesson the pilot can no longer finish.
static func step(run: Dictionary, snap: Dictionary, dt: float) -> Dictionary:
	var ev := {"say": [], "completed": -1, "skipped": [], "finished": false, "aborted": {}}
	if run.done:
		return ev
	var steps: Array = run.lesson.steps
	var st: Dictionary = steps[run.step]
	if not run.started:
		run.started = true
		run.s0 = snap.duplicate()
		run.step_t = 0.0
		run.held = 0.0
	run.t += dt
	run.step_t += dt
	for tr in st.get("track", []):
		_track(run, tr, value(snap, run.s0, tr.metric))
	for w in st.get("warn", []):
		if all(w.when, snap, run.s0) and run.t - float(run.cool.get(w.say, -999.0)) >= WARN_COOLDOWN:
			run.cool[w.say] = run.t
			ev.say.append([w.say, int(w.get("level", 1))])
	var ok := all(st.done, snap, run.s0)
	run.held = run.held + dt if ok else 0.0
	if ok and run.held >= float(st.get("hold", 0.0)):
		_complete(run, ev, snap, run.step)
	else:
		var j := _later_met(run, snap, dt)
		if j > run.step:
			for k in range(run.step, j):
				ev.skipped.append(k)
			_complete(run, ev, snap, j)
	if not run.done:
		_check_abort(run, ev, snap, dt)
	return ev


## Mark step i done (recording its numbers) and move on to the next one.
static func _complete(run: Dictionary, ev: Dictionary, snap: Dictionary, i: int) -> void:
	var steps: Array = run.lesson.steps
	for r in steps[i].get("record", []):
		run.rec[r.name] = value(snap, run.s0, r.metric)
	ev.completed = i
	run.step = i + 1
	run.started = false
	run.later = {}
	if run.step >= steps.size():
		run.done = true
		ev.finished = true


## Furthest later "any_order" step whose conditions (absolute metrics only) have held for its own
## hold time, or -1.
static func _later_met(run: Dictionary, snap: Dictionary, dt: float) -> int:
	var steps: Array = run.lesson.steps
	var best := -1
	for j in range(run.step + 1, steps.size()):
		var sj: Dictionary = steps[j]
		if not sj.get("any_order", false) or sj.done.any(func(c): return str(c[0]).begins_with("d_")):
			continue
		if all(sj.done, snap, {}):
			run.later[j] = float(run.later.get(j, 0.0)) + dt
			if run.later[j] >= float(sj.get("hold", 0.0)):
				best = j
		else:
			run.later[j] = 0.0
	return best


static func _check_abort(run: Dictionary, ev: Dictionary, snap: Dictionary, dt: float) -> void:
	if run.t < ABORT_GRACE:
		return
	var rules: Array = run.lesson.get("abort", [])
	for i in rules.size():
		var r: Dictionary = rules[i]
		var rng: Array = r.get("steps", [0, 99])
		if run.step < int(rng[0]) or run.step > int(rng[1]) or not all(r.when, snap, {}):
			run.abort_t[i] = 0.0
			continue
		run.abort_t[i] = float(run.abort_t.get(i, 0.0)) + dt
		if run.abort_t[i] >= float(r.get("for", 0.0)):
			ev.aborted = abort(run, str(r.reason), str(r.get("tip", "")))
			return


## End the lesson early (a rule fired, or the aircraft crashed). {step} and {n} in `reason` become
## the current step's title and number. Returns the info the result card shows: title, reason,
## tip (what to improve), hint, step and the step list with done / current / todo.
static func abort(run: Dictionary, reason: String, tip := "") -> Dictionary:
	var steps: Array = run.lesson.steps
	var cur := mini(run.step, steps.size() - 1)
	var list := []
	for i in steps.size():
		list.append({"title": steps[i].title, "state": "done" if i < run.step else ("current" if i == cur else "todo")})
	run.done = true
	run.aborted = {
		"title": str(run.lesson.get("incomplete", "%s not completed" % run.lesson.title)),
		"reason": reason.replace("{step}", str(steps[cur].title)).replace("{n}", str(cur + 1)),
		"tip": tip, "hint": str(steps[cur].get("hint", "")), "step": cur, "steps": list}
	return run.aborted


static func _track(run: Dictionary, tr: Dictionary, v: float) -> void:
	var k: String = tr.name
	match str(tr.reduce):
		"absmax": run.trk[k] = maxf(float(run.trk.get(k, 0.0)), absf(v))
		"max": run.trk[k] = maxf(float(run.trk.get(k, -INF)), v)
		"min": run.trk[k] = minf(float(run.trk.get(k, INF)), v)
		"avg":
			var a: Dictionary = run.trk.get(k, {"sum": 0.0, "n": 0})
			a.sum += v
			a.n += 1
			run.trk[k] = a


## Final number of a tracked / recorded quantity (or NAN if it never happened).
static func result(run: Dictionary, source: String, name: String) -> float:
	var src: Dictionary = run.trk if source == "trk" else run.rec
	if not src.has(name):
		return NAN
	var v = src[name]
	if v is Dictionary:
		return v.sum / maxf(float(v.n), 1.0)
	return float(v)


## Grade the finished run: items [{label, value, unit, points (2 good, 1 ok, 0 off)}] and 1..3 stars.
static func grade(run: Dictionary) -> Dictionary:
	var items := []
	var pts := 0
	for g in run.lesson.get("grades", []):
		var v := result(run, g.source, g.name)
		var p := 0
		if not is_nan(v):
			if v >= float(g.good[0]) and v <= float(g.good[1]):
				p = 2
			elif v >= float(g.ok[0]) and v <= float(g.ok[1]):
				p = 1
		items.append({"label": g.label, "value": v, "unit": g.get("unit", ""), "points": p})
		pts += p
	var frac := float(pts) / maxf(2.0 * items.size(), 1.0)
	return {"items": items, "stars": 3 if frac >= 0.8 else (2 if frac >= 0.5 else 1)}


static func load_stars() -> Dictionary:
	if FileAccess.file_exists(SAVE):
		var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
		if d is Dictionary:
			return d
	return {}


static func save_stars(id: String, stars: int) -> void:
	var d := load_stars()
	d[id] = maxi(int(d.get(id, 0)), stars)
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))
