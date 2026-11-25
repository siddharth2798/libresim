class_name VehicleParams
extends RefCounted
## Per-vehicle shader values (seed, lamps, wheel_turn, steer) for world/vehicle.gdshader and vehicle_ground.gdshader.
## Forward+ and Mobile: instance uniforms on the shared material. Compatibility (OpenGL): Godot holds at most 4096
## instance-uniform slots there, too few for a busy apron (errors, vehicles drawn with defaults), so the shaders
## declare plain uniforms on that renderer and each vehicle gets its own copy of surface 0's material.


## True when the running renderer takes instance uniforms for these shaders.
static func per_instance(method := RenderingServer.get_current_rendering_method()) -> bool:
	return method != "gl_compatibility"


## Call once per new MeshInstance3D before set(): on Compatibility, a private copy of surface 0's material.
static func own(mi: MeshInstance3D, method := RenderingServer.get_current_rendering_method()) -> void:
	if per_instance(method) or mi.mesh == null:
		return
	var m := mi.mesh.surface_get_material(0) as ShaderMaterial
	if m == null or m.shader == null:
		return
	var own_mat := ShaderMaterial.new()  # built, not duplicate(): same shader, same values, own uniforms
	own_mat.shader = m.shader
	own_mat.render_priority = m.render_priority
	for u in m.shader.get_shader_uniform_list():
		var v: Variant = m.get_shader_parameter(u.name)
		if v != null:
			own_mat.set_shader_parameter(u.name, v)
	if mi.mesh.get_surface_count() == 1:  # the ground decal: one surface, a material override
		mi.material_override = own_mat
	else:  # the body (glass is surface 1, which keeps the shared material)
		mi.set_surface_override_material(0, own_mat)


## Set one per-vehicle value.
static func set_value(mi: MeshInstance3D, name: StringName, value: float) -> void:
	var own_mat := mi.material_override as ShaderMaterial
	if own_mat == null and mi.mesh != null and mi.mesh.get_surface_count() > 0:
		own_mat = mi.get_surface_override_material(0) as ShaderMaterial
	if own_mat != null:
		own_mat.set_shader_parameter(name, value)
	else:
		mi.set_instance_shader_parameter(name, value)
