extends Node
## MenuTheme (ui/menu/menu_theme.gd): Fira Sans is the default UI font, the tokens equal the chosen
## design (docs/UI-IMPLEMENTATION-PLAN.md, U0), the filled accent button has dark ink with a readable
## contrast, and every control gets the 3 px accent focus ring. Looks themselves are judged by screenshots.

const WEIGHTS := ["regular", "medium", "semibold", "bold"]


## WCAG 2.x relative luminance and contrast ratio of two opaque colours.
func _lum(c: Color) -> float:
	var ch := []
	for v in [c.r, c.g, c.b]:
		ch.append(v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4))
	return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2]


func _contrast(a: Color, b: Color) -> float:
	var la := _lum(a)
	var lb := _lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func test_four_fira_weights_load() -> String:
	for w in WEIGHTS:
		var f := MenuTheme.font(w)
		if f == null or not f is FontFile:
			return "weight %s did not load as a FontFile" % w
		if not (f as FontFile).get_font_name().begins_with("Fira Sans"):
			return "weight %s is %s, not Fira Sans" % [w, (f as FontFile).get_font_name()]
	return ""


func test_weights_are_distinct_cached_and_unknown_falls_back() -> String:
	var seen := {}
	for w in WEIGHTS:
		var f := MenuTheme.font(w)
		if seen.has(f):
			return "%s returned the same font as another weight" % w
		seen[f] = true
		if MenuTheme.font(w) != f:
			return "%s is not cached (a second call gave another object)" % w
	if MenuTheme.font("nonsense") != MenuTheme.font("regular"):
		return "an unknown weight should give Regular"
	if (MenuTheme.font("bold") as FontFile).font_weight <= (MenuTheme.font("regular") as FontFile).font_weight:
		return "Bold should be heavier than Regular"
	return ""


func test_theme_default_font_is_fira_regular() -> String:
	var t := MenuTheme.make()
	if t.default_font != MenuTheme.font("regular"):
		return "Theme.default_font is not Fira Sans Regular"
	var l := Label.new()
	add_child(l)
	var ok := false
	l.theme = t
	ok = l.get_theme_font("font") == MenuTheme.font("regular")
	l.free()
	return "" if ok else "a Label under MenuTheme.make() does not resolve to Fira Sans Regular"


func test_use_font_and_heading_use_emphasis_weights() -> String:
	var l := Label.new()
	MenuTheme.use_font(l, "bold", 30)
	var ok := l.get_theme_font("font") == MenuTheme.font("bold") and l.get_theme_font_size("font_size") == 30
	l.free()
	if not ok:
		return "use_font did not set the weight and size"
	var h := MenuTheme.heading("x")
	var hw := h.get_theme_font("font") == MenuTheme.font("semibold")
	h.free()
	return "" if hw else "heading() should be SemiBold"


func test_tokens_equal_the_design() -> String:
	var have := {
		"ACCENT": MenuTheme.ACCENT, "ACCENT_INK": MenuTheme.ACCENT_INK, "TEXT": MenuTheme.TEXT, "DIM": MenuTheme.DIM,
		"FAINT": MenuTheme.FAINT, "OK": MenuTheme.OK, "WARN": MenuTheme.WARN, "BAD": MenuTheme.BAD,
	}
	var want := {
		"ACCENT": Color("59bfff"), "ACCENT_INK": Color("04131d"), "TEXT": Color("edf1f7"), "DIM": Color("aab5c5"),
		"FAINT": Color("7d889a"), "OK": Color("6fe3a0"), "WARN": Color("ffb454"), "BAD": Color("ff6b57"),
	}
	for k in want:
		if not have[k].is_equal_approx(want[k]):
			return "token %s is %s, design says %s" % [k, have[k].to_html(), want[k].to_html()]
	if absf(MenuTheme.ACCENT.r - 0.349) > 0.002 or absf(MenuTheme.ACCENT.g - 0.749) > 0.002 or MenuTheme.ACCENT.b != 1.0:
		return "ACCENT is not (0.349, 0.749, 1.0)"
	if not MenuTheme.PANEL.is_equal_approx(Color(9 / 255.0, 13 / 255.0, 19 / 255.0, 0.82)):
		return "PANEL is not rgba(9,13,19,.82)"
	return ""


func test_dim_text_is_readable_on_the_glass() -> String:
	# the glass over a dark backdrop is about #090d13; the old DIM (0.62 grey) was about 4:1
	var r := _contrast(MenuTheme.DIM, Color(9 / 255.0, 13 / 255.0, 19 / 255.0))
	return "" if r >= 7.0 else "DIM on the glass is only %.2f:1" % r


func test_primary_button_has_dark_ink_on_the_accent() -> String:
	var b := Button.new()
	MenuTheme.style_primary(b)
	var ink := b.get_theme_color("font_color")
	var fill: Color = (b.get_theme_stylebox("normal") as StyleBoxFlat).bg_color
	var hover: Color = (b.get_theme_stylebox("hover") as StyleBoxFlat).bg_color
	var hov_ink := b.get_theme_color("font_hover_color")
	b.free()
	if _lum(ink) > 0.1:
		return "primary font colour %s is not dark" % ink.to_html()
	var r := _contrast(ink, fill)
	if r < 4.5:
		return "ink on the accent fill is %.2f:1, needs >= 4.5" % r
	if _contrast(hov_ink, hover) < 4.5:
		return "ink on the hover fill is below 4.5:1"
	if _lum(hover) <= _lum(fill):
		return "hover fill should be lighter than the normal fill"
	if _contrast(Color.WHITE, MenuTheme.ACCENT) >= 4.5:
		return "sanity: white on the accent should fail (it is the reason for dark ink)"
	return ""


func test_warn_tone_keeps_dark_ink() -> String:
	var b := Button.new()
	MenuTheme.style_primary(b, true, MenuTheme.WARN)
	var r := _contrast(b.get_theme_color("font_color"), (b.get_theme_stylebox("normal") as StyleBoxFlat).bg_color)
	b.free()
	return "" if r >= 4.5 else "ink on the amber fill is %.2f:1" % r


func test_focus_ring_is_three_px_accent_on_every_control() -> String:
	var t := MenuTheme.make()
	for type in ["Button", "OptionButton", "CheckBox", "CheckButton", "MenuButton", "HSlider", "VSlider", "LineEdit", "SpinBox"]:
		var s := t.get_stylebox("focus", type) as StyleBoxFlat
		if s == null:
			return "%s has no focus stylebox" % type
		for w in [s.border_width_left, s.border_width_right, s.border_width_top, s.border_width_bottom]:
			if w != 3:
				return "%s focus border is %d px, not 3" % [type, w]
		if not s.border_color.is_equal_approx(MenuTheme.ACCENT):
			return "%s focus ring is not the accent colour" % type
		if s.draw_center:
			return "%s focus ring must not fill the control" % type
	return ""


func test_hover_is_a_lighter_fill() -> String:
	var t := MenuTheme.make()
	var n := (t.get_stylebox("normal", "Button") as StyleBoxFlat).bg_color
	var h := (t.get_stylebox("hover", "Button") as StyleBoxFlat).bg_color
	return "" if h.a > n.a else "Button hover fill %s is not lighter than normal %s" % [h, n]
