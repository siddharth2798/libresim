extends Node
## Debug: the radio panel in the real flight scene with a transcript and the menu open.
##   godot --path game res://tests/debug_atc.tscn -- --airport=VABB --stand [--atc_mode=dep|arr]
##   godot --path game res://tests/debug_atc.tscn -- --airport=VAPO --air=2000 --air-nm=9 --atc_mode=arr
##   godot --path game res://tests/debug_atc.tscn -- --lesson=landing --atc_mode=lesson   (ATC stays quiet in a lesson)
##   godot --path game res://tests/debug_atc.tscn -- --airport=VAJJ --atc_mode=lesson   (idle 25 s: nothing may be said unprompted)
## Plays a short departure (stand: tune Delivery, ATIS, clearance, tune Ground, taxi) or arrival
## (inbound, final) through the radio menu, then saves atc_<mode>_<w>x<h>.png (menu open and
## menu closed) at 1280x720 and 1920x1080 to $FREESIM_SHOTS (default /tmp) and prints the
## transcript. Needs a display.

var f: Node
var panel: Node
var _mode := "dep"
var _out := "/tmp"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--atc_mode="):
			_mode = a.substr(11)
	if not OS.get_environment("FREESIM_SHOTS").is_empty():
		_out = OS.get_environment("FREESIM_SHOTS")
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


## Pick the menu entry with this id (nothing happens if the menu does not offer it).
func _pick(id: String) -> void:
	for e in panel.session.menu():
		if e.id == id:
			panel.session.pick(e)
			print("ATC pick ", id, "  state ", panel.session.c.s.state)
			return
	print("ATC menu has no '%s': %s" % [id, panel.session.menu().map(func(m): return m.id)])


func _shot(name: String) -> void:
	for i in 6:
		await get_tree().process_frame
	var size := get_viewport().get_visible_rect().size
	var path := _out.path_join("atc_%s_%s_%dx%d.png" % [_mode, name, size.x, size.y])
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


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
		get_tree().quit(1)
		return
	if _mode == "lesson":  # ATC must stay out of a lesson: no calls, no panel, clearances implied
		await _wait(25.0)
		print("ATC lesson '%s': panel visible %s, log lines %d, state %s, cleared_takeoff %s cleared_land %s" % [Session.training,
			panel.visible, s.c.log.size(), s.c.s.state, Props.get_v("atc/cleared_takeoff"), Props.get_v("atc/cleared_land")])
		for e in s.c.log:
			print("  [%s] %s: %s" % [e.kind, e.who, e.text])
		await _shot("lesson")
		get_tree().quit()
		return
	if _mode == "keys":  # the e2e panel sequence: does any of these keys make ATC speak?
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
			print("ATC after %s: panel visible %s, log %d, state %s" % [OS.get_keycode_string(code), panel.visible, s.c.log.size(), s.c.s.state])
		for e in s.c.log:
			print("  [%s] %s: %s" % [e.kind, e.who, e.text])
		get_tree().quit()
		return
	if _mode == "dep":
		await _pick_wait("tune")  # first need of a parked aircraft: Clearance Delivery
		await _pick_wait("atis")
		await _pick_wait("clearance")
		await _pick_wait("tune")  # Ground
		await _pick_wait("taxi")
	else:
		await _pick_wait("tune")  # Approach / Tower, whichever the airport has
		await _pick_wait("inbound")
		await _pick_wait("tune")
		await _pick_wait("final")
	print("ATC state ", s.c.s.state, " facility ", Props.get_v("atc/facility"), " squawk ", Props.get_v("atc/squawk"))
	for e in s.c.log:
		print("  [%s] %s: %s" % [e.kind, e.who, e.text])
	for size in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		get_window().size = size
		await _wait(1.5)
		panel._open = true
		panel._refresh()
		await _wait(0.5)
		await _shot("menu")
		panel._open = false
		panel._refresh()
		await _wait(0.5)
		await _shot("log")
		print("ATC panel rect at %s: %s" % [size, panel.get_global_rect()])
	get_tree().quit()


func _pick_wait(id: String) -> void:
	_pick(id)
	await _wait(4.5)
