extends Node
## Debug: the clickable 2D FCU card of the outside views, driven in the real A320 flight scene with injected mouse input
## (Input.parse_input_event at window coordinates: the piece's screen transform, so UI scale and Retina are included). One report
## line per step: windows, lamps, FMA, hover note. Needs a display; run muted:
##   godot --audio-driver Dummy --path game res://tests/debug_fcu_panel.tscn -- --aircraft=a320 --airport=VABB --air \
##     --shots=<abs dir> --steps=layout:Full,view:1,click:btn_ap1,wheel:knob_spd:5,shot:name
## Steps (comma separated): layout:<Full|Custom|Split>, view:<camera mode index, 1 = chase>, click:<zone id>, +click:<zone id> (Shift),
## wheel:<zone id>:<detents, signed>, drag:<zone id>:<screen px, up negative>, hover:<zone id>, rightclick:<zone id>, wait:<s>,
## set:<prop>=<value>, shot:<name> (saves <shots>/<name>.png), report. Zone ids: knob_spd .. knob_vs, btn_loc, btn_ap1 ...
var f: Node
var _shots := ""
var _steps: PackedStringArray = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots = a.substr(8)
		elif a.begins_with("--steps="):
			_steps = a.substr(8).split(",", false)
	DirAccess.make_dir_recursive_absolute(_shots)
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)
	_run.call_deferred()


func _piece() -> Array:
	var ov: Control = f.get_node("UI/Panel")
	var r: Rect2 = InstrumentPanel.rects().fcu
	for p in ov._pieces:
		if p[0] is TextureRect and (p[1] as Rect2).encloses(r):
			return p
	return []


## Window coordinates of the middle of a zone of the card.
func _at(id: String) -> Vector2:
	var p := _piece()
	var r: Rect2 = InstrumentPanel.rects().fcu
	for z in FcuLayout.zones():
		if z.id == id:
			var panel_px: Vector2 = r.position + (z.rect as Rect2).get_center()
			var local: Vector2 = (panel_px - (p[1] as Rect2).position) / (p[1] as Rect2).size * (p[0] as Control).size
			return (p[0] as Control).get_screen_transform() * local
	return Vector2.ZERO


