extends Node
## Cloud lighting (GRAPHICS-PLAN G3): volumetric_clouds.gdshader compiles (the dummy renderer parses it
## headless) and exposes its tuning uniforms; CloudLayer passes light_steps on, clamped to 1..4.

const SHADER := "res://world/volumetric_clouds.gdshader"
const TUNING := ["light_steps", "light_dist", "light_first", "light_grow", "light_absorb", "phase_g_fwd",
	"phase_g_back", "phase_mix", "phase_w", "phase_max", "powder_w", "powder_k", "ms_octaves", "ms_a", "ms_b",
	"ms_c", "sun_gain"]


func test_cloud_shader_exposes_the_lighting_uniforms() -> String:
	var names := []
	for u in (load(SHADER) as Shader).get_shader_uniform_list():
		names.append(u.name)
	if names.is_empty():
		return "volumetric_clouds.gdshader did not compile"
	for n in TUNING:
		if not names.has(n):
			return "missing uniform %s" % n
	return ""


func test_light_steps_default_keeps_the_old_single_sample() -> String:
	var code := (load(SHADER) as Shader).code  # the dummy renderer keeps no defaults: read them from the source
	if not code.contains("uniform int light_steps = 1;") or not code.contains("uniform float light_dist = 300.0;"):
		return "light_steps should default to 1 at 300 m (the Low / Medium look)"
	return ""


func test_cloud_layer_passes_light_steps() -> String:
	var cl := CloudLayer.new()
	add_child(cl)
	var got := []
	for n in [3, 9, 0]:
		cl.light_steps = n
		cl.update_layer(Vector3.ZERO, 1400.0, 0.5, Vector2.ZERO, Vector3(0.3, 0.8, 0.2), Color.WHITE, Color.GRAY)
		got.append(cl._mat.get_shader_parameter("light_steps"))
	cl.queue_free()
	return "" if got == [3, 4, 1] else "light_steps should reach the material clamped to 1..4: %s" % [got]
