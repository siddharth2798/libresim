class_name ControlsOverlay
extends CanvasLayer
## In-flight joystick / gamepad bindings: the start screen's controls page in a
## centred glass panel. J (or toggle()) opens / closes it; Esc closes it.

var _panel: PanelContainer


func _ready() -> void:
	layer = 20
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = MenuTheme.make()
	add_child(root)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in [["offset_left", 40], ["offset_top", 30], ["offset_right", -40], ["offset_bottom", -30]]:
		_panel.set(s[0], s[1])
	root.add_child(_panel)
	var v := VBoxContainer.new()
	_panel.add_child(v)
	var bar := HBoxContainer.new()
	v.add_child(bar)
	var t := MenuTheme.heading("Controls — joystick & gamepad", 18)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(t)
	var close := Button.new()
	close.text = "Close (J)"
	close.pressed.connect(toggle)
	bar.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var page := HBoxContainer.new()
	page.set_script(load("res://ui/menu/controls_page.gd"))
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(page)
	visible = false


func toggle() -> void:
	visible = not visible


func _unhandled_key_input(e: InputEvent) -> void:
	if not e.pressed or e.echo:
		return
	if e.keycode == KEY_J or (visible and e.keycode == KEY_ESCAPE):
		toggle()
		get_viewport().set_input_as_handled()
