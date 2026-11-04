class_name FlowRail
extends PanelContainer
## The left rail of the Free-flight flow: a readiness box and one flat Button per step with a number
## badge, the title, the live value (FlowValues) and a status mark (StatusDot). The current step is
## highlighted, every entry is clickable (signal step_pressed) and Up / Down move between entries.
## Below the steps, at the bottom, the reasons the setup is not ready (SetupChecks texts, "bad" first, then
## "warn"; hidden when there are none); each is a Button that jumps to the step it belongs to (step_pressed).
## It only shows what start_flow.gd hands to refresh(); it owns no setup state.

signal step_pressed(index: int)

const WIDTH := 240
const ENTRY_H := 56

var entries: Array[Button] = []
var current := -1  # the highlighted step
var ready_title: Label
var ready_sub: Label
var reason_box: VBoxContainer  # the reasons list (hidden when empty)
var reason_btns: Array[Button] = []
var _reason_sig := ""
var _ready_dot: StatusDot
var _ready_box: PanelContainer
var _badges: Array[Label] = []
var _badge_panels: Array[PanelContainer] = []
var _values: Array[Label] = []
var _dots: Array[StatusDot] = []


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	size_flags_vertical = SIZE_EXPAND_FILL
	add_theme_stylebox_override("panel", MenuTheme.box(MenuTheme.PANEL, 10, Color(1, 1, 1, 0.08), 8.0))
	var scroll := ScrollContainer.new()  # a very small window scrolls the rail instead of pushing the footer off
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.size_flags_vertical = SIZE_EXPAND_FILL  # so the reasons sit at the bottom of a tall rail
	col.add_theme_constant_override("separation", 4)
	scroll.add_child(col)
	col.add_child(_ready_panel())
	for i in FlowValues.KEYS.size():
		var b := _entry(i)
		col.add_child(b)
		entries.append(b)
	var gap := Control.new()
	gap.size_flags_vertical = SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(gap)
	reason_box = VBoxContainer.new()
	reason_box.add_theme_constant_override("separation", 2)
	reason_box.visible = false
	col.add_child(reason_box)


func _ready_panel() -> Control:
	_ready_box = PanelContainer.new()
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	_ready_box.add_child(hb)
	_ready_dot = StatusDot.new("ok", 14)
	hb.add_child(_ready_dot)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 0)
	hb.add_child(v)
	ready_title = Label.new()
	MenuTheme.use_font(ready_title, "semibold", 15)
	v.add_child(ready_title)
	ready_sub = Label.new()
	ready_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ready_sub.add_theme_color_override("font_color", MenuTheme.DIM)
	ready_sub.add_theme_font_size_override("font_size", 13)
	v.add_child(ready_sub)
	return _ready_box


func _entry(i: int) -> Button:
	var key: String = FlowValues.KEYS[i]
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, ENTRY_H)
	b.focus_mode = Control.FOCUS_ALL
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func(): step_pressed.emit(i))
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 8)
	for side in ["top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 5)
	b.add_child(m)
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", 10)
	m.add_child(hb)
	var bp := PanelContainer.new()
	bp.custom_minimum_size = Vector2(26, 26)
	bp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bp.size_flags_vertical = SIZE_SHRINK_CENTER
	var bl := Label.new()
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuTheme.use_font(bl, "semibold", 13)
	bp.add_child(bl)
	hb.add_child(bp)
	_badge_panels.append(bp)
	_badges.append(bl)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.size_flags_vertical = SIZE_SHRINK_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 0)
	hb.add_child(v)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 6)
	v.add_child(top)
	var t := Label.new()
	t.text = FlowValues.TITLES[key]
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	MenuTheme.use_font(t, "semibold", 15)
	top.add_child(t)
	if key in FlowValues.OPTIONAL:
		var o := Label.new()
		o.text = "OPTIONAL"
		o.mouse_filter = Control.MOUSE_FILTER_IGNORE
		o.add_theme_color_override("font_color", MenuTheme.DIM)
		MenuTheme.use_font(o, "semibold", 10)
		top.add_child(o)
	var dot := StatusDot.new("none", 11)
	dot.size_flags_horizontal = SIZE_SHRINK_END
	_dots.append(dot)
	var gap := Control.new()
	gap.size_flags_horizontal = SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(gap)
	top.add_child(dot)
	var val := Label.new()
	val.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	val.clip_text = true
	val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	val.add_theme_color_override("font_color", MenuTheme.DIM)
	val.add_theme_font_size_override("font_size", 13)
	v.add_child(val)
	_values.append(val)
	return b


func _ready() -> void:  # Up / Down (and Left) stay inside the rail; Right and Tab go on to the page
	for i in entries.size():
		entries[i].focus_neighbor_top = entries[maxi(i - 1, 0)].get_path()
		entries[i].focus_neighbor_bottom = entries[mini(i + 1, entries.size() - 1)].get_path()
		entries[i].focus_neighbor_left = entries[i].get_path()
	_link_reasons()


