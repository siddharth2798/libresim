extends Node
## E2E start-screen test (no command-line flight options, so the start screen behaves
## as for a player). Configured by environment variables:
##   E2E_OUT=/tmp/e2e/run1  E2E_PHASE=1|2
## Phase 1: the home screen shows alone, Free flight opens the stepper (every step renders and
## shows alone, number keys jump, Esc goes back home), Training / Saved flights / Controls /
## Options open with a Back button, then a VAPO / Overcast / 07:30 setup is chosen and FLY
## pressed; e2e_menu_watch.gd checks the flight. Phase 2 (a new process): the start screen
## remembers that setup and the last choice (Training).

const SETUP := {"airport": "VAPO", "runway": "28", "start": "runway", "time_h": 7.5, "record": false}

var _s: Control
var checks: Array = []
var shots: Array = []
var out := ""


func check(name: String, ok: bool, detail := "") -> void:
	checks.append({"name": name, "ok": ok, "detail": detail})
	print("E2E %s %s: %s" % ["PASS" if ok else "FAIL", name, detail])


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var p := out.path_join("shots/menu_%s.png" % name)
	get_viewport().get_texture().get_image().save_png(p)
	shots.append({"name": name, "path": p})


static func write(dir: String, tag: String, checks_: Array, shots_: Array) -> void:
	DirAccess.make_dir_recursive_absolute(dir.path_join("results"))
	var f := FileAccess.open(dir.path_join("results/%s.json" % tag), FileAccess.WRITE)
	f.store_string(JSON.stringify({"tag": tag, "scenario": tag, "checks": checks_, "shots": shots_, "metrics": {}}, "  "))
	f.close()


func _ready() -> void:
	out = OS.get_environment("E2E_OUT")
	if out == "":
		out = "/tmp/e2e"
	DirAccess.make_dir_recursive_absolute(out.path_join("shots"))
	_s = load("res://ui/menu/start_screen.tscn").instantiate()
	add_child(_s)
	await get_tree().create_timer(1.0).timeout
	if OS.get_environment("E2E_PHASE") == "2":
		await _phase2()
	else:
		await _phase1()


func _only_visible(id: String) -> bool:
	for k in _s._screens:
		if _s._screens[k].visible != (k == id):
			return false
	return true


