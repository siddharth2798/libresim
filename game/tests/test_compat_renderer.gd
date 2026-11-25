extends Node
## Compatibility (OpenGL) fallback (perf study F14): the shaders that failed there are guarded per renderer, the fog
## shaders are never loaded there, and vehicles take plain uniforms on a material copy instead of instance uniforms.
## The suite runs on the headless dummy renderer, so each shader is resolved here for every renderer the way Godot's
## preprocessor would (`#if CURRENT_RENDERER == RENDERER_COMPATIBILITY` / `#else` / `#endif`) and then checked; the
## real Compatibility run is in docs/USAGE.md ("Compatibility renderer").

const RENDERERS := ["RENDERER_COMPATIBILITY", "RENDERER_MOBILE", "RENDERER_FORWARD_PLUS"]


## The source as `renderer` sees it: only `#if CURRENT_RENDERER == X` / `!= X`, `#else`, `#endif` are resolved
## (all these shaders use); other directives are kept.
static func resolve(src: String, renderer: String) -> String:
	var out := PackedStringArray()
	var stack: Array[bool] = []  # is each open #if branch live?
	for line in src.split("\n"):
		var cut := line.find("//")
		var t := (line if cut < 0 else line.substr(0, cut)).strip_edges()  # comments do not count
		if t.begins_with("#if CURRENT_RENDERER"):
			var parts := t.split(" ", false)
			var hit := parts[3] == renderer
			stack.append(hit if parts[2] == "==" else not hit)
		elif t.begins_with("#else") and not stack.is_empty():
			stack[-1] = not stack[-1]
		elif t.begins_with("#endif") and not stack.is_empty():
			stack.pop_back()
		elif not stack.has(false):
			out.append(t)
	return "\n".join(out)