## Repaint from the setup: `list` is SetupChecks.checks(setup); `cur` the shown step; `visited` step -> true.
func refresh(setup: Dictionary, list: Array, cur: int, visited: Dictionary) -> void:
	var rt := FlowValues.ready_text(list)
	ready_title.text = rt[0]
	ready_sub.text = rt[1]
	current = cur
	_set_reasons(list)
	var worst := SetupChecks.worst(list)
	_ready_dot.level = worst
	var tone := StatusDot.color_of(worst)
	_ready_box.add_theme_stylebox_override("panel", MenuTheme.box(Color(tone, 0.12), 10, Color(tone, 0.4), 10.0))
	for i in entries.size():
		var key: String = FlowValues.KEYS[i]
		var here := i == cur
		var done: bool = visited.has(i) and not here
		var lvl := FlowValues.level(key, setup, list)
		_values[i].text = FlowValues.rail_value(key, setup)
		_dots[i].level = lvl
		_badges[i].text = "✓" if done else str(i + 1)
		var fill := Color(1, 1, 1, 0.12)
		var ink := MenuTheme.TEXT
		if here:
			fill = MenuTheme.ACCENT
			ink = MenuTheme.ACCENT_INK
		elif done:
			fill = Color(MenuTheme.OK, 0.22)
			ink = MenuTheme.OK
		_badges[i].add_theme_color_override("font_color", ink)
		_badge_panels[i].add_theme_stylebox_override("panel", MenuTheme.box(fill, 13, Color(0, 0, 0, 0), 0.0))
		_style_entry(entries[i], here)
		entries[i].tooltip_text = FlowValues.tooltip(key, setup, list, i)


func _style_entry(b: Button, here: bool) -> void:
	var edge := Color(MenuTheme.ACCENT, 0.5) if here else Color(0, 0, 0, 0)
	b.add_theme_stylebox_override("normal", MenuTheme.box(Color(MenuTheme.ACCENT, 0.16) if here else Color(0, 0, 0, 0), 10, edge))
	b.add_theme_stylebox_override("hover", MenuTheme.box(Color(MenuTheme.ACCENT, 0.24) if here else Color(1, 1, 1, 0.09), 10, edge))
	b.add_theme_stylebox_override("pressed", MenuTheme.box(Color(MenuTheme.ACCENT, 0.32), 10, edge))
	b.add_theme_stylebox_override("hover_pressed", MenuTheme.box(Color(MenuTheme.ACCENT, 0.32), 10, edge))
	# no "focus" override: the theme's 3 px accent ring (MenuTheme.focus_box) stays visible


## The reasons under the steps: bad first, then warn, one wrapped Button each that jumps to its step. Rebuilt only
## when the list changes (a repaint every frame must not drop the focus).
func _set_reasons(list: Array) -> void:
	var items := reason_items(list)
	var sig := JSON.stringify(items.map(func(c): return [c.step, c.level, c.text]))
	if sig == _reason_sig:
		return
	_reason_sig = sig
	var had_focus := false
	for b in reason_btns:
		had_focus = had_focus or b.has_focus()
		reason_box.remove_child(b)
		b.queue_free()
	reason_btns.clear()
	for c in items:
		var b := _reason_button(c)
		reason_box.add_child(b)
		reason_btns.append(b)
	reason_box.visible = not items.is_empty()
	_link_reasons()
	if had_focus and current >= 0:
		entries[current].grab_focus()


## Down from the last step reaches the reasons; Up / Down move along them; Left stays.
func _link_reasons() -> void:
	if not is_inside_tree():  # get_path() needs the tree; _ready links again
		return
	for i in reason_btns.size():
		reason_btns[i].focus_neighbor_left = reason_btns[i].get_path()
		reason_btns[i].focus_neighbor_top = (reason_btns[i - 1] if i > 0 else entries[-1]).get_path()
		reason_btns[i].focus_neighbor_bottom = reason_btns[mini(i + 1, reason_btns.size() - 1)].get_path()
	entries[-1].focus_neighbor_bottom = (reason_btns[0] if not reason_btns.is_empty() else entries[-1]).get_path()


## SetupChecks items in the order shown: the "bad" ones first, then the rest (a stable order within each).
static func reason_items(list: Array) -> Array:
	return list.filter(func(c): return c.level == "bad") + list.filter(func(c): return c.level != "bad")


func _reason_button(c: Dictionary) -> Button:
	var b := Button.new()
	var bad: bool = c.level == "bad"
	var tone: Color = MenuTheme.BAD if bad else MenuTheme.WARN
	b.text = "▲ " + str(c.text)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", 13)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, tone)
	b.add_theme_stylebox_override("normal", MenuTheme.box(Color(0, 0, 0, 0), 8, Color(0, 0, 0, 0), 6.0))
	b.add_theme_stylebox_override("hover", MenuTheme.box(Color(tone, 0.12), 8, Color(0, 0, 0, 0), 6.0))
	b.add_theme_stylebox_override("pressed", MenuTheme.box(Color(tone, 0.2), 8, Color(0, 0, 0, 0), 6.0))
	b.add_theme_stylebox_override("hover_pressed", MenuTheme.box(Color(tone, 0.2), 8, Color(0, 0, 0, 0), 6.0))
	var at := FlowValues.KEYS.find(str(c.step))
	b.tooltip_text = "%s: go to %s" % ["Problem" if bad else "Note", FlowValues.TITLES.get(str(c.step), "the step")]
	b.pressed.connect(func(): step_pressed.emit(at))
	return b
