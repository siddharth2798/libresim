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


## Large home-screen card: dim glass normally, brighter with an accent border when lit
## (hovered or focused).
static func card(lit: bool) -> StyleBoxFlat:
	var s := box(Color(0.10, 0.15, 0.22, 0.93) if lit else PANEL, 16, Color(ACCENT, 0.95) if lit else Color(1, 1, 1, 0.10), 24.0)
	s.set_border_width_all(3 if lit else 1)
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 16 if lit else 6
	return s


## Fill / outline look for the button the player should press next (primary) or a quiet one.
static func style_primary(b: Button, primary := true) -> void:
	var fill := Color(ACCENT, 0.8) if primary else Color(1, 1, 1, 0.07)
	b.add_theme_stylebox_override("normal", box(fill, 8, Color(0, 0, 0, 0) if primary else Color(ACCENT, 0.9)))
	b.add_theme_stylebox_override("hover", box(Color(ACCENT, 0.95) if primary else Color(1, 1, 1, 0.16), 8))
	b.add_theme_stylebox_override("pressed", box(Color(ACCENT, 0.5), 8))
	b.add_theme_color_override("font_color", Color.WHITE)


## Small dark pill for secondary actions that should stay quiet but readable over the backdrop.
static func style_quiet(b: Button) -> void:
	b.add_theme_stylebox_override("normal", box(Color(0.03, 0.05, 0.08, 0.55), 19))
	b.add_theme_stylebox_override("hover", box(Color(1, 1, 1, 0.16), 19))
	b.add_theme_stylebox_override("pressed", box(Color(ACCENT, 0.45), 19))
	b.add_theme_color_override("font_color", Color(TEXT, 0.85))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)


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
