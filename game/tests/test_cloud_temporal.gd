extends Node
## Temporal cloud upscaling (G7: world/cloud_temporal.gd). Scale from the preset step counts, when a camera
## cut drops history, and how much of the new march is blended. No viewport and no shader compile.


func test_scale_follows_the_preset_steps() -> String:
	var want := {"low": 1, "medium": 1, "high": 2, "ultra": 2, "max": 4}
	for p in want:
		var steps := int(Graphics.PRESETS[p].clouds)
		var got := CloudTemporal.scale_for_steps(steps)
		if got != int(want[p]):
			return "%s at %d steps should march at 1/%d, got 1/%d" % [p, steps, int(want[p]), got]
	if CloudTemporal.HALF_STEPS != int(Graphics.PRESETS.high.clouds):
		return "the half-resolution band should start at the high preset"
	if CloudTemporal.QUARTER_STEPS != int(Graphics.PRESETS.max.clouds):
		return "the quarter-resolution band should start at the max preset"
	if CloudTemporal.scale_for_steps(0) != 1 or CloudTemporal.scale_for_steps(23) != 1:
		return "low and medium stay full resolution"
	if CloudTemporal.scale_for_steps(24) != 2 or CloudTemporal.scale_for_steps(63) != 2:
		return "high and ultra stay half resolution"
	if CloudTemporal.scale_for_steps(64) != 4 or CloudTemporal.scale_for_steps(128) != 4:
		return "max and above stay quarter resolution"
	return ""


func test_history_resets_on_a_jump_or_a_turn() -> String:
	if CloudTemporal.history_reset(50.0, 0.0) or CloudTemporal.history_reset(0.0, deg_to_rad(20.0)):
		return "50 m and 20 degrees are the limits, not past them"
	if not CloudTemporal.history_reset(50.01, 0.0):
		return "a jump past 50 m clears history"
	if not CloudTemporal.history_reset(0.0, deg_to_rad(20.0) + 0.01):
		return "a turn past 20 degrees clears history"
	if CloudTemporal.history_reset(4.0, deg_to_rad(2.0)):
		return "ordinary flight motion keeps history"
	var still := Transform3D(Basis.IDENTITY, Vector3(100.0, 20.0, -40.0))
	if CloudTemporal.is_camera_cut(still, still):
		return "a camera that did not move is not a cut"
	var hop := Transform3D(Basis.IDENTITY, still.origin + Vector3(12.0, 0.0, 0.0))
	if CloudTemporal.is_camera_cut(still, hop):
		return "12 m is not a cut"
	var cut := Transform3D(Basis.IDENTITY, still.origin + Vector3(80.0, 0.0, 0.0))
	if not CloudTemporal.is_camera_cut(still, cut):
		return "80 m is a cut"
	var mild := Transform3D(Basis(Vector3.UP, deg_to_rad(10.0)), still.origin)
	if CloudTemporal.is_camera_cut(still, mild):
		return "10 degrees is not a cut"
	var swung := Transform3D(Basis(Vector3.UP, deg_to_rad(25.0)), still.origin)
	if not CloudTemporal.is_camera_cut(still, swung):
		return "25 degrees is a cut"
	return ""


func test_blend_weight_keeps_full_resolution_unfiltered() -> String:
	for scale in [1, 2, 4]:
		if not is_equal_approx(CloudTemporal.blend_weight(true, scale), 1.0):
			return "a cut shows only the new march (scale %d)" % scale
	if not is_equal_approx(CloudTemporal.blend_weight(false, 1), 1.0):
		return "full resolution does not blend history"
	var half := CloudTemporal.blend_weight(false, 2)
	var quarter := CloudTemporal.blend_weight(false, 4)
	if half <= 0.0 or half >= 1.0 or quarter <= 0.0 or quarter >= 1.0:
		return "half and quarter keep a share of history: %f %f" % [half, quarter]
	if quarter > half:
		return "quarter resolution should trust history at least as much as half: %f > %f" % [quarter, half]
	return ""


