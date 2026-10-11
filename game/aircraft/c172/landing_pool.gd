class_name LandingPool
extends MeshInstance3D
## Lit patch on the ground ahead of a landing or taxi light (aircraft/c172/ground_pool.gdshader).
## Laid flat on the ground under the aircraft (fdm/agl_m), yawed with the heading, fading out
## as the aircraft climbs away from the ground. The real SpotLight3D still lights objects.

const SHADER := preload("res://aircraft/c172/ground_pool.gdshader")
const FADE_AGL := Vector2(25.0, 90.0)  # m: full below, gone above

var near_m := 6.0
var far_m := 70.0
var width_m := 18.0
var strength := 0.3
var lateral := 0.0
var _mat := ShaderMaterial.new()


func setup(near: float, far: float, width: float, gain: float, side_m: float) -> void:
	near_m = near
	far_m = far
	width_m = width
	strength = gain
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	mesh = pm
	_mat.shader = SHADER
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	visible = false
	lateral = side_m


## Pool brightness 0..1: on, night, fading out with height above the ground.
static func pool_level(on: bool, night: float, agl: float) -> float:
	if not on:
		return 0.0
	return night * (1.0 - smoothstep(FADE_AGL.x, FADE_AGL.y, agl))


## Lay the pool for an aircraft at `xf` (global) with height `agl` above the ground.
func place(xf: Transform3D, agl: float, lv: float) -> void:
	visible = lv > 0.002
	if not visible:
		return
	var fwd := -xf.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.1:
		visible = false
		return
	fwd = fwd.normalized()
	var right := Vector3.UP.cross(-fwd).normalized()
	var ground := xf.origin - Vector3(0.0, agl - 0.4, 0.0)  # above the runway strip (LIFT + distance lift)
	var mid := (near_m + far_m) * 0.5
	var b := Basis(right * width_m, Vector3.UP, fwd * (far_m - near_m))
	# PlaneMesh UV.y runs from -Z (v=0) to +Z (v=1): put v=0 at the near end
	global_transform = Transform3D(b, ground + fwd * mid + right * lateral)
	_mat.set_shader_parameter("level", lv * strength)
