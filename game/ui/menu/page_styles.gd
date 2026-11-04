class_name PageStyles
extends RefCounted
## Looks the Failures, Recording, Training and Saved flights pages share (list entries, chips, a count badge, a
## page title line). Static helpers over MenuTheme tokens; no state. (The shared controls are Segmented and SwitchRow.)

const SOFT := Color(MenuTheme.ACCENT, 0.20)  # a lit list entry: accent fill ...
const LINE := Color(MenuTheme.ACCENT, 0.55)  # ... and its border


## A flat toggle entry for a vertical list (areas, help levels): transparent, lit with the accent when pressed.
static func list_item(b: Button, pad_x := 12.0, pad_y := 8.0) -> void:
	b.toggle_mode = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_states(b, [Color(0, 0, 0, 0), Color(1, 1, 1, 0.09), SOFT, Color(MenuTheme.ACCENT, 0.30)], 8, pad_x, pad_y, false)


## A raised toggle card (lessons, saved flights): grey fill, lit with an accent border when pressed.
static func card_item(b: Button, pad_x := 12.0, pad_y := 8.0) -> void:
	b.toggle_mode = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_states(b, [Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.12), SOFT, Color(MenuTheme.ACCENT, 0.30)], 10, pad_x, pad_y, true)


## A small pill toggle (the systems random failures may come from).
static func chip(b: Button) -> void:
	b.toggle_mode = true
	b.add_theme_font_size_override("font_size", MenuTheme.SIZE_NOTE)
	_states(b, [Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.12), SOFT, Color(MenuTheme.ACCENT, 0.30)], 999, 12, 3, true)


## The quiet "x" button of a list row.
static func tiny_button(b: Button) -> void:
	_states(b, [Color(1, 1, 1, 0.07), MenuTheme.HOVER_FILL, Color(MenuTheme.ACCENT, 0.4), Color(MenuTheme.ACCENT, 0.5)], 8, 10, 3, false)


## A count shown at the right edge of a Button (children of a Button are not laid out, so it is anchored to it).
static func badge_on(b: Button) -> Label:
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.offset_right = -10
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", MenuTheme.ACCENT)
	l.add_theme_font_override("font", MenuTheme.font("semibold"))
	b.add_child(l)
	return l


## A bordered dark inset (a path, a picture, a card): the page's quiet container look.
static func inset() -> StyleBoxFlat:
	return MenuTheme.box(Color(0, 0, 0, 0.28), 10, MenuTheme.LINE, 12.0)


## A scroll area that never scrolls sideways and takes the room it is given.
static func scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return s


## Stars of a lesson: filled amber ones then outlines ("" fallback text when not flown).
static func stars_text(n: int) -> String:
	n = clampi(n, 0, 3)
	return ("★".repeat(n) + "☆".repeat(3 - n)) if n > 0 else "not flown yet"


## states = [normal fill, hover fill, pressed fill, hover_pressed fill].
static func _states(b: Button, fills: Array, radius: int, pad_x: float, pad_y: float, border_always: bool) -> void:
	var names := ["normal", "hover", "pressed", "hover_pressed"]
	for i in 4:
		var lit := i >= 2
		var s := StyleBoxFlat.new()
		s.bg_color = fills[i]
		s.set_corner_radius_all(radius)
		s.content_margin_left = pad_x
		s.content_margin_right = pad_x
		s.content_margin_top = pad_y
		s.content_margin_bottom = pad_y
		if lit:
			s.border_color = MenuTheme.ACCENT
			s.set_border_width_all(2)
		elif border_always:
			s.border_color = Color(1, 1, 1, 0.10)
			s.set_border_width_all(1)
		b.add_theme_stylebox_override(names[i], s)
	b.add_theme_stylebox_override("focus", MenuTheme.focus_box(radius if radius < 20 else 14))
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
