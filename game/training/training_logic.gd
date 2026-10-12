class_name TrainingLogic
extends RefCounted
## Training lesson engine (data in training/lessons.json). No nodes: feed it a snapshot of
## the flight (dict of metrics) each frame and it advances through the lesson's steps,
## raises coach warnings, tracks the numbers used for grading, and scores the result.

const PATH := "res://training/lessons.json"
const SAVE := "user://training.json"
const WARN_COOLDOWN := 5.0


static func load_lessons() -> Array:
	var j = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return j.lessons if j is Dictionary else []


static func find(id: String) -> Dictionary:
	for l in load_lessons():
		if l.id == id:
			return l
	return {}


static func new_run(lesson: Dictionary) -> Dictionary:
	return {"lesson": lesson, "step": 0, "s0": {}, "started": false, "held": 0.0, "rec": {}, "trk": {},
		"cool": {}, "t": 0.0, "step_t": 0.0, "done": false}


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


## Advance one frame. Returns {say: [[text, level]], completed: step index or -1, finished: bool}.
static func step(run: Dictionary, snap: Dictionary, dt: float) -> Dictionary:
	var ev := {"say": [], "completed": -1, "finished": false}
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
	if all(st.done, snap, run.s0):
		run.held += dt
	else:
		run.held = 0.0
	if run.held >= float(st.get("hold", 0.0)) and all(st.done, snap, run.s0):
		for r in st.get("record", []):
			run.rec[r.name] = value(snap, run.s0, r.metric)
		ev.completed = run.step
		run.step += 1
		run.started = false
		if run.step >= steps.size():
			run.done = true
			ev.finished = true
	return ev


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
