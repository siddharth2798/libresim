extends SubViewportContainer
## A turntable of the exterior. Drag to yaw. Scroll, or the + and − buttons, to zoom.
## Repaints from the livery entry, debounced, without hiding the model (PaintPipeline.preview, not apply).
## Headless: a note, no scene load.

var _note: Label
var _view: SubViewport
var _pivot: Node3D
var _holder: Node3D
var _cam: Camera3D
var _root: Node
var _def: AircraftDef
var _stored: Variant = {}
var _busy := false
var _dirty := false
var _built := ""
var _zoom := 1.0
var _base := Vector3.ZERO
const _ZOOM_MIN := 0.55
const _ZOOM_MAX := 3.4


func _ready() -> void:
	custom_minimum_size = Vector2(340, 300)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.text = "The turntable preview needs a window."
	_note.visible = DisplayServer.get_name() == "headless"
	add_child(_note)
	if DisplayServer.get_name() == "headless":
		return
	_view = SubViewport.new()
	_view.own_world_3d = true
	_view.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_view.size = Vector2i(680, 600)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.14, 0.18)
	var world := WorldEnvironment.new()
	world.environment = env
	_view.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	_view.add_child(sun)
	_pivot = Node3D.new()
	_view.add_child(_pivot)
	_holder = Node3D.new()
	_pivot.add_child(_holder)
	_cam = Camera3D.new()
	_cam.current = true
	_view.add_child(_cam)
	add_child(_view)


func show_aircraft(def: AircraftDef) -> void:
	_def = def
	if DisplayServer.get_name() == "headless" or def == null:
		return
	if _built == def.id and _root != null:
		return
	_built = def.id
	if _root != null:
		_root.queue_free()
		_root = null
	var path := def.dir + "/models/exterior.glb"
	if not ResourceLoader.exists(path):
		_note.visible = true
		_note.text = "This aircraft has no exterior model to preview."
		return
	_note.visible = false
	_root = (load(path) as PackedScene).instantiate()
	_holder.add_child(_root)
	_frame()


func set_paint(stored: Variant) -> void:
	_stored = stored
	if DisplayServer.get_name() == "headless" or _root == null:
		return
	_dirty = true
	if not _busy:
		_run()


## Buttons drawn over the turntable. The page parents them; this viewport would lay them out as a second child.
func zoom_controls() -> Control:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	row.offset_left = -88.0
	row.offset_top = 8.0
	row.offset_right = -8.0
	row.offset_bottom = 40.0
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_theme_constant_override("separation", 4)
	row.add_child(_zoom_button("−", "Zoom out", 1.0 / 1.18))
	row.add_child(_zoom_button("+", "Zoom in", 1.18))
	return row


func _zoom_button(text: String, tip: String, factor: float) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(36, 28)
	b.pressed.connect(_nudge_zoom.bind(factor))
	return b


func _nudge_zoom(factor: float) -> void:
	_set_zoom(_zoom * factor)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and (button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			_set_zoom(_zoom * (1.12 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12))
			accept_event()
			return
	if _pivot == null or not event is InputEventMouseMotion:
		return
	var motion := event as InputEventMouseMotion
	if motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_pivot.rotate_y(-motion.relative.x * 0.01)


func _set_zoom(zoom: float) -> void:
	_zoom = clampf(zoom, _ZOOM_MIN, _ZOOM_MAX)
	if _cam == null or _base.length_squared() < 0.01:
		return
	_cam.position = _base / _zoom
	_cam.look_at(Vector3.ZERO)


func _run() -> void:
	_busy = true
	await get_tree().create_timer(0.3).timeout
	while _dirty and is_instance_valid(self):
		_dirty = false
		var stored = _stored
		if _root != null and _def != null:
			await PaintPipeline.preview(self, _root, _def, stored)
	_busy = false


func _frame() -> void:
	var aabb := AABB()
	var any := false
	for mi in _root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var box := m.global_transform * m.mesh.get_aabb()
		aabb = box if not any else aabb.merge(box)
		any = true
	if not any:
		return
	var c := aabb.get_center()
	_holder.position = -c
	var r := maxf(aabb.size.length() * 0.55, 2.0)
	_base = Vector3(r * 0.15, r * 0.32, r)
	_zoom = 1.0
	_set_zoom(_zoom)
