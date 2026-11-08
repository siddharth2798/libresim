extends Node
## Post effects (core/post_fx.gd, post_fx_rules.gd, post_fx_look.gd, world/postfx/*): option defaults, the gating
## rules (preset x renderer x option), the motion-blur reset rules, the look functions, the per-aircraft data for
## every installed aircraft, and that applying the effects headless (dummy renderer: no compute) raises no error.

const FX_DEFAULTS := {"bloom": true, "motion_blur": true, "sun_shafts": true, "sharpen": true, "color_grading": true,
	"heat_shimmer": true, "lens_rain": true, "lens_effects": false, "depth_of_field": false, "volumetric_fog": true}

var _scene: Node3D


## Stands in for AircraftModel: the shimmer only needs `def` and fg_to_local (model frame -> local).
class FakeModel extends Node3D:
	var def: AircraftDef
	func fg_to_local(p: Vector3) -> Vector3:
		return p


func teardown() -> void:
	if _scene:
		_scene.free()
		_scene = null


func test_post_fx_option_defaults() -> String:
	for k in FX_DEFAULTS:
		if not UserOptions.DEFAULTS.has(k) or UserOptions.DEFAULTS[k] != FX_DEFAULTS[k]:
			return "UserOptions.DEFAULTS.%s should be %s" % [k, FX_DEFAULTS[k]]
	for fx in PostFxRules.FX:
		if not UserOptions.DEFAULTS.has(fx):
			return "effect %s has no option" % fx
	return ""


func test_post_fx_gating_by_preset_and_renderer() -> String:
	var R := PostFxRules
	var cases := [  # fx, preset, renderer, option, expected
		["motion_blur", "high", "forward_plus", true, true], ["motion_blur", "ultra", "forward_plus", true, true],
		["motion_blur", "max", "forward_plus", true, true], ["motion_blur", "medium", "forward_plus", true, false],
		["motion_blur", "high", "mobile", true, false], ["motion_blur", "high", "forward_plus", false, false],
		["motion_blur", "nonsense", "forward_plus", true, false], ["sun_shafts", "medium", "mobile", true, false],
		["sun_shafts", "low", "forward_plus", true, false], ["heat_shimmer", "high", "mobile", true, false],
		["heat_shimmer", "high", "forward_plus", true, true], ["lens_rain", "medium", "mobile", true, true],
		["lens_rain", "low", "mobile", true, false], ["color_grading", "low", "mobile", true, true],
		["lens_effects", "low", "gl_compatibility", true, true], ["depth_of_field", "low", "gl_compatibility", true, false],
		["volumetric_fog", "high", "forward_plus", true, true], ["volumetric_fog", "medium", "forward_plus", true, false],
		["volumetric_fog", "max", "mobile", true, false], ["volumetric_fog", "ultra", "forward_plus", false, false],
		["no_such_fx", "max", "forward_plus", true, false],
	]
	for c in cases:
		if R.active(c[0], c[1], c[2], c[3]) != c[4]:
			return "%s on %s / %s (option %s) should be %s" % c
	if R.bloom_on("low", true) or not R.bloom_on("medium", true) or R.bloom_on("ultra", false):
		return "bloom: off on Low, else the option"
	if R.sharpen_needed(false, 1.0) or not R.sharpen_needed(true, 1.0) or not R.sharpen_needed(false, 0.7):
		return "sharpen only with TAA or a render scale != 1"
	var f := R.flags_for("ultra", "forward_plus", FX_DEFAULTS, false, 1.0)
	if not f.motion_blur or f.sharpen or f.lens_effects or f.depth_of_field or not f.bloom or not f.sun_shafts:
		return "ultra defaults without TAA: %s" % f
	var m := R.flags_for("medium", "mobile", FX_DEFAULTS, false, 0.85)
	if m.motion_blur or m.heat_shimmer or m.sun_shafts or not m.lens_rain or m.sharpen:
		return "medium on Mobile: %s" % m
	var low := R.flags_for("low", "mobile", FX_DEFAULTS, false, 0.7)
	return "" if not low.bloom and not low.sun_shafts and low.color_grading else "low: %s" % low


