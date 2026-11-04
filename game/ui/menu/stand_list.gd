class_name StandList
extends ScrollContainer
## The stands on offer as a scrolling column of two-line choice buttons: the name, then "jetbridge gate / remote stand
## . near Terminal 1", with the same blue / amber dot as the map. One is the choice (accent outline); `picked(name)`
## when the pilot presses one. Holds no state beyond the buttons.

signal picked(name: String)

var _col: VBoxContainer
var _btns := {}  # name -> Button
var _group := ButtonGroup.new()
static var _dots := {}


func _init() -> void:
	size_flags_vertical = SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0, 150)
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_col = VBoxContainer.new()
	_col.size_flags_horizontal = SIZE_EXPAND_FILL
	_col.add_theme_constant_override("separation", 4)
	add_child(_col)


## rows: [{name, jetbridge, sub}] in display order.
func set_rows(rows: Array, selected: String) -> void:
	for c in _col.get_children():
		_col.remove_child(c)
		c.queue_free()
	_btns.clear()
	for r in rows:
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = _group
		b.tooltip_text = "%s  ·  %s" % [r.name, r.sub]
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 50)
		b.clip_contents = true
		AirportStartPanel.style_choice(b)
		_fill(b, r)
		var nm: String = r.name
		b.pressed.connect(func(): picked.emit(nm))
		_col.add_child(b)
		_btns[nm] = b
	mark(selected)


func mark(name: String) -> void:
	for n in _btns:
		_btns[n].set_pressed_no_signal(n == name)
	if _btns.has(name) and is_visible_in_tree():
		_show.call_deferred(name)


func button(name: String) -> Button:
	return _btns.get(name)


func _show(name: String) -> void:  # (deferred: the row may have been replaced meanwhile)
	var b: Button = _btns.get(name)
	if b != null and is_instance_valid(b) and is_ancestor_of(b):
		ensure_control_visible(b)


## The two lines and the dot; the labels shorten with an ellipsis instead of widening the column.
func _fill(b: Button, r: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	var dot := TextureRect.new()
	dot.texture = _dot(r.jetbridge)
	dot.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(dot)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	for k in 2:
		var l := Label.new()
		l.text = str(r.name) if k == 0 else str(r.sub)
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.custom_minimum_size = Vector2(10, 0)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if k == 1:
			l.add_theme_color_override("font_color", MenuTheme.DIM)
			l.add_theme_font_size_override("font_size", MenuTheme.SIZE_NOTE)
		col.add_child(l)
	b.add_child(row)


static func _dot(jetbridge: bool) -> Texture2D:
	if not _dots.has(jetbridge):
		var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
		var col := AirportDiagram.GATE if jetbridge else AirportDiagram.BAY
		for x in 14:
			for y in 14:
				if Vector2(x + 0.5, y + 0.5).distance_to(Vector2(7, 7)) <= 5.5:
					img.set_pixel(x, y, col)
		_dots[jetbridge] = ImageTexture.create_from_image(img)
	return _dots[jetbridge]
