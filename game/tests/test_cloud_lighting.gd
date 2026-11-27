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


func test_cloud_layer_writes_only_what_changed() -> String:
	# update_layer / set_inside run every frame: a still frame writes no uniform and no global (PERFORMANCE-RULES 10),
	# the cloud_noise texture global is set once at most (re-setting it re-queues every terrain material).
	var cl := CloudLayer.new()
	add_child(cl)
	var args := [Vector3(10, 20, 300), 1400.0, 0.5, Vector2(5, 6), Vector3(0.3, 0.8, 0.2), Color.WHITE, Color.GRAY, 0.1]
	cl.callv("update_layer", args)
	cl.set_inside(0.0, 0.0, Color.BLACK)
	var mat_w := cl._p.writes
	var glob_w := cl.global_writes
	var noise_due := 0 if cl._noise_published else 1
	cl._img_lo = Image.create(4, 4, false, Image.FORMAT_RF)  # the noise is ready
	for i in 30:
		cl.callv("update_layer", args)
		cl.set_inside(0.0, 0.0, Color.BLACK)
	var still_mat := cl._p.writes - mat_w
	var still_glob := cl.global_writes - glob_w  # only the one cloud_noise publish
	args[2] = 0.6  # the coverage moves: that uniform and the shadow global follow
	cl.callv("update_layer", args)
	var cov = cl._mat.get_shader_parameter("coverage")
	var moved_glob := cl.global_writes - glob_w - still_glob
	cl.free()
	if still_mat != 0:
		return "30 identical frames wrote %d cloud uniforms" % still_mat
	if still_glob != noise_due:
		return "identical frames should write only the one cloud_noise publish, got %d global writes" % still_glob
	if not is_equal_approx(float(cov), 0.6) or moved_glob != 1:
		return "a coverage change should reach the material (%s) and the cloud_shadow global (%d writes)" % [cov, moved_glob]
	return ""
