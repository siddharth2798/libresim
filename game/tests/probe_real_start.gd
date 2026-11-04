extends Node
## Probe: the REAL start path, without the start screen's dry_run hook. One run takes one flow from the start screen's
## own buttons to the flight scene, lets 2 s of simulated time pass and reports. Needs the generated data (data/processed).
##   godot --headless --fixed-fps 120 --audio-driver Dummy --path game res://tests/probe_real_start.tscn -- --flow=<name>
## flows: fly_now      Free flight, a ready setup, the filled Fly button
##        fly_again    home "Fly again" (a last flight saved in the scratch file)
##        continue     home "Continue: next lesson" (one lesson flown in the scratch stars file)
##        fly_anyway   an overweight C172: Fly turns amber, the "Fly anyway?" question, its "Fly anyway" button
## Last line: REAL START PASS|FAIL flow=.. reason=.. (exit code 0 / 1). PASS needs: the scene changed to the flight scene,
## the flight node holds its parts (FDM, weather, UI) and the FDM publishes its state, 2 s of physics time ran, and no script / engine ERROR was logged
## (warnings are not counted). Never touches the player's files: Session.save_path, TrainingLogic.save_path and
## SituationStore.dir are scratch paths, and Session.interactive_override = 0 keeps options and saves in memory.

const SAVE := "user://_probe_start_last_flight.json"
const STARS := "user://_probe_start_training.json"
const FLIGHT := "res://world/flight.tscn"
const SIM_S := 2.0
const WALL_S := 240.0

var flow := "fly_now"
var _screen: Control


## Collects every logged ERROR (script errors included); warnings are ignored.
class Errs extends Logger:
	var lines: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _bt: Array) -> void:
		if error_type != Logger.ERROR_TYPE_WARNING:
			lines.append("%s (%s:%d) %s" % [rationale if rationale != "" else code, file.get_file(), line, function])


## Lives under the root so it survives the scene change that the start screen makes.
class Watch extends Node:
	var flow := ""
	var errs: Errs
	var expect_training := false
	var sim := 0.0
	var wall0 := 0
	var seen_flight := false
	var done := false

	func _process(_dt: float) -> void:
		if done:
			return
		var cs := get_tree().current_scene
		if (Time.get_ticks_msec() - wall0) / 1000.0 > WALL_S:
			_finish("timeout: the flight scene did not appear in %d s" % int(WALL_S))
		elif cs != null and cs.scene_file_path == FLIGHT:
			seen_flight = true
			var missing := ["Fdm", "UI", "Weather"].filter(func(n): return cs.get_node_or_null(n) == null)
			if not missing.is_empty() and sim == 0.0:
				return  # still building
			if not missing.is_empty():
				_finish("flight scene lacks " + ", ".join(missing))

	func _physics_process(dt: float) -> void:
		if seen_flight and not done:
			sim += dt
			if sim >= SIM_S:
				_finish("")

	func _finish(reason: String) -> void:
		done = true
		if reason == "":
			if not Props.has("fdm/position_enu"):
				reason = "the flight model never published fdm/position_enu"
			elif expect_training and Session.training == "":
				reason = "a lesson was expected but Session.training is empty"
			elif not expect_training and Session.training != "":
				reason = "a free flight but Session.training = " + Session.training
			elif not errs.lines.is_empty():
				reason = "%d logged error(s), first: %s" % [errs.lines.size(), errs.lines[0]]
		print("REAL START %s flow=%s reason=%s sim_s=%.2f wall_s=%.1f aircraft=%s airport=%s training=%s errors=%d" % [
			"PASS" if reason == "" else "FAIL", flow, reason if reason != "" else "ok", sim,
			(Time.get_ticks_msec() - wall0) / 1000.0, Session.setup.aircraft, Session.setup.airport, Session.training, errs.lines.size()])
		for l in errs.lines.slice(0, 8):
			print("   ERROR ", l)
		get_tree().quit(0 if reason == "" else 1)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--flow="):
			flow = a.substr(7)
	Session.skip_menu = false
	Session.interactive_override = 0
	Session.save_path = SAVE
	TrainingLogic.save_path = STARS
	SituationStore.dir = "user://_probe_start_saves/"
	for p in [SAVE, STARS]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	Session.setup = Session.DEFAULT.duplicate(true)
	var w := Watch.new()
	w.flow = flow
	w.errs = Errs.new()
	OS.add_logger(w.errs)
	w.wall0 = Time.get_ticks_msec()
	w.expect_training = flow == "continue"
	get_tree().root.add_child.call_deferred(w)
	_screen = load("res://ui/menu/start_screen.tscn").instantiate()
	add_child(_screen)
	await get_tree().create_timer(0.5).timeout
	match flow:
		"fly_now":
			_screen.go("flight")
			_screen.screen("flight").fly_btn.pressed.emit()
		"fly_again":
			var s := Session.DEFAULT.duplicate(true)
			s.merge({"airport": "VAJJ", "runway": "", "weather": "Clear", "time_h": 12.0}, true)
			FileAccess.open(SAVE, FileAccess.WRITE).store_string(JSON.stringify(s))
			_screen.screen("home").enter()
			var b: Button = _screen.screen("home")._cards[0].action_btn
			print("PROBE Fly again visible=%s text=%s" % [b.visible, b.text])
			b.pressed.emit()
		"continue":
			FileAccess.open(STARS, FileAccess.WRITE).store_string(JSON.stringify({"takeoff": 2}))
			_screen.screen("home").enter()
			var b: Button = _screen.screen("home")._cards[1].action_btn
			print("PROBE Continue visible=%s text=%s" % [b.visible, b.text])
			b.pressed.emit()
		"fly_anyway":
			for k in ["copilot_kg", "rear_kg", "baggage_kg"]:
				Session.setup[k] = {"copilot_kg": 120.0, "rear_kg": 200.0, "baggage_kg": 54.0}[k]
			Session.setup.fuel_gal = 26.0
			_screen.go("flight")
			var fl: Control = _screen.screen("flight")
			await get_tree().process_frame
			print("PROBE Fly label=%s checks=%s" % [fl.fly_btn.text, SetupChecks.reasons(SetupChecks.checks(Session.setup))])
			fl.fly_btn.pressed.emit()
			await get_tree().process_frame
			var q: FlyConfirm = _screen._confirm
			print("PROBE confirm open=%s" % (q != null))
			if q != null:
				q.fly_btn.pressed.emit()
		_:
			print("REAL START FAIL flow=%s reason=unknown flow" % flow)
			get_tree().quit(1)
