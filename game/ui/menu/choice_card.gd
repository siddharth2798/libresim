extends Button
## Large choice card for the home screen (the chosen design's card): round glyph badge with the key hint
## at the right, big title, one-line description and, when the player has history, a "last" box and one
## shortcut button inside the card ("Fly again", "Continue: ..."). The card itself is the main action.
## Lit (accent border) while hovered or focused, also while its shortcut button has the focus; hovering moves the
## focus here so only one card is ever lit. Call setup() before adding it to the tree.

const Glyphs := preload("res://ui/menu/menu_glyphs.gd")
const BASE_SIZE := Vector2(410, 236)
const PAD := 18

var action_btn: Button  # the shortcut button (not "shortcut": Button has that property); hidden until set_action(); a real Button inside the card, so it has its own focus and click
var _glyph: Control
var _title: Label
var _blurb: Label
var _hint: Label
var _body: MarginContainer
var _box: PanelContainer  # the "last setup" / "progress" box
var _box_lines: Array[Label] = []
var _marks: HFlowContainer  # one "Title ★★☆" per lesson under the box (Training card only, see set_marks)
var _mark_labels: Array[Label] = []
var _k := 1.0
var _lit_normal: StyleBoxFlat
var _normal: StyleBoxFlat


func setup(kind: String, title: String, blurb: String, hint: String) -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_normal = MenuTheme.card(false)  # the same object is edited (not swapped) while the shortcut button has the focus
	add_theme_stylebox_override("normal", _normal)
	add_theme_stylebox_override("disabled", MenuTheme.card(false))
	for k in ["hover", "pressed", "hover_pressed"]:
		add_theme_stylebox_override(k, MenuTheme.card(true))
	var lit := MenuTheme.card(true)  # focus is drawn on top of normal: a tint plus the border
	lit.bg_color = Color(MenuTheme.ACCENT, 0.10)
	lit.shadow_size = 0
	add_theme_stylebox_override("focus", lit)
	_lit_normal = MenuTheme.card(true)
	_body = MarginContainer.new()
	_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		_body.add_theme_constant_override("margin_" + side, PAD)
	add_child(_body)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(v)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	_glyph = Control.new()
	_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glyph.draw.connect(func(): Glyphs.draw(_glyph, kind, has_focus() or is_hovered() or _shortcut_focused()))
	top.add_child(_glyph)
	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(gap)
	_hint = _label(hint, Color(MenuTheme.ACCENT, 0.9))
	_hint.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(_hint)
	_title = _label(title, Color.WHITE)
	_title.add_theme_font_override("font", MenuTheme.font("semibold"))
	v.add_child(_title)
	_blurb = _label(blurb, MenuTheme.DIM)
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_blurb)
	var fill := Control.new()
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(fill)
	_box = PanelContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_stylebox_override("panel", MenuTheme.box(Color(1, 1, 1, 0.06), 10, Color(0, 0, 0, 0), 9.0))
	_box.visible = false
	v.add_child(_box)
	var bl := VBoxContainer.new()
	bl.add_theme_constant_override("separation", 0)
	bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(bl)
	for i in 3:
		var l := _label("", MenuTheme.TEXT if i == 1 else MenuTheme.DIM)
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		bl.add_child(l)
		_box_lines.append(l)
	_marks = HFlowContainer.new()
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marks.add_theme_constant_override("h_separation", 14)
	_marks.add_theme_constant_override("v_separation", 0)
	_marks.visible = false
	v.add_child(_marks)
	action_btn = Button.new()
	action_btn.visible = false
	action_btn.clip_text = true
	action_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	v.add_child(action_btn)
	mouse_entered.connect(grab_focus)
	for c in [self, action_btn]:
		c.focus_entered.connect(_lit_changed)
		c.focus_exited.connect(_lit_changed)
	mouse_exited.connect(_glyph.queue_redraw)
	_body.minimum_size_changed.connect(_fit)
	set_scale_k(1.0)


func _ready() -> void:
	set_scale_k(_k)  # the line height of the blurb needs the theme font, which is known only in the tree


