extends Node
## E2E start-screen test (no command-line flight options, so the start screen behaves
## as for a player). Configured by environment variables:
##   E2E_OUT=/tmp/e2e/run1  E2E_PHASE=1|2
## Phase 1: every page renders and shows alone, number keys switch pages, then a VAPO /
## Overcast / 07:30 setup is chosen and FLY pressed; e2e_menu_watch.gd checks the flight.
## Phase 2 (a new process): the start screen remembers that setup.

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


func _only_visible(i: int) -> bool:
	for k in _s._pages.size():
		if _s._pages[k].visible != (k == i):
			return false
	return true


func _phase1() -> void:
	for i in _s.PAGES.size():
		_s._show(i)
		await get_tree().create_timer(0.8).timeout
		var pg: Control = _s._pages[i]
		check("page %d %s" % [i + 1, _s.PAGES[i][0]], _only_visible(i) and pg.get_child_count() > 0 and pg.size.y > 50.0,
			"children %d, size %s" % [pg.get_child_count(), pg.size])
		await shot("page_%d" % (i + 1))
	for i in [2, 7, 0]:  # number keys switch pages
		var e := InputEventKey.new()
		e.keycode = KEY_1 + i
		e.physical_keycode = KEY_1 + i
		e.pressed = true
		get_viewport().gui_release_focus()
		Input.parse_input_event(e)
		await get_tree().process_frame
		await get_tree().process_frame
		check("key %d switches page" % (i + 1), _only_visible(i), "")
	Session.setup.merge(SETUP, true)
	Session.apply_weather_preset("Overcast")
	_s._update_summary()
	var summary: String = _s._summary.text
	check("summary_updates", summary.contains("VAPO") and summary.contains("Overcast") and summary.contains("07:30"), summary)
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
	check("summary_shows_it", _s._summary.text.contains("VAPO"), _s._summary.text)
	await shot("remembered")
	write(out, "menu_phase2", checks, shots)
	get_tree().quit()