func _button(at: Vector2, button: int, down: bool, shift := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = down
	e.shift_pressed = shift
	e.position = at
	e.global_position = at
	if down:
		e.button_mask = 1 << (button - 1)
	Input.parse_input_event(e)
	await get_tree().process_frame
	await get_tree().process_frame


func _move(at: Vector2, held := false) -> void:
	get_viewport().warp_mouse(get_viewport().get_final_transform().affine_inverse() * at)  # the hover note is placed at the real pointer
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	Input.parse_input_event(mm)
	await get_tree().process_frame


func _click(id: String, shift := false, button := MOUSE_BUTTON_LEFT) -> void:
	var at := _at(id)
	await _move(at)
	await _button(at, button, true, shift)
	await _button(at, button, false, shift)


func _drag(id: String, dy: float) -> void:
	var at := _at(id)
	await _move(at)
	await _button(at, MOUSE_BUTTON_LEFT, true)
	for i in 10:
		await _move(at + Vector2(0, dy * (i + 1) / 10.0), true)
	await _button(at + Vector2(0, dy), MOUSE_BUTTON_LEFT, false)


func _report(step: String) -> void:
	var a := FcuWindows.spd()
	var h := FcuWindows.hdg()
	var l := FcuWindows.alt()
	var v := FcuWindows.vs()
	var fma := ""
	for c in ["thrust", "vertical", "lateral", "approach", "misc"]:
		fma += "[%s]" % str(Props.get_v("ap/fma/" + c, "")).replace("\n", "/")
	var lamps := ""
	for k in ["ap1", "ap2", "athr", "loc", "appr"]:
		lamps += " %s=%d" % [k, 1 if Props.get_b("ap/" + k) else 0]
	var tip: CockpitTip = null
	for c in f.get_node("Camera").get_children():
		if c is CockpitTip:
			tip = c
	if tip != null:
		print("   tip panel at %s size %s min %s mouse %s view %s" % [tip._panel.position, tip._panel.size, tip._panel.get_combined_minimum_size(),
			get_viewport().get_mouse_position(), get_viewport().get_visible_rect().size])
	print("STEP %-24s | SPD %s%s HDG %s%s ALT %s%s V/S %s | FMA %s | lamps%s | cam %s | mouse mode %s | tip [%s]" % [step, a.text,
		"." if a.dot else "", h.text, "." if h.dot else "", l.text, "." if l.dot else "", v.text, fma, lamps,
		"%s dist %.1f" % [(f.get_node("Camera") as CameraRig).mode, (f.get_node("Camera") as CameraRig)._dist], Input.mouse_mode, tip.shown().replace("\n", " | ") if tip else "-"])


func _put(spec: String) -> void:
	var kv := spec.split("=")
	var v: Variant = kv[1]
	if kv[1] == "true" or kv[1] == "false":
		v = kv[1] == "true"
	elif kv[1].is_valid_float():
		v = float(kv[1])
	Props.set_v(kv[0], v)


func _run() -> void:
	await get_tree().create_timer(8.0).timeout
	var cam: CameraRig = f.get_node("Camera")
	var ov: Control = f.get_node("UI/Panel")
	cam.set_mode(1)
	await get_tree().create_timer(2.0).timeout
	_report("start")
	for st in _steps:
		var p := st.split(":")
		match p[0]:
			"wait":
				await get_tree().create_timer(float(p[1])).timeout
			"set":
				_put(st.substr(4))
			"shot":
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(_shots.path_join(p[1] + ".png"))
			"crop":  # the FCU card and the strip under it (the note), at twice the size
				await RenderingServer.frame_post_draw
				var a := _at("knob_spd") - Vector2(60, 40)
				var b := _at("btn_ls") + Vector2(560, 150)
				var img := get_viewport().get_texture().get_image().get_region(Rect2i(Rect2(a, b - a).intersection(Rect2(Vector2.ZERO, Vector2(get_viewport().get_visible_rect().size)))))
				img.resize(img.get_width() * 2, img.get_height() * 2, Image.INTERPOLATE_LANCZOS)
				img.save_png(_shots.path_join(p[1] + ".png"))
			"layout":
				ov.layout = ov.LAYOUTS.find(p[1])
				ov._build()
				await get_tree().process_frame
			"custom":  # custom:<x>:<y>:<h>: the Custom layout with the FCU piece on there (a throw-away config, not the player's)
				ScreenLayout.cfg_path = "user://fcu_panel_debug.cfg"
				var def := AircraftDef.current()
				var pieces := ScreenLayout.load_pieces(def)
				pieces.fcu.merge({"on": true, "x": float(p[1]), "y": float(p[2]), "h": float(p[3])}, true)
				ScreenLayout.save_pieces(def, pieces)
				ScreenLayout.use_custom()  # as the layout editor does: the overlay re-reads the layout name when the revision changes
				ov.layout = ov.LAYOUTS.find("Custom")
				ov._build()
				await get_tree().process_frame
			"view":
				cam.set_mode(int(p[1]))
			"click":
				await _click(p[1])
			"+click":
				await _click(p[1], true)
			"rightclick":
				await _click(p[1], false, MOUSE_BUTTON_RIGHT)
			"wheel":
				var n := int(p[2])
				for i in absi(n):
					var at := _at(p[1])
					await _move(at)
					await _button(at, MOUSE_BUTTON_WHEEL_UP if n > 0 else MOUSE_BUTTON_WHEEL_DOWN, true)
					await _button(at, MOUSE_BUTTON_WHEEL_UP if n > 0 else MOUSE_BUTTON_WHEEL_DOWN, false)
			"drag":
				await _drag(p[1], float(p[2]))
			"hover":
				var at := _at(p[1])
				await _move(at)
				await get_tree().create_timer(0.6).timeout
			"away":  # the pointer off the panel (the note goes)
				await _move(Vector2(640, 150))
				await get_tree().create_timer(0.5).timeout
			"report":
				pass
		await get_tree().create_timer(0.5).timeout
		_report(st)
	get_tree().quit()
