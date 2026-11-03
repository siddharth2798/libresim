class_name VfogComposite
extends MeshInstance3D
## The full-screen pass that applies the froxel fog to the fog_disabled materials (world/vfog_composite.gdshader).
## Child of the current camera; VolumetricFog sets the planes and the Environment fog to undo every frame.

const SHADER := preload("res://world/vfog_composite.gdshader")

var mat := ShaderMaterial.new()
var planes := -1


func _ready() -> void:
	mat.shader = SHADER
	mat.render_priority = Material.RENDER_PRIORITY_MIN  # first of the transparents: rain, lights and clouds draw over it
	material_override = mat
	extra_cull_margin = 1e6
	sorting_offset = -1000.0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED


## n + 1 full-screen quads in one mesh, plane index in z: one draw call, drawn in index order (blending relies on it).
static func build_mesh(n: int) -> ArrayMesh:
	var v := PackedVector3Array()
	for i in n + 1:
		for p in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			v.append(Vector3(p.x, p.y, i))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	return m


## near_m / far_m: first / last plane (m of view depth); env: the Environment whose fog the engine adds here.
func configure(n: int, near_m: float, far_m: float, env: Environment) -> void:
	if n != planes:
		planes = n
		mesh = build_mesh(n)
		mat.set_shader_parameter("n", float(n))
		mat.set_shader_parameter("spread", VfogRules.SPREAD)
	mat.set_shader_parameter("z0", near_m)
	mat.set_shader_parameter("z1", maxf(far_m, near_m + 10.0))
	var on := env != null and env.fog_enabled
	var c := env.fog_light_color.srgb_to_linear() * env.fog_light_energy if on else Color.BLACK
	mat.set_shader_parameter("env_k", env.fog_density if on else 0.0)
	mat.set_shader_parameter("env_col", Vector3(c.r, c.g, c.b))


## The composite can only undo plain exponential Environment fog (vfog_composite.gdshader).
static func env_fog_invertible(env: Environment) -> bool:
	if env == null or not env.fog_enabled:
		return true
	return env.fog_mode == Environment.FOG_MODE_EXPONENTIAL and env.fog_aerial_perspective <= 0.0 \
		and env.fog_sun_scatter <= 0.0 and absf(env.fog_height_density) < 1e-4
