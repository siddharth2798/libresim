extends HBoxContainer
## Controls page (start screen, and in flight via ui/controls_overlay.gd): connected
## joysticks / gamepads, one row per action with Bind (capture the next axis moved
## > 0.5 or button pressed), invert / range / deadzone / curve and a live bar, reset
## to gamepad, joystick or Airbus Captain Pack defaults, rebindable flight keys
## (key_bindings_section.gd) and the other hotkeys. Saves on every change.

signal changed

const ROW := preload("res://ui/menu/controls_row.gd")
const CAPTURE_S := 10.0
const MAX_BUTTONS := 40

var bindings_path := InputBindings.PATH
var table := {}
var _rows := {}  # action -> row
var _devices: Label
var _status: Label
var _capture := ""  # action waiting for input
var _capture_t := 0.0
var _base := {}  # Vector2i(device, axis) -> raw value when capture started
var _base_btn := {}  # Vector2i(device, button) -> pressed when capture started


func _ready() -> void:
	add_theme_constant_override("separation", 16)
	table = InputBindings.load_from(bindings_path)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	col.add_child(top)
	var dev := VBoxContainer.new()
	dev.size_flags_horizontal = SIZE_EXPAND_FILL
	top.add_child(dev)
	dev.add_child(MenuTheme.heading("Joysticks & gamepads"))
	_devices = Label.new()
	_devices.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dev.add_child(_devices)
	var btns := VBoxContainer.new()
	top.add_child(btns)
	for p in [["Reset: gamepad defaults", "gamepad"], ["Reset: joystick defaults", "joystick"],
			["Reset: Airbus Captain Pack", InputProfiles.CAPTAIN_PACK]]:
		var b := Button.new()
		b.text = p[0]
		b.pressed.connect(_reset.bind(p[1]))
		btns.add_child(b)
	_status = MenuTheme.note("Bind, then move an axis or press a button (Esc cancels). Keyboard keeps working for anything not bound.")
	col.add_child(_status)
	col.add_child(MenuTheme.heading("Axes"))
	for a in InputBindings.AXES:
		_add_row(col, a)
	col.add_child(MenuTheme.heading("Buttons"))
	for a in InputBindings.BUTTONS:
		_add_row(col, a)
	var keys := VBoxContainer.new()
	keys.set_script(load("res://ui/menu/key_bindings_section.gd"))
	keys.connect("changed", func(): changed.emit())
	col.add_child(keys)
	col.add_child(MenuTheme.heading("Other keys"))
	var kb := GridContainer.new()
	kb.set_script(load("res://ui/menu/keyboard_reference.gd"))
	col.add_child(kb)
	Input.joy_connection_changed.connect(func(_d, _c): _list_devices())
	_list_devices()


func _add_row(parent: Control, a: String) -> void:
	var r: HBoxContainer = HBoxContainer.new()
	r.set_script(ROW)
	parent.add_child(r)
	r.setup(a, table[a])
	r.edited.connect(_save)
	r.bind_requested.connect(_start_capture)
	_rows[a] = r


func _list_devices() -> void:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		_devices.text = "None connected. Plug one in; it shows up here (hot-plug works)."
		return
	var lines := []
	for d in pads:
		lines.append("Pad %d: %s%s" % [d, Input.get_joy_name(d), "  (gamepad layout)" if Input.is_joy_known(d) else ""])
	_devices.text = "\n".join(lines)


func _reset(profile: String) -> void:
	_cancel_capture()
	var d := InputBindings.defaults(profile)
	for a in d:
		table[a].clear()
		table[a].merge(d[a])  # keep the row's dictionary reference
		_rows[a].refresh()
	_status.text = "Reset to %s defaults." % profile
	if profile == InputProfiles.CAPTAIN_PACK:
		_status.text += " Numbering is provisional: check each Bind. Set each quadrant lever's idle (Lo) and full (Hi)."
	_save()


func _save() -> void:
	InputBindings.save_to(table, bindings_path)
	Props.set_v("input/bindings_rev", int(Props.get_v("input/bindings_rev", 0)) + 1)
	changed.emit()


func _start_capture(a: String) -> void:
	_cancel_capture()
	_capture = a
	_capture_t = CAPTURE_S
	_base.clear()
	_base_btn.clear()
	for d in Input.get_connected_joypads():
		for ax in JOY_AXIS_MAX:
			_base[Vector2i(d, ax)] = Input.get_joy_axis(d, ax)
		for bt in MAX_BUTTONS:
			_base_btn[Vector2i(d, bt)] = Input.is_joy_button_pressed(d, bt)
	_rows[a].set_waiting(true)
	_status.text = "%s: move an axis or press a button…" % InputBindings.LABELS[a]


func _cancel_capture() -> void:
	if _capture != "":
		_rows[_capture].set_waiting(false)
	_capture = ""


func _input(e: InputEvent) -> void:
	if _capture != "" and e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		_cancel_capture()
		_status.text = "Binding cancelled."
		get_viewport().set_input_as_handled()


func _process(dt: float) -> void:
	if not is_visible_in_tree():
		return
	if _capture != "":
		_capture_t -= dt
		if _capture_t <= 0.0:
			_cancel_capture()
			_status.text = "Nothing detected; binding cancelled."
		else:
			_poll_capture()
	for a in _rows:
		_rows[a].set_value(_live(a))


func _poll_capture() -> void:
	var want_axis := InputBindings.is_axis(_capture)
	for d in Input.get_connected_joypads():
		if want_axis:
			for ax in JOY_AXIS_MAX:
				if absf(Input.get_joy_axis(d, ax) - _base.get(Vector2i(d, ax), 0.0)) > 0.5:
					_finish(d, "axis", ax)
					return
		else:
			for bt in MAX_BUTTONS:
				if Input.is_joy_button_pressed(d, bt) and not _base_btn.get(Vector2i(d, bt), false):
					_finish(d, "button", bt)
					return


func _finish(device: int, key: String, idx: int) -> void:
	var b: Dictionary = table[_capture]
	b[key] = idx
	b.device = device
	b.guid = Input.get_joy_guid(device)
	b.name = ""  # now tied to this pad, not a profile's name match
	b.erase("lo")  # a new axis has its own travel
	b.erase("hi")
	_rows[_capture].set_waiting(false)
	_rows[_capture].refresh()
	_status.text = "%s -> %s" % [InputBindings.LABELS[_capture], InputBindings.describe(b)]
	_capture = ""
	_save()


func _live(a: String) -> float:
	var b: Dictionary = table[a]
	var dev := InputBindings.resolve_device(b)
	if dev < 0:
		return 0.0
	if InputBindings.is_axis(a):
		return InputBindings.shape(Input.get_joy_axis(dev, int(b.axis)), b) if int(b.axis) >= 0 else 0.0
	return 1.0 if int(b.button) >= 0 and Input.is_joy_button_pressed(dev, int(b.button)) else 0.0