func test_jitter_is_off_at_full_resolution() -> String:
	var view := Vector2(1920, 1080)
	if CloudTemporal.jitter_uv(3, 1, view) != Vector2.ZERO:
		return "full resolution is not jittered"
	for scale in [2, 4]:
		for frame in 16:
			var j := CloudTemporal.jitter_uv(frame, scale, view)
			var lim := Vector2(0.5 * float(scale) / view.x, 0.5 * float(scale) / view.y)
			if absf(j.x) > lim.x + 1e-6 or absf(j.y) > lim.y + 1e-6:
				return "jitter must stay inside the low-res texel: %s" % j
	if CloudTemporal.jitter_uv(1, 2, view) == CloudTemporal.jitter_uv(2, 2, view):
		return "successive frames should sample different sub-texel rays"
	return ""


func test_upscale_shader_compiles() -> String:
	var names := []
	for u in (load("res://world/cloud_upscale.gdshader") as Shader).get_shader_uniform_list():
		names.append(u.name)
	if names.is_empty():
		return "cloud_upscale.gdshader did not compile"
	for n in ["reproj", "blend_w", "history_on", "block"]:
		if not n in names:
			return "cloud_upscale.gdshader is missing %s" % n
	return ""


func test_reproject_centres_and_follows_a_move() -> String:
	var proj := Projection.create_perspective(70.0, 16.0 / 9.0, 0.05, 160000.0, false)
	var centre := CloudTemporal.reproject_uv(Vector3(0, 0, -200.0), proj)
	if centre.distance_to(Vector2(0.5, 0.5)) > 0.02:
		return "a point on the optical axis lands on the centre: %s" % centre
	var right := CloudTemporal.reproject_uv(Vector3(40, 0, -200.0), proj)
	if right.x <= centre.x:
		return "a point to the right of the camera projects right: %s" % right
	var still := CloudTemporal.reproj_matrix(Transform3D.IDENTITY, proj, Transform3D.IDENTITY)
	var again := CloudTemporal.reproject_uv(Vector3(0, 0, -200.0), still)
	if again.distance_to(centre) > 0.001:
		return "a still camera reprojects onto itself: %s vs %s" % [centre, again]
	var moved := CloudTemporal.reproj_matrix(Transform3D.IDENTITY, proj, Transform3D(Basis.IDENTITY, Vector3(30, 0, 0)))
	var shifted := CloudTemporal.reproject_uv(Vector3(0, 0, -200.0), moved)
	if shifted.x <= centre.x + 0.01:
		return "a camera that moved right should find the old centre off to the right: %s" % shifted
	return ""


func test_upscaled_march_is_not_jittered() -> String:
	# A jittered half / quarter-res march made the horizon and the windshield frame blink (tests/debug_flicker.tscn).
	var view := Vector2(1920, 1080)
	for scale in [2, 4]:
		for frame in 16:
			if CloudTemporal.march_jitter(frame, scale, view) != Vector2.ZERO:
				return "the scale %d march jitters on frame %d" % [scale, frame]
	return ""


func test_surfaces_nearer_than_the_layer_get_no_cloud() -> String:
	# Below, above and inside a 1,400 m base, 900 m thick layer: anything nearer than this is in front of every cloud.
	if not is_equal_approx(CloudTemporal.clear_dist(12.0, 1400.0, 900.0), 1388.0):
		return "below the base: the gap to the base"
	if not is_equal_approx(CloudTemporal.clear_dist(3000.0, 1400.0, 900.0), 700.0):
		return "above the top: the gap to the top"
	if CloudTemporal.clear_dist(1800.0, 1400.0, 900.0) != 0.0:
		return "inside the layer every surface can have cloud in front"
	return ""


func test_upscale_reads_the_reversed_depth_buffer() -> String:
	# The depth buffer is reversed (1 near, 0 sky) and screen y runs down; Camera3D.get_camera_projection() is OpenGL
	# style. Feeding the stored depth in as clip z put the sky at the near plane: the edge test and the history
	# reprojection compared the wrong distances, and the horizon and the windshield frame blinked.
	var src := FileAccess.get_file_as_string("res://world/cloud_upscale.gdshader")
	if not "1.0 - 2.0 * raw_depth(uv)" in src or not "1.0 - uv.y * 2.0" in src:
		return "the upscale must convert the stored depth and screen y to OpenGL clip space"
	if "vec4(uv * 2.0 - 1.0, raw_depth(uv), 1.0)" in src:
		return "raw depth used as clip z again"
	return ""
