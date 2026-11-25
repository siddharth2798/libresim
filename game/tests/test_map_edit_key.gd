extends "res://tests/route_live_base.gd"
## The N map's edit mode has a rebindable key (KeyBindings map_edit_route, default E; MapKeys): it toggles edit mode
## only while the map is open, shows on the Edit route button and in the hint line, and clashes with no other default
## key of any aircraft (nor the fixed hotkeys).

const NO_FILE := "user://no_such_key_bindings_for_tests.json"


func _key(code: Key, shift := false, echo := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.shift_pressed = shift
	e.pressed = true
	e.echo = echo
	return e


func test_edit_route_key_is_bound_and_clashes_with_nothing() -> String:
	var t := KeyBindings.defaults()
	var slots: Array = t.get("map_edit_route", [])
	if slots.size() != 1 or KeyBindings.describe(slots[0]) != "E" or not "map_edit_route" in KeyBindings.PRESS:
		return "Map: edit route defaults to E: %s" % [slots]
	if KeyBindings.LABELS.get("map_edit_route", "") == "" or KeyBindings.RESERVED.has(KEY_E):
		return "it has a Controls page label and E is no fixed hotkey"
	for ctl in [AircraftControls.default_set(), AircraftControls.for_def(AircraftDef.load_def("a320"))]:
		if not ctl.offers("map_edit_route") or not "map_edit_route" in ctl.key_actions():
			return "every aircraft (%s) offers the map key on the Controls page" % ctl.id
		for c in KeyBindings.conflicts(t, ctl.key_actions()):
			if "edit route" in str(c) or "V/S" in str(c):
				return "%s: %s" % [ctl.id, c]
	return ""


func test_map_keys_toggle_edit_only_while_open() -> String:
	var k := MapKeys.new()
	k.path = NO_FILE
	if k.action(_key(KEY_E), false) != "":
		return "E does nothing while the map is closed"
	if k.action(_key(KEY_E), true) != "edit" or k.action(_key(KEY_E, false, true), true) != "":
		return "E toggles edit mode once per press while the map is open"
	if k.action(_key(KEY_N), false) != "toggle" or k.action(_key(KEY_G), true) != "fit" or k.action(_key(KEY_SPACE), true) != "follow":
		return "the fixed map keys still work"
	if not "E: edit route" in k.hint(false) or not "E: done" in k.hint(true):
		return "the hint line names the key: %s / %s" % [k.hint(false), k.hint(true)]
	var strip := MapStrip.new()
	_nodes.append(strip)
	strip.sync(true, false, true, false, k.edit_key())
	var off: String = strip.buttons.edit.text
	strip.sync(true, false, true, true, k.edit_key())
	if off != "Edit route (E)" or strip.buttons.edit.text != "Editing route (E)" or not "(E)" in strip.buttons.edit.tooltip_text:
		return "the button shows the key: %s / %s" % [off, strip.buttons.edit.text]
	return ""


func test_e_on_the_open_map_turns_edit_mode_on_and_off() -> String:
	var d := _flying()
	var m: Control = load("res://ui/moving_map.gd").new()
	m.db = d
	m.keys.path = NO_FILE
	add_child(m)
	_nodes.append(m)
	m.visible = false
	m._unhandled_key_input(_key(KEY_E))
	if m.editing():
		return "the closed map ignores E"
	m.visible = true
	m._unhandled_key_input(_key(KEY_E))
	if not m.editing():
		return "E on the open map starts edit mode"
	m._unhandled_key_input(_key(KEY_E))
	if m.editing():
		return "E again ends it"
	return ""
