extends Node
## Debug: walk every start-screen page (home, the five Free-flight steps, Training, Saved flights, each Options and Controls tab,
## credits, the controls overlay J and the pause screen) at one window size and UI scale, save a screenshot of each and print the
## layout audit (tests/ui_audit.gd). Needs a display; scratch data only: nothing of the player's saves, options, bindings or
## training stars is read or written (the UI scale is kept in memory).
##   FREESIM_SIZE=1280x720   window size in pixels (see the UI scale note below: the system scale is taken as 1)
##   FREESIM_UISCALE=125%    Auto | 100% | 125% | 150% | 200%
##   FREESIM_SHOTS=<dir>     where <tag><name>.png go;  FREESIM_TAG=<prefix>
##   WALK_ONLY=home,flight,training,saves,options,controls,credits,overlay,pause   (default all)
## Prints "AUDIT <page>: <n> findings" and the findings; "WALK DONE" at the end.

const Audit := preload("res://tests/ui_audit.gd")
const Pause := preload("res://ui/pause_menu.gd")

var _s: Control
var _out := ""
var _tag := ""
var _findings := 0


class StubFdm extends Node:
	var paused := false
	var replaying := false


class StubFlight extends Node:
	var fdm_node := StubFdm.new()
	var _apt := "VAJJ"


func _ready() -> void:
	var size := OS.get_environment("FREESIM_SIZE")
	if size.contains("x"):
		get_window().size = Vector2i(int(size.get_slice("x", 0)), int(size.get_slice("x", 1)))
	get_window().always_on_top = true
	Session.skip_menu = false
	Session.interactive_override = 0  # nothing is written: options stay in memory, last_flight.json untouched
	Session.save_path = "user://_walk_last_flight.json"
	TrainingLogic.save_path = "user://_walk_training.json"
	SituationStore.dir = "user://_walk_saves/"
	# A fixed percentage is relative to the system scale (2 on Retina), but the UI units it leaves (window / percentage) do not
	# depend on it. So the probe pretends the system scale is 1: the window is W x H pixels, the factor is exactly the percentage.
	var choice := OS.get_environment("FREESIM_UISCALE")
	if choice != "":
		if get_window().size_changed.is_connected(UiScale.apply):
			get_window().size_changed.disconnect(UiScale.apply)
		UserOptions.set_v("ui_scale", choice)  # in memory only
		await get_tree().process_frame
		var f := UiScale.factor_for(Vector2(get_window().size), choice, 1.0)
		get_window().content_scale_factor = f
		UiScale.factor = f
		UiScale.changed.emit(f)
	_tag = OS.get_environment("FREESIM_TAG")
	_out = OS.get_environment("FREESIM_SHOTS")
	if _out == "":
		_out = OS.get_user_data_dir()
	await get_tree().process_frame
	_s = load("res://ui/menu/start_screen.tscn").instantiate()
	add_child(_s)
	await get_tree().create_timer(0.8).timeout
	var only := OS.get_environment("WALK_ONLY").split(",", false)
	var vr := get_viewport().get_visible_rect()
	print("WALK window=%s ui_units=%s factor=%.2f" % [get_window().size, vr.size, get_window().content_scale_factor])
	if only.is_empty() or only.has("home"):
		await _page("home", _s)
	if only.is_empty() or only.has("flight"):
		_s.go("flight")
		for i in _s.screen("flight").STEPS.size():
			_s.screen("flight").show_step(i)
			await _page("flight_%d" % (i + 1), _s)
	if only.is_empty() or only.has("training"):
		_s.go("training")
		await _page("training", _s)
	if only.is_empty() or only.has("saves"):
		_s.go("saves")
		await _page("saves", _s)
	for id in ["options", "controls"]:
		if not (only.is_empty() or only.has(id)):
			continue
		_s.go(id)
		var page: Control = _s.screen(id).pages[0]
		for t in page.tabs.ids():
			page.tabs.select(t)
			print("MIN %s_%s tab page needs %s" % [id, t, page.tabs.page(t).get_combined_minimum_size()])
			await _page("%s_%s" % [id, t], _s)
	if only.is_empty() or only.has("credits"):
		_s.go("home")
		var e := InputEventKey.new()
		e.keycode = KEY_F12
		e.pressed = true
		Input.parse_input_event(e)
		await _page("credits", _s.get_node("Credits"))
		Input.parse_input_event(e)
	if only.is_empty() or only.has("overlay"):
		var ov := ControlsOverlay.new()
		add_child(ov)
		ov.toggle()
		for t in ["joystick", "keyboard", "other"]:
			var pg := _find_tabs(ov)
			if pg != null:
				pg.select(t)
			await _page("overlay_" + t, ov)
		ov.queue_free()
	if only.is_empty() or only.has("pause"):
		await _pause()
	print("WALK DONE findings=%d" % _findings)
	get_tree().quit()


func _find_tabs(n: Node) -> MenuTabs:
	if n is MenuTabs:
		return n
	for k in n.get_children():
		var r := _find_tabs(k)
		if r != null:
			return r
	return null


func _pause() -> void:
	var back := ColorRect.new()  # something to blur behind the pause screen
	back.color = Color(0.25, 0.4, 0.6)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var f := StubFlight.new()
	f.add_child(f.fdm_node)
	add_child(f)
	var layer := CanvasLayer.new()
	f.add_child(layer)
	var p := Control.new()
	p.set_script(Pause)
	p.set("flight", f)
	layer.add_child(p)
	p.open()
	for id in ["home", "options", "controls", "settings"]:  # saves and failures need the real flight tree
		p.show_page(id)
		await _page("pause_" + id, p)
	p.close()
	f.queue_free()
	back.queue_free()


func _page(name: String, root: Node) -> void:
	await get_tree().create_timer(0.45).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join("%s%s.png" % [_tag, name]))
	var found := Audit.audit(root, get_viewport().get_visible_rect())
	_findings += found.size()
	print("AUDIT %s: %d findings" % [name, found.size()])
	for line in found:
		print("   ", line)
