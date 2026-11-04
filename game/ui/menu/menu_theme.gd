class_name MenuTheme
extends RefCounted
## Start-screen look: dark translucent glass panels, one cool accent, Fira Sans type.
## Tokens follow the chosen design (docs/ui-rework/shared.css); change them here only.

const ACCENT := Color("59bfff")
const ACCENT_INK := Color("04131d")  # text on a filled accent button (white on the accent is only 2:1)
const TEXT := Color("edf1f7")
const DIM := Color("aab5c5")  # about 7:1 on the glass
const FAINT := Color("7d889a")
const PANEL := Color(9.0 / 255.0, 13.0 / 255.0, 19.0 / 255.0, 0.82)  # rgba(9,13,19,.82)
const PANEL_2 := Color(22.0 / 255.0, 30.0 / 255.0, 42.0 / 255.0, 0.78)
const LINE := Color(1, 1, 1, 0.10)
const OK := Color("6fe3a0")
const WARN := Color("ffb454")
const BAD := Color("ff6b57")
const HOVER_FILL := Color(1, 1, 1, 0.17)  # a plain button: lighter fill on hover
const FOCUS_WIDTH := 3  # px of the accent focus ring

## Type scale (px at UiScale 1.0): body, title, section label, note, big button.
const SIZE_BODY := 16
const SIZE_TITLE := 28
const SIZE_SEC := 13
const SIZE_NOTE := 14
const SIZE_BIG := 20

const FONT_PATHS := {
	"regular": "res://ui/fonts/FiraSans-Regular.ttf",
	"medium": "res://ui/fonts/FiraSans-Medium.ttf",
	"semibold": "res://ui/fonts/FiraSans-SemiBold.ttf",
	"bold": "res://ui/fonts/FiraSans-Bold.ttf",
}

static var _fonts := {}


## The Fira Sans weight "regular" | "medium" | "semibold" | "bold" (loaded once; unknown names give regular).
static func font(weight := "regular") -> Font:
	if not FONT_PATHS.has(weight):
		weight = "regular"
	if not _fonts.has(weight):
		_fonts[weight] = load(FONT_PATHS[weight]) as Font
	return _fonts[weight]


## Sets a Control's font and (optionally) size to a weight, e.g. MenuTheme.use_font(label, "semibold", 28).
static func use_font(c: Control, weight: String, size := 0) -> void:
	c.add_theme_font_override("font", font(weight))
	if size > 0:
		c.add_theme_font_size_override("font_size", size)


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
## `tone` recolours the filled button (WARN for "Fly anyway"); the ink on it stays dark.
static func style_primary(b: Button, primary := true, tone := ACCENT) -> void:
	var lit := tone.lerp(Color.WHITE, 0.33)
	var fill := tone if primary else Color(1, 1, 1, 0.07)
	b.add_theme_stylebox_override("normal", box(fill, 8, Color(0, 0, 0, 0) if primary else Color(ACCENT, 0.9)))
	b.add_theme_stylebox_override("hover", box(lit if primary else HOVER_FILL, 8))
	b.add_theme_stylebox_override("pressed", box(tone.lerp(Color.BLACK, 0.2) if primary else Color(ACCENT, 0.3), 8))
	if primary:
		b.add_theme_stylebox_override("disabled", box(Color(tone, 0.45), 8))
		b.add_theme_font_override("font", font("semibold"))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, ACCENT_INK if primary else TEXT)
	if primary:
		b.add_theme_color_override("font_disabled_color", Color(ACCENT_INK, 0.7))


## Small dark pill for secondary actions that should stay quiet but readable over the backdrop.
static func style_quiet(b: Button) -> void:
	b.add_theme_stylebox_override("normal", box(Color(0.03, 0.05, 0.08, 0.55), 19))
	b.add_theme_stylebox_override("hover", box(Color(1, 1, 1, 0.16), 19))
	b.add_theme_stylebox_override("pressed", box(Color(ACCENT, 0.45), 19))
	b.add_theme_color_override("font_color", Color(TEXT, 0.85))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)


## The 3 px accent focus ring: no fill, drawn just outside the control (keyboard / gamepad focus).
static func focus_box(radius := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.bg_color = Color(0, 0, 0, 0)
	s.border_color = ACCENT
	s.set_border_width_all(FOCUS_WIDTH)
	s.set_corner_radius_all(radius)
	s.set_expand_margin_all(2.0)
	return s


static func make() -> Theme:
	var t := Theme.new()
	t.default_font = font("regular")
	t.default_font_size = SIZE_BODY
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 10, Color(1, 1, 1, 0.08), 18.0))
	for k in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		var c := Color(1, 1, 1, 0.06)
		match k:
			"hover": c = HOVER_FILL
			"pressed", "hover_pressed": c = Color(ACCENT, 0.45)
		var b := box(c, 6)
		for type in ["Button", "OptionButton"]:
			t.set_stylebox(k, type, b)
	for type in ["Button", "OptionButton", "CheckBox", "CheckButton", "MenuButton", "HSlider", "VSlider", "LineEdit", "SpinBox"]:
		t.set_stylebox("focus", type, focus_box())
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
	l.add_theme_font_override("font", font("semibold"))
	l.add_theme_color_override("font_color", ACCENT)
	return l


static func note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", DIM)
	l.add_theme_font_size_override("font_size", SIZE_NOTE)
	return l