func _label(text: String, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", col)
	return l


## Fill the box: `small` (dim), `main` (bright), `extra` (dim, may be ""). An empty `main` hides the box.
func set_last(small: String, main: String, extra := "") -> void:
	for i in 3:
		_box_lines[i].text = [small, main, extra][i]
		_box_lines[i].visible = _box_lines[i].text != ""
	_box.visible = main != ""
	_fit()


## A compact row of the stars of every lesson under the box: `marks` = [{title, stars 0..3}] (HomeShortcuts.lesson_marks).
## Flown lessons get amber stars, a lesson not flown yet three dim ones. An empty list hides the row.
func set_marks(marks: Array) -> void:
	for c in _marks.get_children():
		_marks.remove_child(c)
		c.free()
	_mark_labels.clear()
	for m in marks:
		var cell := HBoxContainer.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_theme_constant_override("separation", 5)
		var t := _label(str(m.title), MenuTheme.DIM)
		var n := int(m.stars)
		var st := _label("★".repeat(n) + "☆".repeat(3 - n), MenuTheme.WARN if n > 0 else MenuTheme.FAINT)
		cell.add_child(t)
		cell.add_child(st)
		_marks.add_child(cell)
		_mark_labels.append(t)
		_mark_labels.append(st)
	_marks.visible = not marks.is_empty()
	set_scale_k(_k)


## The text of the star row, "Takeoff ★★☆ · Cruise ☆☆☆" (tests, tooltips).
func marks_text() -> String:
	var parts: Array[String] = []
	for i in range(0, _mark_labels.size(), 2):
		parts.append("%s %s" % [_mark_labels[i].text, _mark_labels[i + 1].text])
	return " · ".join(parts)


## Show the shortcut button with this text (primary: filled accent with dark ink; else outlined). "" hides it.
func set_action(text: String, primary: bool, tip := "") -> void:
	action_btn.visible = text != ""
	action_btn.text = text
	action_btn.tooltip_text = tip
	MenuTheme.style_primary(action_btn, primary)
	_fit()


func _shortcut_focused() -> bool:
	return action_btn != null and action_btn.has_focus()


## Focus on the card or on its shortcut button: the whole card shows its lit border.
func _lit_changed() -> void:
	var src := _lit_normal if _shortcut_focused() else MenuTheme.card(false)
	_normal.bg_color = src.bg_color
	_normal.border_color = src.border_color
	_normal.set_border_width_all(src.border_width_left)
	_normal.shadow_size = src.shadow_size
	_glyph.queue_redraw()


## Scale the card for bigger windows (1.0 at 1280x720).
func set_scale_k(k: float) -> void:
	_k = k
	for side in ["left", "right", "top", "bottom"]:
		_body.add_theme_constant_override("margin_" + side, int(PAD * minf(k, 1.0)))  # tighter in a small window
	_glyph.custom_minimum_size = Vector2.ONE * 56.0 * k
	_title.add_theme_font_size_override("font_size", int(30 * k))
	_blurb.add_theme_font_size_override("font_size", int(16 * k))
	_blurb.custom_minimum_size.y = 2.0 * _blurb.get_theme_font("font").get_height(int(16 * k))
	_hint.add_theme_font_size_override("font_size", int(14 * k))
	_box_lines[0].add_theme_font_size_override("font_size", int(13 * k))
	_box_lines[1].add_theme_font_size_override("font_size", int(15 * k))
	_box_lines[2].add_theme_font_size_override("font_size", int(13 * k))
	for l in _mark_labels:
		l.add_theme_font_size_override("font_size", int(13 * k))
	action_btn.add_theme_font_size_override("font_size", int(16 * k))
	action_btn.custom_minimum_size = Vector2(0, 42.0 * k)
	_fit()


## The card is a Button, not a Container: its height is the base height, or what the content needs.
func _fit() -> void:
	if _body == null:
		return
	custom_minimum_size = Vector2(BASE_SIZE.x * _k, maxf(BASE_SIZE.y * _k, _body.get_combined_minimum_size().y))
