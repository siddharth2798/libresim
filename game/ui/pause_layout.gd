extends RefCounted
## The widgets of the pause screen (ui/pause_menu.gd): title bar, the left column of big items,
## the content panel and the key-hint footer. Each builder returns {root, ...the labels and
## buttons the pause screen updates}. No behaviour here; the pause screen wires the callbacks.

const Credits := preload("res://ui/credits_screen.gd")  # the data attribution line stays on screen
const LOGO := "res://branding/logo.png"
const NAV_W := 270.0
const DANGER := Color(0.85, 0.25, 0.22)
const GLASS := Color(0.05, 0.07, 0.10)  # panel colour (more see-through than the start screen's)
const HINTS := [["Esc", "Resume"], ["↑ ↓", "Navigate"], ["← →", "Menu / page"], ["Enter", "Select"], ["Mouse", "Click anything"]]


## "PAUSED", the context line and the logo.
static func header() -> Dictionary:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 0)
	hb.add_child(vb)
	var t := Label.new()
	t.text = "PAUSED"
	t.add_theme_font_size_override("font_size", 44)
	t.add_theme_color_override("font_color", Color.WHITE)
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	t.add_theme_constant_override("outline_size", 6)
	vb.add_child(t)
	var ctx := Label.new()
	ctx.add_theme_font_size_override("font_size", 18)
	ctx.add_theme_color_override("font_color", Color(MenuTheme.TEXT, 0.8))
	ctx.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vb.add_child(ctx)
	if ResourceLoader.exists(LOGO):
		var logo := TextureRect.new()
		logo.texture = load(LOGO)
		logo.custom_minimum_size = Vector2(52, 52)
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(logo)
	return {"root": hb, "context": ctx}


## The big items. on_press(id) / on_focus(id) are bound per button.
static func nav_column(items: Array, on_press: Callable, on_focus: Callable) -> Dictionary:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(NAV_W, 0)
	pc.add_theme_stylebox_override("panel", MenuTheme.box(Color(GLASS, 0.72), 12, Color(1, 1, 1, 0.10), 10.0))
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pc.add_child(sc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 2)
	sc.add_child(vb)
	var buttons := {}
	for it in items:
		if it.has("sep"):
			var sep := HSeparator.new()
			sep.modulate = Color(1, 1, 1, 0.35)
			vb.add_child(sep)
			continue
		var b := _nav_button(it, on_press, on_focus)
		vb.add_child(b)
		buttons[it.id] = b
	return {"root": pc, "buttons": buttons}


static func _nav_button(it: Dictionary, on_press: Callable, on_focus: Callable) -> Button:
	var b := Button.new()
	b.text = it.label
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 38)
	b.add_theme_font_size_override("font_size", 18)
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	b.pressed.connect(on_press.bind(it.id))
	b.focus_entered.connect(on_focus.bind(it.id))
	if it.has("key"):
		var k := Label.new()
		k.text = it.key
		k.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		k.offset_right = -14
		k.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		k.mouse_filter = Control.MOUSE_FILTER_IGNORE
		k.add_theme_font_size_override("font_size", 13)
		k.add_theme_color_override("font_color", MenuTheme.DIM)
		b.add_child(k)
	style_nav(b, false, false)
	return b


## current: the page shown on the right (filled); danger: waiting for the second click.
static func style_nav(b: Button, current: bool, danger: bool) -> void:
	var fill := Color(DANGER, 0.6) if danger else (Color(MenuTheme.ACCENT, 0.3) if current else Color(1, 1, 1, 0.0))
	b.add_theme_stylebox_override("normal", _nav_box(fill))
	b.add_theme_stylebox_override("hover", _nav_box(Color(DANGER, 0.75) if danger else Color(1, 1, 1, 0.13)))
	b.add_theme_stylebox_override("pressed", _nav_box(Color(MenuTheme.ACCENT, 0.5)))
	b.add_theme_color_override("font_color", Color.WHITE if current or danger else MenuTheme.TEXT)


static func _nav_box(fill: Color) -> StyleBoxFlat:
	var s := MenuTheme.box(fill, 8, Color(0, 0, 0, 0), 16.0)
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	return s


## The right-hand panel: page title, sub-title and the host the pages stack in.
static func content_panel() -> Dictionary:
	var pc := PanelContainer.new()
	var glass := MenuTheme.box(Color(GLASS, 0.66), 12, Color(1, 1, 1, 0.10), 12.0)
	glass.content_margin_top = 12
	glass.content_margin_bottom = 12
	pc.add_theme_stylebox_override("panel", glass)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	pc.add_child(vb)
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 30)
	vb.add_child(title)
	var sub := MenuTheme.note("")
	sub.add_theme_font_size_override("font_size", 15)
	vb.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	vb.add_child(gap)
	var host := MarginContainer.new()
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(host)
	return {"root": pc, "title": title, "sub": sub, "host": host}


## Key hints and the data attribution line.
static func footer() -> Dictionary:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 22)
	col.add_child(hb)
	var esc: Label
	for h in HINTS:
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 8)
		var key := Label.new()
		key.text = h[0]
		key.add_theme_font_size_override("font_size", 14)
		key.add_theme_stylebox_override("normal", MenuTheme.box(Color(1, 1, 1, 0.14), 5, Color(1, 1, 1, 0.25), 9.0))
		chip.add_child(key)
		var what := Label.new()
		what.text = h[1]
		what.add_theme_font_size_override("font_size", 15)
		what.add_theme_color_override("font_color", Color(MenuTheme.TEXT, 0.85))
		chip.add_child(what)
		hb.add_child(chip)
		if h[0] == "Esc":
			esc = what
	var attr := Label.new()
	attr.text = Credits.ATTRIBUTION
	attr.add_theme_font_size_override("font_size", 10)
	attr.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	attr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	attr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(attr)
	return {"root": col, "esc_hint": esc}
