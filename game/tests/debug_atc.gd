extends Node
## Debug: the radio in the real flight scene, screenshots of every look.
##   godot --path game res://tests/debug_atc.tscn -- --airport=VABB --stand --atc_mode=dep
##   godot --path game res://tests/debug_atc.tscn -- --airport=VAPO --air=2000 --air-nm=9 --atc_mode=arr
##   godot --path game res://tests/debug_atc.tscn -- --lesson=landing --atc_mode=lesson   (the bar stays hidden, ATC quiet)
##   godot --path game res://tests/debug_atc.tscn -- --airport=VAJJ --atc_mode=lesson     (idle 25 s: nothing unprompted)
##   godot --path game res://tests/debug_atc.tscn -- --airport=VABB --stand --atc_mode=keys (the e2e panel key sequence)
## dep: collapsed bar, open list, a controller message card (ATIS), history, then COM1 on a frequency
## with no facility with assist off and on. arr: bar, open list inbound, open list on final.
## Saves atc_<mode>_<name>_<w>x<h>.png at 1280x720 and 1920x1080 to $FREESIM_SHOTS (default /tmp)
## and prints the transcript. Needs a display. Radio assist is restored to its saved value at the end.

const SIZES := [Vector2i(1280, 720), Vector2i(1920, 1080)]

var f: Node
var panel: Node
var _mode := "dep"
var _out := "/tmp"
var _assist_saved: Variant = true


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--atc_mode="):
			_mode = a.substr(11)
	if not OS.get_environment("FREESIM_SHOTS").is_empty():
		_out = OS.get_environment("FREESIM_SHOTS")
	_assist_saved = UserOptions.get_v("radio_assist")
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)
	_run()


func _quit(code := 0) -> void:
	UserOptions.set_v("radio_assist", _assist_saved)
	get_tree().quit(code)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _shot(name: String) -> void:
	for i in 6:
		await get_tree().process_frame
	var size := get_viewport().get_visible_rect().size
	var path := _out.path_join("atc_%s_%s_%dx%d.png" % [_mode, name, size.x, size.y])
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path, "  radio rect ", panel._box.get_global_rect())


## The same screen at both sizes.
func _both(name: String) -> void:
	for size in SIZES:
		get_window().size = size
		await _wait(1.0)
		await _shot(name)


## Keep the message card on screen while the window is resized (debug only).
func _pin_card() -> void:
	var notes := get_tree().get_first_node_in_group("notifications")
	if notes != null:
		notes.touch("atc", 90.0)
	panel._cards.left = 90.0
	panel._cards.bar_left = 90.0


func _call(i: int, secs := 4.5) -> void:
	var acts: Array = panel._actions if panel._open else []
	if not panel._open:
		panel._set_open(true)
		acts = panel._actions
	print("ATC call %d of %s (state %s, COM1 %.3f)" % [i, acts.map(func(a): return a.id), panel.session.c.s.state, Props.get_f("controls/com1/freq_mhz")])
	panel._perform(i)
	await _wait(secs)


func _print_log() -> void:
	var s: AtcSession = panel.session
	print("ATC state ", s.c.s.state, " facility ", Props.get_v("atc/facility"), " squawk ", Props.get_v("atc/squawk"))
	for e in s.c.log:
		print("  [%s] %s: %s" % [e.kind, e.who, e.text])


func _run() -> void:
	await _wait(5.0)
	panel = f.get_node("UI/Atc")
	for i in 20:
		if panel.session != null:
			break
		await _wait(0.5)
	for k in ["master_bat", "master_alt", "avionics"]:  # a stand start is cold and dark: the radio needs power
		Props.set_v("controls/electrical/" + k, true)
	await _wait(1.0)
	var s: AtcSession = panel.session
	if s == null:
		print("ATC FAIL: the panel never got a session")
		_quit(1)
		return
	match _mode:
		"lesson":
			await _lesson(s)
		"keys":
			await _keys(s)
		"arr":
			await _arrival()
		_:
			await _departure()
	_print_log()
	_quit()


func _departure() -> void:
	UserOptions.set_v("radio_assist", true)
	await _wait(1.5)
	await _both("1_bar")
	panel._set_open(true)
	await _wait(0.6)
	await _both("2_open_departure")
	await _call(0)  # the suggested call: ATIS (COM1 is tuned to it first)
	await _call(0)  # clearance
	_pin_card()
	await _both("3_card")
	panel._set_open(true)
	panel._toggle_history()
	await _wait(0.6)
	await _both("4_history")
	panel._set_open(false)
	var notes := get_tree().get_first_node_in_group("notifications")
	if notes != null:
		notes.touch("atc", 0.05)  # let the pinned card go
	panel._cards.left = 0.0
	panel._cards.bar_left = 0.0
	Props.set_v("controls/com1/freq_mhz", 118.0)  # a frequency nobody answers on
	await _wait(1.0)
	UserOptions.set_v("radio_assist", false)
	await _wait(1.0)
	panel._set_open(true)
	await _wait(0.6)
	await _both("5_wrong_freq_assist_off")
	panel._set_open(false)
	UserOptions.set_v("radio_assist", true)
	Props.set_v("controls/com1/freq_mhz", 118.0)
	await _wait(1.0)
	panel._set_open(true)
	await _wait(0.6)
	await _both("6_wrong_freq_assist_on")


func _arrival() -> void:
	UserOptions.set_v("radio_assist", true)
	await _wait(1.5)
	await _both("1_bar")
	panel._set_open(true)
	await _wait(0.6)
	await _both("2_open_inbound")
	await _call(0)  # ask for landing
	await _wait(2.0)
	panel._set_open(true)
	await _wait(0.6)
	await _both("3_open_before_final")
	await _call(0)  # report final
	_pin_card()
	await _both("4_card_final")
	panel._set_open(true)
	await _wait(0.6)
	await _both("5_open_on_final")


func _lesson(s: AtcSession) -> void:  # ATC must stay out of a lesson: no calls, no bar, clearances implied
	await _wait(25.0)
	print("ATC lesson '%s': radio visible %s, log lines %d, state %s, cleared_takeoff %s cleared_land %s" % [Session.training,
		panel._box.visible, s.c.log.size(), s.c.s.state, Props.get_v("atc/cleared_takeoff"), Props.get_v("atc/cleared_land")])
	await _shot("lesson")
	panel._set_open(true)  # ` still opens it
	await _wait(0.6)
	await _shot("lesson_open")


func _keys(s: AtcSession) -> void:  # the e2e panel sequence: does any of these keys make ATC speak?
	await _wait(6.0)
	for code in [KEY_F9, KEY_F10, KEY_F2, KEY_N, KEY_QUOTELEFT, KEY_QUOTELEFT]:
		for pressed in [true, false]:
			var ev := InputEventKey.new()
			ev.keycode = code
			ev.physical_keycode = code
			ev.pressed = pressed
			Input.parse_input_event(ev)
			await get_tree().process_frame
		await _wait(0.8)
		print("ATC after %s: radio open %s, bar visible %s, log %d, state %s" % [OS.get_keycode_string(code), panel.menu.visible, panel._box.visible, s.c.log.size(), s.c.s.state])
