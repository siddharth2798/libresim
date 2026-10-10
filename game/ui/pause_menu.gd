extends PanelContainer
## Esc: pause menu. Pauses the flight model while open.
## Resume · Restart flight · Failures (F9) · Settings (F10) · New flight (start screen) · Quit.

var flight: Node  # world/flight.gd


func _ready() -> void:
	visible = false
	set_anchors_preset(PRESET_CENTER)
	custom_minimum_size = Vector2(320, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	add_child(vb)
	var t := Label.new()
	t.text = "Paused"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 24)
	vb.add_child(t)
	for item in [["Resume", _close], ["Restart flight (F5)", func(): _close(); flight._reset()],
			["Failures (F9)", func(): _close(); _press(KEY_F9)],
			["Settings (F10)", func(): _close(); _press(KEY_F10)],
			["New flight (start screen)", _new_flight], ["Quit", func(): get_tree().quit()]]:
		var b := Button.new()
		b.text = item[0]
		b.custom_minimum_size = Vector2(0, 40)
		b.pressed.connect(item[1])
		vb.add_child(b)


func _press(key: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = key
	e.pressed = true
	Input.parse_input_event(e)


func _close() -> void:
	visible = false
	flight.fdm_node.paused = false


func _new_flight() -> void:
	Session.skip_menu = false
	get_tree().change_scene_to_file("res://ui/menu/start_screen.tscn")


func _unhandled_key_input(e: InputEvent) -> void:
	if e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		visible = not visible
		flight.fdm_node.paused = visible
		get_viewport().set_input_as_handled()
