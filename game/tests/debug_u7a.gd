extends Node
## Debug: screenshot of the Failures, Recording, Training or Saved flights page (needs a display). Scratch data only:
## Session.save_path, TrainingLogic.save_path and SituationStore.dir are redirected, the player's files are not touched.
##   U7A_PAGE=failures|recording|training|saves   which page (default failures)
##   U7A_ARMED=0|3        failures: how many scheduled failures are armed first (3 = engine after 10 min, alternator at
##                        start, pitot above 1500 ft AGL)
##   U7A_RANDOM=1         failures: random failures on
##   U7A_AIRCRAFT=a320    choose that aircraft first
##   U7A_REC=1            recording: switched on at 1080p 60 fps
##   U7A_LESSON=0..2      training: which lesson is chosen (stars: Takeoff 3, Cruise 1)
##   U7A_SAVES=0..5       saved flights: how many saves exist (default 5; 0 shows the empty state); U7A_PICK=n selects one
##   U7A_FOCUS=1|switch   put the keyboard focus on the first button of the page, or on its first switch row
##   FREESIM_SIZE=1920x1080, FREESIM_SHOTS=<dir>, FREESIM_TAG=<prefix>   window size, where and how the file is named
const SAVES_DIR := "user://_debug_u7a_saves/"
const SAMPLE := [
	["Evening circuit, Mumbai", "VABB", "c172", 2026, 10, 28, 18, 5, "vabb-golden", 1450.0, 88.0, false],
	["Kochi gate, cold and dark", "VOCI", "a320", 2026, 10, 27, 9, 40, "kochi-gate", 0.0, 0.0, true],
	["Monsoon approach practice", "VAPO", "c172", 2026, 10, 25, 15, 22, "monsoon", 2100.0, 74.0, false],
	["Night final 27", "VAPO", "c172", 2026, 10, 22, 21, 10, "night", 900.0, 70.0, false],
	["Ghats crossing, Pune to Mumbai", "VAPO", "c172", 2026, 10, 19, 7, 55, "ghats", 5200.0, 105.0, false],
]


func _env(k: String, d := "") -> String:
	return OS.get_environment(k) if OS.get_environment(k) != "" else d


func _ready() -> void:
	var size := OS.get_environment("FREESIM_SIZE")
	if size.contains("x"):
		get_window().size = Vector2i(int(size.get_slice("x", 0)), int(size.get_slice("x", 1)))
	Session.skip_menu = false
	Session.interactive_override = 0
	Session.save_path = "user://_debug_u7a_last_flight.json"
	TrainingLogic.save_path = "user://_debug_u7a_training.json"
	SituationStore.dir = SAVES_DIR
	Session.setup = Session.DEFAULT.duplicate(true)  # not the player's last flight
	_clean()
	FileAccess.open(TrainingLogic.save_path, FileAccess.WRITE).store_string(JSON.stringify({"takeoff": 3, "cruise": 1}))
	if _env("U7A_AIRCRAFT") != "":
		Session.setup.aircraft = _env("U7A_AIRCRAFT")
		Session.apply_payload_defaults(AircraftDef.load_def(Session.setup.aircraft))
	var page := _env("U7A_PAGE", "failures")
	if page == "failures":
		if _env("U7A_ARMED", "0") == "3":
			Session.setup.failures = {"engine": [2, 10.0], "alternator": [1, 0.0], "pitot_blocked": [3, 1500.0]}
		Session.setup.random.enabled = _env("U7A_RANDOM") == "1"
	if page == "recording" and _env("U7A_REC") == "1":
		Session.setup.record = true
		Session.setup.record_height = 1080
		Session.setup.record_fps = 60
	Session.setup.record_dir = "user://_debug_u7a_rec" if page == "recording" else Session.setup.record_dir
	if page == "saves":
		_make_saves(int(_env("U7A_SAVES", "5")))
	var scr: Control = load("res://ui/menu/start_screen.tscn").instantiate()
	add_child(scr)
	match page:
		"failures", "recording":
			scr.go("flight")
			scr.screen("flight").show_step(3 if page == "failures" else 4)
		_:
			scr.go(page)
	await get_tree().process_frame
	var p: Control = scr.screen("flight").pages[3 if page == "failures" else 4] if page in ["failures", "recording"] else scr.screen(page).pages[0]
	print("u7a page minimum size ", page, " ", p.get_combined_minimum_size())
	if page == "training":
		p._cards[int(_env("U7A_LESSON", "0"))].button_pressed = true  # the group lights only this one
		p._cards[int(_env("U7A_LESSON", "0"))].pressed.emit()
	if page == "saves" and _env("U7A_PICK") != "":
		p._cards[int(_env("U7A_PICK"))].button_pressed = true
		p._cards[int(_env("U7A_PICK"))].pressed.emit()
	if _env("U7A_FOCUS") == "switch":  # the focus ring of the first switch row
		p.find_children("*", "SwitchRow", true, false).front().grab_focus()
	elif _env("U7A_FOCUS") == "1":
		var first: Control = p.find_children("*", "BaseButton", true, false).filter(func(b): return b.focus_mode == Control.FOCUS_ALL).front()
		if first == null:
			first = p.find_children("*", "SwitchRow", true, false).front()
		first.grab_focus()
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var out := _env("FREESIM_SHOTS", OS.get_user_data_dir())
	get_viewport().get_texture().get_image().save_png(out.path_join("u7a_%s%s.png" % [_env("FREESIM_TAG"), page]))
	_clean()
	get_tree().quit()


func _make_saves(n: int) -> void:
	for i in mini(n, SAMPLE.size()):
		var s: Array = SAMPLE[i]
		var img := Image.load_from_file("res://../docs/ui-rework/assets/saves/%s.jpg" % s[8])
		var meta := {"name": s[0], "unix": float(1000 - i), "date": "%04d-%02d-%02d %02d:%02d" % [s[3], s[4], s[5], s[6], s[7]],
			"airport": s[1], "alt_ft": s[9], "agl_ft": maxf(s[9] - 40.0, 0.0), "ias_kt": s[10], "on_ground": s[11], "aircraft": s[2]}
		SituationStore.write({"meta": meta, "setup": {"weather": "Fair", "time_h": s[6] + s[7] / 60.0, "wind_dir_deg": 270.0, "wind_kt": 8.0}}, s[0], img)


func _clean() -> void:
	for p in [Session.save_path, TrainingLogic.save_path]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	var da := DirAccess.open(SAVES_DIR)
	if da != null:
		for f in da.get_files():
			DirAccess.remove_absolute(SAVES_DIR + f)
		DirAccess.remove_absolute(SAVES_DIR)
