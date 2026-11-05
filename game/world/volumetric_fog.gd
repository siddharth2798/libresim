class_name VolumetricFog
extends Node
## Near-field volumetric fog (Forward+ only; the "volumetric_fog" option and the presets' "vfog" level): Godot's Environment
## volumetric fog plus FogVolumes, driven by the weather Props each frame: light shafts under broken cloud, rain curtains
## under storm cells (CloudStorm), streaks in heavy rain, morning mist over low ground, puffs in cloud, glow round lights at night.
## The far haze stays the custom aerial perspective; VfogRules keep the froxel fog to what that does not draw. fog_disabled
## materials get it through VfogComposite (child of the camera); standard materials get it from the engine.
## Created / reconfigured by Graphics.apply_to_scene: VolumetricFog.apply(root, level)
## All FogVolumes sit in the render frame: placed from world (ENU) positions every frame and moved with FloatingOrigin.shifted
## at once, so an origin shift never leaves them 5 km off for a frame.

const NODE := "VolumetricFog"
const AIR := preload("res://world/vfog_air.gdshader")
const RAIN := preload("res://world/vfog_rain.gdshader")
const AIR_GLOW := 0.8  # froxel air emission x haze colour; lowered so sunlit air is not whiter than the haze
const MIST_GLOW := 0.5  # mist emission x haze colour: shaded mist stays as pale as the air around it
const FLOOR_EVERY := 2.0  # s between terrain samples for the mist floor

var level := 0  # VfogRules.QUALITY key, 0 = off
var forced := false  # tests: run whatever the renderer / option say
var active := false
var air: FogVolume
var curtains: Array[FogVolume] = []
var composite: VfogComposite
var _env: Environment
var _grid := Vector2i(-1, -1)  # froxel grid last sent to the RenderingServer (global)
var _clock := 0.0  # storm clock when there is no Weather node
var _floor := 0.0
var _floor_timer := 0.0
var _warned := false
static var _no_vfog := OS.get_cmdline_user_args().has("--no-vfog")


## Create or reconfigure the node under `root` for a quality level (0 = off).
static func apply(root: Node, lvl: int) -> VolumetricFog:
	if root == null:
		return null
	var n := root.get_node_or_null(NODE) as VolumetricFog
	if n == null:
		n = VolumetricFog.new()
		n.name = NODE
		root.add_child(n)
	n.level = lvl
	return n


## The effect runs: a quality level, the user option, a High+ preset and Forward+ (PostFxRules "volumetric_fog").
func wanted() -> bool:
	if forced:
		return level > 0
	if _no_vfog:  # --no-vfog: before / after renders and benches
		return false
	return level > 0 and PostFxRules.active("volumetric_fog", Graphics.preset, RenderingServer.get_current_rendering_method(),
		bool(UserOptions.get_v("volumetric_fog")))


func _ready() -> void:
	process_priority = 100  # after SkyTime / CloudInside have set this frame's Environment fog
	air = FogVolume.new()
	air.name = "Air"
	air.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	var m := ShaderMaterial.new()
	m.shader = AIR
	air.material = m
	add_child(air)
	for i in VfogRules.MAX_CURTAINS:
		var fv := FogVolume.new()
		fv.name = "Curtain%d" % i
		fv.shape = RenderingServer.FOG_VOLUME_SHAPE_CYLINDER
		var rm := ShaderMaterial.new()
		rm.shader = RAIN
		rm.set_shader_parameter("seed", 17.0 * i)
		fv.material = rm
		fv.visible = false
		add_child(fv)
		curtains.append(fv)
	composite = VfogComposite.new()
	composite.name = "VfogComposite"
	FloatingOrigin.shifted.connect(_on_shift)


func _exit_tree() -> void:
	if FloatingOrigin.shifted.is_connected(_on_shift):
		FloatingOrigin.shifted.disconnect(_on_shift)
	if composite and not composite.is_inside_tree():
		composite.free()


func _on_shift(delta: Vector3) -> void:
	air.position += delta
	for fv in curtains:
		fv.position += delta


func _process(dt: float) -> void:
	step(dt)


func step(dt: float) -> void:
	var root := get_parent()
	var we := root.get_node_or_null("WorldEnvironment") as WorldEnvironment if root else null
	_env = we.environment if we else null
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var on := wanted() and _env != null and cam != null
	if on and not VfogComposite.env_fog_invertible(_env):
		if not _warned:
			push_warning("VolumetricFog: the Environment fog is not plain exponential (aerial perspective / sun scatter / height): volumetric fog off")
			_warned = true
		on = false
	_set_active(on, cam)
	if not on:
		return
	var q := VfogRules.quality(level)
	_configure_env(q)
	_update(dt, root, cam, q)


