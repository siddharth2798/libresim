extends Node
## The Recording step (ui/menu/recording_page.gd): the options are the same Session.setup keys as before (record,
## record_dir, record_height, record_fps, record_mp4), now on a SwitchRow and two Segmented controls.

var _keep := {}
var _nodes: Array[Node] = []


func _page() -> Control:
	_keep = {"setup": Session.setup}
	Session.setup = Session.DEFAULT.duplicate(true)
	Session.setup.record_dir = "user://_recording_page_test"  # a set folder: nothing looks for (or makes) the game folder
	var p := HBoxContainer.new()
	p.set_script(load("res://ui/menu/recording_page.gd"))
	add_child(p)
	_nodes.append(p)
	return p


func teardown() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	if not _keep.is_empty():
		Session.setup = _keep.setup
		_keep = {}


func test_recording_size_estimate() -> String:
	var rp = load("res://ui/menu/recording_page.gd")
	if rp.mb_per_minute(720, 30) != 300.0 or rp.mb_per_minute(1080, 60) != 1200.0 or rp.mb_per_minute(0, 24) != 480.0:
		return "720p30 = 300, 1080p60 = 1200, native 24 = 480: %s %s %s" % [rp.mb_per_minute(720, 30), rp.mb_per_minute(1080, 60), rp.mb_per_minute(0, 24)]
	return ""


func test_recording_page_shows_and_writes_the_setup() -> String:
	var p := _page()
	if p.record_switch.is_on() or p.resolution.get_value() != 720 or p.rate.get_value() != 30 or not p.mp4_switch.is_on():
		return "defaults: off, 720p, 30 fps, MP4 on"
	if p._options.modulate.a >= 1.0:
		return "the options are dimmed while recording is off"
	p.record_switch.toggled.emit(true)
	if not Session.setup.record or p._options.modulate.a != 1.0:
		return "the switch writes record and lights the options"
	p.resolution.selected.emit(1080)
	p.rate.selected.emit(60)
	p.mp4_switch.toggled.emit(false)
	if Session.setup.record_height != 1080 or Session.setup.record_fps != 60 or Session.setup.record_mp4:
		return "choices not stored: %s" % [Session.setup]
	if not p._size_note.text.begins_with("About 1200 MB per minute"):
		return "size line: " + p._size_note.text
	p.resolution.selected.emit(0)
	if Session.setup.record_height != 0:
		return "native window is 0"
	return ""


func test_recording_page_folder_and_refresh() -> String:
	var p := _page()
	if not p._dir.text.begins_with("user://_recording_page_test") or p._dir.text.contains("(game folder)"):
		return "a chosen folder is shown as it is: " + p._dir.text
	Session.setup.record = true
	Session.setup.record_fps = 24
	Session.setup.record_height = 1080
	p.refresh()
	if not p.record_switch.is_on() or p.rate.get_value() != 24 or p.resolution.get_value() != 1080:
		return "refresh() follows a replaced setup"
	return ""
