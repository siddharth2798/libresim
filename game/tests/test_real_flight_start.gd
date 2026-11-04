extends Node
## The real start path, no dry_run hook (tests/probe_real_start.gd): from the start screen's own buttons (Fly now, home "Fly
## again", home "Continue", and the amber "Fly anyway" with its question) the scene changes to the flight scene, the flight node
## is built, 2 s of physics time pass and no ERROR is logged. A scene change would end this runner, so each flow runs the probe
## in a child Godot process (headless, about 5 s each) and reads its last line. The probe works on scratch paths; this test also
## checks that the player's own save files were not touched. Skipped (passes, says so) without the generated data.

const FLOWS := ["fly_now", "fly_again", "continue", "fly_anyway"]
const OWN := ["user://last_flight.json", "user://training.json", "user://options.cfg", "user://key_bindings.json", "user://input_bindings.json", "user://graphics.cfg"]


func _run(flow: String) -> Dictionary:
	var out := []
	var args := ["--headless", "--fixed-fps", "120", "--audio-driver", "Dummy", "--path", ProjectSettings.globalize_path("res://"),
		"res://tests/probe_real_start.tscn", "--", "--flow=" + flow]
	var code := OS.execute(OS.get_executable_path(), args, out, true)
	var text := "\n".join(out)
	var line := ""
	for l in text.split("\n"):
		if l.begins_with("REAL START "):
			line = l
	return {"code": code, "line": line, "text": text}


func _stamps() -> Dictionary:
	var d := {}
	for p in OWN:
		d[p] = FileAccess.get_modified_time(p) if FileAccess.file_exists(p) else -1
	return d


func _check(flow: String, also := "") -> String:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://").path_join("../data/processed")):
		print("    (skipped: no data/processed, the flight scene cannot load)")
		return ""
	var before := _stamps()
	var err := _once(flow, also)
	if err != "":  # one retry: the headless renderer now and then logs a one-off "wrong RID" error while the flight scene builds (seen once in about 20 runs)
		print("    (%s failed once: %s; retrying)" % [flow, err.left(200)])
		err = _once(flow, also)
	if err != "":
		return err
	return "" if _stamps() == before else "%s changed one of the player's files %s" % [flow, OWN]


func _once(flow: String, also: String) -> String:
	var r := _run(flow)
	var line: String = r.line
	if not line.begins_with("REAL START PASS flow=%s " % flow) or r.code != 0:
		return "%s: exit %d, '%s'" % [flow, r.code, line if line != "" else str(r.text).right(300)]
	for need in ["sim_s=2.0", "errors=0", also]:
		if need != "" and not line.contains(need):
			return "%s: expected '%s' in '%s'" % [flow, need, line]
	return ""


func test_free_flight_fly_now_reaches_the_flight() -> String:
	return _check("fly_now")


func test_fly_again_reaches_the_flight() -> String:
	return _check("fly_again")


func test_continue_lesson_reaches_the_flight_and_runs_the_lesson() -> String:
	return _check("continue", "training=cruise")  # the lesson after the one flown (takeoff)


func test_fly_anyway_confirmation_reaches_the_flight() -> String:
	return _check("fly_anyway")


func test_the_probe_uses_scratch_paths_only() -> String:
	var src := FileAccess.get_file_as_string("res://tests/probe_real_start.gd")
	for need in ["Session.save_path = SAVE", "TrainingLogic.save_path = STARS", "SituationStore.dir =", "Session.interactive_override = 0"]:
		if not src.contains(need):
			return "the probe must redirect: " + need
	return ""
