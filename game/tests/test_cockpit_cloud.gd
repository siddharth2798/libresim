extends Node
## Cloud never draws on the cockpit (A320 flown into cloud, High / Max): the low-resolution cloud march, the history
## blend and the one-frame-old depth copy put block-sized cloud on windshield-frame pixels, which at the cockpit's
## 0.5 to 2 m is cloud light (many times brighter than the cockpit) on a few percent of alpha. The pixel's own depth now caps
## the cloud (CloudTemporal.max_alpha, mirrored in cloud_upscale.gdshader and volumetric_clouds.gdshader).
## The picture itself is checked by tools/check_cockpit_clouds.py (a window is needed); this is the structural half.

const COCKPIT_SHADERS := ["cockpit_lit", "cockpit_alpha", "cockpit_unshaded", "cockpit_unshaded_alpha"]


func test_no_cloud_in_the_near_field() -> String:
	for d in [0.2, 0.6, 1.0, 2.0, 3.0]:
		if CloudTemporal.max_alpha(d) != 0.0 and d <= 0.5 * CloudTemporal.NEAR_CLEAR_M:
			return "cloud allowed %.1f m from the eye: %.4f" % [d, CloudTemporal.max_alpha(d)]
	if CloudTemporal.max_alpha(1.0) > 0.0:
		return "the windshield frame (1 m) must get no cloud at all"
	if CloudTemporal.NEAR_CLEAR_M < 4.0:
		return "the near field must cover the cockpit (overhead panel about 2 m)"
	if CloudTemporal.NEAR_CLEAR_M > 10.0:
		return "a near field this deep would hole a wing view of the aircraft in cloud"
	return ""


func test_cloud_alpha_never_exceeds_what_the_ray_can_hold() -> String:
	var prev := -1.0
	for d in [0.0, 1.0, 6.0, 10.0, 30.0, 100.0, 400.0, 3000.0, 60000.0]:
		var a := CloudTemporal.max_alpha(d)
		var phys := 1.0 - exp(-d * CloudTemporal.CLOUD_EXT)
		if a > phys + 1e-6:
			return "%.0f m: cap %.4f is above the physical bound %.4f" % [d, a, phys]
		if a < prev - 1e-6:
			return "the cap must not fall with distance (%.0f m)" % d
		prev = a
	if CloudTemporal.max_alpha(60000.0) < 0.99:
		return "distant cloud and the sky behind it must be left alone"
	if absf(CloudTemporal.max_alpha(300.0) - (1.0 - exp(-300.0 * CloudTemporal.CLOUD_EXT))) > 1e-6:
		return "beyond the near field the cap is the physical bound"
	return ""


func test_shaders_apply_the_same_cap() -> String:
	var up := FileAccess.get_file_as_string("res://world/cloud_upscale.gdshader")
	var ext := "const float CLOUD_EXT = %s;" % str(CloudTemporal.CLOUD_EXT)
	if not ext in up:
		return "cloud_upscale.gdshader must use CloudTemporal.CLOUD_EXT (%s)" % ext
	var cap := up.find("float a_max")
	var drop := up.find("if (outc.a < 1e-4)")
	if cap < 0 or drop < 0 or cap > drop:
		return "the cap must come before the final discard, on both passes (accum and blit)"
	if not "smoothstep(0.5 * near_m, near_m, d_near)" in up or not "outc *= a_max / outc.a" in up:
		return "the upscale must scale cloud down to the cap"
	var vol := FileAccess.get_file_as_string("res://world/volumetric_clouds.gdshader")
	if not "alpha *= smoothstep(0.5 * near_m, near_m, scene_dist)" in vol:
		return "the full-resolution cloud march must keep the near field clear too (Compatibility draws only this)"
	if not "uniform float near_m" in vol or not "uniform float near_m" in up:
		return "both shaders take near_m"
	return ""


func test_the_near_field_reaches_the_materials() -> String:
	var layer := CloudLayer.new()
	add_child(layer)
	layer.update_layer(Vector3(0, 0, 1000.0), 800.0, 0.6, Vector2.ZERO, Vector3(0.3, 0.8, 0.2), Color.WHITE, Color.GRAY)
	var got = layer._mat.get_shader_parameter("near_m")
	layer.queue_free()
	if got == null or absf(float(got) - CloudTemporal.NEAR_CLEAR_M) > 1e-4:
		return "CloudLayer must send near_m to the cloud material, got %s" % str(got)
	var src := FileAccess.get_file_as_string("res://world/cloud_upscale.gd")
	if src.count("\"near_m\"") < 2:
		return "CloudUpscale must send near_m to both the accumulate and the blit material"
	return ""


func test_cockpit_materials_write_depth_before_the_cloud() -> String:
	# The cloud pass (render priority CloudLayer.PRIORITY, no depth test) reads the scene depth: a cockpit surface that
	# does not write depth, or that draws after it, is invisible to it. Opaque and alpha-with-prepass both write it.
	for n in COCKPIT_SHADERS:
		var src := FileAccess.get_file_as_string("res://aircraft/common/%s.gdshader" % n)
		if src == "":
			return "%s.gdshader missing" % n
		var mode := src.get_slice("render_mode", 1).get_slice(";", 0)
		for bad in ["depth_draw_never", "depth_test_disabled", "skip_vertex_transform"]:
			if bad in mode:
				return "%s: %s hides the cockpit from the cloud pass" % [n, bad]
		if not ("depth_draw_opaque" in mode or "depth_prepass_alpha" in mode or "depth_draw_always" in mode):
			return "%s must write depth (depth_draw_opaque or depth_prepass_alpha)" % n
	var surf := FileAccess.get_file_as_string("res://aircraft/common/cockpit_surface.gd")
	if "render_priority = 1" in surf or "render_priority = CloudLayer" in surf:
		return "cockpit materials must not take a priority at or after the cloud pass"
	return ""
