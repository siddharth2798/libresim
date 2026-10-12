extends Node
## Probe: fly a training lesson (training/lessons.json) in the real flight scene with a
## scripted pilot (tests/lesson_pilots.gd) and log when each step completes. Not part of the
## unit suite. Run (faster than real time):
##   godot --headless --fixed-fps 120 --path game res://tests/landing_probe.tscn -- --lesson=landing --pilot=good
## Options after "--": --lesson=takeoff|cruise|landing  --pilot=<kind, see lesson_pilots.gd>
## --max=<sim seconds, default 400>  --retry [--pilot2=good] (after the first attempt ends, wait
## until the aircraft has stopped, press Try again and fly once more).
## --nm=<n> --ft=<ft above the field>  shorten the airborne start (e.g. --nm=1.3 --ft=400)
## --pics=<dir>  (needs a window, not --headless) save <dir>/card.png at 20 s and <dir>/end.png 1 s after the end.
## Note: a finished lesson saves its stars to user://training.json (back it up first).

var f: Node
var ts: TrainingSession
var pl: Node  # tests/e2e/e2e_pilot.gd: attitude loops
var args := {}
var t := 0.0
var _log_t := 0.0
var _last_step := 0
var _step_t0 := 0.0
var st := {}  # pilot state (lesson_pilots.gd)
var _ended := false
var _retried := false
var _settle := 0  # physics frames to wait after a retry: the property tree still holds the old state for one tick
var _times: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	Engine.max_fps = 0
	if args.has("nm"):
		Session.setup.air_nm = float(args.nm)
	if args.has("ft"):
		Session.setup.air_ft = float(args.ft)
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)
	ts = f.get_node("Training")
	pl = Node.new()
	pl.set_script(load("res://tests/e2e/e2e_pilot.gd"))
	add_child(pl)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for n in ["Controls", "JoystickControls"]:
		var c := f.get_node_or_null(n)
		if c:
			c.set_process(false)
			c.set_physics_process(false)
	pl.active = true
	print("PROBE lesson %s pilot %s start %s ft %s nm %s kt" % [Session.training, args.get("pilot", "good"), Session.setup.air_ft, Session.setup.air_nm, Session.setup.get("air_kt", 90)])


func _physics_process(dt: float) -> void:
	if pl == null:
		return
	if _settle > 0:
		_settle -= 1
		return
	t += dt
	LessonPilots.tick(self, dt)
	var run: Dictionary = ts.run
	if run.is_empty():
		return
	var step: int = run.step
	if step != _last_step:
		_times.append(t - _step_t0)
		print("PROBE t=%6.1f step %d done after %.1f s (flaps %d ias %.0f agl %.0f gp %.2f)" % [t, _last_step + 1, t - _step_t0, int(Props.get_v("controls/flaps", 0)), _kias(), _agl(), ts._snap.get("gp_dev", 0.0)])
		_last_step = step
		_step_t0 = t
	if args.has("pics") and t > 20.0 and not st.has("shot1"):
		st.shot1 = true
		_snap("card")
	if t >= _log_t:
		_log_t += 5.0
		var s: Dictionary = ts._snap
		print("PROBE t=%5.0f step %d ias %5.1f agl %5.0f alt %5.0f gp_dev %5.2f cross %6.1f along %7.0f vs %5.0f thr %.2f rpm %4.0f flaps %d pitch %5.1f wow %d" % [t, step + 1, s.get("ias", 0), s.get("agl", 0), s.get("alt", 0),
			s.get("gp_dev", 0), s.get("cross", 0), s.get("along", 0), s.get("vs", 0), s.get("throttle", 0), s.get("rpm", 0), s.get("flaps", 0), s.get("pitch", 0), s.get("wow", 0)])
	var done: bool = run.done or ts.result_kind != ""
	if done and not _ended:
		_ended = true
		_report()
	if t > float(args.get("max", 400.0)) and not _ended:
		_ended = true
		print("PROBE TIMEOUT at t=%.0f on step %d (%s)" % [t, step + 1, run.lesson.steps[mini(step, run.lesson.steps.size() - 1)].title])
		_report()


func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(str(args.pics))
	get_viewport().get_texture().get_image().save_png(str(args.pics).path_join(name + ".png"))
	print("PROBE saved %s.png" % name)


func _report() -> void:
	var run: Dictionary = ts.run
	var kind: String = ts.result_kind
	print("PROBE damage: crashed=%s %s" % [Props.get_b("damage/crashed"), Props.get_v("damage/events", [])])
	print("PROBE END t=%.1f step=%d done=%s kind=%s step times=%s" % [t, run.step + 1, run.done, kind, _times.map(func(x): return snappedf(x, 0.1))])
	if not run.aborted.is_empty():
		print("PROBE ABORT %s | %s | tip: %s" % [run.aborted.title, run.aborted.reason, run.aborted.tip])
	if kind == "complete":
		var g := TrainingLogic.grade(run)
		print("PROBE GRADE stars=%d items=%s" % [g.stars, g.items.map(func(i): return "%s=%.1f(%d)" % [i.label, i.value, i.points])])
	if args.has("pics"):
		await get_tree().create_timer(1.0).timeout
		await _snap("end")
	if args.has("retry") and not _retried:
		_retried = true
		var waited := 0.0  # let it roll to a stop first: Try again must also work from a stopped aircraft
		while Props.get_f("fdm/groundspeed_mps") > 0.5 and waited < 60.0 and not Props.get_b("damage/crashed"):
			await get_tree().physics_frame
			waited += 1.0 / 120.0
		print("PROBE before retry: gs %.1f kt wow %d crashed %s card visible %s result card %s" % [Units.mps_to_kt(Props.get_f("fdm/groundspeed_mps")),
			int(Props.get_b("fdm/wow")), Props.get_b("damage/crashed"), ts._hud._card.visible, is_instance_valid(ts._hud._wrap)])
		ts.retry()
		args["pilot"] = args.get("pilot2", "good")
		pl.pitch_tgt = 0.0
		t = 0.0
		_log_t = 0.0
		_last_step = 0
		_step_t0 = 0.0
		_times.clear()
		st = {}
		_ended = false
		_settle = 3
		await get_tree().physics_frame
		print("PROBE RETRY: step %d ias %.0f agl %.0f alt %.0f wow %d crashed %s card visible %s result card %s flaps %d thr %.2f brake %.1f" % [ts.run.step + 1, _kias(), _agl(),
			Units.m_to_ft(Props.get_f("fdm/alt_m")), int(Props.get_b("fdm/wow")), Props.get_b("damage/crashed"), ts._hud._card.visible, is_instance_valid(ts._hud._wrap),
			int(Props.get_v("controls/flaps", 0)), Props.get_f("controls/throttle"), Props.get_f("controls/brake_left")])
		return
	get_tree().quit()


func _kias() -> float:
	return Units.mps_to_kt(Props.get_f("fdm/cas_mps"))


func _agl() -> float:
	return Units.m_to_ft(Props.get_f("fdm/agl_m"))
