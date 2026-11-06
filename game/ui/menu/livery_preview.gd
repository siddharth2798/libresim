extends SubViewportContainer
## A turntable of the exterior. Drag to yaw. Scroll, or the + and − buttons, to zoom.
## A colour change composes the atlas once (a loader covers the model while the GPU draws it). Moving a
## picture, or its scale and position, restamps that cached atlas on the next frame. Headless: a note, no scene load.

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
var _bases := {}  # atlas rel -> {key, image}: the recoloured atlas, before stickers
var _live := {}  # atlas rel -> ImageTexture already on the mesh
var _shown := {}  # atlas rel -> true once that texture is the surface override
var _scratch := {}  # atlas rel -> Image stamped into each frame (the cache stays clean)
var _veil: BusyOverlay
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
	_veil = BusyOverlay.new()
	_veil.z_index = 3
	add_child(_veil)


func show_aircraft(def: AircraftDef) -> void:
	_def = def
	if DisplayServer.get_name() == "headless" or def == null:
		return
	if _built == def.id and _root != null:
		return
	_built = def.id
	_bases.clear()
	_live.clear()
	_shown.clear()
	_scratch.clear()
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
		_pump()


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


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _veil != null:
		_veil.position = Vector2.ZERO
		_veil.size = size


func _pump() -> void:
	while is_instance_valid(self) and _dirty:
		_dirty = false
		await get_tree().process_frame  # sliders in this frame collapse into one paint
		if not is_instance_valid(self) or _root == null or _def == null:
			break
		_dirty = false
		await _repaint()
	if is_instance_valid(self):
		_busy = false


func _repaint() -> void:
	var jobs: Array = PaintPipeline.plan(_def, "", _stored)
	var missing := false
	for a in jobs:
		var job: Dictionary = a
		if not _fresh(job):
			missing = true
			break
	if missing and _veil != null:
		_veil.show_busy("Painting the aircraft…")
		await get_tree().process_frame  # the veil draws before the compose hitch
		if not is_instance_valid(self):
			return
	for a in jobs:
		var job: Dictionary = a
		if _fresh(job):
			continue
		var img: Image = await PaintPipeline.preview_base(self, _def, job)
		if img != null:
			_bases[job.rel] = {"key": _key(job), "image": img}
	if _veil != null:
		_veil.hide_busy()
	if is_instance_valid(_root):
		_blit(jobs)


func _fresh(job: Dictionary) -> bool:
	var have: Dictionary = _bases.get(job.rel, {})
	return str(have.get("key", "")) == _key(job)


func _key(job: Dictionary) -> String:
	return Livery.cache_key(_def.id, job.colors, {})


func _blit(jobs: Array) -> void:
	var rels := {}
	for a in jobs:
		rels[(a as Dictionary).rel] = true
	var same := rels.size() == _shown.size()
	if same:
		for r in rels:
			if not _shown.has(r):
				same = false
				break
	if not same:
		PaintPipeline.begin_preview(_root, _def)
		_shown.clear()
		_live.clear()
		_scratch.clear()
	for a in jobs:
		var job: Dictionary = a
		var src: Variant = _bases.get(job.rel, {}).get("image", null)
		if not src is Image:
			continue
		var scratch: Image = _scratch.get(job.rel, null)
		if scratch == null or scratch.get_size() != (src as Image).get_size():
			scratch = (src as Image).duplicate()
			_scratch[job.rel] = scratch
		else:
			scratch.copy_from(src)
		var stickers: Array = job.get("stickers", [])
		if not stickers.is_empty():
			LiveryStickers.stamp(scratch, stickers)
		if _shown.has(job.rel):
			(_live[job.rel] as ImageTexture).update(scratch)
		else:
			var tex := ImageTexture.create_from_image(scratch)
			_live[job.rel] = tex
			PaintPipeline.override(_root, str(job.path), tex)
			_shown[job.rel] = true
	if jobs.is_empty() and not _shown.is_empty():
		PaintPipeline.begin_preview(_root, _def)
		_shown.clear()
		_live.clear()
		_scratch.clear()


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