func _press_key(code: Key, keep_focus := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	if not keep_focus:
		get_viewport().gui_release_focus()
	Input.parse_input_event(e)
	await get_tree().process_frame
	var up := e.duplicate()  # buttons press on key release
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame
	await get_tree().process_frame


func _inside(c: Control) -> bool:
	return c.is_visible_in_tree() and get_viewport().get_visible_rect().encloses(c.get_global_rect())


func _phase1() -> void:
	var home: Control = _s.screen("home")
	check("home_first", _s.cur == "home" and _only_visible("home") and home._cards.size() == 2, "screens built: %s" % [_s._screens.keys()])
	check("home_fits", home._cards.all(func(c): return _inside(c)) and home._more.all(func(b): return _inside(b)), "cards %s" % [home._cards.map(func(c): return c.get_global_rect())])
	await shot("home")
	home._cards[0].grab_focus()  # keyboard: Right / Left move between the cards, Enter confirms
	await _press_key(KEY_RIGHT, true)
	var right_ok: bool = get_viewport().gui_get_focus_owner() == home._cards[1]
	await _press_key(KEY_LEFT, true)
	check("home_arrow_keys", right_ok and get_viewport().gui_get_focus_owner() == home._cards[0], str(get_viewport().gui_get_focus_owner()))
	await _press_key(KEY_2)
	check("home_key_2_focuses_training", get_viewport().gui_get_focus_owner() == home._cards[1], str(get_viewport().gui_get_focus_owner()))
	await _press_key(KEY_1)
	await _press_key(KEY_ENTER, true)
	check("home_enter_confirms", _s.cur == "flight", _s.cur)
	_s.go("home")
	home._cards[0].pressed.emit()  # click Free flight
	await get_tree().process_frame
	var flow: Control = _s.screen("flight")
	check("free_flight_path", _s.cur == "flight" and _only_visible("flight") and flow != null and flow.cur == 0, "cur %s" % _s.cur)
	check("choice_remembered", UserOptions.get_v("start_mode") == "flight", str(UserOptions.get_v("start_mode")))
	for i in flow.STEPS.size():
		flow.show_step(i)
		await get_tree().create_timer(0.8).timeout
		var pg: Control = flow.pages[i]
		check("step %d %s" % [i + 1, flow.STEPS[i][0]], pg.visible and flow.pages.filter(func(p): return p.visible).size() == 1 and pg.get_child_count() > 0 and pg.size.y > 50.0,
			"children %d, size %s" % [pg.get_child_count(), pg.size])
		check("step %d buttons fit" % (i + 1), _inside(flow.back_btn) and _inside(flow.primary_btn), "next %s" % flow.primary_btn.get_global_rect())
		await shot("step_%d" % (i + 1))
	for i in [2, 4, 0]:  # number keys jump to a step
		await _press_key(KEY_1 + i)
		check("key %d jumps to step %d" % [i + 1, i + 1], flow.cur == i, "at step %d" % (flow.cur + 1))
	await _press_key(KEY_ESCAPE)  # Back on the first step returns to the home screen
	check("esc_back_home", _s.cur == "home" and _only_visible("home"), _s.cur)
	home._cards[1].pressed.emit()  # click Training
	await get_tree().create_timer(0.8).timeout
	var tr: Control = _s.screen("training")
	check("training_path", _s.cur == "training" and _only_visible("training") and tr.primary_btn.text.contains("START LESSON"), _s.cur)
	check("start_lesson_visible", _inside(tr.primary_btn) and _inside(tr.back_btn), "start %s" % tr.primary_btn.get_global_rect())
	check("training_choice_remembered", UserOptions.get_v("start_mode") == "training", str(UserOptions.get_v("start_mode")))
	await shot("training")
	tr.back_btn.pressed.emit()
	for id in ["saves", "controls", "options"]:
		_s.go(id)
		await get_tree().create_timer(0.8).timeout
		var fr: Control = _s.screen(id)
		check("page %s" % id, _only_visible(id) and fr.pages[0].size.y > 50.0 and _inside(fr.back_btn), "size %s" % fr.pages[0].size)
		await shot(id)
	_s.go("home")
	Session.setup.merge(SETUP, true)
	Session.apply_weather_preset("Overcast")
	flow._update_summary()
	var summary: String = flow.summary.text
	check("summary_updates", summary.contains("VAPO") and summary.contains("Overcast") and summary.contains("07:30"), summary)
	UserOptions.set_v("start_mode", "training")  # phase 2 checks that the home screen focuses it
	write(out, "menu_phase1", checks, shots)
	var w := Node.new()
	w.set_script(load("res://tests/e2e/e2e_menu_watch.gd"))
	w.set("out", out)
	get_tree().root.add_child(w)
	_s._fly()


func _phase2() -> void:
	var s: Dictionary = Session.setup
	check("remembers_airport", s.airport == "VAPO" and str(s.runway) == "28", "airport %s runway %s" % [s.airport, s.runway])
	check("remembers_weather", s.weather == "Overcast" and absf(float(s.cloud_cover) - 0.95) < 0.01, "weather %s cover %s" % [s.weather, s.cloud_cover])
	check("remembers_time", absf(float(s.time_h) - 7.5) < 0.01, "time_h %s" % s.time_h)
	var home: Control = _s.screen("home")
	check("home_focuses_last_choice", get_viewport().gui_get_focus_owner() == home._cards[1], str(get_viewport().gui_get_focus_owner()))
	await shot("home_remembered")
	_s.go("flight")
	await get_tree().create_timer(0.5).timeout
	check("summary_shows_it", _s.screen("flight").summary.text.contains("VAPO"), _s.screen("flight").summary.text)
	await shot("remembered")
	UserOptions.set_v("start_mode", "flight")  # back to the default (tools/e2e.sh also restores options.cfg)
	write(out, "menu_phase2", checks, shots)
	get_tree().quit()
