extends TextureRect
## 2D instrument panel along the bottom of the screen for outside views
## (Tab toggles; always hidden in the cockpit view, where the 3D panel is used).
## Mouse input is forwarded to the panel SubViewport so knobs work here too.

var cockpit: Cockpit
var cam: CameraRig
var wanted := true


func setup(c: Cockpit, rig: CameraRig) -> void:
	cockpit = c
	cam = rig
	texture = c.viewport.get_texture()
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_right = 0.0
	mouse_filter = MOUSE_FILTER_STOP
	_resize()
	get_viewport().size_changed.connect(_resize)


func _resize() -> void:
	var vs := get_viewport().get_visible_rect().size
	var h := minf(vs.y * 0.34, vs.x * InstrumentPanel.natural_size().y / InstrumentPanel.natural_size().x)
	offset_top = -h
	offset_bottom = 0.0


func _unhandled_key_input(e: InputEvent) -> void:
	if e.pressed and not e.echo and e.keycode == KEY_TAB:
		wanted = not wanted


func _process(_dt: float) -> void:
	if cam == null:
		return
	visible = wanted and cam.mode != CameraRig.Mode.COCKPIT
	if visible:
		cockpit.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _gui_input(e: InputEvent) -> void:
	if not (e is InputEventMouse):
		return
	# map from this rect (keep-aspect, centred) into panel pixels
	var tex_size := Vector2(cockpit.viewport.size)
	var s := minf(size.x / tex_size.x, size.y / tex_size.y)
	var off := (size - tex_size * s) * 0.5
	var ev: InputEventMouse = e.duplicate()
	ev.position = (e.position - off) / s
	ev.global_position = ev.position
	cockpit.viewport.push_input(ev)
	accept_event()
