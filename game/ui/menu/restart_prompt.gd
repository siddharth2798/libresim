class_name RestartPrompt
extends Control
## "Restart now?" modal when a change needs the other renderer (a preset on Forward+ vs Mobile, or the renderer switch):
## Godot only picks the renderer at start. Restart now relaunches libresim (RendererRestart, the flight is saved and
## resumed); Later keeps the "restart to apply" note. Same look and key rules as FlyConfirm (dim backdrop, focus trapped,
## Esc = Later, takes every key while open). Shown by Graphics on its own CanvasLayer over menus, pause screen and flight.

signal later
signal restart

var renderer_name := "Forward+"
var in_flight := false
var later_btn: Button
var restart_btn: Button


static func make(renderer: String, flying: bool) -> RestartPrompt:
	var p := RestartPrompt.new()
	p.renderer_name = "Forward+" if renderer == "forward_plus" else "Mobile"
	p.in_flight = flying
	return p


## The prompt's body text (pure, tested).
static func message(renderer_label: String, flying: bool) -> String:
	var s := "This setting uses the %s renderer. Godot picks the renderer when libresim starts, so it applies after a restart (a few seconds)." % renderer_label
	if flying:
		s += " Your flight is saved and carries on from where you are."
	return s


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	name = "RestartPrompt"
	theme = MenuTheme.make()
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
	panel.add_theme_stylebox_override("panel", MenuTheme.box(Color(0.035, 0.05, 0.075, 0.97), 12, Color(MenuTheme.ACCENT, 0.85), 24.0))
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var title := Label.new()
	title.text = title_text()
	title.add_theme_font_size_override("font_size", MenuTheme.SIZE_TITLE)
	v.add_child(title)
	var body := Label.new()
	body.text = message(renderer_name, in_flight)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(470, 0)
	v.add_child(body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	later_btn = _button("Later", false)
	later_btn.pressed.connect(func(): later.emit())
	row.add_child(later_btn)
	restart_btn = _button("Restart now", true)
	restart_btn.pressed.connect(func(): restart.emit())
	row.add_child(restart_btn)
	FlyConfirm.trap_focus([later_btn, restart_btn])
	restart_btn.grab_focus.call_deferred()


func title_text() -> String:
	return "Restart to switch to %s?" % renderer_name


func _button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 48)
	b.add_theme_font_size_override("font_size", MenuTheme.SIZE_BIG)
	MenuTheme.style_primary(b, primary, MenuTheme.ACCENT)
	return b


func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		later.emit()


func _unhandled_key_input(e: InputEvent) -> void:
	if is_visible_in_tree():
		get_viewport().set_input_as_handled()
