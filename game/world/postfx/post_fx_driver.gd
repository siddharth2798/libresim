class_name PostFxDriver
extends Node
## Feeds the post effects every frame (core/post_fx.gd creates it as "PostFxDriver" under the flight scene root and
## sets `flags` from PostFxRules.flags_for). Reads only Props, the sun, the camera and the aircraft data; the look
## numbers come from PostFxLook, the gating from PostFxRules. Nothing here names an aircraft: the camera view is the
## CameraRig's generic mode, sizes come from AircraftDef (PostFxRules.aircraft_extent_m), exhausts from aircraft.json.

const RAIN_WET := 0.35  # /s: drops build up on the lens
const RAIN_DRY := 0.08  # /s: and dry off slowly once out of the rain
const SHAFTS_GAIN := 0.3  # sun shafts at PostFxLook.shafts_strength 1 (tune by eye)

var flags := {}  # effect -> bool (PostFxRules.flags_for)
var motion_blur := MotionBlurEffect.new()
var sun_shafts := SunShaftsEffect.new()
var grade := ColorGrade.new()
var screen := ScreenPost.new()
var shimmer: HeatShimmer
var _cam: Camera3D
var _view := -99
var _shimmer_model: Node3D
var _dof: CameraAttributesPractical
var _lens_rain := 0.0
var _root: Node


func _init() -> void:
	add_child(screen)  # here, not in _ready(): a driver freed before entering the tree must not orphan it


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 20  # after the camera rig (10): this frame's camera transform
	if not FloatingOrigin.shifted.is_connected(_on_shift):
		FloatingOrigin.shifted.connect(_on_shift)


## root: the scene (flight.tscn). Attaches the compositor effects to its WorldEnvironment (else the camera).
func configure(root: Node, f: Dictionary) -> void:
	_root = root
	flags = f
	motion_blur.enabled = bool(f.get("motion_blur", false))
	motion_blur.needs_motion_vectors = motion_blur.enabled  # no velocity pass when it is off
	sun_shafts.enabled = bool(f.get("sun_shafts", false))
	var we := root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var cam := root.get_viewport().get_camera_3d() if root.is_inside_tree() else null
	var comp: Compositor = we.compositor if we else (cam.compositor if cam else null)
	if comp == null:
		comp = Compositor.new()
	var list: Array = comp.compositor_effects
	for e in [motion_blur, sun_shafts]:  # motion blur first: shafts are a light source, not something that moved
		var i := list.find(e)
		if e.enabled and i < 0:
			list.append(e)
		elif not e.enabled and i >= 0:
			list.remove_at(i)  # a disabled compute effect still asks the mobile renderer for a depth resolve
	comp.compositor_effects = list
	if we:
		we.compositor = comp
	elif cam:
		cam.compositor = comp
	motion_blur.reset = true


func _on_shift(_d: Vector3) -> void:
	motion_blur.reset = true  # the whole world jumped 5 km: last frame's transforms mean nothing


func _process(dt: float) -> void:
	if _root == null or not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		screen.visible = false  # no 3D view (a menu scene): nothing to post-process
		return
	var view := int((cam as CameraRig).mode) if cam is CameraRig else PostFxRules.VIEW_OTHER
	var model: Node3D = (cam as CameraRig).aircraft if cam is CameraRig else null
	if cam != _cam or view != _view:
		motion_blur.reset = true  # view switch or a new camera: a cut
		_cam = cam
		_view = view
	var def: AircraftDef = model.def if model and "def" in model else null
	var extent := PostFxRules.aircraft_extent_m(def)
	var to_ac := cam.global_position.distance_to(model.global_position) if model else 0.0
	var near_cut := PostFxRules.near_cutoff_m(to_ac, extent)
	motion_blur.frame_dt = dt
	motion_blur.near_cut = near_cut
	var w := _weather(cam)
	_update_shafts(cam, w)
	var we := _root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	grade.apply(we.environment if we else null, bool(flags.get("color_grading", false)), PostFxLook.grade(w.el, w.cover, w.rain))
	_update_shimmer(cam, model, w, near_cut)
	var target := PostFxLook.lens_rain(view, w.rain, w.in_cloud) if flags.get("lens_rain", false) else 0.0
	_lens_rain = move_toward(_lens_rain, target, dt * (RAIN_WET if target > _lens_rain else RAIN_DRY))
	if target == 0.0 and not PostFxRules.lens_rain_wanted(view):
		_lens_rain = 0.0  # cockpit: the outside lens is not in the picture at all
	screen.configure(bool(flags.get("sharpen", false)), bool(flags.get("lens_effects", false)), _lens_rain, Props.get_f("fdm/ias_mps"))
	_update_dof(cam, view, to_ac, extent)