func test_post_fx_view_rules() -> String:
	var R := PostFxRules
	if R.dof_wanted(R.VIEW_COCKPIT, true) or R.dof_wanted(R.VIEW_COCKPIT, false):
		return "no depth of field in the cockpit, replay or not"
	if not R.dof_wanted(R.VIEW_FREE, false) or R.dof_wanted(1, false) or not R.dof_wanted(1, true):
		return "DoF: free camera always, chase only in replay"
	if R.lens_rain_wanted(R.VIEW_COCKPIT) or not R.lens_rain_wanted(1) or not R.lens_rain_wanted(R.VIEW_OTHER):
		return "lens rain: outside views only"
	return "" if PostFxLook.lens_rain(R.VIEW_COCKPIT, 1.0, true) == 0.0 and PostFxLook.lens_rain(2, 0.5, false) > 0.0 else "lens rain amounts"


func test_post_fx_motion_blur_resets() -> String:
	var R := PostFxRules
	var a := Transform3D(Basis(), Vector3(0, 300, 0))
	if R.is_cut(a, a.translated(Vector3(0, 0, -4.2)), 1.0 / 60.0):
		return "250 m/s flight is not a cut"
	if not R.is_cut(a, a.translated(Vector3(5000, 0, 0)), 1.0 / 60.0):
		return "a 5 km jump (floating origin) is a cut"
	if not R.is_cut(a, a.translated(Vector3(260, 0, 0)), 1.0 / 60.0):
		return "the fly-by camera re-placing itself is a cut"
	if R.is_cut(a, Transform3D(Basis(Vector3.UP, 0.05), a.origin), 1.0 / 60.0):
		return "a 3 degree turn per frame is motion"
	if not R.is_cut(a, Transform3D(Basis(Vector3.UP, PI * 0.5), a.origin), 1.0 / 60.0):
		return "a 90 degree turn in one frame is a view switch"
	var s := R.next_skip(0, true, false)
	var seq := [s]
	for i in 3:
		s = R.next_skip(s, false, false)
		seq.append(s)
	if seq != [R.SKIP_FRAMES, R.SKIP_FRAMES - 1, 0, 0] or R.next_skip(0, false, true) != R.SKIP_FRAMES:
		return "skip frames after a reset / cut: %s" % [seq]
	# same streak length at 60 and 144 fps: motion per frame scales with dt, the scale with 1/dt
	var v60 := 0.01
	var v144 := v60 * 60.0 / 144.0
	if not is_equal_approx(v60 * R.blur_scale(0.5, 1.0 / 60.0), v144 * R.blur_scale(0.5, 1.0 / 144.0)):
		return "blur length depends on the frame rate"
	if R.blur_scale(0.5, 0.0) != 0.0 or R.blur_scale(0.5, 1e-5) > 1.5 + 1e-6:
		return "blur scale must be bounded"
	return ""


func test_post_fx_near_cutoff_from_aircraft_size() -> String:
	var ext := {}
	for id in AircraftDef.list_ids():
		var def := AircraftDef.load_def(id)
		var e := PostFxRules.aircraft_extent_m(def)
		if e < 2.0 or e > 200.0:
			return "%s: implausible size %.1f m" % [id, e]
		ext[id] = e
		if PostFxRules.near_cutoff_m(0.0, e) < e * 0.5:
			return "%s: from the cockpit the whole airframe must count as near" % id
	var fake := AircraftDef.make("fake", {}, "res://aircraft/none", {"metrics": {"wingspan_m": 60.0}})
	return "" if PostFxRules.aircraft_extent_m(fake) >= 60.0 else "the extent follows the wingspan"


## Cockpit view: the panel rides with the camera and is never blurred (the velocity buffer smeared it every ~10
## frames at speed). Outside views keep the aircraft's own motion.
func test_cockpit_is_never_motion_blurred() -> String:
	if PostFxRules.blur_near_param(30.0, PostFxRules.VIEW_COCKPIT) != -30.0:
		return "the cockpit view should pass a negative near cut"
	if PostFxRules.blur_near_param(30.0, PostFxRules.VIEW_OTHER) != 30.0 or PostFxRules.blur_near_param(30.0, PostFxRules.VIEW_FREE) != 30.0:
		return "outside views keep a positive near cut"
	var src := FileAccess.get_file_as_string("res://world/postfx/motion_blur.glsl")
	if not src.contains("rigid_near && dc < near_cut"):
		return "the shader should leave near pixels alone when near_cut is negative"
	var drv := FileAccess.get_file_as_string("res://world/postfx/post_fx_driver.gd")
	if not drv.contains("motion_blur.near_cut = PostFxRules.blur_near_param("):
		return "the driver should pass the signed near cut"
	return ""


