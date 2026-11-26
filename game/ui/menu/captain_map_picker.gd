class_name CaptainMapPicker
extends VBoxContainer
## "Choose action": the action list of the Captain Pack map for one control and one aircraft (ui/menu/captain_map_panel.gd shows it in place
## of the pictures). Only the actions that aircraft offers for a control of that type (core/captain_assign.gd `choices`), in sections,
## with a search box (the Controls page's ControlsFilter: name or action id). Each row says where the action is bound now. Pick a
## row: `chosen(action)`. Back, Esc: `cancelled`. Focus stays inside (hidden views cannot take it).

signal chosen(action: String)
signal cancelled

var search: LineEdit
var back_btn: Button
var buttons := {}  # action -> Button
var _rows: Array = []  # [{action, button, texts}]
var _heads: Array = []  # [{label, actions}]
var _none: Label


## sections = CaptainAssign.choices(); where = action -> text of where it is bound now ("Base wheel", or "" when unbound).
func setup(title: String, sections: Array, where: Dictionary, current := "") -> CaptainMapPicker:
	add_theme_constant_override("separation", 8)
	var head := Label.new()
	head.text = title
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_theme_font_size_override("font_size", MenuTheme.SIZE_BIG)
	head.add_theme_color_override("font_color", MenuTheme.ACCENT)
	add_child(head)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	add_child(bar)
	search = LineEdit.new()
	search.placeholder_text = "Search actions"
	search.clear_button_enabled = true
	search.custom_minimum_size = Vector2(220, 38)
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text_changed.connect(_filter)
	bar.add_child(search)
	back_btn = Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(110, 38)
	back_btn.pressed.connect(func(): cancelled.emit())
	bar.add_child(back_btn)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 3)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for s in sections:
		var h := MenuTheme.heading(s[0], 13)
		list.add_child(h)
		var acts: Array = []
		for a in s[1]:
			list.add_child(_row(a, str(where.get(a, "")), a == current))
			acts.append(a)
		_heads.append({"label": h, "actions": acts})
	_none = MenuTheme.note("%s: no action matches. Clear the search box to see them all." % ControlsFilter.NO_MATCH)
	_none.visible = false
	list.add_child(_none)
	return self


func _row(a: String, bound: String, is_current: bool) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 32)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_contents = true
	b.pressed.connect(func(): chosen.emit(a))
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var l := Label.new()
	l.text = str(InputBindings.LABELS.get(a, a)) + ("   (this control)" if is_current else "")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	var w := Label.new()
	w.text = ("now on " + bound) if bound != "" else ""
	w.add_theme_color_override("font_color", MenuTheme.DIM)
	w.add_theme_font_size_override("font_size", 13)
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(w)
	buttons[a] = b
	_rows.append({"action": a, "button": b, "texts": [InputBindings.LABELS.get(a, a), a, bound]})
	return b


func _filter(query: String) -> void:
	var shown := 0
	for r in _rows:
		var ok := ControlsFilter.matches(query, r.texts)
		r.button.visible = ok
		shown += int(ok)
	for h in _heads:
		h.label.visible = h.actions.any(func(a): return buttons[a].visible)
	_none.visible = shown == 0


## Number of rows currently shown (tests).
func shown() -> int:
	return _rows.filter(func(r): return r.button.visible).size()


func _input(e: InputEvent) -> void:
	if is_visible_in_tree() and e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		cancelled.emit()
