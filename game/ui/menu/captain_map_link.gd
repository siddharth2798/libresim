class_name CaptainMapLink
extends Button
## The link to the Captain Pack map (ui/menu/captain_map_panel.gd) under the pad list on the Controls page's joystick tab, so it is also
## on the pause screen and the in-flight overlay (they host the same page). With a pack connected it reads "Captain Pack map" as a
## filled button; without one it is a quiet link that opens the preview of the profile's default mapping.

const TEXT_FOUND := "Captain Pack map"
const TEXT_NONE := "Captain Pack map (preview: no pack connected)"

var page: Object  # the Controls page (its table, aircraft and Bind flow)
var _panel: CaptainMapPanel


## Adds the Captain Pack extras of the pad list: the "offer again" link and the map link.
static func add_to(parent: Control, controls_page: Object) -> CaptainMapLink:
	parent.add_child(CaptainAskAgain.new())  # only with a Captain Pack and the offer declined
	var l := CaptainMapLink.new()
	l.page = controls_page
	parent.add_child(l)
	return l


func _ready() -> void:
	size_flags_horizontal = SIZE_SHRINK_BEGIN
	pressed.connect(_open)
	Input.joy_connection_changed.connect(_on_joy)
	refresh()


func _on_joy(_device: int, _connected: bool) -> void:
	refresh()


func refresh() -> void:
	var found := CaptainDetect.present(CaptainDetect.connected_pads())
	text = TEXT_FOUND if found else TEXT_NONE
	custom_minimum_size = Vector2(0, 40) if found else Vector2.ZERO
	if found:
		MenuTheme.style_primary(self, true)
		alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		flat = true
		theme_type_variation = &""
		alignment = HORIZONTAL_ALIGNMENT_LEFT
		add_theme_color_override("font_color", MenuTheme.ACCENT)
		for k in ["normal", "hover", "pressed", "disabled"]:
			remove_theme_stylebox_override(k)
	flat = not found


func _open() -> void:
	if is_instance_valid(_panel):
		return
	_panel = CaptainMapPanel.open(self, page)
