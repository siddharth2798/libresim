extends Node
## The shared start-screen controls Segmented (ui/menu/segmented.gd) and SwitchRow (ui/menu/switch_row.gd): the pure
## helpers, then the nodes driven by synthetic clicks and keys. The look is checked with the page screenshots.

var _nodes: Array[Node] = []


func _add(n: Node) -> Node:
	add_child(n)
	_nodes.append(n)
	return n


func teardown() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()


func _click(b: Button) -> void:  # what a mouse click does to a toggle button in a group
	b.set_pressed_no_signal(true)
	b.pressed.emit()


func test_segmented_options_are_normalized() -> String:
	var e := Segmented.normalize([[1, "One"], [2, "Two", "tip"], "plain", {"value": 4, "label": "Four"}, 7])
	if e.size() != 5 or e[0].label != "One" or e[1].tip != "tip" or e[2].value != "plain" or e[2].label != "plain":
		return "normalize: %s" % [e]
	if e[3].value != 4 or e[3].label != "Four" or e[4].label != "7":
		return "normalize dict / number: %s" % [e]
	return ""


func test_segmented_index_of_matches_numbers_not_types() -> String:
	var e := Segmented.normalize([[720, "720p"], [0, "Native"], ["a", "A"]])
	if Segmented.index_of(e, 720) != 0 or Segmented.index_of(e, 720.0) != 0 or Segmented.index_of(e, 0) != 1:
		return "an int and a float of the same number should match"
	if Segmented.index_of(e, null) != -1 or Segmented.index_of(e, "720") != -1 or Segmented.index_of(e, 5) != -1:
		return "null, a string of the number and an unknown value match nothing"
	if Segmented.index_of(e, "a") != 2:
		return "a string value should match"
	return ""


func test_segmented_only_the_ends_are_rounded() -> String:
	if Segmented.corner_radii(0, 1, 7) != Vector4i(7, 7, 7, 7):
		return "a single segment is round all over"
	if Segmented.corner_radii(0, 3, 7) != Vector4i(7, 0, 0, 7) or Segmented.corner_radii(2, 3, 7) != Vector4i(0, 7, 7, 0):
		return "first rounds the left, last the right"
	if Segmented.corner_radii(1, 3, 7) != Vector4i.ZERO:
		return "a middle segment is square"
	return ""


func test_segmented_pick_emits_once_and_select_is_silent() -> String:
	var s: Segmented = _add(Segmented.new())
	s.set_options([[24, "24 fps"], [30, "30 fps"], [60, "60 fps"]], 30)
	var got := []
	s.selected.connect(func(v): got.append(v))
	if s.get_value() != 30 or not s.button_of(30).button_pressed or s.button_of(24).button_pressed:
		return "30 fps should start lit"
	_click(s.button_of(60))
	if got != [60] or s.get_value() != 60 or not s.button_of(60).button_pressed:
		return "picking 60 should emit it once: %s / %s" % [got, s.get_value()]
	_click(s.button_of(60))
	if got != [60] or not s.button_of(60).button_pressed:
		return "a re-click must not emit and must stay lit: %s" % [got]
	s.select(24)
	if got != [60] or s.get_value() != 24 or s.button_of(60).button_pressed or not s.button_of(24).button_pressed:
		return "select() moves the light without a signal: %s" % [got]
	return ""


func test_segmented_unmatched_value_lights_nothing_and_rebuilds_clean() -> String:
	var s: Segmented = _add(Segmented.new())
	s.set_options(["a", "b"], "zzz")
	if s.get_value() != null or s.button_of("a").button_pressed or s.button_of("b").button_pressed:
		return "an unknown current value lights nothing"
	s.set_options([["x", "X"], ["y", "Y"], ["z", "Z"]], "y")
	if s.get_child_count() != 3 or s.button_of("a") != null or s.get_value() != "y":
		return "set_options should replace the buttons: %d children" % s.get_child_count()
	return ""


func test_segmented_disabled_and_focus_ring() -> String:
	var s: Segmented = _add(Segmented.new())
	s.set_options([1, 2], 1)
	var b := s.button_of(2)
	var ring: StyleBoxFlat = b.get_theme_stylebox("focus")
	if ring.draw_center or ring.border_color != MenuTheme.ACCENT or ring.border_width_left != MenuTheme.FOCUS_WIDTH:
		return "the focus ring should be MenuTheme.focus_box()"
	if b.focus_mode != Control.FOCUS_ALL:
		return "a segment takes the keyboard focus"
	s.disabled = true
	if not b.disabled or b.focus_mode != Control.FOCUS_NONE:
		return "disabled greys the segments and drops the focus"
	s.set_options([1, 2], 1)
	if not s.button_of(1).disabled:
		return "options set while disabled stay disabled"
	return ""


func test_switch_pure_helpers() -> String:
	if SwitchRow.next_state(false, false) != true or SwitchRow.next_state(true, false) != false:
		return "a click flips the state"
	if SwitchRow.next_state(false, true) != false or SwitchRow.next_state(true, true) != true:
		return "a disabled switch does not flip"
	if SwitchRow.knob_x(false, 46.0, 18.0, 4.0) != 4.0 or SwitchRow.knob_x(true, 46.0, 18.0, 4.0) != 24.0:
		return "knob x: off at the left pad, on at the right pad"
	return ""


func test_switch_click_and_keys_flip_it() -> String:
	var r: SwitchRow = _add(SwitchRow.new().setup("Record", "desc", false))
	var got := []
	r.toggled.connect(func(on): got.append(on))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	r._gui_input(click)
	if got != [true] or not r.is_on():
		return "a click should switch it on: %s" % [got]
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = true
	r._gui_input(key)
	if got != [true, false] or r.is_on():
		return "Enter should switch it off: %s" % [got]
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	r._gui_input(space)
	if got != [true, false, true]:
		return "Space should switch it on: %s" % [got]
	var other := InputEventKey.new()
	other.keycode = KEY_A
	other.pressed = true
	r._gui_input(other)
	if got.size() != 3:
		return "another key must not flip it"
	return ""


func test_switch_set_on_is_silent_and_disabled_is_inert() -> String:
	var r: SwitchRow = _add(SwitchRow.new().setup("Mute", "", true))
	var got := []
	r.toggled.connect(func(on): got.append(on))
	if not r.is_on() or r.focus_mode != Control.FOCUS_ALL:
		return "setup(on) starts on and takes the focus"
	r.set_on(false)
	if not got.is_empty() or r.is_on():
		return "set_on must not emit"
	r.disabled = true
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	r._gui_input(click)
	if not got.is_empty() or r.is_on() or r.focus_mode != Control.FOCUS_NONE or r.modulate.a >= 1.0:
		return "a disabled switch ignores clicks, has no focus and is dimmed"
	return ""


func test_switch_description_line_hides_when_empty() -> String:
	var r: SwitchRow = _add(SwitchRow.new().setup("A", "", false))
	if r._desc.visible:
		return "no description, no line"
	r.set_description("Starts with the flight.")
	if not r._desc.visible or r._desc.text != "Starts with the flight.":
		return "a description shows its line"
	r.set_title("B")
	if r._title.text != "B":
		return "set_title"
	return ""