static func _code(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func test_resolver_follows_the_branches() -> String:
	var src := "a\n#if CURRENT_RENDERER == RENDERER_COMPATIBILITY\nb\n#else\nc\n#endif\nd"
	if resolve(src, "RENDERER_COMPATIBILITY") != "a\nb\nd" or resolve(src, "RENDERER_MOBILE") != "a\nc\nd":
		return "the test's preprocessor must pick one branch per renderer"
	return ""


func test_clouds_use_portable_derivatives_on_compatibility() -> String:
	var src := _code("res://world/volumetric_clouds.gdshader")
	for r in RENDERERS:
		var code := resolve(src, r)
		var fine := code.contains("dFdxFine") or code.contains("dFdyFine")
		if r == "RENDERER_COMPATIBILITY" and fine:
			return "dFdxFine / dFdyFine are not supported on Compatibility: no clouds draw there"
		if r != "RENDERER_COMPATIBILITY" and not fine:
			return "%s keeps the fine derivatives (unchanged look)" % r
		if not code.contains("vec4 quad_mean("):
			return "%s lost the quad mean" % r
	if (load("res://world/volumetric_clouds.gdshader") as Shader).get_shader_uniform_list().is_empty():
		return "volumetric_clouds.gdshader did not compile"
	return ""


func test_vehicle_shaders_use_no_instance_uniforms_on_compatibility() -> String:
	for path in ["res://world/vehicle.gdshader", "res://world/vehicle_ground.gdshader"]:
		var src := _code(path)
		for r in RENDERERS:
			var code := resolve(src, r)
			if r == "RENDERER_COMPATIBILITY":
				if code.contains("instance uniform"):
					return "%s: instance uniforms on Compatibility overflow its 4096 slots" % path
				if not code.contains("uniform float lamps"):
					return "%s: plain lamps uniform on Compatibility" % path
			elif not code.contains("instance uniform float lamps"):
				return "%s: %s keeps instance uniforms (one shared material)" % [path, r]
	if (load("res://world/vehicle.gdshader") as Shader).get_shader_uniform_list().is_empty():
		return "vehicle.gdshader did not compile"
	return ""


## The material a vehicle owns: the override on a one-surface mesh (the ground decal), else on surface 0 (body + glass).
static func _own(mi: MeshInstance3D) -> ShaderMaterial:
	if mi.material_override != null:
		return mi.material_override as ShaderMaterial
	return mi.get_surface_override_material(0) as ShaderMaterial


func test_vehicle_values_on_each_renderer() -> String:
	var mesh := GroundVehicles.mesh("gpu")
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	VehicleParams.own(mi, "mobile")
	VehicleParams.set_value(mi, &"lamps", 1.0)
	var shared_ok := _own(mi) == null and float(mi.get_instance_shader_parameter("lamps")) == 1.0
	mi.free()
	if not shared_ok:
		return "Mobile / Forward+: the shared material and an instance uniform"
	var a := MeshInstance3D.new()
	a.mesh = mesh
	var b := MeshInstance3D.new()
	b.mesh = mesh
	VehicleParams.own(a, "gl_compatibility")
	VehicleParams.own(b, "gl_compatibility")
	VehicleParams.set_value(a, &"lamps", 1.0)
	VehicleParams.set_value(a, &"seed", 0.25)
	var ma := _own(a)
	var mb := _own(b)
	var err := ""
	if ma == null or mb == null or ma == mb or ma == mesh.surface_get_material(0):
		err = "Compatibility: each vehicle owns a copy of the body material"
	elif float(ma.get_shader_parameter("lamps")) != 1.0 or float(ma.get_shader_parameter("seed")) != 0.25:
		err = "Compatibility: the values go to the vehicle's own material"
	elif mb.get_shader_parameter("lamps") != null and float(mb.get_shader_parameter("lamps")) != 0.0:
		err = "another vehicle's material is untouched"
	a.free()
	b.free()
	return err


func test_fog_shaders_only_where_supported() -> String:
	if VolumetricFog.supported("gl_compatibility") or not VolumetricFog.supported("forward_plus") or not VolumetricFog.supported("mobile"):
		return "fog shaders are unsupported on Compatibility only"
	var src := _code("res://world/volumetric_fog.gd")
	if src.contains("preload(\"res://world/vfog_air") or src.contains("preload(\"res://world/vfog_rain"):
		return "a preload of a `shader_type fog` shader errors on Compatibility as soon as the script loads"
	for p in [VolumetricFog.AIR_PATH, VolumetricFog.RAIN_PATH]:
		if not _code(p).begins_with("shader_type fog"):
			return "%s should be the fog shader" % p
	return ""


func test_clouds_read_opengl_depth_and_stay_inside_the_clip_volume() -> String:
	# On OpenGL the depth texture is 0..1 for NDC -1..1 and clip z = w is the far plane's edge: with the Vulkan form
	# the full-screen quad drew nothing there (no clouds on the Compatibility fallback).
	var src := _code("res://world/volumetric_clouds.gdshader")
	var compat := resolve(src, "RENDERER_COMPATIBILITY")
	if not compat.contains("depth * 2.0 - 1.0"):
		return "Compatibility maps depth 0..1 to NDC -1..1"
	if compat.contains("VERTEX.xy * 2.0, 1.0, 1.0"):
		return "Compatibility: the quad must not sit on the far plane edge (z = w)"
	for r in ["RENDERER_MOBILE", "RENDERER_FORWARD_PLUS"]:
		var code := resolve(src, r)
		if code.contains("depth * 2.0 - 1.0") or not code.contains("VERTEX.xy * 2.0, 1.0, 1.0"):
			return "%s keeps its depth and quad exactly as before" % r
	return ""


func test_ground_decal_takes_a_material_override_on_compatibility() -> String:
	# A surface override on the one-surface decal mesh made Compatibility log "Parameter material is null" errors.
	var gd := MeshInstance3D.new()
	gd.mesh = GroundVehicles.ground_mesh("gpu")
	VehicleParams.own(gd, "gl_compatibility")
	VehicleParams.set_value(gd, &"lamps", 1.0)
	var m := gd.material_override as ShaderMaterial
	var ok := m != null and float(m.get_shader_parameter("lamps")) == 1.0 and gd.get_surface_override_material(0) == null
	gd.free()
	return "" if ok else "the decal owns a material_override with its own lamps value"
