extends Node
## Debug: what is on screen from the Fly click until the flight is shown (needs a display; run with --audio-driver Dummy).
## Opens the real start screen, clicks Free flight (or Training) and Fly with injected mouse input, and captures the
## window every frame (every 4th once the flight is up) into $FREESIM_SHOTS/<tag>_NN.png, with a log line per frame:
## the veil, its film frame, the scene underneath and every other visible overlay.
## Env: FREESIM_AIRCRAFT=c172|a320  FREESIM_SHOTS=dir  FREESIM_TAG=before  FREESIM_SIZE=1280x720
##      FREESIM_MODE=flight|training  FREESIM_PRESET=Low|Medium|High  FREESIM_SLOW=1 (hold the veil's first frame back)

const MAX_FRAMES := 900
const SHOT_W := 480

var _s: Control
var _out := ""
var _tag := "shot"
var _imgs: Array = []
var _log: Array = []
var _t0 := 0
var _frame := 0
var _on := false
var _flight_frames := 0


func _ready() -> void:
	var size := OS.get_environment("FREESIM_SIZE")
	get_window().size = Vector2i(1280, 720)
	if size.contains("x"):
		get_window().size = Vector2i(int(size.get_slice("x", 0)), int(size.get_slice("x", 1)))
	_out = OS.get_environment("FREESIM_SHOTS") if OS.get_environment("FREESIM_SHOTS") != "" else OS.get_user_data_dir()
	if OS.get_environment("FREESIM_TAG") != "":
		_tag = OS.get_environment("FREESIM_TAG")
	DirAccess.make_dir_recursive_absolute(_out)
	Session.interactive_override = 0  # nothing is saved
	var ac := OS.get_environment("FREESIM_AIRCRAFT")
	if ac != "":
		Session.setup.aircraft = ac
		Session.apply_payload_defaults(AircraftDef.load_def(ac))
	if OS.get_environment("FREESIM_START") != "":
		Session.setup.start = OS.get_environment("FREESIM_START")
	if OS.get_environment("FREESIM_AIRPORT") != "":
		Session.setup.airport = OS.get_environment("FREESIM_AIRPORT")
		Session.setup.runway = ""
	var preset := OS.get_environment("FREESIM_PRESET")
	if preset != "":
		Graphics.set_preset(preset)
	_s = load("res://ui/menu/start_screen.tscn").instantiate()
	get_tree().root.add_child.call_deferred(_s)
	_start.call_deferred()


func _start() -> void:
	await get_tree().create_timer(1.5, true, false, true).timeout
	get_tree().current_scene = _s
	var home: Control = _s.screen("home")
	var training := OS.get_environment("FREESIM_MODE") == "training"
	await _click(home._cards[1 if training else 0])
	var waited := 0.0
	while _s.cur != ("training" if training else "flight") and waited < 8.0:
		await get_tree().create_timer(0.25, true, false, true).timeout
		waited += 0.25
	await get_tree().create_timer(1.2, true, false, true).timeout
	var btn: Button
	if training:
		btn = _s.screen("training").primary_btn
	else:
		btn = _s.screen("flight").fly_btn
	print("fly button: ", btn.text, " visible ", btn.is_visible_in_tree())
	_t0 = Time.get_ticks_msec()
	_on = true
	await _click(btn)
	for i in 6:
		await get_tree().process_frame
	if is_instance_valid(_s) and _s._confirm != null:  # "Fly anyway?" for a setup with a warning
		await _click(_s._confirm.fly_btn)


func _process(_dt: float) -> void:
	if not _on:
		return
	_grab.call_deferred()


func _grab() -> void:
	await RenderingServer.frame_post_draw
	var cs: Node = get_tree().current_scene
	var scene: String = str(cs.name) if cs != null else "none"
	var veil := BusyOverlay.root_veil(get_tree())
	var is_flight: bool = cs != null and cs.has_node("UI")
	if is_flight and veil == null:
		_flight_frames += 1
	var keep := _frame < 150 or _frame % 4 == 0 or (_flight_frames > 0 and _flight_frames < 8)
	if keep and _imgs.size() < MAX_FRAMES:
		var img := get_viewport().get_texture().get_image()
		img.resize(SHOT_W, int(SHOT_W * img.get_height() / float(img.get_width())), Image.INTERPOLATE_BILINEAR)
		_imgs.append(img)
		_log.append("%4d %5d ms scene=%s %s  extra=%s" % [_frame, Time.get_ticks_msec() - _t0, scene, _veil_line(veil), _overlays(cs)])
	_frame += 1
	if _flight_frames >= 8 or _frame > 1500:
		_on = false
		_finish()


func _veil_line(veil: BusyOverlay) -> String:
	if veil == null:
		return "veil=none"
	var film: LoaderFilm = veil._film
	return "veil=on dim=%s film=%s tex=%s" % [veil._dim.visible, film.visible, film.texture != null]


## Visible controls and canvas layers that could draw: anything in the flight scene's UI, and any layer other than the veil's.
func _overlays(cs: Node) -> String:
	var names: Array = []
	for n in get_tree().root.get_children():
		if n is CanvasLayer and n.visible and n.name != "BusyLayer":
			names.append("%s(L%d)" % [n.name, n.layer])
	if cs != null:
		for c in cs.get_children():
			if c is CanvasLayer and c.visible:
				names.append("%s(L%d)" % [c.name, c.layer])
	return ",".join(names)


func _finish() -> void:
	for i in _imgs.size():
		_imgs[i].save_png(_out.path_join("%s_%02d.png" % [_tag, i]))
	var f := FileAccess.open(_out.path_join("%s_log.txt" % _tag), FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	for l in _log.slice(0, 40):
		print(l)
	print("DONE ", _imgs.size(), " frames in ", _out)
	get_tree().quit()


func _px(ctl: Control) -> Vector2:
	return get_viewport().get_final_transform() * (ctl.get_global_transform_with_canvas() * (ctl.size * 0.5))


func _button(at: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	e.position = at
	e.global_position = at
	Input.parse_input_event(e)


func _click(ctl: Control) -> void:
	var at := _px(ctl)
	var m := InputEventMouseMotion.new()
	m.position = at
	m.global_position = at
	Input.parse_input_event(m)
	await get_tree().process_frame
	await get_tree().process_frame
	print("click ", ctl.name, " at ", at, " rect ", ctl.get_global_rect(), " hovered ", get_viewport().gui_get_hovered_control())
	_button(at, true)
	await get_tree().process_frame
	_button(at, false)
