extends RefCounted
## Realistic runways, Stage 1: world/runway_v2.gdshader and its includes compile, bend with the Earth like every far
## shader, take every uniform RunwayMarkings.uniforms() fills, and stay under 300 lines a file.

const SHADER := "res://world/runway_v2.gdshader"
const FILES := ["res://world/runway_v2.gdshader", "res://world/runway_surface.gdshaderinc", "res://world/runway_marks.gdshaderinc",
	"res://world/runway_wear.gdshaderinc", "res://world/runway_cracks.gdshaderinc", "res://world/runway_markings.gd",
	"res://world/runway_glyphs.gd", "res://world/runway_noise.gd", "res://world/runway_bake.gd", "res://world/runway_bake.gdshader",
	"res://world/runway_bakes.gd", "res://world/runway_quality.gd", "res://world/touchdown_marks.gd", "res://world/strip.gdshaderinc"]
const VAJJ := {"airport": "VAJJ", "width": 45.0, "length": 1128.0, "ends": [
	{"ident": "26", "x": -59084.5, "y": 38734.9, "heading_true": 259.98},
	{"ident": "08", "x": -60195.3, "y": 38538.6, "heading_true": 79.98}]}


func _uniforms() -> Dictionary:
	var out := {}
	for u in (load(SHADER) as Shader).get_shader_uniform_list():
		out[u.name] = u
	return out


func test_runway_v2_compiles_with_its_uniforms() -> String:
	var names := _uniforms()
	if names.is_empty():
		return "runway_v2.gdshader did not compile"
	for n in ["marks", "mark_count", "bake_mix", "surface", "lod_lift"]:  # (textures with shader defaults bound are not listed)
		if not names.has(n):
			return "missing uniform %s" % n
	for k in RunwayMarkings.uniforms(VAJJ):
		if not names.has(k):
			return "RunwayMarkings.uniforms() sets %s, which the shader does not have" % k
	return ""


func test_runway_v2_bends_with_the_earth_and_keeps_the_strip_vertex() -> String:
	if not Curvature.SHADERS.has(SHADER):
		return "runway_v2 is drawn far away: list it in Curvature.SHADERS"
	var src := FileAccess.get_file_as_string(SHADER)
	for frag in ["curvature.gdshaderinc", "curve_drop(", "ground_lift(", "vp.xyz *= 0.9985", "haze_color(", "wetness"]:
		if not src.contains(frag):
			return "runway_v2.gdshader lost %s (keep the strip.gdshaderinc vertex, haze and wetness)" % frag
	return ""


func test_every_detail_level_compiles() -> String:
	# runway_detail is a uniform: one compiled shader serves Low, Medium and High; the branches it gates must exist
	var src := ""
	for f in FILES.slice(0, 5):
		src += FileAccess.get_file_as_string(f)
	for lvl in ["runway_detail < 3", "runway_detail >= 1", "runway_detail >= 2"]:
		if not src.contains(lvl):
			return "no %s branch" % lvl
	if not ProjectSettings.has_setting("shader_globals/runway_detail") or not FileAccess.get_file_as_string(SHADER).contains("global uniform int runway_detail"):
		return "runway_detail must be a project shader global read by runway_v2"
	for c in [["low", 0], ["medium", 1], ["high", 2], ["ultra", 3], ["max", 3]]:
		if RunwayQuality.level(c[0]) != c[1]:
			return "%s preset: runway_detail %d, want %d" % [c[0], RunwayQuality.level(c[0]), c[1]]
	return ""


func test_files_stay_small() -> String:
	for f in FILES:
		var n := FileAccess.get_file_as_string(f).split("\n").size()
		if n >= 300:
			return "%s is %d lines (limit 300)" % [f, n]
	return ""


func test_bake_shader_compiles_and_sizes_follow_the_runway() -> String:
	if (load(RunwayBake.SHADER) as Shader).get_shader_uniform_list().is_empty():
		return "runway_bake.gdshader did not compile"
	var vabb := {"width": 60.0, "length": 3470.2}
	if RunwayBake.size_for(vabb) != Vector2i(300, 6941):
		return "VABB bake %s, want 300 x 6941 texels (0.2 m across, 0.5 m along)" % RunwayBake.size_for(vabb)
	if RunwayBake.size_for({"width": 45.0, "length": 9000.0}).y > RunwayBake.MAX_PX:
		return "a long runway must get coarser texels, not a texture over the size limit"
	return ""


