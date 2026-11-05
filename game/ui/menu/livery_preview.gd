extends SubViewportContainer
## A turntable of the exterior. Drag to yaw. Repaints from the livery entry, debounced, without
## hiding the model (PaintPipeline.preview, not apply). Headless: a note, no scene load.

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


func _gui_input(event: InputEvent) -> void:
	if _pivot == null or not event is InputEventMouseMotion:
		return
	var motion := event as InputEventMouseMotion
	if motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_pivot.rotate_y(-motion.relative.x * 0.01)


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
	_cam.position = Vector3(r * 0.15, r * 0.32, r)
	_cam.look_at(Vector3.ZERO)
