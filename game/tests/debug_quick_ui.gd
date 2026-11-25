extends Node
## Debug: the four quick UI / avionics fixes in the real A320 flight scene with injected input (needs a display; run with
## --audio-driver Dummy). Prints CHECK lines, screenshots to $FREESIM_SHOTS/quick_<tag>.png (default user://).
##   1  E on the open N map turns edit mode on and off (and the button shows the key)
##   2  the pause screen's Edit route: Save plan, an edit, Load plan (replaces the route ahead), Apply and resume
##   3  V/S: Alt+; (turn) presets and the FMA stays ALT; Shift+Alt+' (pull) flies it; Shift+Alt+; (push) levels off
##   4  the PFD with an ILS tuned (see tests/test_pfd_ils.gd for the drawing rules)
## Env: FREESIM_SIZE=1600x900 window size.

var f: Node
var _out := ""
var _fails := 0
const AC := "a320"


func _ready() -> void:
	var size := OS.get_environment("FREESIM_SIZE")
	if size.contains("x"):
		get_window().size = Vector2i(int(size.get_slice("x", 0)), int(size.get_slice("x", 1)))
	_out = OS.get_environment("FREESIM_SHOTS") if OS.get_environment("FREESIM_SHOTS") != "" else OS.get_user_data_dir()
	Session.interactive_override = 0  # nothing is saved
	PlanStore.dir = "user://quick_ui_plans/"
	var s := Session.DEFAULT.duplicate(true)
	s.aircraft = AC
	s.airport = "VABB"
	s.runway = "27"
	s.start = "air"
	Session.setup = s
	Session.apply_payload_defaults(AircraftDef.load_def(AC))
	var cruise := RouteEdit.default_cruise_ft(AC)
	var d := RouteEdit.db()
	var a: Vector2 = d.position_of("VABB")
	var b: Vector2 = d.position_of("VAPO")
	var side := (b - a).orthogonal().normalized() * 9000.0
	var wps: Array = []
	for k in [[0.25, 1.0], [0.5, -1.0], [0.75, 1.0]]:
		wps.append(RouteBuilder.user_waypoint(a.lerp(b, k[0]) + side * k[1], wps, cruise))
	Session.setup.route = {"dest": "VAPO", "wps": wps, "cruise_ft": cruise, "kind": "manual", "air_at": 1}
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)
	_run.call_deferred()


