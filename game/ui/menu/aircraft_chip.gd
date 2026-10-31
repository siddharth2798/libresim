class_name AircraftChip
extends Button
## One choice on the aircraft page: the aircraft's picture, its name and a short line (the first part
## of aircraft.json "category"). Toggle button in a ButtonGroup, so exactly one chip is lit.

const SIZE := Vector2(300, 58)
const THUMB := Vector2(96, 38)

var id := ""


func setup(j: Dictionary, group: ButtonGroup) -> AircraftChip:
	id = str(j.get("id", ""))
	toggle_mode = true
	button_group = group
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	custom_minimum_size = SIZE
	add_theme_stylebox_override("normal", MenuTheme.box(Color(1, 1, 1, 0.05), 10, Color(1, 1, 1, 0.10)))
	add_theme_stylebox_override("hover", MenuTheme.box(Color(1, 1, 1, 0.12), 10, Color(1, 1, 1, 0.25)))
	var lit := MenuTheme.box(Color(MenuTheme.ACCENT, 0.20), 10, Color(MenuTheme.ACCENT, 0.95))
	lit.set_border_width_all(2)
	for k in ["pressed", "hover_pressed", "focus"]:
		add_theme_stylebox_override(k, lit)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 7)
	add_child(m)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(row)
	var thumb := TextureRect.new()
	thumb.texture = AircraftDef.load_def(id).preview()
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb.custom_minimum_size = THUMB
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(thumb)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var title := Label.new()
	title.text = str(j.get("short_name", j.get("name", id)))
	title.clip_text = true
	title.add_theme_font_size_override("font_size", 16)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title)
	var sub := Label.new()
	sub.text = str(j.get("category", "")).split(" · ")[0]
	sub.clip_text = true
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", MenuTheme.DIM)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(sub)
	return self
