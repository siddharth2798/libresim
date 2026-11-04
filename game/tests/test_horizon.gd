extends RefCounted
## Horizon fix (docs/GRAPHICS-PLAN.md G4): the visual Earth curvature (world/curvature.gd, twin of
## curvature.gdshaderinc) and the view-dependent haze table (world/haze_lut.gd, read by haze_sky.gdshaderinc).


static func _sun(el_deg: float, az_deg := 270.0) -> Vector3:
	var el := deg_to_rad(el_deg)
	var az := deg_to_rad(az_deg)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))


func test_curvature_drop_is_d2_over_2r_and_tiny_near_the_camera() -> String:
	var eye := Vector3(100.0, 2000.0, -50.0)
	for d in [2000.0, 10000.0, 100000.0]:
		var want: float = d * d / (2.0 * 6371000.0)
		var got := Curvature.drop(eye + Vector3(d * 0.6, -1500.0, d * 0.8), eye)
		if absf(got - want) > want * 1e-4:
			return "drop at %d m: %.3f, want %.3f" % [d, got, want]
	if Curvature.drop(eye + Vector3(1500.0, 0.0, 0.0), eye) > 0.2:
		return "drop within ~2 km of the camera should be negligible"
	if Curvature.drop(eye + Vector3(0.0, -5000.0, 0.0), eye) != 0.0:
		return "the drop depends on the horizontal distance only"
	return ""


func test_curvature_keeps_the_ground_flat_under_a_nearby_aircraft() -> String:
	var eye := Vector3.ZERO
	var focus := Vector3(3000.0, 0.0, 0.0)  # tower view of the aircraft 3 km away
	if Curvature.drop(focus, eye, focus) > 1e-4:
		return "ground under the aircraft must not drop (it would float the unbent aircraft)"
	var far_focus := Vector3(20000.0, 0.0, 0.0)  # camera far from the aircraft: plain curvature
	if absf(Curvature.drop(far_focus, eye, far_focus) - 20000.0 * 20000.0 / (2.0 * Curvature.R)) > 0.01:
		return "the exemption must vanish when the aircraft is far from the camera"
	if absf(Curvature.drop(Vector3(0.0, 0.0, 3000.0), eye, focus) - 9e6 / (2.0 * Curvature.R)) > 1e-3:
		return "ground away from the aircraft bends as usual"
	return ""


func test_curvature_local_offset_moves_straight_down_in_world() -> String:
	var b := Basis(Vector3(0.3, 1.0, -0.2).normalized(), 0.7) * Basis.from_scale(Vector3(2.0, 0.5, 3.0))  # rotation x scale, as a Node3D
	var w := b * Curvature.local_offset(b, 12.5)
	if w.distance_to(Vector3(0.0, -12.5, 0.0)) > 1e-3:
		return "world offset %s, want (0, -12.5, 0)" % w
	return ""


func test_curvature_horizon_dip_matches_the_bent_ground() -> String:
	# a ray from h at the dip angle grazes the bent sea: h - d tan(dip) + d^2 / 2R has its minimum 0
	for h in [300.0, 4572.0, 7620.0]:
		var s := HazeLut.horizon_dip_sin(h)
		var t := tan(asin(s))
		var d := t * Curvature.R  # where the ray is lowest over the bent ground
		var gap: float = h - d * t + d * d / (2.0 * Curvature.R)
		if absf(gap) > 0.5:
			return "dip at %d m misses the bent horizon by %.2f m" % [h, gap]
	if absf(rad_to_deg(asin(HazeLut.horizon_dip_sin(7620.0))) - 2.8) > 0.05:
		return "dip at FL250 should be ~2.8 deg"
	return ""


func test_curvature_is_in_every_far_shader() -> String:
	var inc := FileAccess.get_file_as_string("res://world/curvature.gdshaderinc")
	if not inc.contains("0.5 / 6371000.0"):
		return "curvature.gdshaderinc must use R = 6371 km like Curvature.R"
	for p in Curvature.SHADERS:
		var src := FileAccess.get_file_as_string(p)
		if not src.contains("curvature.gdshaderinc") or not src.contains("curve_drop("):
			return "%s draws far geometry but does not bend it (curvature.gdshaderinc)" % p
	return ""


