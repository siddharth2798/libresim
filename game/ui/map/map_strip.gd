class_name MapStrip
extends PanelContainer
## The top strip of the N map (ui/moving_map.gd): the title line, then its buttons. pressed(id) for each:
## out, in, follow, orient, fit, edit, clear, close. sync() shows the map's state (toggles, greyed buttons).

signal pressed(id: String)

const BUTTONS := [["out", "-", "Zoom out (-)"], ["in", "+", "Zoom in (+)"],
	["follow", "Follow", "Keep the aircraft in the middle (Space)"], ["orient", "North up", "North up / heading up (O)"],
	["fit", "Fit route", "Show the whole route (G)"],
	["edit", "Edit route", "Edit the planned route on the map: drag a waypoint to move it, drag a leg to add one, click to add, right-click to remove"],
	["clear", "Clear route", "Cancel direct-to and route (Backspace)"], ["close", "Close (N)", "Close the map (N)"]]
const TOGGLES := ["follow", "orient", "edit"]
## Bars at the top of the flight screen (the radio, the flight-data bar) join this group; the map's top edge goes below
## them (top_clear) so this strip's title is never under one. A member may say which rect counts (map_clear_rect()).
const CLEAR_GROUP := "map_top_clear"
const BOTTOM_GROUP := "map_bottom_clear"  # the same at the bottom: the data attribution line (bottom_clear)

var title: Label
var buttons := {}  # id -> Button
var _row: HBoxContainer  # the title (when there is room) and the buttons


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = MapStyle.PANEL
	sb.set_content_margin_all(6.0)
	add_theme_stylebox_override("panel", sb)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	add_child(rows)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 6)
	rows.add_child(_row)
	title = Label.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	_row.add_child(title)
	var row := _row
	for spec in BUTTONS:
		var b := Button.new()
		b.text = spec[1]
		b.tooltip_text = spec[2]
		b.focus_mode = Control.FOCUS_NONE  # Space and Enter must not press a button
		b.toggle_mode = spec[0] in TOGGLES
		b.pressed.connect(func(): pressed.emit(spec[0]))
		row.add_child(b)
		buttons[spec[0]] = b
	resized.connect(_fit)


## A narrow window (or a large UI size) leaves the title no room beside the buttons: it gets its own line above them.
func _fit() -> void:
	var need := title.get_theme_font("font").get_string_size("EDIT ROUTE  ·  MAP  000 nm", HORIZONTAL_ALIGNMENT_LEFT, -1,
		title.get_theme_font_size("font_size")).x
	for b in buttons.values():
		need += (b as Button).get_combined_minimum_size().x + 6.0
	var own_line := size.x - 12.0 < need
	var rows := _row.get_parent()
	if own_line and title.get_parent() == _row:
		_row.remove_child(title)
		rows.add_child(title)
		rows.move_child(title, 0)
	elif not own_line and title.get_parent() != _row:
		rows.remove_child(title)
		_row.add_child(title)
		_row.move_child(title, 0)


func sync(follow: bool, heading_up: bool, has_route: bool, editing: bool) -> void:
	buttons.follow.set_pressed_no_signal(follow)
	buttons.orient.set_pressed_no_signal(heading_up)
	buttons.orient.text = "Heading up" if heading_up else "North up"
	buttons.fit.disabled = not has_route
	buttons.clear.disabled = not has_route
	buttons.edit.set_pressed_no_signal(editing)
	buttons.edit.text = "Editing route" if editing else "Edit route"


## The lowest bottom edge (canvas units) of the visible CLEAR_GROUP bars in the top quarter of the screen, 0 = none,
## at most 40 % of the screen.
static func top_clear(map: Control) -> float:
	var bottom := 0.0
	var top_quarter := map.get_viewport_rect().size.y * 0.25
	for n in map.get_tree().get_nodes_in_group(CLEAR_GROUP):
		if not (n is Control and (n as Control).is_visible_in_tree()):
			continue
		var r: Rect2 = n.call("map_clear_rect") if n.has_method("map_clear_rect") else (n as Control).get_global_rect()
		if r.size.y > 0.0 and r.position.y < top_quarter:
			bottom = maxf(bottom, r.end.y)
	return minf(bottom, top_quarter * 1.6)


## Height (canvas units) from the bottom of the screen to the top of the highest visible BOTTOM_GROUP item in the
## bottom half, 0 = none, at most a quarter of the screen.
static func bottom_clear(map: Control) -> float:
	var h := map.get_viewport_rect().size.y
	var top := h
	for n in map.get_tree().get_nodes_in_group(BOTTOM_GROUP):
		if n is Control and (n as Control).is_visible_in_tree():
			var r := (n as Control).get_global_rect()
			if r.size.y > 0.0 and r.position.y >= h * 0.5:  # really at the bottom (not a line wrapped up the screen)
				top = minf(top, r.position.y)
	return minf(h - top, h * 0.25)  # the map keeps most of the screen whatever the line does
