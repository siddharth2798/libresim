extends Button
## Large choice card for the home screen: glyph badge, big title, one-line description and
## a key hint. Lit (accent border) while hovered or focused; hovering moves the focus here
## so only one card is ever lit. Call setup() before adding it to the tree.

const Glyphs := preload("res://ui/menu/menu_glyphs.gd")
const BASE_SIZE := Vector2(400, 280)

var _glyph: Control
var _title: Label
var _blurb: Label
var _hint: Label


func setup(kind: String, title: String, blurb: String, hint: String) -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_stylebox_override("normal", MenuTheme.card(false))
	add_theme_stylebox_override("disabled", MenuTheme.card(false))
	for k in ["hover", "pressed", "hover_pressed"]:
		add_theme_stylebox_override(k, MenuTheme.card(true))
	var lit := MenuTheme.card(true)  # focus is drawn on top of normal: a tint plus the border
	lit.bg_color = Color(MenuTheme.ACCENT, 0.10)
	lit.shadow_size = 0
	add_theme_stylebox_override("focus", lit)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 20)
	add_child(m)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 10)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)
	_glyph = Control.new()
	_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_glyph.draw.connect(func(): Glyphs.draw(_glyph, kind, has_focus() or is_hovered()))
	v.add_child(_glyph)
	_title = _label(title, Color.WHITE)
	v.add_child(_title)
	_blurb = _label(blurb, MenuTheme.DIM)
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_blurb)
	_hint = _label(hint, Color(MenuTheme.ACCENT, 0.85))
	v.add_child(_hint)
	mouse_entered.connect(grab_focus)
	focus_entered.connect(_glyph.queue_redraw)
	focus_exited.connect(_glyph.queue_redraw)
	mouse_exited.connect(_glyph.queue_redraw)
	set_scale_k(1.0)


func _label(text: String, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", col)
	return l


## Scale the card for bigger windows (1.0 at 1280x720).
func set_scale_k(k: float) -> void:
	custom_minimum_size = BASE_SIZE * k
	_glyph.custom_minimum_size = Vector2.ONE * 96.0 * k
	_title.add_theme_font_size_override("font_size", int(34 * k))
	_blurb.add_theme_font_size_override("font_size", int(18 * k))
	_hint.add_theme_font_size_override("font_size", int(14 * k))
