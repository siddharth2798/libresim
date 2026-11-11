extends HBoxContainer
## Controls page (start screen, pause screen, and in flight via ui/controls_overlay.gd), in tabs (ui/menu/menu_tabs.gd):
## Keyboard (rebindable keys: flight controls and ground operations, key_bindings_section.gd), Joystick & gamepad (devices,
## one row per action in Axes / Buttons / Ground operations, controls_row.gd: Bind, clear, a live bar, Tune for axes;
## resets) and Other keys (fixed hotkeys, keyboard_reference.gd). Saves on every change; lists what the aircraft offers.
## The tab bar is sticky (the rows scroll under it) and carries two extras: "Controls for" (the aircraft whose action list is
## shown, show_aircraft(); it only changes the list, never the flight setup or a binding) and a search box that hides the
## rows that do not match (controls_filter.gd; Ctrl+F or Cmd+F focuses it).

signal changed

const ROW := preload("res://ui/menu/controls_row.gd")
const CAPTURE_S := 10.0
const MAX_BUTTONS := 40

var bindings_path := InputBindings.PATH
var controls: AircraftControls  # set before adding to the tree; default = the current aircraft
var table := {}
var start_tab := "keyboard"  # "keyboard" | "joystick" | "other"; set before adding to the tree
var tabs: MenuTabs
var keys: VBoxContainer  # the Keyboard tab (key_bindings_section.gd)
var search: LineEdit
var aircraft_switch: Segmented  # null when only one aircraft is installed
var _rows := {}  # action -> row
var _heads: Array[Label] = []  # the Axes / Buttons / Ground operations headings of the joystick tab, hidden with their rows
var _empties := {}  # tab id -> the "No match" note
var _query := ""
var _other: GridContainer  # the Other keys tab's hotkey list (keyboard_reference.gd)
var _devices: Label
var _status: Label
var _capture := ""  # action waiting for input
var _capture_t := 0.0
var _base := {}  # Vector2i(device, axis) -> raw value when capture started
var _base_btn := {}  # Vector2i(device, button) -> pressed when capture started


func _ready() -> void:
	if controls == null:
		controls = AircraftControls.current()
	table = InputBindings.load_from(bindings_path)
	tabs = MenuTabs.new().setup(false, true)
	add_child(tabs)
	_header_extras()
	_fill_tabs()
	tabs.select(start_tab if tabs.page(start_tab) else "keyboard", false)
	tabs.tab_changed.connect(func(_id): _cancel_capture())
	Input.joy_connection_changed.connect(func(_d, _c): _list_devices())
	_list_devices()


## The three tabs for the current `controls` (first time: add_tab; after an aircraft switch: replace_page).
func _fill_tabs() -> void:
	_rows.clear()
	_heads.clear()
	_empties.clear()
	for t in [["keyboard", "Keyboard", _keyboard_tab()], ["joystick", "Joystick & gamepad", _joystick_tab()], ["other", "Other keys", _other_keys_tab()]]:
		if tabs.page(t[0]) == null:
			tabs.add_tab(t[0], t[1], t[2])
		else:
			tabs.replace_page(t[0], t[2])
	apply_filter(_query)


func _header_extras() -> void:
	var h := ControlsHeader.add(tabs, controls.id if controls.id != "" else AircraftDef.current().id, show_aircraft, apply_filter)
	aircraft_switch = h.switch
	search = h.search


## Lists the actions of another aircraft. Only this page changes: the flight setup, the saved bindings and the
## key profile are untouched (actions an aircraft lacks stay in the profile). The search words stay.
func show_aircraft(id: String) -> void:
	var def := AircraftDef.load_def(id) if AircraftDef.list_ids().has(id) else null  # load_def would turn an unknown id into the default aircraft
	if def == null or def.id == controls.id:
		return
	_cancel_capture()
	controls = AircraftControls.for_def(def)
	_fill_tabs()
	if aircraft_switch != null:
		aircraft_switch.select(def.id)


## Hides the rows that do not match `query` on every tab (controls_filter.gd) and shows a "No match" note on a tab
## that ends up empty. Returns the number of rows left on the tab that shows.
func apply_filter(query: String) -> int:
	_query = query
	var shown := {"keyboard": keys.filter(query), "other": _other.filter(query), "joystick": _filter_joystick(query)}
	for t in _empties:
		(_empties[t] as Control).visible = shown[t] == 0 and not ControlsFilter.words(query).is_empty()
	return shown.get(tabs.current(), 0)


