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
			if st.get("any_order", false) and st.done.any(func(c): return str(c[0]).begins_with("d_")):
				return "an any_order step of %s uses a relative (d_) metric" % l.id
		for r in l.get("abort", []):
			var rng: Array = r.get("steps", [])
			if rng.size() != 2 or int(rng[0]) < 0 or int(rng[1]) < int(rng[0]) or int(rng[0]) >= l.steps.size():
				return "bad abort step range %s in %s" % [rng, l.id]
			if str(r.get("reason", "")) == "" or r.get("when", []).is_empty():
				return "abort rule without reason / conditions in %s" % l.id
			for c in r.when:
				if c.size() != 3 or not (str(c[1]) in [">=", "<=", ">", "<", "==", "abs<", "abs>", "between"]):
					return "bad abort condition %s in %s" % [c, l.id]
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


## Feed the same snapshot for `secs` seconds; returns what happened.
func _feed(run: Dictionary, snap: Dictionary, secs: float) -> Dictionary:
	var out := {"completed": [], "skipped": [], "aborted": {}, "finished": false}
	for i in int(secs / 0.1 + 0.5):
		var ev := TrainingLogic.step(run, snap, 0.1)
		if ev.completed >= 0:
			out.completed.append(ev.completed)
		out.skipped.append_array(ev.skipped)
		if not ev.aborted.is_empty():
			out.aborted = ev.aborted
		out.finished = out.finished or ev.finished
	return out


func _land(extra := {}) -> Dictionary:
	var s := {"ias": 70.0, "agl": 600.0, "wow": 0.0, "vs": -350.0, "rpm": 1600.0, "flaps": 0.0, "gs": 65.0, "cross": 2.0,
		"gp_dev": 0.2, "dist": 3000.0, "along": -3000.0, "rem": 5500.0, "throttle": 0.3, "alt": 2500.0, "hdg": 280.0}
	s.merge(extra, true)
	return s


func test_training_landing_run_completes_and_grades() -> String:
	var run := TrainingLogic.new_run(TrainingLogic.find("landing"))
	_feed(run, _land({"ias": 80.0, "rpm": 1950.0}), 3.0)  # nothing done yet: power not reduced
	if run.step != 0:
		return "slow-down step must wait for the power reduction (step %d)" % run.step
	_feed(run, _land(), 2.5)  # 70 kt, 1,600 rpm
	_feed(run, _land({"flaps": 2.0, "ias": 66.0}), 3.5)
	_feed(run, _land({"flaps": 2.0, "ias": 65.0, "dist": 4000.0}), 4.0)  # on the path but still far out
	if run.step != 2:
		return "glide-path step must wait until 1,500 m out (step %d)" % run.step
	_feed(run, _land({"flaps": 2.0, "ias": 65.0, "dist": 1200.0, "agl": 300.0}), 3.5)
	_feed(run, _land({"flaps": 2.0, "ias": 62.0, "along": -10.0, "dist": 10.0, "agl": 90.0, "gp_dev": 0.0}), 0.5)
	_feed(run, _land({"flaps": 2.0, "ias": 55.0, "along": 200.0, "dist": 0.0, "agl": 10.0, "vs": -250.0, "gp_dev": 0.0}), 1.0)
	var td := _feed(run, _land({"flaps": 2.0, "ias": 52.0, "along": 300.0, "dist": 0.0, "agl": 4.0, "wow": 1.0, "vs": -10.0}), 0.5)
	if not run.aborted.is_empty() or not (4 in td.completed):
		return "touching down in the flare step is the goal, not an abort: %s %s" % [td, run.aborted]
	var fin := _feed(run, _land({"gs": 6.0, "wow": 1.0, "agl": 4.0, "along": 500.0, "dist": 0.0, "flaps": 2.0, "ias": 5.0}), 0.5)
	if not fin.finished or TrainingLogic.grade(run).stars < 2:
		return "rolled out but the lesson did not finish with 2+ stars (%s)" % fin
	return ""


func test_training_early_touchdown_ends_the_lesson() -> String:
	var run := TrainingLogic.new_run(TrainingLogic.find("landing"))
	_feed(run, _land({"flaps": 0.0}), 2.5)  # step 1 done, flaps never extended
	var r := _feed(run, _land({"agl": 4.0, "wow": 1.0, "ias": 60.0, "vs": -50.0}), 1.0)
	var info: Dictionary = r.aborted
	if info.is_empty() or not run.done:
		return "touching down during step 2 must end the lesson (%s)" % r
	if info.step != 1 or str(info.reason).find("touched down") < 0 or str(info.reason).find("Flaps and trim") < 0:
		return "the card must say where it ended: %s" % info.reason
	if info.title != "Approach not completed" or str(info.tip) == "" or info.steps[0].state != "done" or info.steps[1].state != "current" or info.steps[2].state != "todo":
		return "incomplete card content: %s" % info
	var after := TrainingLogic.step(run, _land({"wow": 1.0}), 0.1)
	if not after.aborted.is_empty() or after.completed >= 0 or r.finished:
		return "a finished run must stay finished"
	return ""


func test_training_abort_waits_out_the_restart_grace() -> String:
	var run := TrainingLogic.new_run(TrainingLogic.find("landing"))
	var stale := _land({"wow": 1.0, "agl": 4.0, "gs": 0.0})  # Props still hold the previous attempt for a frame
	var r := _feed(run, stale, 1.0)
	if not r.aborted.is_empty():
		return "no early end in the first second after a (re)start"
	r = _feed(run, _land(), 1.0)  # the new attempt is airborne again
	if not r.aborted.is_empty() or run.done:
		return "a stale first frame must not end the new attempt"
	return ""