func test_post_fx_exhausts_every_aircraft() -> String:
	for id in AircraftDef.list_ids():
		var def := AircraftDef.load_def(id)
		for e in HeatShimmer.exhausts_of(def):
			if int(e.engine) < 1 or int(e.engine) > def.engine_count():
				return "%s: exhaust engine %d out of 1..%d" % [id, e.engine, def.engine_count()]
			if float(e.r) <= 0.0 or float(e.len) <= 0.0 or not (e.dir as Vector3).is_normalized():
				return "%s: bad exhaust %s" % [id, e]
	var none := AircraftDef.make("bare", {}, "res://aircraft/none", {"metrics": {}})
	if not HeatShimmer.exhausts_of(none).is_empty() or not HeatShimmer.exhausts_of(null).is_empty():
		return "no exhausts section = no plumes"
	var one := AircraftDef.make("one", {"exhausts": {"list": [{"pos": [1, 0, 0], "kind": "piston"}]}}, "res://aircraft/none", {"metrics": {}})
	var ex := HeatShimmer.exhausts_of(one)
	if ex.size() != 1 or not is_equal_approx(float(ex[0].k), 0.35) or ex[0].dir != Vector3(1, 0, 0):
		return "piston defaults: %s" % [ex]
	if PostFxLook.exhaust_heat(false, 1000.0, 1.0) != 0.0 or PostFxLook.exhaust_heat(true, 900.0, 1.0) < 0.99:
		return "exhaust heat from running / egt"
	return ""


func test_post_fx_looks_stay_subtle() -> String:
	for el in [-20.0, -5.0, 0.0, 3.0, 8.0, 20.0, 60.0, 89.0]:
		for cover in [0.0, 0.5, 1.0]:
			for rain in [0.0, 0.5, 1.0]:
				var g := PostFxLook.grade(el, cover, rain)
				if g.contrast < 0.96 or g.contrast > 1.06 or g.saturation < 0.85 or g.saturation > 1.1 or absf(g.warmth) > 0.4:
					return "grade out of range at el %s cover %s rain %s: %s" % [el, cover, rain, g]
				if g.has("brightness"):
					return "the grade must not touch brightness (auto exposure owns it)"
	if PostFxLook.grade(5.0, 0.1, 0.0).warmth <= 0.1 or PostFxLook.grade(30.0, 1.0, 0.8).warmth >= 0.0:
		return "golden hour warm, monsoon cool"
	var g0 := PostFxLook.warmth_gains(0.4)
	if absf(0.2126 * g0.x + 0.7152 * g0.y + 0.0722 * g0.z - 1.0) > 1e-4:
		return "white balance must keep luminance"
	if PostFxLook.shafts_strength(-10.0, 0.0, 0.4, 0.0, 15000.0, 1.0) > 0.0 or PostFxLook.shafts_strength(10.0, 0.0, 0.4, 1.0, 15000.0, 1.0) > 0.0:
		return "no shafts at night or in rain"
	if PostFxLook.shafts_strength(10.0, 0.0, 0.5, 0.0, 15000.0, 1.0) < 0.3:
		return "a low sun with broken cloud gives shafts"
	if PostFxLook.ground_shimmer(-5.0, 0.0, 0.0, 0.0, 10.0, 35.0) > 0.0 or PostFxLook.ground_shimmer(40.0, 0.0, 0.5, 0.0, 10.0, 35.0) > 0.0 \
			or PostFxLook.ground_shimmer(40.0, 0.0, 0.0, 0.0, 600.0, 35.0) > 0.0:
		return "no ground shimmer at night, in rain or above 1500 ft"
	var d := PostFxLook.dof(30.0, 11.0)
	return "" if d.far_start > 30.0 + 11.0 and d.near_end < 30.0 - 11.0 else "the aircraft must stay in focus: %s" % d


func test_post_fx_lut_identity() -> String:
	var imgs := ColorGrade.lut_images(0.0)
	if imgs.size() != ColorGrade.LUT_SIZE:
		return "LUT slices"
	var c := imgs[8].get_pixel(4, 12)
	var n := float(ColorGrade.LUT_SIZE - 1)
	return "" if absf(c.r - 4.0 / n) < 0.01 and absf(c.g - 12.0 / n) < 0.01 and absf(c.b - 8.0 / n) < 0.01 else "warmth 0 is the identity: %s" % c


