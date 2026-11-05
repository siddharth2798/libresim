class_name FlyConfirm
extends Control
## "Fly anyway?" modal of the Free-flight Fly paths: a dim backdrop over the whole screen and a panel that
## lists the problems SetupChecks found ("bad" reasons only) with Go back and Fly anyway. Fly is never blocked;
## this only asks. Focus starts on Go back, Esc = Go back, Enter presses the focused button. While it is open
## it takes every key, so nothing behind it (steps, Ctrl+Enter) reacts.
## Use: var m := FlyConfirm.make(SetupChecks.reasons(...)); parent.add_child(m); m.confirmed / m.cancelled.
## The look uses MenuTheme tokens only; the panel and buttons come from the screen's theme.

signal confirmed
signal cancelled

var reasons: Array[String] = []
var go_back_btn: Button
var fly_btn: Button
var reason_labels: Array[Label] = []


static func make(bad: Array[String]) -> FlyConfirm:
	var m := FlyConfirm.new()
	m.reasons = bad
	return m


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP  # the setup behind cannot be clicked
	name = "FlyConfirm"
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.04, 0.72)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	panel.add_theme_stylebox_override("panel", MenuTheme.box(Color(0.035, 0.05, 0.075, 0.97), 12, Color(MenuTheme.WARN, 0.85), 24.0))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var title := Label.new()
	title.text = "Fly anyway?"
	title.add_theme_font_size_override("font_size", MenuTheme.SIZE_TITLE)
	title.add_theme_color_override("font_color", MenuTheme.WARN)
	v.add_child(title)
	var intro := Label.new()
	intro.text = "This setup has %s you will feel in flight:" % ("problems" if reasons.size() > 1 else "a problem")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(intro)
	for r in reasons:
		var l := Label.new()
		l.text = "•  " + r
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color", MenuTheme.TEXT)
		v.add_child(l)
		reason_labels.append(l)
	v.add_child(MenuTheme.note("You can still fly: nothing is blocked. To fix it, go back to the setup."))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	go_back_btn = _button("Go back", false)
	go_back_btn.pressed.connect(func(): cancelled.emit())
	row.add_child(go_back_btn)
	fly_btn = _button("Fly anyway  ▶", true)
	fly_btn.pressed.connect(func(): confirmed.emit())
	row.add_child(fly_btn)
	trap_focus([go_back_btn, fly_btn])
	go_back_btn.grab_focus.call_deferred()


## Tab, Shift+Tab and the arrow keys cycle through these controls only: the screen behind is dimmed and unclickable, so
## the keyboard must not be able to reach it either (the engine's default order is the whole scene tree).
static func trap_focus(ring: Array[Button]) -> void:
	for i in ring.size():
		var b := ring[i]
		var nxt := ring[(i + 1) % ring.size()]
		var prv := ring[(i - 1 + ring.size()) % ring.size()]
		b.focus_next = b.get_path_to(nxt)
		b.focus_previous = b.get_path_to(prv)
		b.focus_neighbor_right = b.get_path_to(nxt)
		b.focus_neighbor_left = b.get_path_to(prv)
		b.focus_neighbor_top = b.get_path_to(b)
		b.focus_neighbor_bottom = b.get_path_to(b)


func _button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 48)
	b.add_theme_font_size_override("font_size", MenuTheme.SIZE_BIG)
	MenuTheme.style_primary(b, primary, MenuTheme.WARN)
	return b


func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		cancelled.emit()


func _unhandled_key_input(e: InputEvent) -> void:
	if is_visible_in_tree():
		get_viewport().set_input_as_handled()  # steps, Ctrl+Enter and the like stay behind the dialog