func test_haze_lut_texel_directions_round_trip() -> String:
	for el in [-2.0, 5.0, 40.0]:
		var sun := _sun(el, 250.0)
		for j in HazeLut.H:
			for i in HazeLut.W:
				var uv := HazeLut.lut_uv(HazeLut.texel_dir(i, j, sun), sun, 0.0)
				var want := Vector2((i + 0.5) / HazeLut.W, (j + 0.5) / HazeLut.H)
				if uv.distance_to(want) > 1e-3:
					return "texel (%d, %d) at sun %d deg maps to %s, want %s" % [i, j, el, uv, want]
	# below the horizon (terrain): the bottom row; the dip lifts the lookup
	var sun := _sun(10.0)
	if absf(HazeLut.lut_uv(Vector3(0.0, -0.3, 1.0).normalized(), sun, 0.0).y - 0.5 / HazeLut.H) > 1e-4:
		return "views below the horizon should read the horizon row"
	if HazeLut.lut_uv(Vector3(0.0, 0.0, 1.0), sun, 0.05).y <= 0.5 / HazeLut.H + 0.01:
		return "with a horizon dip, eye level is above the horizon row"
	var inc := FileAccess.get_file_as_string("res://world/haze_sky.gdshaderinc")
	if not inc.contains("HAZE_LUT_N = vec2(%.1f, %.1f)" % [HazeLut.W, HazeLut.H]) or not inc.contains("HAZE_S_MAX = %.1f" % HazeLut.S_MAX):
		return "haze_sky.gdshaderinc table layout differs from HazeLut"
	return ""


func test_haze_lut_is_the_sky_model_warmer_towards_the_sun() -> String:
	var sun := _sun(4.0)
	var glow := Color(1.0, 0.7, 0.4) * 1.2
	var c := HazeLut.texel_color(3, 0, sun, 1.2, 1.0, glow)
	var d := HazeLut.texel_dir(3, 0, sun)
	var want := Atmosphere.sky(d, sun, 1.2, 1.0) + HazeLut.glow_at(d, sun, glow)
	if Vector3(c.r - want.r, c.g - want.g, c.b - want.b).length() > 1e-3:
		return "texel colour %s should be the sky model %s" % [c, want]
	var to_sun := HazeLut.texel_color(0, 0, sun, 1.2, 1.0, glow)
	var away := HazeLut.texel_color(HazeLut.W - 1, 0, sun, 1.2, 1.0, glow)
	if to_sun.r / to_sun.b <= 1.3 * away.r / away.b:
		return "haze towards a low sun should be warmer (r/b %.2f) than away (%.2f)" % [to_sun.r / to_sun.b, away.r / away.b]
	if to_sun.get_luminance() <= away.get_luminance():
		return "haze towards the sun should be brighter"
	var up := HazeLut.texel_color(HazeLut.W - 1, HazeLut.H - 1, sun, 1.2, 1.0, glow)
	if up.b / up.r <= away.b / away.r:
		return "higher rows should be bluer than the horizon row"
	return ""


func test_haze_lut_fills_once_then_refreshes_one_row_per_frame() -> String:
	var lut := HazeLut.new()
	var sun := _sun(20.0)
	var ref := Color(0.6, 0.7, 0.8)
	lut.update(sun, 20.0, 1.0, Color.WHITE, ref, 1.0, 0.0)
	if lut.tex == null:
		return "the first update must fill the table at once"
	var first := lut.img.get_pixel(5, 0)
	lut.update(sun, 20.1, 1.0, Color.WHITE, ref, 1.0, 0.0)  # same 0.25 deg bucket: no refill
	if lut._row != HazeLut.H:
		return "a sun move inside one bucket must not refill"
	lut.update(_sun(40.0), 40.0, 1.0, Color.WHITE, ref, 1.0, 0.0)
	var frames := 1
	while lut._row < HazeLut.H and frames < 20:
		if not lut.img.get_pixel(5, 0).is_equal_approx(first):
			return "the visible table must not change before the refill completes"
		lut.update(_sun(40.0), 40.0, 1.0, Color.WHITE, ref, 1.0, 0.0)
		frames += 1
	if frames != HazeLut.H:
		return "refill took %d frames, want %d (one row each)" % [frames, HazeLut.H]
	if lut.img.get_pixel(5, 0).is_equal_approx(first):
		return "the refilled table should show the new sun"
	return ""
