extends VBoxContainer
## One block per sticker slot: load a picture, scale and slide it inside the box, mirror, remove.
## `edited` carries the fields to store, or {} to clear the slot.

signal edited(key: String, fields: Dictionary)
signal load_asked(key: String)

var _guard := false


func bind(slots: Array, placed: Dictionary) -> void:
	_guard = true
	for c in get_children():
		c.free()
	for s in slots:
		add_child(_block(s, placed.get(s.key, {})))
	_guard = false


func _block(slot: Dictionary, cur: Variant) -> Control:
	var st: Dictionary = cur if cur is Dictionary else {}
	var has := str(st.get("image", "")) != ""
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var title := Label.new()
	title.text = str(slot.label)
	box.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var load := Button.new()
	load.text = "Change picture" if has else "Load picture"
	load.pressed.connect(func(): load_asked.emit(str(slot.key)))
	row.add_child(load)
	var remove := Button.new()
	remove.text = "Remove"
	remove.disabled = not has
	remove.pressed.connect(func(): edited.emit(str(slot.key), {}))
	row.add_child(remove)
	if not has:
		return box
	var fields := {
		"image": str(st.image),
		"scale": clampf(float(st.get("scale", 1.0)), 0.25, 1.0),
		"dx": clampf(float(st.get("dx", 0.0)), -1.0, 1.0),
		"dy": clampf(float(st.get("dy", 0.0)), -1.0, 1.0),
		"mirror": bool(st.get("mirror", true)),
	}
	box.add_child(_slider("Scale", 0.25, 1.0, fields.scale, _apply.bind(str(slot.key), fields, "scale")))
	box.add_child(_slider("Across", -1.0, 1.0, fields.dx, _apply.bind(str(slot.key), fields, "dx")))
	box.add_child(_slider("Up", -1.0, 1.0, fields.dy, _apply.bind(str(slot.key), fields, "dy")))
	if slot.has("mirror_box"):
		var mirror := CheckBox.new()
		mirror.text = "Mirror on the other side"
		mirror.button_pressed = fields.mirror
		mirror.toggled.connect(_set_mirror.bind(str(slot.key), fields))
		box.add_child(mirror)
	return box


func _apply(value: float, key: String, fields: Dictionary, field: String) -> void:
	fields[field] = value
	_send(key, fields)


func _set_mirror(on: bool, key: String, fields: Dictionary) -> void:
	fields.mirror = on
	_send(key, fields)


func _slider(label: String, lo: float, hi: float, value: float, on_change: Callable) -> Control:
	var row := HBoxContainer.new()
	var name := Label.new()
	name.text = label
	name.custom_minimum_size = Vector2(56, 0)
	row.add_child(name)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = 0.05
	sl.value = value
	sl.size_flags_horizontal = SIZE_EXPAND_FILL
	sl.custom_minimum_size = Vector2(120, 0)
	sl.value_changed.connect(on_change)
	row.add_child(sl)
	return row


func _send(key: String, fields: Dictionary) -> void:
	if not _guard:
		edited.emit(key, fields.duplicate())
