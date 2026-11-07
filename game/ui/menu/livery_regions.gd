extends VBoxContainer
## One card per paint region: the colour it has now, and a grid of square swatches. The swatches do not
## stretch, so a short window cannot squash them into lines.

signal picked(key: String, color: Color)

const SWATCHES: Array[Color] = [
	Color("#ffffff"), Color("#d9d9d9"), Color("#8a8a8a"), Color("#1c1c1c"),
	Color("#102a5c"), Color("#c8102e"), Color("#e07a1f"), Color("#f0c419"),
	Color("#1e7a3a"), Color("#0e7c86"), Color("#1d4e89"), Color("#8a6a2f"),
]
const CHIP := 32.0

var _guard := false


func bind(lv: Dictionary, colors: Dictionary) -> void:
	_guard = true
	for c in get_children():
		c.free()
	add_theme_constant_override("separation", 8)
	for r in lv.get("regions", []):
		add_child(_card(r, colors.get(r.key, r.default) as Color))
	_guard = false


func _card(r: Dictionary, color: Color) -> Control:
	var card := PanelContainer.new()
	card.set_meta("key", str(r.key))
	card.size_flags_horizontal = SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", MenuTheme.box(Color(1, 1, 1, 0.04), 8, Color(1, 1, 1, 0.08), 10))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	var title := Label.new()
	title.text = str(r.label)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	MenuTheme.use_font(title, "semibold", 16)
	head.add_child(title)
	head.add_child(_current(str(r.key), color))
	var grid := GridContainer.new()
	grid.name = "Swatches"
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = SIZE_SHRINK_BEGIN
	grid.size_flags_vertical = SIZE_SHRINK_BEGIN
	box.add_child(grid)
	for c in SWATCHES:
		grid.add_child(_chip(str(r.key), c, color))
	return card


func _current(key: String, color: Color) -> ColorPickerButton:
	var pick := ColorPickerButton.new()
	pick.name = "Current"
	pick.flat = true
	pick.edit_alpha = false
	pick.custom_minimum_size = Vector2(36, 36)
	pick.size_flags_horizontal = SIZE_SHRINK_END
	pick.size_flags_vertical = SIZE_SHRINK_CENTER
	pick.tooltip_text = "Any colour"
	pick.color = color
	var fill := ColorRect.new()
	fill.name = "Fill"
	fill.color = color
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pick.add_child(fill)
	_ring(pick, color, false)
	pick.color_changed.connect(func(col: Color):
		fill.color = col
		_ring(pick, col, false)
		_pick(key, col)
	)
	return pick


func _chip(key: String, color: Color, current: Color) -> Control:
	var wrap := Panel.new()
	wrap.custom_minimum_size = Vector2(CHIP, CHIP)
	wrap.size_flags_horizontal = SIZE_SHRINK_CENTER
	wrap.size_flags_vertical = SIZE_SHRINK_CENTER
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.set_meta("color", color)
	_paint(wrap, color, _near(color, current))
	var hit := Button.new()
	hit.flat = true
	hit.tooltip_text = "#" + color.to_html(false)
	hit.custom_minimum_size = Vector2(CHIP, CHIP)
	hit.size_flags_horizontal = SIZE_SHRINK_CENTER
	hit.size_flags_vertical = SIZE_SHRINK_CENTER
	hit.focus_mode = Control.FOCUS_ALL
	hit.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hit.pressed.connect(_pick.bind(key, color))
	wrap.add_child(hit)
	return wrap


func _pick(key: String, color: Color) -> void:
	if _guard:
		return
	_show(key, color)
	picked.emit(key, color)


func _show(key: String, color: Color) -> void:
	for card in get_children():
		if str(card.get_meta("key", "")) != key:
			continue
		var pick := card.find_child("Current", true, false) as ColorPickerButton
		if pick != null:
			pick.set_block_signals(true)
			pick.color = color
			var fill := pick.get_node_or_null("Fill") as ColorRect
			if fill != null:
				fill.color = color
			pick.set_block_signals(false)
		var grid := card.find_child("Swatches", true, false)
		if grid == null:
			return
		for wrap in grid.get_children():
			_paint(wrap, wrap.get_meta("color"), _near(wrap.get_meta("color"), color))


func _paint(wrap: Control, color: Color, on: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	sb.border_color = MenuTheme.ACCENT if on else Color(1, 1, 1, 0.28)
	sb.set_border_width_all(3 if on else 1)
	wrap.add_theme_stylebox_override("panel", sb)


func _ring(pick: ColorPickerButton, color: Color, _on: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	sb.border_color = Color(1, 1, 1, 0.45)
	sb.set_border_width_all(1)
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		pick.add_theme_stylebox_override(state, sb)


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02