func test_post_fx_shaders_compile() -> String:
	for p in ["res://world/postfx/motion_blur.glsl", "res://world/postfx/pf_copy.glsl", "res://world/postfx/sun_shafts.glsl"]:
		var f := load(p) as RDShaderFile
		if f == null:
			return "%s did not import" % p
		for v in f.get_version_list():
			var err: String = f.get_spirv(v).compile_error_compute
			if err != "":
				return "%s (%s): %s" % [p, v, err]
	return ""


func test_post_fx_apply_headless() -> String:
	_scene = Node3D.new()
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = Environment.new()
	_scene.add_child(we)
	var cam := CameraRig.new()  # not set up (no aircraft): the driver must cope
	_scene.add_child(cam)
	add_child(_scene)
	cam.make_current()
	var flags := PostFx.apply(_scene, "low")
	if we.environment.glow_enabled:
		return "no glow on Low"
	flags = PostFx.apply(_scene, "ultra")  # twice: reconfigures, does not duplicate
	var driver := _scene.get_node_or_null(PostFx.DRIVER) as PostFxDriver
	if driver == null or _scene.get_children().filter(func(n): return n is PostFxDriver).size() != 1:
		return "one PostFxDriver under the scene"
	var list: Array = we.compositor.compositor_effects if we.compositor else []
	var want: Array = []
	if flags.get("motion_blur", false):
		want.append(driver.motion_blur)
	if flags.get("sun_shafts", false):
		want.append(driver.sun_shafts)
	if we.compositor == null or list != want:
		return "enabled compositor effects belong on the WorldEnvironment, got %d" % list.size()
	if we.environment.glow_enabled != flags.bloom:
		return "glow follows the bloom option"
	Props.set_v("environment/precip", 1.0)
	driver._process(1.0 / 60.0)  # a chase-view frame without an aircraft: must not error
	driver.motion_blur.reset = false
	cam.mode = CameraRig.Mode.COCKPIT
	driver._process(1.0 / 60.0)
	Props.set_v("environment/precip", 0.0)
	if not driver.motion_blur.reset:
		return "a view switch resets the motion blur"
	if driver.screen.get_param("rain") != 0.0:
		return "no lens rain in the cockpit view"
	driver.motion_blur.reset = false
	FloatingOrigin.shifted.emit(Vector3.ZERO)
	return "" if driver.motion_blur.reset and driver.motion_blur.frame_dt > 0.0 else "an origin shift resets the motion blur"


func test_post_fx_exhaust_plumes_follow_engines() -> String:
	for id in AircraftDef.list_ids():
		var def := AircraftDef.load_def(id)
		var m := FakeModel.new()
		m.def = def
		add_child(m)
		var sh := HeatShimmer.new()
		add_child(sh)
		sh.setup(m)
		var n := HeatShimmer.exhausts_of(def).size()
		var saved := []
		for i in def.engine_count():
			saved.append([Props.get_v("engines/%d/running" % (i + 1)), Props.get_v("engines/%d/egt_k" % (i + 1))])
			Props.set_v("engines/%d/running" % (i + 1), true)
			Props.set_v("engines/%d/egt_k" % (i + 1), 900.0)
		sh.update_shimmer(0.0, 120.0, 4000.0)
		var hot := sh.visible
		for i in def.engine_count():
			Props.set_v("engines/%d/running" % (i + 1), false)
		sh.update_shimmer(0.0, 120.0, 4000.0)
		var cold := sh.visible
		for i in saved.size():
			Props.set_v("engines/%d/running" % (i + 1), saved[i][0])
			Props.set_v("engines/%d/egt_k" % (i + 1), saved[i][1])
		sh.free()
		m.free()
		if hot != (n > 0) or cold:
			return "%s: plumes (%d) should show only with hot running engines (hot %s, cold %s)" % [id, n, hot, cold]
	return ""


## The menus (ui/post_fx_toggles.gd) offer a switch for bloom and every effect PostFxRules knows.
func test_menu_toggles_cover_every_effect() -> String:
	var keys := PostFxToggles.ROWS.map(func(r): return r[0])
	for fx in PostFxRules.FX:
		if not fx in keys:
			return "no menu switch for %s" % fx
	if not "bloom" in keys:
		return "no menu switch for bloom"
	if PostFxToggles._why_not("motion_blur", "low", "mobile") == "" or PostFxToggles._why_not("motion_blur", "max", "forward_plus") != "":
		return "motion blur should be dimmed on Low / Mobile and live on Max / Forward+"
	return ""
