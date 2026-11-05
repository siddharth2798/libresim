extends VBoxContainer
## One row per paint region: a short row of plain swatches and a colour picker. No airline marks.

signal picked(key: String, color: Color)

const SWATCHES: Array[Color] = [
	Color("#ffffff"), Color("#d9d9d9"), Color("#8a8a8a"), Color("#1c1c1c"),
	Color("#102a5c"), Color("#c8102e"), Color("#e07a1f"), Color("#f0c419"),
	Color("#1e7a3a"), Color("#0e7c86"), Color("#1d4e89"), Color("#8a6a2f"),
]

var _guard := false


func bind(lv: Dictionary, colors: Dictionary) -> void:
	_guard = true
	for c in get_children():
		c.free()
	for r in lv.get("regions", []):
		add_child(_row(r, colors.get(r.key, r.default) as Color))
	_guard = false


func _row(r: Dictionary, color: Color) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var title := Label.new()
	title.text = str(r.label)
	box.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	box.add_child(row)
	for c in SWATCHES:
		var b := Button.new()
		b.custom_minimum_size = Vector2(22, 22)
		b.tooltip_text = "#" + c.to_html(false)
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_corner_radius_all(3)
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(state, sb)
		b.pressed.connect(_pick.bind(str(r.key), c))
		row.add_child(b)
	var pick := ColorPickerButton.new()
	pick.edit_alpha = false
	pick.custom_minimum_size = Vector2(36, 22)
	pick.color = color
	pick.color_changed.connect(func(col): _pick(str(r.key), col))
	row.add_child(pick)
	return box


func _pick(key: String, color: Color) -> void:
	if not _guard:
		picked.emit(key, color)
