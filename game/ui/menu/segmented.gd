class_name Segmented
extends HBoxContainer
## Start-screen control: a row of joined toggle Buttons (one ButtonGroup), exactly one lit. Pages put their options in,
## listen to `selected` and write the value into Session.setup; the control keeps no state outside itself.
##   set_options(options, current = null) -> Segmented   rebuild the buttons. `options`: [value, label] /
##                       [value, label, tooltip] / {value, label, tip} / plain values (label = str(value)).
##                       `current` is the value to light (none if it matches nothing).
##   select(value)       light the button of `value` without emitting `selected`
##   get_value()         the lit value (null when none)
##   set_disabled(bool)  grey out all segments (`disabled` property does the same)
##   button_of(value)    the Button of a value (focus, tests), null if none
##   signal selected(value)   the player picked a different segment (not on select(), not on a re-click)
## Keyboard: Tab enters the row, Left / Right move focus, Space / Enter picks. Focus ring: MenuTheme.focus_box().
## Minimum width is the sum of the labels; `equal_width` (default true) stretches the segments to the row width;
## `pad_x` (12) is the space beside each label. Pure helpers (headless tests): normalize, index_of, corner_radii.

signal selected(value: Variant)

var equal_width := true
var pad_x := 12  # space left and right of each label; set before set_options (a tight row uses less)
var disabled := false:
	set = set_disabled

var _entries: Array = []
var _buttons: Array[Button] = []
var _group := ButtonGroup.new()
var _value: Variant = null


func _init() -> void:
	add_theme_constant_override("separation", 2)


func set_options(options: Array, current: Variant = null) -> Segmented:
	for b in _buttons:
		remove_child(b)
		b.free()
	_buttons.clear()
	_group = ButtonGroup.new()
	_entries = normalize(options)
	_value = null
	for i in _entries.size():
		var e: Dictionary = _entries[i]
		var b := Button.new()
		b.text = e.label
		b.tooltip_text = e.tip
		b.toggle_mode = true
		b.button_group = _group
		b.focus_mode = Control.FOCUS_NONE if disabled else Control.FOCUS_ALL
		b.disabled = disabled
		b.custom_minimum_size = Vector2(0, 36)
		if equal_width:
			b.size_flags_horizontal = SIZE_EXPAND_FILL
		_style(b, i, _entries.size())
		b.pressed.connect(_on_pressed.bind(i))
		add_child(b)
		_buttons.append(b)
	select(current)
	return self


func select(value: Variant) -> void:
	var idx := index_of(_entries, value)
	_value = _entries[idx].value if idx >= 0 else null
	for i in _buttons.size():
		_buttons[i].set_pressed_no_signal(i == idx)


func get_value() -> Variant:
	return _value


func button_of(value: Variant) -> Button:
	var idx := index_of(_entries, value)
	return _buttons[idx] if idx >= 0 else null


func set_disabled(d: bool) -> void:
	disabled = d
	for b in _buttons:
		b.disabled = d
		b.focus_mode = Control.FOCUS_NONE if d else Control.FOCUS_ALL


func _on_pressed(i: int) -> void:
	var v: Variant = _entries[i].value
	if _value != null and typeof(v) == typeof(_value) and v == _value:
		_buttons[i].set_pressed_no_signal(true)  # a re-click keeps the segment lit
		return
	_value = v
	selected.emit(v)


## One segment's look: joined pills, only the ends rounded; the lit one has the accent fill and border.
func _style(b: Button, i: int, n: int) -> void:
	var states := {
		"normal": [Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.10)],
		"hover": [MenuTheme.HOVER_FILL, Color(1, 1, 1, 0.16)],
		"pressed": [Color(MenuTheme.ACCENT, 0.30), MenuTheme.ACCENT],
		"hover_pressed": [Color(MenuTheme.ACCENT, 0.42), MenuTheme.ACCENT],
		"disabled": [Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.06)],
	}
	var r := corner_radii(i, n, 7)
	for k in states:
		var s := StyleBoxFlat.new()
		s.bg_color = states[k][0]
		s.border_color = states[k][1]
		s.set_border_width_all(1)
		s.corner_radius_top_left = r.x
		s.corner_radius_top_right = r.y
		s.corner_radius_bottom_right = r.z
		s.corner_radius_bottom_left = r.w
		s.content_margin_left = pad_x
		s.content_margin_right = pad_x
		s.content_margin_top = 6
		s.content_margin_bottom = 6
		b.add_theme_stylebox_override(k, s)
	b.add_theme_stylebox_override("focus", MenuTheme.focus_box(8))
	b.add_theme_font_override("font", MenuTheme.font("medium"))
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(MenuTheme.TEXT, 0.45))


## [{value, label, tip}] from the mixed forms `set_options` takes.
static func normalize(options: Array) -> Array:
	var out := []
	for o in options:
		if o is Array and o.size() >= 2:
			out.append({"value": o[0], "label": str(o[1]), "tip": str(o[2]) if o.size() > 2 else ""})
		elif o is Dictionary and o.has("value"):
			out.append({"value": o.value, "label": str(o.get("label", o.value)), "tip": str(o.get("tip", ""))})
		else:
			out.append({"value": o, "label": str(o), "tip": ""})
	return out


## Index of `value` in normalized entries (int and float of the same number match), -1 when absent or null.
static func index_of(entries: Array, value: Variant) -> int:
	if value == null:
		return -1
	for i in entries.size():
		var v: Variant = entries[i].value
		var num := (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		if (num or typeof(v) == typeof(value)) and v == value:
			return i
	return -1


## Corner radii (top-left, top-right, bottom-right, bottom-left) of segment i of n: only the row's two ends are rounded.
static func corner_radii(i: int, n: int, r: int) -> Vector4i:
	var left := i == 0
	var right := i == n - 1
	return Vector4i(r if left else 0, r if right else 0, r if right else 0, r if left else 0)