## Needs a renderer: passes quietly headless (run the suite windowed to exercise it).
func test_bake_paints_a_threshold_stripe() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var host := tree.root.get_child(tree.root.get_child_count() - 1)  # the runner scene (root is busy while it starts)
	var tex := RunwayBake.bake(VAJJ, RunwayMarkings.uniforms(VAJJ), host)
	if tex == null:
		return "" if DisplayServer.get_name() == "headless" else "bake returned nothing with a renderer"
	var img := tex.get_image()
	var size := RunwayBake.size_for(VAJJ)
	if img.get_size() != size:
		return "baked %s, want %s" % [img.get_size(), size]
	var u := RunwayMarkings.uniforms(VAJJ)
	var x: float = (u.thr_pitch - 1.8) + 0.9 + u.thr_pitch * 2.0  # middle of the third stripe right of the axis
	var stripe := img.get_pixel(int((x / 45.0 + 0.5) * size.x), int(20.0 / RunwayBake.texel_for(VAJJ).y)).a
	var bare := img.get_pixel(int(0.5 * size.x), int(600.0 / RunwayBake.texel_for(VAJJ).y) + 30).a
	if stripe < 0.5 or bare > 0.2:
		return "paint channel: stripe %.2f (want > 0.5), mid-runway gap %.2f (want ~0)" % [stripe, bare]
	return ""


func test_near_runways_are_baked_one_at_a_time_and_far_ones_freed() -> String:
	var near := RunwayBakes.NEAR_M * 0.5
	var p := RunwayBakes.plan([near, near * 0.4, RunwayBakes.FAR_M * 1.5, RunwayBakes.NEAR_M * 1.2], [false, false, true, true], false)
	if p.bake != 1:
		return "the nearest unbaked runway within %d m should bake first, got %d" % [RunwayBakes.NEAR_M, p.bake]
	if p.free != [2]:
		return "a baked runway beyond %d m should be freed (and one between NEAR and FAR kept): %s" % [RunwayBakes.FAR_M, p.free]
	if RunwayBakes.plan([near], [false], true).bake != -1:
		return "only one bake at a time"
	if RunwayBakes.plan([RunwayBakes.NEAR_M * 1.1], [false], false).bake != -1:
		return "a runway beyond NEAR_M is not baked"
	return ""


func test_airport_builder_uses_runway_v2_with_the_layout() -> String:
	var src := FileAccess.get_file_as_string("res://world/airport_builder.gd")
	if not src.contains("runway_v2.gdshader") or not src.contains("RunwayMarkings.uniforms(") or not src.contains("_bakes.add("):
		return "AirportBuilder must draw runways with runway_v2, RunwayMarkings uniforms and lazy bakes"
	if FileAccess.file_exists("res://world/runway.gdshader"):
		return "the old runway.gdshader is replaced by runway_v2"
	if FileAccess.get_file_as_string("res://world/strip.gdshaderinc").contains("sin(along * 0.37"):
		return "the old sine tyre term is gone"
	return ""


## A pass whose viewport already went with its host (the builder left the tree) still gives its RenderingServer
## canvas item back: it is a bare RID, nothing else frees it, and it was reported as leaked at exit.
func test_cancelled_bake_frees_its_canvas_item_after_the_viewport_is_gone() -> String:
	var vp := SubViewport.new()
	var ci := RenderingServer.canvas_item_create()
	var job := {"vp": vp, "ci": ci, "mat": null}
	vp.free()
	RunwayBake.cancel(job)
	if job.ci.is_valid():
		RenderingServer.free_rid(ci)
		return "the canvas item of a pass whose viewport is gone was kept (leaks until exit)"
	RunwayBake.cancel(job)  # twice is harmless
	return ""


func test_close_up_aggregate_is_ultra_only() -> String:
	# On High the aggregate texture / normal took the full-screen near field over its 0.3 ms per megapixel budget
	# (tests/debug_runway_bench.tscn), so it starts at Ultra; High keeps the light fittings (runway_detail >= 2).
	var src := FileAccess.get_file_as_string("res://world/runway_surface.gdshaderinc")
	var i := src.find("vec3 rw_aggregate(")
	var body := src.substr(i, src.find("return vec3(1.0);", i) - i)
	if i < 0 or not body.contains("runway_detail < 3"):
		return "rw_aggregate must return early below runway_detail 3 (Ultra)"
	if RunwayQuality.level("high") >= 3 or RunwayQuality.level("ultra") < 3:
		return "High must stay below the aggregate level and Ultra at it"
	return ""
