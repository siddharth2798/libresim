extends Control
## F12: credits & licences (CREDITS.md + the Godot engine's own licence notices),
## plus the always-visible map data attribution line required by the data licences.

const ATTRIBUTION := "Imagery: Sentinel-2 cloudless by EOX (Copernicus Sentinel data 2024) CC BY-NC-SA  ·  Elevation: Copernicus DEM © DLR/Airbus  ·  Map data © OpenStreetMap contributors (ODbL)  ·  F12 credits"

var _panel: PanelContainer
var _text: RichTextLabel


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	var attr := Label.new()
	attr.text = ATTRIBUTION
	attr.add_theme_font_size_override("font_size", 10)
	attr.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	attr.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	attr.add_theme_constant_override("outline_size", 3)
	attr.set_anchors_preset(PRESET_TOP_RIGHT)
	attr.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	attr.position = Vector2(-8, 4)
	attr.grow_horizontal = GROW_DIRECTION_BEGIN
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
	var path := ProjectSettings.globalize_path("res://").path_join("../CREDITS.md").simplify_path()
	if not OS.has_feature("editor"):
		path = OS.get_executable_path().get_base_dir().path_join("CREDITS.md")
	var t := "free-sim — Credits & licences   (F12 / Esc to close)\n\n"
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