func test_training_leaving_the_approach_ends_the_lesson() -> String:
	var run := TrainingLogic.new_run(TrainingLogic.find("landing"))
	_feed(run, _land(), 2.0)
	var r := _feed(run, _land({"agl": 70.0, "dist": 1500.0}), 2.5)  # far too low, far out
	if r.aborted.is_empty() or str(r.aborted.reason).find("too low") < 0:
		return "very low far from the runway must end the lesson: %s" % r
	run = TrainingLogic.new_run(TrainingLogic.find("landing"))
	_feed(run, _land(), 2.0)
	r = _feed(run, _land({"gp_dev": 5.0, "dist": 2500.0}), 7.0)
	if r.aborted.is_empty() or str(r.aborted.reason).find("above the glide path") < 0:
		return "far above the path for a long time must end the lesson: %s" % r
	return ""


func test_training_later_steps_tick_off_earlier_ones() -> String:
	var run := TrainingLogic.new_run(TrainingLogic.find("landing"))
	# configured and stable on the path, but the power was never brought below 1,800 rpm
	var stable := _land({"flaps": 2.0, "ias": 66.0, "rpm": 2100.0, "dist": 1200.0, "gp_dev": 0.4})
	var r := _feed(run, stable, 4.0)
	if r.skipped != [0, 1] or r.completed != [2] or run.step != 3:
		return "steps 1-2 should tick off when step 3 holds: %s (now step %d)" % [r, run.step]
	run = TrainingLogic.new_run(TrainingLogic.find("cruise"))
	r = _feed(run, {"vs": 0.0, "pitch_in": 0.0, "d_alt": 0.0, "alt": 2500.0, "agl": 2000.0, "wow": 0.0, "rpm": 2000.0, "ias": 100.0}, 10.0)
	if not r.skipped.is_empty() or run.step != 0:
		return "only steps flagged any_order may be skipped to (the cruise trim step is true from the start)"
	return ""


func test_training_takeoff_and_cruise_do_not_strand() -> String:
	var run := TrainingLogic.new_run(TrainingLogic.find("takeoff"))
	_feed(run, _snap(0, 0, true, {"rpm": 2300.0, "throttle": 1.0}), 2.0)  # full power: step 1 done
	var r := _feed(run, _snap(30, 0, true, {"cross": 40.0, "rem": 2000.0}), 2.0)
	if r.aborted.is_empty() or str(r.aborted.reason).find("left the runway") < 0:
		return "driving off the side of the runway must end the takeoff: %s" % r
	run = TrainingLogic.new_run(TrainingLogic.find("takeoff"))
	_feed(run, _snap(0, 0, true), 2.0)
	_feed(run, _snap(45, 0, true), 0.5)
	_feed(run, _snap(56, 0, false), 0.5)  # airborne: rotate done
	r = _feed(run, _snap(60, 0, true, {"rem": 1200.0}), 3.0)  # settled back down
	if r.aborted.is_empty() or str(r.aborted.reason).find("settled back") < 0:
		return "settling back onto the runway after rotating must end the takeoff: %s" % r
	run = TrainingLogic.new_run(TrainingLogic.find("cruise"))
	_feed(run, _snap(100, 2000, false), 2.0)
	r = _feed(run, _snap(0, 0, true), 2.0)
	if r.aborted.is_empty() or str(r.aborted.reason).find("touched the ground") < 0:
		return "landing during the cruise lesson must end it: %s" % r
	return ""


func test_training_crash_card_and_retry_reset() -> String:
	var lesson := TrainingLogic.find("landing")
	var run := TrainingLogic.new_run(lesson)
	_feed(run, _land({"flaps": 2.0}), 2.0)
	var info := TrainingLogic.abort(run, "You crashed during step {n}, {step}.", "Go gently.")
	if info.reason != "You crashed during step 2, Flaps and trim." or not run.done:
		return "crash text / state: %s" % info.reason
	# the cards: incomplete card replaces the lesson card, reset() brings the lesson card back
	var hud := TrainingHud.new()
	hud.setup(lesson, "full")
	hud.show_step(0)
	hud.show_incomplete(info)
	if hud._card.visible or hud._result == null:
		return "the not-completed card should replace the lesson card"
	hud.reset()
	if not hud._card.visible or hud._result != null:
		return "reset() must bring the lesson card back and drop the result card"
	hud.show_ended(info)
	if not hud._card.visible or not hud._instr.text.begins_with("You crashed"):
		return "a crash keeps the lesson card and says what happened"
	hud.free()
	# Try again calls the flight scene's reset (F5), which restarts the lesson
	var gs := GDScript.new()
	gs.source_code = "extends Node\nvar n := 0\nfunc _reset() -> void:\n\tn += 1\n"
	gs.reload()
	var flight := Node.new()
	flight.set_script(gs)
	var ts := TrainingSession.new()
	flight.add_child(ts)
	ts.retry()
	var n: int = flight.n
	flight.free()
	if n != 1:
		return "retry() must reset the flight once (%d)" % n
	var fresh := TrainingLogic.new_run(lesson)
	if fresh.done or fresh.step != 0 or not fresh.aborted.is_empty() or not fresh.rec.is_empty():
		return "a new run must be clean"
	return ""