func _run() -> void:
	await _wait(3.0)
	var t := 0.0
	while f.get("_air_wait") and t < 60.0:
		await _wait(0.5)
		t += 0.5
	await _wait(1.5)
	for k in ["ap1", "athr", "hdg_managed", "spd_managed"]:
		Props.set_v("controls/fcu/" + k, true)
	await _wait(2.0)
	await _map_key()
	await _pause_plans()
	await _vs_knob()
	await _pfd()
	print("DONE: %d failed checks" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


# ---- 1: the map key ----

func _map_key() -> void:
	var map: Control = f.get_node("UI/Map")
	await _key(KEY_N)
	await _wait(1.0)
	_check(map.visible and not map.editing(), "N opens the map in its plain mode")
	await _key(KEY_E)
	await _wait(0.5)
	_check(map.editing(), "E turns edit mode on")
	var strip: MapStrip = map._strip
	_check("(E)" in strip.buttons.edit.text, "the button shows the key: %s" % strip.buttons.edit.text)
	await _shot("map_edit_key")
	await _key(KEY_E)
	await _wait(0.5)
	_check(not map.editing(), "E again turns it off")
	await _key(KEY_E)
	await _key(KEY_N)  # closing the map ends edit mode
	await _wait(0.5)
	await _key(KEY_E)
	await _wait(0.3)
	_check(not map.visible and not map.editing(), "E does nothing on the closed map")


# ---- 2: Save / Load / Apply on the pause screen ----

func _pause_plans() -> void:
	await _key(KEY_ESCAPE)
	await _wait(0.8)
	var pause: Control = f.get_node("UI/Pause")
	await _click(pause._nav["route"], pause._nav["route"].size * 0.5)
	await _wait(1.5)
	var live: Control = pause._pages["route"]
	var rp: Control = live.page
	_check(rp.plans.visible and rp.plans.save_btn.is_visible_in_tree(), "the plan buttons show on the pause Edit route page")
	var rmap: RouteMap = rp.map
	var before: Array = RouteEdit.route_of(rp.live).wps.map(func(w): return w.id)
	var last: Dictionary = rmap.legs.back()
	var spot := rmap.view.to_px(rmap.legs[maxi(rmap.legs.size() - 2, 0)].b.lerp(last.b, 0.5)) + Vector2(70, -60)
	await _click(rmap, spot)
	await _wait(0.5)
	var edited: Array = RouteEdit.route_of(rp.live).wps.map(func(w): return w.id)
	_check(edited.size() == before.size() + 1, "a click adds a point: %s -> %s" % [before, edited])
	await _click(rp.plans.save_btn, rp.plans.save_btn.size * 0.5)
	await _wait(0.6)
	_check(pause.modal_open(), "the Save dialog counts as a modal of the pause screen")
	await _shot("pause_save_dialog")
	var dlg: RoutePlanDialog = rp.plans.dialog
	dlg.name_box.text = "Quick UI test"
	await _click(dlg.save_btn, dlg.save_btn.size * 0.5)
	await _wait(0.6)
	var saved := PlanStore.read("quick_ui_test")
	var saved_ids: Array = (saved.route.wps as Array).map(func(w): return w.id) if not saved.is_empty() else []
	_check(saved_ids.size() == edited.size() + 1 and saved_ids[0] == "WPT01" and not pause.modal_open() and pause.visible,
		"Save writes the whole route, the flown WPT01 first, then the edited route ahead (%s), the dialog closes, the flight stays paused" % [saved_ids])
	await _click(rp.plans.load_btn, rp.plans.load_btn.size * 0.5)
	await _wait(0.6)
	await _shot("pause_load_dialog")
	var load_b := _find_button(rp.plans.dialog, "Load")
	_check(load_b != null, "the Load dialog lists the saved plan")
	if load_b != null:
		await _click(load_b, load_b.size * 0.5)
		await _wait(0.8)
	var now: Array = RouteEdit.route_of(rp.live).wps.map(func(w): return w.id)
	print("route ahead after Load: ", now, "  note: ", rp.note.text)
	_check(Session.setup.airport == "VABB" and rp.note.text != "", "Load tells the player in the note line and the departure stays VABB")
	await _shot("pause_loaded")
	var gps_before := _gps()
	await _click(live.apply_btn, live.apply_btn.size * 0.5)
	await _wait(1.0)
	_check(not pause.visible and _gps() != [] and Session.setup.airport == "VABB",
		"Apply and resume: GPS %s -> %s" % [gps_before, _gps()])


# ---- 3: the V/S knob ----

func _vs_knob() -> void:
	await _wait(2.0)
	var vert := func() -> String: return str(Props.get_v("ap/fma/vertical", "")).get_slice("\n", 0)
	var alt := Units.m_to_ft(Props.get_f("fdm/alt_m"))
	print("vertical mode %s at %.0f ft, FCU alt %.0f" % [vert.call(), alt, Props.get_f("controls/fcu/alt_ft")])
	Props.set_v("controls/fcu/alt_ft", roundf(alt / 100.0) * 100.0 - 2000.0)  # a lower target, as when set for a descent
	await _wait(0.3)
	var mode0: String = vert.call()
	for k in 8:  # Alt+; eight taps: the preset goes to -800
		await _key(KEY_SEMICOLON, false, true)
	await _wait(0.5)
	_check(vert.call() == mode0 and Props.get_f("controls/fcu/vs_fpm") < -500.0,
		"turning the knob only presets: V/S %s, mode still %s (was %s)" % [Props.get_f("controls/fcu/vs_fpm"), vert.call(), mode0])
	_check(Props.get_b("ap/vs_preset") and FcuWindows.vs().text.begins_with("-"), "the FCU V/S window shows the preset %s" % FcuWindows.vs().text)
	await _shot("vs_preset")
	await _key(KEY_APOSTROPHE, true, true)
	await _wait(2.5)
	_check(vert.call() == "V/S", "Shift+Alt+' pulls: mode %s, %.0f fpm" % [vert.call(), Units.mps_to_fpm(Props.get_f("fdm/vs_mps"))])
	await _shot("vs_pulled")
	await _key(KEY_SEMICOLON, true, true)
	await _wait(1.0)
	_check(Props.get_f("controls/fcu/vs_fpm") == 0.0 and vert.call() == "V/S", "Shift+Alt+; pushes: V/S 0")


# ---- 4: the PFD ----

func _pfd() -> void:
	var vals := {"avionics/nav2/kind": "ILS", "avionics/nav2/valid": true, "avionics/nav2/ident": "IBB27", "controls/nav2/freq_mhz": 110.3,
		"avionics/nav2/dme_nm": 8.4, "avionics/nav2/cdi": 1.0, "avionics/nav2/cdi_raw": 2.4, "avionics/nav2/gs_valid": true,
		"avionics/nav2/gs": -0.4, "avionics/nav2/gs_raw": -0.4}
	for k in vals:
		Props.set_v(k, vals[k])
	var vp := SubViewport.new()
	vp.size = Vector2i(900, 720)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var pfd := PFD.new()
	pfd.size = Vector2(900, 720)
	vp.add_child(pfd)
	await _wait(0.5)
	await RenderingServer.frame_post_draw
	var p := _out.path_join("quick_pfd_ils_half_diamond.png")
	vp.get_texture().get_image().save_png(p)
	print("saved ", p)
	Props.set_v("avionics/nav2/cdi_raw", 0.4)
	Props.set_v("avionics/nav2/cdi", 0.4)
	await _wait(0.3)
	await RenderingServer.frame_post_draw
	p = _out.path_join("quick_pfd_ils_full_diamond.png")
	vp.get_texture().get_image().save_png(p)
	print("saved ", p)


# ---- helpers ----

func _find_button(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text and (n as Button).is_visible_in_tree():
		return n
	for c in n.get_children():
		var b := _find_button(c, text)
		if b != null:
			return b
	return null


func _gps() -> Array:
	return [str(Props.get_v("controls/gps/target", ""))] + Array(Props.get_v("controls/gps/route_next", []))


func _check(ok: bool, what: String) -> void:
	print("CHECK %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _px(ctl: Control, local: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * (ctl.get_global_transform_with_canvas() * local)


func _button(at: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	e.position = at
	e.global_position = at
	Input.parse_input_event(e)


func _click(ctl: Control, local: Vector2) -> void:
	var at := _px(ctl, local)
	var m := InputEventMouseMotion.new()
	m.position = at
	m.global_position = at
	Input.parse_input_event(m)
	await get_tree().process_frame
	_button(at, true)
	await get_tree().process_frame
	_button(at, false)
	await get_tree().process_frame


## A key tap (down, a short hold so held-key polling sees it, up), with Shift / Alt when asked.
func _key(code: Key, shift := false, alt := false) -> void:
	var mods: Array = []
	if shift:
		mods.append(KEY_SHIFT)
	if alt:
		mods.append(KEY_ALT)
	for m in mods:  # the held-key polling reads the modifier keys' own state
		_key_event(m, true, shift, alt)
	_key_event(code, true, shift, alt)
	await get_tree().process_frame
	await get_tree().process_frame
	_key_event(code, false, shift, alt)
	for m in mods:
		_key_event(m, false, false, false)
	await get_tree().process_frame


func _key_event(code: Key, down: bool, shift: bool, alt: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.shift_pressed = shift
	e.alt_pressed = alt
	e.pressed = down
	Input.parse_input_event(e)


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var p := _out.path_join("quick_%s.png" % tag)
	get_viewport().get_texture().get_image().save_png(p)
	print("saved ", p)
