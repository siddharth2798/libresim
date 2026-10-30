class_name CloudWisps
extends MultiMeshInstance3D
## Cloud wisps streaming past the camera inside cloud (cloud_wisps.gdshader): a cheap motion cue for chase and
## cockpit views, where a flat cloud interior otherwise shows no speed. Child of the camera, drawn after the
## cloud pass. Count from the graphics preset (0 on Low); opacity and tint from CloudInside.

var _mat := ShaderMaterial.new()


func _ready() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = q
	_mat.shader = preload("res://world/cloud_wisps.gdshader")
	material_override = _mat
	extra_cull_margin = 1e6
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sorting_offset = 2000.0  # after the cloud pass (1000): it would paint over them
	set_count(0)


## Number of wisps (graphics preset); 0 hides the node.
func set_count(n: int) -> void:
	multimesh.instance_count = n
	visible = n > 0


## Called by CloudInside each frame. cam_air: camera in the air-mass frame (ENU), flow: air velocity relative
## to the aircraft (render frame), strength: peak opacity (0 hides).
func update_wisps(cam_air: Vector3, flow: Vector3, strength: float, tint: Color) -> void:
	_mat.set_shader_parameter("cam_air", cam_air)
	_mat.set_shader_parameter("flow", flow)
	_mat.set_shader_parameter("half_len", CloudLook.wisp_length_m(flow.length()))
	_mat.set_shader_parameter("strength", strength)
	_mat.set_shader_parameter("tint", tint)
	visible = strength > 0.002 and multimesh.instance_count > 0