## Sun and weather inputs shared by the effects (the same sources and occlusion rule as world/sky_time.gd).
func _weather(cam: Camera3D) -> Dictionary:
	var sun := _root.get_node_or_null("Sun") as DirectionalLight3D
	var sun_dir := sun.global_transform.basis.z.normalized() if sun else Vector3.UP
	var cover := Props.get_f("weather/cloud_cover")
	var top := Units.ft_to_m(Props.get_f("weather/cloud_base_ft", 4500.0)) + WeatherFx.CLOUD_THICK
	var alt := FloatingOrigin.to_world(cam.global_position).z
	return {"sun_dir": sun_dir, "sun_color": sun.light_color if sun else Color.WHITE, "el": rad_to_deg(asin(clampf(sun_dir.y, -1.0, 1.0))),
		"cover": cover, "occl": WeatherVisuals.sun_occlusion(cover, 1.0 - smoothstep(top - 150.0, top + 150.0, alt)),
		"rain": Props.get_f("environment/precip"), "vis": Props.get_f("environment/visibility_m", 20000.0),
		"wet": Props.get_f("environment/wetness"), "in_cloud": Props.get_b("environment/in_cloud"),
		"temp_c": Props.get_f("weather/temp_c", 30.0)}


func _update_shafts(cam: Camera3D, w: Dictionary) -> void:
	if not flags.get("sun_shafts", false) or w.in_cloud:
		sun_shafts.strength = 0.0
		return
	var facing := smoothstep(0.0, 0.6, (-cam.global_transform.basis.z).dot(w.sun_dir))
	sun_shafts.sun_dir = w.sun_dir
	sun_shafts.sun_color = w.sun_color
	sun_shafts.strength = SHAFTS_GAIN * PostFxLook.shafts_strength(w.el, w.occl, w.cover, w.rain, w.vis, facing)


func _update_shimmer(cam: Camera3D, model: Node3D, w: Dictionary, near_cut: float) -> void:
	if not flags.get("heat_shimmer", false):
		if shimmer:
			shimmer.visible = false
		return
	if shimmer == null or shimmer.get_parent() != cam:
		if shimmer:
			shimmer.queue_free()
		shimmer = HeatShimmer.new()
		shimmer.name = "HeatShimmer"
		cam.add_child(shimmer)
		_shimmer_model = null
	if model != _shimmer_model:
		shimmer.setup(model)
		_shimmer_model = model
	var ground := PostFxLook.ground_shimmer(w.el, w.occl, w.rain, w.wet, Props.get_f("fdm/agl_m", 1000.0), w.temp_c)
	shimmer.update_shimmer(ground, maxf(near_cut * 1.5, 120.0), 4000.0)


## Depth of field focused on the aircraft, only in replay / the free camera (PostFxRules.dof_wanted).
func _update_dof(cam: Camera3D, view: int, focus_m: float, extent: float) -> void:
	var on: bool = flags.get("depth_of_field", false) and focus_m > 0.0 and PostFxRules.dof_wanted(view, Props.get_b("replay/active"))
	if not on:
		if _dof and cam.attributes == _dof:
			cam.attributes = null
		return
	if _dof == null:
		_dof = CameraAttributesPractical.new()  # exposure stays at its defaults (x1): SkyTime owns the exposure
	var d := PostFxLook.dof(focus_m, extent)
	_dof.dof_blur_near_enabled = true
	_dof.dof_blur_near_distance = d.near_end
	_dof.dof_blur_near_transition = d.near_len
	_dof.dof_blur_far_enabled = true
	_dof.dof_blur_far_distance = d.far_start
	_dof.dof_blur_far_transition = d.far_len
	_dof.dof_blur_amount = d.amount
	if cam.attributes != _dof:
		cam.attributes = _dof
