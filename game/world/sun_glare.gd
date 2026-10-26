class_name SunGlare
extends MeshInstance3D
## Full-screen sun glare pass (sun_glare.gdshader). Child of the camera, like CloudLayer;
## SkyTime feeds it each frame. Off at the Low preset.

var enabled := true
var _mat := ShaderMaterial.new()


func _ready() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mesh = q
	_mat.shader = preload("res://world/sun_glare.gdshader")
	material_override = _mat
	extra_cull_margin = 1e6
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sorting_offset = 2000.0  # after the clouds
	visible = false


## sun_dir: render frame, towards the sun; strength 0..1.
func update_glare(sun_dir: Vector3, color: Color, strength: float) -> void:
	visible = enabled and strength > 0.001
	_mat.set_shader_parameter("sun_dir", sun_dir)
	_mat.set_shader_parameter("sun_color", color)
	_mat.set_shader_parameter("strength", strength)