func _filter_joystick(query: String) -> int:
	var n := 0
	var group_shown := {}
	for a in _rows:
		var texts := [InputBindings.LABELS.get(a, a), a, InputBindings.describe(table[a])]
		var ok := ControlsFilter.matches(query, texts)
		(_rows[a] as Control).visible = ok
		n += int(ok)
		var g := _joy_section(a)
		group_shown[g] = group_shown.get(g, false) or ok
	for i in _heads.size():
		_heads[i].visible = group_shown.get(i, false)
	return n


## Joystick tab section of an action: 0 Axes, 1 Buttons, 2 Ground operations (ControlActions.GROUND).
static func _joy_section(a: String) -> int:
	return 0 if InputBindings.is_axis(a) else (2 if a in ControlActions.GROUND else 1)


func _unhandled_key_input(e: InputEvent) -> void:
	if is_visible_in_tree() and e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F and (e.ctrl_pressed or e.meta_pressed):
		search.grab_focus()
		get_viewport().set_input_as_handled()


func _keyboard_tab() -> Control:
	keys = VBoxContainer.new()
	keys.set_script(load("res://ui/menu/key_bindings_section.gd"))
	keys.set("controls", controls)
	keys.connect("changed", func(): changed.emit())
	_empties["keyboard"] = ControlsHeader.no_match_note()
	keys.add_child(_empties["keyboard"])
	return keys


func _joystick_tab() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
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
	dev.add_child(CaptainAskAgain.new())  # only with a Captain Pack and the offer declined
	for p in [["Reset: gamepad defaults", "gamepad"], ["Reset: joystick defaults", "joystick"],
			["Reset: Airbus Captain Pack", InputProfiles.CAPTAIN_PACK]]:
		var b := Button.new()
		b.text = p[0]
		b.size_flags_vertical = SIZE_SHRINK_CENTER
		b.pressed.connect(_reset.bind(p[1]))
		top.add_child(b)
	_status = MenuTheme.note("Bind, then move an axis or press a button (Esc cancels). Keyboard keeps working for anything not bound.")
	col.add_child(_status)
	_heads = [MenuTheme.heading("Axes"), MenuTheme.heading("Buttons"), MenuTheme.heading("Ground operations")]
	for i in _heads.size():
		col.add_child(_heads[i])
		for a in controls.axes() + controls.buttons():
			if _joy_section(a) == i: _add_row(col, a)
	_empties["joystick"] = ControlsHeader.no_match_note()
	col.add_child(_empties["joystick"])
	return col


func _other_keys_tab() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.add_child(MenuTheme.note("These hotkeys are fixed. The flight-control keys are rebindable under Keyboard."))
	var kb := GridContainer.new()
	kb.set_script(load("res://ui/menu/keyboard_reference.gd"))
	kb.set("controls", controls)
	_other = kb
	col.add_child(kb)
	_empties["other"] = ControlsHeader.no_match_note()
	col.add_child(_empties["other"])
	return col


func _add_row(parent: Control, a: String) -> void:
	var r: VBoxContainer = VBoxContainer.new()
	r.set_script(ROW)
	parent.add_child(r)
	r.setup(a, table[a])
	r.edited.connect(_save)
	r.bind_requested.connect(_start_capture)
	_rows[a] = r


## Joystick tab text with no pad; on macOS it points to ./run.sh (sets SDL_JOYSTICK_MFI=0, see docs/USAGE.md).
static func no_pad_text(os_name: String) -> String:
	return "None connected. Plug one in; it shows up here (hot-plug works)." \
		+ (" On macOS start libresim with ./run.sh if a pad is plugged in but missing." if os_name == "macOS" else "")


func _list_devices() -> void:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		_devices.text = no_pad_text(OS.get_name())
		return
	var lines := []
	for d in pads:
		lines.append("Pad %d: %s%s" % [d, Input.get_joy_name(d), "  (gamepad layout)" if Input.is_joy_known(d) else ""])
	_devices.text = "\n".join(lines)


func _reset(profile: String) -> void:
	_cancel_capture()
	for a in InputProfiles.apply_to(table, profile):  # in place: the rows keep their dictionaries
		if _rows.has(a):
			_rows[a].refresh()
	if profile == InputProfiles.CAPTAIN_PACK:
		CaptainDetect.set_state(CaptainDetect.APPLIED)  # the start-screen offer has nothing left to ask
	_status.text = "Reset to %s defaults." % profile + (" Move each quadrant lever once. Linux numbering is unchecked: press Bind to fix a row."
		if profile == InputProfiles.CAPTAIN_PACK else "")
	_save()


func _save() -> void:
	InputBindings.save_bump(table, bindings_path)
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
	for k in InputBindings.CAL_KEYS:  # a new axis has its own travel
		b.erase(k)
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
	return 1.0 if int(b.button) >= 0 and InputBindings.logical(Input.is_joy_button_pressed(dev, int(b.button)), b) else 0.0
