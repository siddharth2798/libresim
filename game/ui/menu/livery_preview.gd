extends SubViewportContainer
## Exterior turntable. Drag to orbit, scroll to zoom. Colours compose once; a picture is restamped on the
## next frame onto a mipmapped texture, so the fuselage stays solid instead of aliasing into stripes.
## Headless: a note, and the model is not loaded.

var _note: Label
var _view: SubViewport
var _holder: Node3D
var _cam: Camera3D
var _root: Node
var _def: AircraftDef
var _stored: Variant = {}
var _busy := false
var _dirty := false
var _built := ""
var _yaw := -0.62
var _pitch := 0.22
var _zoom := 1.0
var _bounds := AABB()
var _bases := {}
var _shown := {}
var _scratch := {}
var _veil: BusyOverlay
var _ground: MeshInstance3D
var _glyphs := {}  # italic -> registration glyph image, for the number on the turntable
var _text := ""
const SUPERSAMPLE := 2.0
const DEFAULT_ZOOM := 1.3
const _ZOOM_MIN := 0.55
const _ZOOM_MAX := 3.4
const _Frame := preload("res://ui/menu/livery_frame.gd")
const _Paint := preload("res://ui/menu/livery_preview_paint.gd")

func _ready() -> void:
	custom_minimum_size = Vector2(420, 420)
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_default_cursor_shape(Control.CURSOR_MOVE)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
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
	_view.msaa_3d = Viewport.MSAA_4X
	_view.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	_view.anisotropic_filtering_level = Viewport.ANISOTROPY_16X
	# Drawn at twice the size and shrunk to the panel: sharp edges, and sharp on a Retina screen where the
	# panel's pixels are not the display's.
	_view.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	_view.scaling_3d_scale = SUPERSAMPLE
	_view.size = Vector2i(840, 720)
	_view.add_child(_world())
	_light(Vector3(-52, -38, 0), 1.0, Color(1.0, 0.97, 0.92), true)
	_light(Vector3(-20, 140, 0), 0.32, Color(0.8, 0.88, 1.0), false)
	_holder = Node3D.new()
	_view.add_child(_holder)
	_cam = Camera3D.new()
	_cam.current = true
	_cam.fov = _Frame.FOV
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


## Side, front, or the fin. A newly chosen picture uses this so the slot is in view.
func face(part: String) -> void:
	match part:
		"side":
			_yaw = 0.0
			_pitch = 0.08
			_zoom = 1.25
		"nose", "front":
			_yaw = -PI * 0.5
			_pitch = 0.1
			_zoom = 1.05
		"fin", "tail":
			_yaw = PI * 0.5
			_pitch = 0.26
			_zoom = 1.6
		_:
			_yaw = -0.62
			_pitch = 0.22
			_zoom = DEFAULT_ZOOM
	_apply_camera()

