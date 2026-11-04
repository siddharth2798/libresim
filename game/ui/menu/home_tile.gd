extends Button
## A quiet link on the home screen (Saved flights, Controls, Options): a small drawn icon, a bold title and
## one dim line under it, in a glass tile (the chosen design's `htile`). Call setup() before adding it.

const BASE_SIZE := Vector2(236, 52)

var _icon: Control
var _title: Label
var _sub: Label
var _kind := ""


func setup(kind: String, title: String, sub: String) -> void:
	_kind = kind
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal := MenuTheme.box(Color(0.03, 0.05, 0.08, 0.62), 12, Color(1, 1, 1, 0.10), 10.0)
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("disabled", normal)
	var hover := MenuTheme.box(Color(30.0 / 255.0, 44.0 / 255.0, 62.0 / 255.0, 0.9), 12, Color(MenuTheme.ACCENT, 0.5), 10.0)
	for k in ["hover", "pressed", "hover_pressed"]:
		add_theme_stylebox_override(k, hover)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_right", 10)
	m.add_theme_constant_override("margin_top", 4)
	m.add_theme_constant_override("margin_bottom", 4)
	add_child(m)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(h)
	_icon = Control.new()
	_icon.custom_minimum_size = Vector2(24, 24)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.draw.connect(_draw_icon)
	h.add_child(_icon)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	_title = Label.new()
	_title.text = title
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_theme_font_override("font", MenuTheme.font("semibold"))
	_title.add_theme_font_size_override("font_size", 16)
	v.add_child(_title)
	_sub = Label.new()
	_sub.text = sub
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub.clip_text = true
	_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_sub.add_theme_color_override("font_color", MenuTheme.DIM)
	_sub.add_theme_font_size_override("font_size", 13)
	v.add_child(_sub)
	custom_minimum_size = BASE_SIZE


func set_sub(text: String) -> void:
	_sub.text = text


func sub_text() -> String:
	return _sub.text


func set_scale_k(k: float) -> void:
	custom_minimum_size = BASE_SIZE * k
	_icon.custom_minimum_size = Vector2.ONE * 24.0 * k
	_title.add_theme_font_size_override("font_size", int(16 * k))
	_sub.add_theme_font_size_override("font_size", int(13 * k))
	_icon.queue_redraw()


## Plain line icons in the accent colour: a floppy disk, a game pad, a cog.
func _draw_icon() -> void:
	var s := _icon.size.x
	var c := MenuTheme.ACCENT
	var w := maxf(2.0, s / 12.0)
	match _kind:
		"save":
			_icon.draw_rect(Rect2(s * 0.14, s * 0.12, s * 0.72, s * 0.76), c, false, w)
			_icon.draw_rect(Rect2(s * 0.30, s * 0.12, s * 0.38, s * 0.24), c, false, w)
			_icon.draw_rect(Rect2(s * 0.28, s * 0.54, s * 0.44, s * 0.34), c, false, w)
		"pad":
			_icon.draw_rect(Rect2(s * 0.06, s * 0.28, s * 0.88, s * 0.46), c, false, w)
			_icon.draw_line(Vector2(s * 0.28, s * 0.38), Vector2(s * 0.28, s * 0.64), c, w)
			_icon.draw_line(Vector2(s * 0.15, s * 0.51), Vector2(s * 0.41, s * 0.51), c, w)
			_icon.draw_circle(Vector2(s * 0.68, s * 0.43), s * 0.05, c)
			_icon.draw_circle(Vector2(s * 0.78, s * 0.57), s * 0.05, c)
		"gear":
			var o := Vector2(s, s) * 0.5
			_icon.draw_arc(o, s * 0.24, 0.0, TAU, 32, c, w, true)
			for i in 8:
				var d := Vector2.from_angle(TAU * i / 8.0)
				_icon.draw_line(o + d * s * 0.33, o + d * s * 0.46, c, w)
