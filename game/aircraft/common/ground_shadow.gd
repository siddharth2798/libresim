class_name GroundShadow
extends Node3D
## The aircraft's shadow and contact darkening on the ground, from its top-down silhouette (tools/30_planform.py:
## models/planform.json, planform_cast.png, planform_ao.png). Two Decals project straight down onto everything but the
## aircraft itself (LightLogic.AIRCRAFT_LAYER), so they work on Mobile and Forward+ alike:
##   ao    soft darkening right under the aircraft on every preset (real sun shadows do not darken the ground under
##         the belly in the aircraft's own shade); fades out as the wheels leave the ground (by ao_fade_m)
##   cast  the sun's shadow, thrown along the sun from the skin's mid height, where the real one is missing: the sun casts
##         none (Low), or the camera is too far for the shadow split that holds the aircraft (real_reach: Medium's two
##         splits keep it to about 84 m). Follows the sun's shadow_opacity and energy (clouds, dusk, night), weaker with
##         a low sun, gone by CAST_FADE_M above the ground.
## The model's origin is the CG, and fdm/agl_m is the CG above the ground. Pure parts: ao_alpha, cast_alpha, cast_offset
## (tests/test_ground_shadow.gd). GroundShadow.attach(model) adds one when the aircraft has a planform.

const AO_ALPHA := 0.55
const CAST_ALPHA := 0.62
const CAST_FADE_M := Vector2(40.0, 300.0)  # cast shadow full below the first height, gone above the second
const BOX_HALF_M := 4.0  # the decals reach this far above and below the ground point

var model: AircraftModel
var ao: Decal
var cast: Decal
var meta := {}
var _mid := Vector3.ZERO  # model-local centre of the planform rect, at z_mid
var _parked := 0.0  # CG height above the ground with the tyres on it
var _sun: DirectionalLight3D


static func attach(m: AircraftModel) -> GroundShadow:
	var def := m.def
	if def == null or not def.has_file("planform"):
		return null
	var g := GroundShadow.new()
	g.name = "GroundShadow"
	g.model = m
	g.meta = def.json("planform")
	if g.meta.is_empty():
		return null
	var dir := def.path("planform").get_base_dir() + "/"
	g.ao = g._decal(dir + "planform_ao.png")
	g.cast = g._decal(dir + "planform_cast.png")
	m.add_child(g)
	return g


func _decal(path: String) -> Decal:
	var d := Decal.new()
	d.texture_albedo = load(path) if ResourceLoader.exists(path) else null
	d.size = Vector3(float(meta.y1) - float(meta.y0), 2.0 * BOX_HALF_M, float(meta.x1) - float(meta.x0))
	d.cull_mask = 0xFFFFF & ~LightLogic.AIRCRAFT_LAYER
	d.upper_fade = 0.15
	d.lower_fade = 0.15
	d.normal_fade = 0.3  # walls and steep ground take less of it
	d.top_level = true
	d.visible = false
	add_child(d)
	return d


func _ready() -> void:
	var c := Vector3((float(meta.x0) + float(meta.x1)) * 0.5, (float(meta.y0) + float(meta.y1)) * 0.5, float(meta.z_mid))
	_mid = model.structural(c)
	_parked = -model.structural(Vector3(0.0, 0.0, float(meta.z_low))).y


## Opacity of the contact darkening with the CG `agl` m above the ground (`parked` on its wheels).
static func ao_alpha(agl: float, parked: float, fade_m: float) -> float:
	return AO_ALPHA * (1.0 - smoothstep(0.0, maxf(fade_m, 0.1), agl - parked))


## Opacity of the cast shadow: sun travelling along `dir` (unit, down = -y), the sun's shadow opacity x energy share
## `sun_k` (0..1), the CG `agl` m up.
static func cast_alpha(dir: Vector3, sun_k: float, agl: float) -> float:
	var low_sun := smoothstep(0.05, 0.26, -dir.y)  # about 3 to 15 degrees of elevation
	return CAST_ALPHA * clampf(sun_k, 0.0, 1.0) * low_sun * (1.0 - smoothstep(CAST_FADE_M.x, CAST_FADE_M.y, agl))


## How far from the camera the sun's real shadow still holds the aircraft (m): the first split with two splits (the
## second is far too coarse for a 4 m-high airframe), the third with four, nothing with one orthogonal map or none.
static func real_reach(enabled: bool, mode: int, max_m: float, split1: float, split3: float) -> float:
	if not enabled:
		return 0.0
	match mode:
		DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS:
			return max_m * split1
		DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS:
			return max_m * split3
	return 0.0


## Share of the decal shadow with the camera `cam_m` from the aircraft: 0 well inside the real shadow's reach, 1 past it.
static func fallback(cam_m: float, reach: float) -> float:
	if reach <= 0.0:
		return 1.0
	return smoothstep(reach * 0.8, reach, cam_m)


## Horizontal shift (render x, z) of the shadow of a point `h` m above the ground, sun travelling along `dir`.
static func cast_offset(dir: Vector3, h: float) -> Vector2:
	if dir.y >= -0.01:
		return Vector2.ZERO
	return Vector2(dir.x, dir.z) * maxf(h, 0.0) / -dir.y


func _find_sun() -> DirectionalLight3D:
	if is_instance_valid(_sun):
		return _sun
	var root := get_tree().current_scene if is_inside_tree() else null
	if root:
		for l in root.find_children("*", "DirectionalLight3D", true, false):
			if (l as DirectionalLight3D).visible:
				_sun = l
				break
	return _sun


func _process(_dt: float) -> void:
	if model == null or not model.is_inside_tree():
		return
	var agl := Props.get_f("fdm/agl_m", _parked)
	var gt := model.global_transform
	var fwd := -gt.basis.z
	var yaw := Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)) if Vector2(fwd.x, fwd.z).length() > 1e-3 else Basis.IDENTITY
	var centre := gt * _mid
	var ground_y := gt.origin.y - agl
	var a := ao_alpha(agl, _parked, float(meta.y1 - meta.y0) * 0.3)
	ao.visible = a > 0.002
	if ao.visible:
		ao.global_transform = Transform3D(yaw, Vector3(centre.x, ground_y, centre.z))
		ao.modulate = Color(1, 1, 1, a)
	var sun := _find_sun()
	cast.visible = false
	var cam := get_viewport().get_camera_3d()
	if sun == null or cam == null:
		return
	var reach := real_reach(sun.shadow_enabled, sun.directional_shadow_mode, sun.directional_shadow_max_distance,
		sun.directional_shadow_split_1, sun.directional_shadow_split_3)
	var share := fallback(cam.global_position.distance_to(gt.origin), reach)
	if share <= 0.0:
		return
	var dir := -sun.global_basis.z.normalized()
	var k := share * cast_alpha(dir, sun.shadow_opacity * clampf(sun.light_energy / 1.3, 0.0, 1.0), agl)
	if k <= 0.002:
		return
	var off := cast_offset(dir, centre.y - ground_y)
	cast.global_transform = Transform3D(yaw, Vector3(centre.x + off.x, ground_y, centre.z + off.y))
	cast.modulate = Color(1, 1, 1, k)
	cast.visible = true
