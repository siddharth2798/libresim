extends RefCounted
## Training lesson engine (training/training_logic.gd) and the lesson data.


func _snap(ias: float, agl: float, wow: bool, extra := {}) -> Dictionary:
	var s := {"ias": ias, "agl": agl, "wow": 1.0 if wow else 0.0, "vs": 0.0, "throttle": 1.0, "rpm": 2300.0, "cross": 0.0, "hdg": 280.0, "alt": 2000.0}
	s.merge(extra, true)
	return s


func test_training_lessons_are_well_formed() -> String:
	var lessons := TrainingLogic.load_lessons()
	if lessons.size() < 3:
		return "expected the takeoff, cruise and landing lessons"
	for l in lessons:
		for k in ["id", "title", "summary", "setup", "steps", "grades"]:
			if not l.has(k):
				return "lesson %s lacks %s" % [l.get("id", "?"), k]
		for st in l.steps:
			if not (st.has("title") and st.has("text") and st.has("done")):
				return "a step of %s lacks title/text/done" % l.id
			for c in st.done:
				if c.size() != 3 or not (str(c[1]) in [">=", "<=", ">", "<", "==", "abs<", "abs>", "between"]):
					return "bad condition %s in %s" % [c, l.id]
			for g in st.get("gauges", []):
				if not (g.has("min") and g.has("max") and g.has("target") and g.has("tol") and g.has("metric")):
					return "bad gauge in %s" % l.id
	return ""


func test_training_takeoff_run_completes_and_grades() -> String:
	var run := TrainingLogic.new_run(TrainingLogic.find("takeoff"))
	var finished := false
	var script := [
		[_snap(0, 0, true, {"rpm": 700.0, "throttle": 0.1}), 0.1],  # waiting for power
		[_snap(5, 0, true), 0.1],                                    # full power -> step 1 done
		[_snap(45, 0, true, {"cross": 2.0}), 0.1],                   # 40 kt -> step 2 done
		[_snap(56, 0, false), 0.1],                                  # off the ground at 56 -> step 3 done
		[_snap(74, 80, false), 2.0], [_snap(74, 90, false), 2.5],    # climbing at Vy for 4 s -> step 4 done
		[_snap(74, 520, false), 0.1],                                # 500 ft -> finished
	]
	for s in script:
		var ev := TrainingLogic.step(run, s[0], s[1])
		finished = finished or ev.finished
	if not finished:
		return "lesson did not finish (step %d)" % run.step
	var g := TrainingLogic.grade(run)
	if g.stars < 2 or g.items.size() != 3:
		return "a clean takeoff should score 2-3 stars, got %d with %d items" % [g.stars, g.items.size()]
	return ""


func test_training_warnings_and_cooldown() -> String:
	var run := TrainingLogic.new_run(TrainingLogic.find("takeoff"))
	TrainingLogic.step(run, _snap(0, 0, true), 0.1)  # step 1 (full power) completes immediately
	var snap := _snap(30, 0, true, {"cross": 12.0})
	var a: Array = TrainingLogic.step(run, snap, 0.1).say
	var b: Array = TrainingLogic.step(run, snap, 0.1).say
	if a.is_empty() or not b.is_empty():
		return "centreline warning should fire once, then wait out the cooldown (%s / %s)" % [a, b]
	return ""


func test_training_relative_metrics_and_heading_wrap() -> String:
	var s0 := {"hdg": 350.0, "alt": 3000.0}
	var snap := {"hdg": 260.0, "alt": 3040.0}
	if absf(TrainingLogic.value(snap, s0, "d_hdg") - (-90.0)) > 0.01:
		return "heading change should wrap: %f" % TrainingLogic.value(snap, s0, "d_hdg")
	if absf(TrainingLogic.value(snap, s0, "d_alt") - 40.0) > 0.01:
		return "d_alt"
	if not TrainingLogic.test(["d_hdg", "between", [-100, -80]], snap, s0):
		return "between condition"
	return ""
