extends Node
## Debug: a normal game session ends without leaks. The start screen, FLY (the default C172 on the runway at Juhu, or
## the game's own options after --menu, which opens the start screen pre-filled with them), the flight runs until the
## loader film is gone plus SETTLE_S, then "Quit game" on the pause screen (clicked twice: it
## asks to confirm). The engine prints its exit report after this script ends, so read the log: no "leaked at exit",
## "resources still in use at exit" or "RID ... leaked" may follow the EXIT lines (docs/USAGE.md "Automated tests"
## lists the two Godot leaks that do).
##   godot --path game --audio-driver Dummy --windowed --resolution 1280x720 res://tests/debug_exit_leaks.tscn \
##     [-- --menu --aircraft=a320 --airport=VABB] 2>&1 | grep -E "^EXIT|leaked|still in use|SCRIPT ERROR"
## Uses the player's user data like the game does (the setup it flies is written to last_flight.json).
## --preset-walk: in flight, step the graphics preset through every one and back (applied to the scene as Options does,
## without writing graphics.cfg or override.cfg). --restart: quit the way RendererRestart does (OS.set_restart_on_exit),
## relaunching only "godot --version". Both look for crashes at exit after the game changed presets. --record: fly with
## the session recording on (ui/session_recorder.gd), so the quit happens while frames are being read back.

const SETTLE_S := 15.0

var _driver := false


func _ready() -> void:
	if _driver:
		_drive.call_deferred()
		return
	var d := Node.new()  # survives the scene changes (this scene is replaced by the start screen, then the flight)
	d.set_script(get_script())
	d.set("_driver", true)
	d.name = "ExitLeakDriver"
	get_tree().root.add_child.call_deferred(d)
	get_tree().change_scene_to_file.call_deferred("res://ui/menu/start_screen.tscn")


func _drive() -> void:
	var tree := get_tree()
	await tree.create_timer(3.0).timeout
	var start := tree.current_scene
	print("EXIT start screen: ", start.name if start != null else "none")
	if OS.get_cmdline_user_args().is_empty():
		Session.setup = Session.DEFAULT.duplicate(true)
		Session.setup.merge({"airport": "VAJJ", "start": "runway"}, true)
	Session.setup.record = "--record" in OS.get_cmdline_user_args()  # session recording on (F8): quit while it records
	if Session.setup.record:
		Session.setup.record_dir = OS.get_user_data_dir().path_join("recordings")  # not the game folder
	start._fly()
	if start.get("_confirm") != null:  # the setup checks asked "Fly anyway?": yes
		print("EXIT fly anyway: ", SetupChecks.reasons(SetupChecks.checks(Session.setup)))
		start._confirm.confirmed.emit()
	var t0 := Time.get_ticks_msec()
	while (tree.current_scene == null or tree.current_scene.name != "Flight") and Time.get_ticks_msec() - t0 < 120000:
		await tree.process_frame
	print("EXIT flight scene up after %d ms" % (Time.get_ticks_msec() - t0))
	while BusyOverlay.root_veil(tree) != null and Time.get_ticks_msec() - t0 < 240000:
		await tree.process_frame
	print("EXIT loader gone after %d ms" % (Time.get_ticks_msec() - t0))
	await tree.create_timer(SETTLE_S).timeout
	print("EXIT flying: %s at %s, rpm %.0f" % [Session.setup.aircraft, Session.setup.airport, Props.get_f("engine/rpm")])
	var user := OS.get_cmdline_user_args()
	if "--preset-walk" in user:
		var was: String = Graphics.preset
		for q in Graphics.ORDER + [was]:
			Graphics.preset = q
			Graphics.apply_to_scene(tree.current_scene)
			print("EXIT preset ", q)
			await tree.create_timer(1.5).timeout
	if "--restart" in user:
		OS.set_restart_on_exit(true, PackedStringArray(["--version"]))
		print("EXIT restart on exit set")
	var pause := tree.current_scene.get_node("UI/Pause")
	pause.open()
	await tree.create_timer(1.0).timeout
	print("EXIT quit from the pause screen")
	pause._act("quit")  # "Click again to confirm"
	await tree.create_timer(0.3).timeout
	pause._act("quit")