func _set_active(on: bool, cam: Camera3D) -> void:
	active = on
	if _env:
		_env.volumetric_fog_enabled = on
	air.visible = on
	if not on:
		for fv in curtains:
			fv.visible = false
	if on and composite.get_parent() != cam:
		if composite.get_parent():
			composite.get_parent().remove_child(composite)
		cam.add_child(composite)
	composite.visible = on


func _configure_env(q: Dictionary) -> void:
	_env.volumetric_fog_density = 0.0  # set per frame in _update (the thin air)
	_env.volumetric_fog_albedo = Color.WHITE
	_env.volumetric_fog_anisotropy = VfogRules.ANISOTROPY
	_env.volumetric_fog_length = q.length
	_env.volumetric_fog_detail_spread = VfogRules.SPREAD
	_env.volumetric_fog_ambient_inject = 0.0  # the air glows with the haze colour instead (emission, _update)
	_env.volumetric_fog_gi_inject = 0.0
	_env.volumetric_fog_sky_affect = 0.0  # the composite fogs the sky pixels itself
	_env.volumetric_fog_temporal_reprojection_enabled = true
	_env.volumetric_fog_temporal_reprojection_amount = q.reproject
	var grid := Vector2i(q.size, q.depth)
	if grid != _grid:  # global, reallocates the froxel buffers: only on change
		_grid = grid
		RenderingServer.environment_set_volumetric_fog_volume_size(grid.x, grid.y)
		RenderingServer.environment_set_volumetric_fog_filter_active(true)


func _update(dt: float, root: Node, cam: Camera3D, q: Dictionary) -> void:
	var w := FloatingOrigin.to_world(cam.global_position)
	var cover := Props.get_f("weather/cloud_cover")
	var base := Units.ft_to_m(Props.get_f("weather/cloud_base_ft", 4500.0))
	var vis := Props.get_f("environment/visibility_m", Props.get_f("weather/visibility_m", 20000.0))
	var rain := Props.get_f("environment/precip")
	var el := Props.get_f("environment/sun_elev_deg", 30.0)
	var haze := WeatherVisuals.fog_density(vis)
	var aloft := Weather._from_dir_to_ned(Props.get_f("weather/aloft_dir_deg"), Props.get_f("weather/aloft_kt") * Units.KT)
	var surf := Weather._from_dir_to_ned(Props.get_f("weather/wind_dir_deg"), Props.get_f("weather/wind_kt") * Units.KT)
	_update_floor(dt, root, w)
	var mist := VfogRules.mist(Props.get_f("weather/time_h", 10.0), el, vis, Props.get_f("environment/wetness"),
		Props.get_f("weather/wind_kt"), cover)
	var ml := VfogRules.mist_layer(mist if VfogRules.MIST_ENABLED else 0.0, _floor)
	var layer := cam.get_node_or_null("CloudLayer") as CloudLayer
	var k := CloudLook.ramp(layer.density_at(w)) if layer else 0.0
	var m := air.material as ShaderMaterial
	var length: float = q.length
	air.position = cam.global_position
	air.size = Vector3(2.0 * length, 2.0 * maxf(length, absf(w.z - base) + 1500.0), 2.0 * length)
	var shaft := VfogRules.shaft_density(cover, haze, el, rain) * (1.0 - k)
	var thin := VfogRules.thin_air(shaft, VfogRules.night_density(Props.get_f("environment/light_level", 1.0), haze, vis) * (1.0 - k))
	# the air's own glow = the haze colour the custom aerial perspective draws, so the froxel fog never darkens or
	# re-tints it; the sun (albedo, anisotropy, shadow map, cloud-shadow cut) adds the shafts on top
	_env.volumetric_fog_emission = _env.fog_light_color
	_env.volumetric_fog_emission_energy = AIR_GLOW
	_env.volumetric_fog_density = thin  # float: the thin air (FogVolume density is fixed point, see vfog_air.gdshader)
	m.set_shader_parameter("cut", VfogRules.shadow_cut(thin, thin))
	var light := Props.get_f("environment/light_level", 1.0)
	m.set_shader_parameter("base_m", VfogRules.haze_top(cover, base, _floor, light))
	var hc := _env.fog_light_color.srgb_to_linear() * clampf(light, 0.05, 1.0) * MIST_GLOW
	m.set_shader_parameter("mist_glow", Vector3(hc.r, hc.g, hc.b))  # Vector3: a Color would be linearised again
	m.set_shader_parameter("mist", ml.density)
	m.set_shader_parameter("mist_floor", _floor)
	m.set_shader_parameter("mist_top", ml.top)
	m.set_shader_parameter("rain", VfogRules.rain_density(rain))
	m.set_shader_parameter("cloud", VfogRules.cloud_density(k, _env.fog_density))
	m.set_shader_parameter("cam", cam.global_position)
	_cloud_params(m, layer)
	m.set_shader_parameter("wind", Vector2(surf.y, -surf.x))  # NED -> render x (east), z (south)
	_update_curtains(dt, root, w, base, Vector2(aloft.y, aloft.x))
	var near := _near_cut(cam)
	composite.configure(int(q.slices), near, VfogRules.composite_far(length, _env.fog_density if _env.fog_enabled else 0.0), _env)


