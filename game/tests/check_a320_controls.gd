extends Control
## Visual hardware check of the Thrustmaster Captain Pack on the A320: a window listing every control that has to be
## moved once (captain_check.gd), each ticked green when the game's own response proves it works (the real
## JoystickControls with the profile, no saved bindings, nothing is saved). Work through it at your own pace; press
## Complete (or close the window) to finish: the report of what was ticked and what was not goes to the log file.
##
##   SDL_JOYSTICK_MFI=0 SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS=1 ~/.local/bin/godot --path game --windowed \
##       --resolution 1280x720 --audio-driver Dummy res://tests/check_a320_controls.tscn -- [--air] [--out=/tmp/a320_check_report.txt]
##   --air: wheels off the ground (flaps notch 1 then gives CONF 1 instead of 1+F; the checklist accepts both).
## --shot=/path.png saves a picture of the window after 2 s and quits (for looking at the layout without hardware).
## Complete writes the report and quits; Reset ticks starts the list again. The same window shows the live values.

var _out := "/tmp/a320_check_report.txt"
var _air := false
var _shot := ""
var _t := 0.0
var _ctl: AircraftControls
var _joy: JoystickControls
var _check := CaptainCheck.new()
var _flap_names: Array = []
var _rows := {}  # id -> [mark Label, text Label]
var _live := {}  # group -> Label
var _count: Label
var _event: Label
var _log: PackedStringArray = []
var _finished := false


func _ready() -> void:
	process_priority = 100
	AudioServer.set_bus_mute(0, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_move_to_foreground()
	get_tree().set_auto_accept_quit(false)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a == "--air":
			_air = true
		elif a.begins_with("--shot="):
			_shot = a.substr(7)
	Session.save_path = "user://check_a320_unused.json"
	Session.setup["aircraft"] = "a320"
	_ctl = AircraftControls.for_def(AircraftDef.load_def("a320"))
	_ctl.seed_props()
	var cfg = JSON.parse_string(FileAccess.get_file_as_string("res://aircraft/a320/config.json"))
	var fl = cfg.get("controls", {}).get("flaps") if cfg is Dictionary else null
	var dets = fl.get("detents", []) if fl is Dictionary else (fl if fl is Array else [])
	for i in dets.size():
		_flap_names.append(str(dets[i].get("lever", i)) if dets[i] is Dictionary else str(i))
	Props.set_v("fdm/flap_detents", maxi(dets.size(), 4))
	Props.set_v("fdm/wow", not _air)
	_joy = JoystickControls.new()
	add_child(_joy)
	_joy.table = InputBindings.defaults(InputProfiles.CAPTAIN_PACK)
	_joy._rev = int(Props.get_v("input/bindings_rev", 0))
	_build()


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = MenuTheme.make()
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.06, 0.09)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var head := HBoxContainer.new()
	root.add_child(head)
	var title := Label.new()
	title.text = "Captain Pack check, A320: move each control once, in any order"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_count = Label.new()
	_count.add_theme_font_size_override("font_size", 20)
	head.add_child(_count)
	var reset := Button.new()
	reset.text = "Reset ticks"
	reset.pressed.connect(func(): _check.reset())
	head.add_child(reset)
	var done_btn := Button.new()
	done_btn.text = "Complete"
	done_btn.custom_minimum_size = Vector2(150, 40)
	MenuTheme.style_primary(done_btn)
	done_btn.pressed.connect(_finish)
	head.add_child(done_btn)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 14)
	root.add_child(cols)
	var layout := [["Sidestick", "Flaps lever", "Speed brake lever"],
		["Thrust lever 1 (left)", "Thrust lever 2 (right)", "Engine mode selector", "Gear lever"],
		["Auto brake dial", "Engine masters", "Parking brake switch"]]
	for col in layout:
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 6)
		cols.add_child(v)
		for name in col:
			v.add_child(_group(name))
	_event = Label.new()
	_event.add_theme_color_override("font_color", MenuTheme.DIM)
	_event.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_event.custom_minimum_size = Vector2(0, 40)
	root.add_child(_event)


func _group(name: String) -> Control:
	var p := PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	var h := Label.new()
	h.text = name
	h.add_theme_font_size_override("font_size", 16)
	h.add_theme_color_override("font_color", MenuTheme.ACCENT)
	v.add_child(h)
	var live := Label.new()
	live.add_theme_font_size_override("font_size", 12)
	live.add_theme_color_override("font_color", MenuTheme.DIM)
	v.add_child(live)
	_live[name] = live
	for g in CaptainCheck.GROUPS:
		if g[0] != name:
			continue
		for it in g[1]:
			var row := HBoxContainer.new()
			var mark := Label.new()
			mark.custom_minimum_size = Vector2(22, 0)
			var text := Label.new()
			text.text = it[1]
			text.add_theme_font_size_override("font_size", 14)
			row.add_child(mark)
			row.add_child(text)
			v.add_child(row)
			_rows[it[0]] = [mark, text]
	return p


