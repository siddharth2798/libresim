class_name MenuTheme
extends RefCounted
## Start-screen look: dark translucent glass panels, one cool accent, larger type.

const ACCENT := Color(0.35, 0.75, 1.0)
const TEXT := Color(0.92, 0.94, 0.97)
const DIM := Color(0.62, 0.66, 0.72)
const PANEL := Color(0.06, 0.08, 0.11, 0.82)


static func box(col: Color, radius := 6, border := Color(0, 0, 0, 0), margin := 10.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin * 0.6
	s.content_margin_bottom = margin * 0.6
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(1)
	return s


static func make() -> Theme:
	var t := Theme.new()
	t.default_font_size = 16
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 10, Color(1, 1, 1, 0.08), 18.0))
	for k in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		var c := Color(1, 1, 1, 0.06)
		match k:
			"hover": c = Color(1, 1, 1, 0.14)
			"pressed", "hover_pressed": c = Color(ACCENT, 0.45)
			"focus": c = Color(0, 0, 0, 0)
		var b := box(c, 6, Color(ACCENT, 0.9) if k == "focus" else Color(0, 0, 0, 0))
		t.set_stylebox(k, "Button", b)
		t.set_stylebox(k, "OptionButton", b)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_stylebox("normal", "LineEdit", box(Color(0, 0, 0, 0.35), 6))
	t.set_stylebox("normal", "SpinBox", box(Color(0, 0, 0, 0.35), 6))
	t.set_stylebox("panel", "ItemList", box(Color(0, 0, 0, 0.3), 6))
	t.set_stylebox("selected", "ItemList", box(Color(ACCENT, 0.4), 4))
	t.set_stylebox("selected_focus", "ItemList", box(Color(ACCENT, 0.55), 4))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_constant("v_separation", "ItemList", 8)
	t.set_color("font_color", "ItemList", TEXT)
	t.set_stylebox("slider", "HSlider", box(Color(1, 1, 1, 0.15), 3, Color(0, 0, 0, 0), 2.0))
	t.set_stylebox("grabber_area", "HSlider", box(Color(ACCENT, 0.8), 3, Color(0, 0, 0, 0), 2.0))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT, 3, Color(0, 0, 0, 0), 2.0))
	return t


static func heading(text: String, size := 15) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ACCENT)
	return l


static func note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", DIM)
	l.add_theme_font_size_override("font_size", 14)
	return l
