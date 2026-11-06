class_name LiveWeatherNotice
extends Control
## First-time question for the Live weather switch. A dim backdrop and a centred panel, the same glass,
## type and buttons as FlyConfirm. It is a control on the start screen, so it follows the UI scale.
## "Use live weather" accepts; "Not now" and Esc decline. The caller writes the seen-file and frees this.

signal accepted
signal declined

const BODY := "The game asks aviationweather.gov and open-meteo.com for the weather at this airport. It sends only a station id or coordinates rounded to about a kilometre. Those sites see your IP address. There is no account."

var use_btn: Button
var not_now_btn: Button
var _done := false


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	name = "LiveWeatherNotice"
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
	title.text = "Live weather"
	title.add_theme_font_size_override("font_size", MenuTheme.SIZE_TITLE)
	title.add_theme_color_override("font_color", MenuTheme.ACCENT)
	v.add_child(title)
	var body := Label.new()
	body.text = BODY
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(472, 0)
	body.add_theme_color_override("font_color", MenuTheme.TEXT)
	v.add_child(body)
	var note := MenuTheme.note("You can switch this off later on this page. Not now asks again next time.")
	note.custom_minimum_size = Vector2(472, 0)
	v.add_child(note)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	not_now_btn = _button("Not now", false)
	not_now_btn.pressed.connect(_answer.bind(false))
	row.add_child(not_now_btn)
	use_btn = _button("Use live weather", true)
	use_btn.pressed.connect(_answer.bind(true))
	row.add_child(use_btn)
	FlyConfirm.trap_focus([not_now_btn, use_btn])
	not_now_btn.grab_focus.call_deferred()


func _button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(180, 48)
	b.add_theme_font_size_override("font_size", MenuTheme.SIZE_BIG)
	MenuTheme.style_primary(b, primary)
	return b


func _answer(use: bool) -> void:
	if _done:
		return
	_done = true
	if use:
		accepted.emit()
	else:
		declined.emit()


func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_answer(false)


func _unhandled_key_input(_e: InputEvent) -> void:
	if is_visible_in_tree():
		get_viewport().set_input_as_handled()
