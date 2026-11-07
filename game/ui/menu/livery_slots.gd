extends VBoxContainer
## One block per sticker slot. The picture shows in a thumbnail at once, and scale, slide and mirror
## edit the same fields the aircraft is painted with. The mirror toggle is a checkbox, not a filled bar.

signal edited(key: String, fields: Dictionary)
signal load_asked(key: String)

var _guard := false


func bind(slots: Array, placed: Dictionary) -> void:
	_guard = true
	for c in get_children():
		c.free()
	add_theme_constant_override("separation", 10)
	for s in slots:
		add_child(_block(s, placed.get(s.key, {})))
	_guard = false


func _block(slot: Dictionary, cur: Variant) -> Control:
	var st: Dictionary = cur if cur is Dictionary else {}
	var has := str(st.get("image", "")) != ""
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 6)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	card.add_child(top)
	top.add_child(_thumb(str(st.get("image", ""))))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	top.add_child(col)
	var title := Label.new()
	title.text = str(slot.label)
	MenuTheme.use_font(title, "semibold", 16)
	col.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)
	var load := Button.new()
	load.text = "Change picture" if has else "Add picture"
	load.pressed.connect(func(): load_asked.emit(str(slot.key)))
	row.add_child(load)
	var remove := Button.new()
	remove.text = "Remove"
	remove.disabled = not has
	remove.focus_mode = Control.FOCUS_NONE if not has else Control.FOCUS_ALL
	remove.pressed.connect(func(): edited.emit(str(slot.key), {}))
	row.add_child(remove)
	if not has:
		col.add_child(MenuTheme.note("PNG, JPG or WebP, up to 4 MB. It appears on the aircraft as you place it."))
		return card
	var fields := {
		"image": str(st.image),
		"scale": clampf(float(st.get("scale", 1.0)), 0.25, 1.0),
		"dx": clampf(float(st.get("dx", 0.0)), -1.0, 1.0),
		"dy": clampf(float(st.get("dy", 0.0)), -1.0, 1.0),
		"mirror": bool(st.get("mirror", true)),
	}
	var key := str(slot.key)
	card.add_child(_slider("Size", 0.25, 1.0, fields.scale, "scale", _apply.bind(key, fields, "scale")))
	card.add_child(_slider("Sideways", -1.0, 1.0, fields.dx, "dx", _apply.bind(key, fields, "dx")))
	card.add_child(_slider("Up", -1.0, 1.0, fields.dy, "dy", _apply.bind(key, fields, "dy")))
	if slot.has("mirror_box"):
		var mirror := _check("Also on the other side", fields.mirror)
		mirror.toggled.connect(_set_mirror.bind(key, fields))
		card.add_child(mirror)
	return card


func _thumb(file_name: String) -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(84, 84)
	panel.size_flags_vertical = SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.35)
	bg.set_corner_radius_all(8)
	bg.border_color = Color(1, 1, 1, 0.14)
	bg.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", bg)
	var img := LiveryStore.load_image(file_name) if file_name != "" else null
	if img != null:
		var tex := TextureRect.new()
		tex.texture = ImageTexture.create_from_image(img)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tex.offset_left = 6
		tex.offset_top = 6
		tex.offset_right = -6
		tex.offset_bottom = -6
		panel.add_child(tex)
		return panel
	var lab := Label.new()
	lab.text = "No picture"
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuTheme.use_font(lab, "regular", 13)
	lab.add_theme_color_override("font_color", MenuTheme.FAINT)
	panel.add_child(lab)
	return panel


func _check(text: String, on: bool) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.size_flags_horizontal = SIZE_SHRINK_BEGIN
	var s := StyleBoxEmpty.new()
	s.content_margin_left = 4
	s.content_margin_right = 4
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		c.add_theme_stylebox_override(state, s)
	return c


func _apply(value: float, key: String, fields: Dictionary, field: String) -> void:
	fields[field] = value
	_send(key, fields)


func _set_mirror(on: bool, key: String, fields: Dictionary) -> void:
	fields.mirror = on
	_send(key, fields)


func _slider(label: String, lo: float, hi: float, value: float, field: String, on_change: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name := Label.new()
	name.text = label
	name.custom_minimum_size = Vector2(78, 0)
	row.add_child(name)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = 0.05
	sl.value = value
	sl.size_flags_horizontal = SIZE_EXPAND_FILL
	sl.custom_minimum_size = Vector2(80, 0)
	var num := Label.new()
	num.custom_minimum_size = Vector2(48, 0)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	num.add_theme_color_override("font_color", MenuTheme.DIM)
	var show := func(v: float) -> void:
		num.text = "%d%%" % int(round(v * 100.0)) if field == "scale" else "%+.1f" % v
	show.call(value)
	sl.value_changed.connect(func(v: float) -> void:
		show.call(v)
		on_change.call(v)
	)
	row.add_child(sl)
	row.add_child(num)
	return row


func _send(key: String, fields: Dictionary) -> void:
	if not _guard:
		edited.emit(key, fields.duplicate())