func _val(name: String, default: Variant = 0.0) -> Variant:
	return Props.get_v("controls/" + name) if Props.has("controls/" + name) else default


func _snapshot() -> Dictionary:
	var pad := InputBindings.resolve_device(_joy.table["autobrake_btv"])
	var btn := {}
	for b in range(21, 26):
		btn[b] = pad >= 0 and Input.is_joy_button_pressed(pad, b)
	var p1 := _ctl.levers.pos(0) if _ctl.levers.count > 0 else 0.0
	var p2 := _ctl.levers.pos(1) if _ctl.levers.count > 1 else 0.0
	return {"pitch": float(_val("pitch")), "roll": float(_val("roll")), "yaw": float(_val("yaw")),
		"thr1": p1, "thr2": p2, "name1": LeverDetents.name_at(p1, _ctl.levers.detents, 0.01),
		"name2": LeverDetents.name_at(p2, _ctl.levers.detents, 0.01),
		"rev1": float(_val("reverse_1")), "rev2": float(_val("reverse_2")), "flaps": int(_val("flaps")),
		"sb": float(_val("speedbrake")), "mode": int(_val("engine_mode")), "gear": int(_val("gear")),
		"ab": int(_val("autobrake")), "m1": bool(_val("engine_master_1", false)),
		"m2": bool(_val("engine_master_2", false)), "park": bool(_val("parking_brake", false)), "btn": btn}


func _process(dt: float) -> void:
	if _finished:
		return
	_t += dt
	if _shot != "" and _t > 2.0:
		get_viewport().get_texture().get_image().save_png(_shot)
		get_tree().quit()
		return
	var s := _snapshot()
	for id in _check.feed(s, dt):
		_note("ticked: %s" % id)
	_refresh(s)


func _refresh(s: Dictionary) -> void:
	for id in _rows:
		var ok := _check.is_done(id)
		_rows[id][0].text = "✓" if ok else "○"
		var col: Color = MenuTheme.OK if ok else MenuTheme.TEXT
		_rows[id][0].add_theme_color_override("font_color", col)
		_rows[id][1].add_theme_color_override("font_color", col if ok else MenuTheme.DIM)
	_count.text = "%d / %d" % [_check.checked(), _check.total()]
	var flap: String = str(_flap_names[clampi(s.flaps, 0, _flap_names.size() - 1)]) if not _flap_names.is_empty() else str(s.flaps)
	var modes := ["NORM", "CRANK", "IGN/START"]
	var live := {
		"Sidestick": "pitch %.2f   roll %.2f   twist %.2f" % [s.pitch, s.roll, s.yaw],
		"Thrust lever 1 (left)": "position %.3f %s   reverse %.2f" % [s.thr1, s.name1, s.rev1],
		"Thrust lever 2 (right)": "position %.3f %s   reverse %.2f" % [s.thr2, s.name2, s.rev2],
		"Flaps lever": "setting %s" % flap, "Speed brake lever": "%.2f" % s.sb,
		"Engine mode selector": modes[clampi(s.mode, 0, 2)], "Gear lever": "DOWN" if s.gear == 1 else "UP",
		"Auto brake dial": "level %d   buttons %s" % [s.ab, _pressed(s.btn)],
		"Engine masters": "ENG 1 %s   ENG 2 %s" % ["ON" if s.m1 else "OFF", "ON" if s.m2 else "OFF"],
		"Parking brake switch": "ON" if s.park else "OFF"}
	for g in live:
		_live[g].text = "now: " + live[g]
	_event.text = "  |  ".join(_log)


func _pressed(btn: Dictionary) -> String:
	var out: PackedStringArray = []
	for b in btn:
		if btn[b]:
			out.append(str(b))
	return ",".join(out) if not out.is_empty() else "none"


func _note(s: String) -> void:
	print(s)
	_log.append(s)
	if _log.size() > 4:
		_log = _log.slice(_log.size() - 4)


## Write the report (what ticked, what did not) and quit.
func _finish() -> void:
	if _finished:
		return
	_finished = true
	var lines: PackedStringArray = ["Captain Pack check, A320: %d / %d ticked (%s)" % [
		_check.checked(), _check.total(), "wheels off the ground" if _air else "on the ground"]]
	for g in CaptainCheck.GROUPS:
		for it in g[1]:
			lines.append("[%s] %s: %s" % ["x" if _check.is_done(it[0]) else " ", g[0], it[1]])
	var f := FileAccess.open(_out, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines) + "\n")
		f.close()
	print("\n".join(lines))
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_finish()
