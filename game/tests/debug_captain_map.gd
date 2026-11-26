extends Node
## Debug: screenshots of the Captain Pack map (ui/menu/captain_map_panel.gd) with FAKE pads, no hardware; nothing real is read or written
## (scratch bindings and learned-number files under user://):
##   1_detected_a320.png      pack detected, the profile's bindings, aircraft switch on the A320
##   2_live_lit.png           some controls held or moving
##   3_action_picker.png      "Choose action" open on an unbound control
##   4_assigned_moved.png     after choosing: the action moved from another control (message line)
##   5_identify_unconfirmed.png  Identify on, an unconfirmed control (hat right) pressed
##   6_identify_unknown.png   Identify, a button the map does not know: "This is:" list
##   7_c172.png               the same pack for the Cessna 172S: other labels, "not used on"
##   8_no_pack_preview.png    no pack connected: preview of the default mapping
##   9_ui_scale_150.png       the panel at UI scale 150 %
##   10_controls_page_link.png  the link on the Controls page (Joystick tab)
##   11_no_pictures.png       the photos missing: drawn outline and the same markers
## ~/.local/bin/godot --path game --windowed --resolution 1280x720 --audio-driver Dummy res://tests/debug_captain_map.tscn -- --shots=<dir>

const PADS := [{"id": 0, "name": "TCA Sidestick X Copilot", "guid": "side"}, {"id": 1, "name": "TCA Q-Eng 1&2", "guid": "quad"}]
const REST := {"1:0": 0.47, "1:1": 0.47, "1:2": -1.0, "1:5": -1.0}  # quadrant levers at rest: idle, idle, flaps 0, speed brake retracted

## Stands in for the Controls page (its table, aircraft, Bind flow, save) so Bind is enabled in the picture.
class StubPage extends Node:
	signal changed
	var table := {}
	var controls: AircraftControls
	var _capture := ""
	var _rows := {}

	func _start_capture(a: String) -> void:
		_capture = a

	func _cancel_capture() -> void:
		_capture = ""

	func _save() -> void:
		changed.emit()


var _out := ""
var _axes := {}  # "pad:axis" -> raw
var _btns := {}  # "pad:button" -> held
var _a320: AircraftControls


func _ready() -> void:
	AudioServer.set_bus_mute(0, true)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_out = a.substr(8)
	if _out == "":
		_out = OS.get_user_data_dir()
	Session.interactive_override = 0
	Session.setup["aircraft"] = "a320"
	CaptainDetect.bindings_path = "user://_captain_map_scratch.json"
	CaptainMap.learned_path = "user://_captain_map_learned_scratch.json"
	CaptainMap.reload_learned()
	_a320 = AircraftControls.for_def(AircraftDef.load_def("a320"))
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.16, 0.22)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	await get_tree().process_frame  # the parent is busy setting up children during _ready
	await _run()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CaptainMap.learned_path))
	get_tree().quit()


func _panel(table := {}, with_page := false, controls := _a320) -> CaptainMapPanel:
	var stub: StubPage = null
	if with_page:
		stub = StubPage.new()
		stub.table = table
		stub.controls = controls
		add_child(stub)
	var p := CaptainMapPanel.open(self, stub, table, controls)
	p.save_path = "user://_captain_map_scratch.json"
	p.read_axis = func(pad: int, axis: int) -> float: return _axes.get("%d:%d" % [pad, axis], REST.get("%d:%d" % [pad, axis], 0.0))
	p.read_button = func(pad: int, button: int) -> bool: return _btns.get("%d:%d" % [pad, button], false)
	return p


func _shot(name: String, delay := 0.5) -> void:
	await get_tree().create_timer(delay).timeout
	get_viewport().get_texture().get_image().save_png(_out.path_join(name))
	print("saved ", name)


func _close(p: CaptainMapPanel) -> void:
	p.close()
	await get_tree().process_frame
	await get_tree().process_frame


func _run() -> void:
	var defaults := InputBindings.defaults(InputProfiles.CAPTAIN_PACK)
	CaptainDetect.pads_provider = func(): return PADS
	var p := _panel(defaults, true)
	await _shot("1_detected_a320.png")
	_axes = {"0:0": 0.6, "0:1": -0.8, "0:2": 0.3, "1:0": -0.485, "1:2": -0.051}
	_btns = {"0:0": true, "1:20": true, "1:2": true, "1:23": true}
	p.select("quadrant", "lever1")
	await _shot("2_live_lit.png", 0.2)
	_axes.clear()
	_btns.clear()
	p.select("sidestick", "xbox")  # unbound in the profile
	p.open_picker()
	await _shot("3_action_picker.png", 0.3)
	p.close_picker()
	p.select("sidestick", "key_x")
	p.assign("gear_switch")  # was on the quadrant's gear lever: it moves here (and replaces the map key)
	await _shot("4_assigned_moved.png", 0.3)
	p.set_identify(true)
	await get_tree().create_timer(0.2).timeout
	_btns = {"0:14": true}  # hat right: documented as unconfirmed
	await _shot("5_identify_unconfirmed.png", 0.2)
	_btns = {"0:32": true}  # a button the map does not know
	await _shot("6_identify_unknown.png", 0.2)
	_btns.clear()
	await _close(p)
	var c172 := AircraftControls.for_def(AircraftDef.load_def("c172"))
	p = _panel(InputBindings.defaults(InputProfiles.CAPTAIN_PACK), true, c172)
	p.select("quadrant", "speedbrake")
	await _shot("7_c172.png")
	await _close(p)
	CaptainDetect.pads_provider = func(): return []
	p = _panel()
	await _shot("8_no_pack_preview.png")
	await _close(p)
	CaptainDetect.pads_provider = func(): return PADS
	if get_window().size_changed.is_connected(UiScale.apply):
		get_window().size_changed.disconnect(UiScale.apply)
	get_window().content_scale_factor = 1.5
	p = _panel(defaults)
	await _shot("9_ui_scale_150.png")
	await _close(p)
	get_window().content_scale_factor = 1.0
	await _controls_page()
	p = _panel(defaults)
	for d in p.pictures:
		p.pictures[d].texture = null
		p.pictures[d].queue_redraw()
	await _shot("11_no_pictures.png")
	await _close(p)


func _controls_page() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = MenuTheme.make()
	add_child(root)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 28
	panel.offset_right = -28
	panel.offset_top = 28
	panel.offset_bottom = -28
	root.add_child(panel)
	var page := HBoxContainer.new()
	page.set_script(load("res://ui/menu/controls_page.gd"))
	page.set("start_tab", "joystick")
	page.set("bindings_path", "user://_captain_map_scratch.json")
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(page)
	await _shot("10_controls_page_link.png")
	root.queue_free()