func zoom_by(factor: float) -> void:
	_zoom = clampf(_zoom * factor, _ZOOM_MIN, _ZOOM_MAX)
	_apply_camera()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and (button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			zoom_by(1.12 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12)
			accept_event()
			return
	if _cam == null or not event is InputEventMouseMotion:
		return
	var motion := event as InputEventMouseMotion
	if motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_yaw -= motion.relative.x * 0.008
		_pitch = clampf(_pitch + motion.relative.y * 0.005, -0.25, 0.9)
		_apply_camera()
		accept_event()


func _notification(what: int) -> void:
	if what != NOTIFICATION_RESIZED:
		return
	if _veil != null:
		_veil.position = Vector2.ZERO
		_veil.size = size
	_fit_viewport()


func _pump() -> void:
	_busy = true
	while is_instance_valid(self) and _dirty:
		_dirty = false
		await get_tree().process_frame
		if not is_instance_valid(self) or _root == null or _def == null:
			break
		if _dirty:
			continue
		await _repaint()
	if not is_instance_valid(self):
		return
	if _dirty:
		_pump()
	else:
		_busy = false


func _repaint() -> void:
	_text = RegistrationPaint.text_for(_def.section("registration"))
	var jobs: Array = PaintPipeline.plan(_def, _text, _stored)
	var missing := false
	for a in jobs:
		if not _fresh(a):
			missing = true
			break
	if missing and _veil != null:
		_veil.show_busy("Painting the aircraft…")
		await get_tree().process_frame
		if not is_instance_valid(self):
			return
	for a in jobs:
		var job: Dictionary = a
		if _fresh(job):
			continue
		var img: Image = await PaintPipeline.preview_base(self, _def, job)
		if img != null:
			_bases[job.rel] = {"key": _key(job), "image": img}
		if not job.steps.is_empty():
			await PaintPipeline.glyph_images(self, _text, job.steps, _glyphs)
			if not is_instance_valid(self):
				return
	if _veil != null:
		_veil.hide_busy()
	if is_instance_valid(_root):
		_blit(jobs)

func _fresh(job: Dictionary) -> bool:
	return str(_bases.get(job.rel, {}).get("key", "")) == _key(job)


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
		if not job.steps.is_empty() and _glyphs.size() > 0:
			RegistrationPaint.stamp_steps(scratch, job.steps, _glyphs)
		_Paint.assign(_root, str(job.path), ImageTexture.create_from_image(_Paint.for_screen(scratch)))
		_shown[job.rel] = true
	if jobs.is_empty() and not _shown.is_empty():
		PaintPipeline.begin_preview(_root, _def)
		_shown.clear()
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
	_holder.position = -aabb.get_center()
	if _ground != null:
		_ground.position = Vector3(0, -aabb.size.y * 0.5 - 0.03, 0)
	_bounds = AABB(-aabb.size * 0.5, aabb.size)
	_yaw = -0.62
	_pitch = 0.22
	_zoom = DEFAULT_ZOOM
	_fit_viewport()


func _fit_viewport() -> void:
	if _view == null:
		return
	var s := size
	if s.x < 32.0 or s.y < 32.0:
		_apply_camera()
		return
	var px := Vector2i(maxi(2, int(s.x)), maxi(2, int(s.y)))
	var long := maxi(px.x, px.y)
	if long > 1440:
		var k := 1440.0 / float(long)
		px = Vector2i(maxi(2, int(px.x * k)), maxi(2, int(px.y * k)))
	if _view.size != px:
		_view.size = px
	_apply_camera()


func _apply_camera() -> void:
	if _cam == null or _bounds.size.length_squared() < 0.01:
		return
	var aspect := 1.4
	if _view != null and _view.size.y > 0:
		aspect = float(_view.size.x) / float(_view.size.y)
	var dir := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	_cam.fov = _Frame.FOV
	_cam.position = dir * (_Frame.distance(_bounds, dir, aspect) / _zoom)
	_cam.look_at(Vector3.ZERO, Vector3.UP)


func _world() -> Node3D:
	# A soft studio sky: the paint is lit from above and reflects a horizon, not a flat grey. Linear tone mapping keeps
	# the colour the pilot picked (AgX and Filmic fade a saturated red or blue towards pink and grey).
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.52, 0.78)
	sky_mat.sky_horizon_color = Color(0.80, 0.85, 0.92)
	sky_mat.ground_horizon_color = Color(0.80, 0.85, 0.92)
	sky_mat.ground_bottom_color = Color(0.22, 0.23, 0.25)
	sky_mat.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.55
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.fog_enabled = true  # the far edge of the ground melts into the horizon, no seam
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 160.0
	env.fog_depth_end = 800.0
	env.fog_light_color = sky_mat.sky_horizon_color
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	var root := Node3D.new()
	var world := WorldEnvironment.new()
	world.environment = env
	root.add_child(world)
	_ground = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 900.0
	disc.bottom_radius = 900.0
	disc.height = 0.05
	_ground.mesh = disc
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.46, 0.48, 0.5)
	gm.roughness = 0.95
	_ground.material_override = gm
	root.add_child(_ground)
	return root


func _light(rot: Vector3, energy: float, col: Color, shadows: bool) -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = rot
	sun.light_energy = energy
	sun.light_color = col
	sun.shadow_enabled = shadows
	sun.directional_shadow_max_distance = 60.0
	sun.shadow_blur = 1.6
	_view.add_child(sun)