## The cloud-shadow inputs the terrain reads as global shader parameters (CloudLayer._publish_shadow), as material
## parameters: global uniforms read wrong values in fog shaders (Godot 4.7).
func _cloud_params(m: ShaderMaterial, layer: CloudLayer) -> void:
	m.set_shader_parameter("pattern_origin", FloatingOrigin.pattern_origin())
	if layer == null:
		m.set_shader_parameter("cloud_shadow", Vector4.ZERO)
		return
	var cm := layer.material_override as ShaderMaterial
	var wb := FloatingOrigin.wrap_base_value()
	m.set_shader_parameter("cloud_shadow", layer.shadow)
	m.set_shader_parameter("cloud_uv_off", Vector2(fposmod(wb.x + layer.drift.x, 9000.0), fposmod(wb.y + layer.drift.y, 9000.0)) / 9000.0)
	if cm:
		var sd = cm.get_shader_parameter("sun_dir")
		m.set_shader_parameter("cloud_sun", (sd as Vector3).normalized() if sd is Vector3 else Vector3.UP)
		m.set_shader_parameter("cloud_noise", cm.get_shader_parameter("noise_lo"))


## Pixels nearer than the aircraft (and its size) keep the engine's own fog: the composite would apply it twice.
func _near_cut(cam: Camera3D) -> float:
	var rig := cam as CameraRig
	var model: Node3D = rig.aircraft if rig else null
	if model == null:
		return 15.0
	var def: AircraftDef = model.def if "def" in model else null
	return PostFxRules.near_cutoff_m(cam.global_position.distance_to(model.global_position), PostFxRules.aircraft_extent_m(def))


## The mist floor: the lowest ground within ~3 km (sampled every FLOOR_EVERY s), so mist pools in the valleys.
func _update_floor(dt: float, root: Node, w: Vector3) -> void:
	_floor_timer -= dt
	if _floor_timer > 0.0:
		return
	_floor_timer = FLOOR_EVERY
	var t := root.get_node_or_null("Terrain") if root else null
	if t == null or not t.has_method("height_at"):
		_floor = 0.0
		return
	var lo := INF
	for i in range(-3, 4):
		for j in range(-3, 4):
			lo = minf(lo, maxf(float(t.height_at(w.x + i * 1000.0, w.y + j * 1000.0)), 0.0))
	_floor = lo


## Storm cells near the camera (the same cells, clock and drift as CloudPhysics) -> rain curtain cylinders.
func _update_curtains(dt: float, root: Node, w: Vector3, base: float, wind_en: Vector2) -> void:
	_clock += dt
	var c := CloudPhysics.conditions()
	var cells := []
	if c.kind == CloudField.CUMULONIMBUS:
		cells = VfogRules.storm_cells(Vector2(w.x, w.y), _storm_clock(root), wind_en, float(c.storms))
	var t := root.get_node_or_null("Terrain") if root else null
	for i in curtains.size():
		var fv := curtains[i]
		fv.visible = i < cells.size()
		if not fv.visible:
			continue
		var cl: Dictionary = cells[i]
		var ce: Vector2 = cl.center
		var ground := maxf(float(t.height_at(ce.x, ce.y)), 0.0) if t and t.has_method("height_at") else 0.0
		var h := maxf(base - ground, 200.0)
		fv.position = FloatingOrigin.to_render_d(ce.x, ce.y, ground + h * 0.5)
		fv.size = Vector3(2.4 * cl.radius, h, 2.4 * cl.radius)
		var rm := fv.material as ShaderMaterial
		rm.set_shader_parameter("density", VfogRules.curtain_density(cl.strength, Props.get_f("weather/precip")))
		rm.set_shader_parameter("drift", Vector2(wind_en.x, -wind_en.y))


## Weather's CloudPhysics clock (the cells' drift), else our own.
func _storm_clock(root: Node) -> float:
	var wx := root.get_node_or_null("Weather") if root else null
	if wx and "cloud" in wx and wx.cloud != null:
		var t = wx.cloud.get("_t")
		if t != null:
			return float(t)
	return _clock
