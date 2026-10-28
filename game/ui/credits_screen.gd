extends Control
## F12: credits & licences (CREDITS.md + the Godot engine's own licence notices),
## plus the always-visible map data attribution line required by the data licences.

const ATTRIBUTION := "Imagery: EOxCloudless (Sentinel-2) cloudless.eox.at by EOX IT Services GmbH (Contains modified Copernicus Sentinel data 2024) CC BY-NC-SA  ·  Elevation: Copernicus DEM © DLR/Airbus  ·  Land cover: ESA WorldCover 2021 CC BY 4.0  ·  Map data © OpenStreetMap contributors (ODbL)  ·  F12 credits"

var _panel: PanelContainer
var _text: RichTextLabel


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)  # offsets too: a zero-size control put the line off-screen
	mouse_filter = MOUSE_FILTER_IGNORE
	var attr := Label.new()
	attr.text = ATTRIBUTION
	attr.add_theme_font_size_override("font_size", 10)
	attr.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	attr.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	attr.add_theme_constant_override("outline_size", 3)
	# bottom centre, between the instrument stacks; wraps to two lines on narrow windows
	attr.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	attr.offset_left = 330
	attr.offset_right = -130
	attr.offset_top = -32
	attr.offset_bottom = -4
	attr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	attr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	attr.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	attr.grow_vertical = Control.GROW_DIRECTION_BEGIN  # a third line on a narrow window grows upward
	attr.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(attr)
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(PRESET_FULL_RECT)
	_panel.offset_left = 60
	_panel.offset_right = -60
	_panel.offset_top = 40
	_panel.offset_bottom = -40
	_panel.visible = false
	add_child(_panel)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = false
	_text.scroll_active = true
	_text.selection_enabled = true
	_panel.add_child(_text)


func _load_text() -> String:
	var path := Paths.docs_dir().path_join("CREDITS.md")
	var t := "libresim — Credits & licences   (F12 / Esc to close)\n\n"
	var f := FileAccess.open(path, FileAccess.READ)
	t += f.get_as_text() if f else "CREDITS.md not found next to the game.\n"
	t += "\n\n==== Godot Engine licence ====\n\n" + Engine.get_license_text()
	t += "\n\n==== Third-party components inside Godot ====\n"
	for c in Engine.get_copyright_info():
		t += "\n" + str(c.name)
		for p in c.parts:
			t += "\n  " + ", ".join(p.copyright) + "  [" + str(p.license) + "]"
	return t


func _unhandled_key_input(e: InputEvent) -> void:
	if not e.pressed or e.echo:
		return
	if e.keycode == KEY_F12 or (e.keycode == KEY_ESCAPE and _panel.visible):
		_panel.visible = not _panel.visible
		if _panel.visible and _text.text.is_empty():
			_text.text = _load_text()
		get_viewport().set_input_as_handled()
