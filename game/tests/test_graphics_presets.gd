extends Node
## Quality presets (core/graphics_settings.gd): shadows are off on Low and cascade (PSSM 2 / 4 splits)
## further out with each step up; the sun in flight.tscn starts with four splits. Max is the top
## preset; Low / Medium run on Mobile, High and up on Forward+ with its screen-space effects.


func test_shadow_presets_grow_with_quality() -> String:
	var last := -1.0
	var last_mode := -1
	for p in Graphics.ORDER:
		var s: Dictionary = Graphics.PRESETS[p]
		if not s.has("pssm") or int(s.pssm) < 0 or int(s.pssm) > 2:
			return "%s: pssm missing or not 0..2" % p
		if s.shadow < last or int(s.pssm) < last_mode:
			return "%s: shadow distance or cascade count went down" % p
		if (s.shadow > 0.0) != (p != "low"):
			return "%s: only Low should have no shadows" % p
		last = s.shadow
		last_mode = int(s.pssm)
	return "" if Graphics.PRESETS.ultra.shadow >= 3000.0 else "Ultra should cascade out to kilometres"


func test_flight_sun_uses_four_cascades() -> String:
	var flight: Node = load("res://world/flight.tscn").instantiate()
	var sun := flight.get_node("Sun") as DirectionalLight3D
	var ok := sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS and sun.directional_shadow_blend_splits
	flight.free()
	return "" if ok else "the flight scene sun should start with 4 blended shadow splits"


func test_cloud_shadow_globals_follow_the_layer() -> String:
	var layer := CloudLayer.new()
	add_child(layer)
	var sun := Color(1.0, 0.95, 0.9)
	layer.update_layer(Vector3.ZERO, 1000.0, 0.5, Vector2(1234.0, 0.0), Vector3(0, 1, 0), sun, Color(0.5, 0.5, 0.5), 0.0)
	var on := layer.shadow
	layer.update_layer(Vector3.ZERO, 1000.0, 0.0, Vector2.ZERO, Vector3(0, 1, 0), sun, Color(0.5, 0.5, 0.5), 0.0)
	var clear := layer.shadow
	layer.update_layer(Vector3.ZERO, 1000.0, 0.8, Vector2.ZERO, Vector3(0, 1, 0), sun, Color(0.5, 0.5, 0.5), 0.6)
	var deck := layer.shadow
	layer.free()
	if not is_equal_approx(on.x, 1000.0) or not is_equal_approx(on.y, 0.5) or on.z < 0.3:
		return "scattered cloud in sunlight should cast shadows: %s" % on
	if clear.z != 0.0:
		return "a clear sky should cast none: %s" % clear
	return "" if deck.z == 0.0 else "under a thick deck (no direct sun) there should be no patchy shadows: %s" % deck


func test_max_is_the_top_preset() -> String:
	if Graphics.ORDER.back() != "max" or Graphics.PRESETS.keys() != Graphics.ORDER:
		return "Max should be the last preset and PRESETS should follow ORDER: %s" % [Graphics.ORDER]
	var m: Dictionary = Graphics.PRESETS.max
	var u: Dictionary = Graphics.PRESETS.ultra
	if m.scale <= 1.0 or m.fsr:
		return "Max supersamples (scale > 1, bilinear down, no FSR)"
	for k in ["shadow", "clouds", "bld", "trees", "tree_lod", "lod_k", "wisps", "rain"]:
		if m[k] <= u[k]:
			return "Max should reach further than Ultra in %s" % k
	return ""


func test_renderer_per_preset() -> String:
	for p in Graphics.ORDER:
		var want := "mobile" if p in ["low", "medium"] else "forward_plus"
		if Graphics.preset_renderer(p) != want:
			return "%s should run on %s" % [p, want]
	var cf := ConfigFile.new()  # project.godot itself: ProjectSettings would also show a player's override.cfg
	cf.load("res://project.godot")
	return "" if cf.get_value("rendering", "renderer/rendering_method", "") == "forward_plus" else "project default renderer should be Forward+"


func test_forward_plus_features_only_high_up() -> String:
	for p in Graphics.ORDER:
		var s: Dictionary = Graphics.PRESETS[p]
		var fp := Graphics.preset_renderer(p) == "forward_plus"
		if not fp and (s.ssao or s.ssil or s.taa or s.ssr > 0):
			return "%s runs on Mobile: SSAO / SSIL / SSR / TAA would do nothing" % p
		if fp and not s.ssao:
			return "%s: every Forward+ preset gets SSAO" % p
		if not fp and s.real_lights > 4:
			return "%s: Mobile presets keep 4 real apron lights (lights-per-mesh limit)" % p
	if not Graphics.PRESETS.max.ssil or Graphics.PRESETS.ultra.ssil:
		return "SSIL is for Max only"
	return "" if Graphics.PRESETS.ultra.taa and Graphics.PRESETS.ultra.ssr > 0 and not Graphics.PRESETS.high.taa else "SSR / TAA from Ultra up"


func test_steps_grow_with_quality() -> String:
	var last := {}
	for p in Graphics.ORDER:
		var s: Dictionary = Graphics.PRESETS[p]
		for k in ["atlas", "soft", "pos_soft", "clouds", "cloud_light", "real_lights", "ssr"]:
			if not s.has(k):
				return "%s has no '%s'" % [p, k]
			if last.has(k) and s[k] < last[k]:
				return "%s: %s went down from the preset below" % [p, k]
			last[k] = s[k]
		if int(s.soft) < RenderingServer.SHADOW_QUALITY_HARD or int(s.soft) > RenderingServer.SHADOW_QUALITY_SOFT_ULTRA:
			return "%s: soft shadow quality out of range" % p
	return ""


func test_apple_silicon_budget_keeps_the_preset_table() -> String:
	var med: Dictionary = Graphics.PRESETS.medium
	var air := RenderBudget.clamp_preset(med, Vector2i(2560, 1664), true)
	var other := RenderBudget.clamp_preset(med, Vector2i(2560, 1664), false)
	if air.scale >= float(med.scale) or int(air.msaa) != 0 or int(air.clouds) > 10 or int(air.atlas) > 2048:
		return "an Air-sized frame should drop scale, MSAA, cloud steps and the shadow atlas"
	if not is_equal_approx(float(other.scale), float(med.scale)) or int(other.clouds) != int(med.clouds):
		return "other machines keep the preset"
	if not is_equal_approx(float(Graphics.PRESETS.medium.scale), 0.85) or int(Graphics.PRESETS.medium.clouds) != 16:
		return "the budget must not rewrite the preset table"
	return ""


func test_apple_budget_keeps_a_4k_frame_sharp() -> String:
	var hi := RenderBudget.clamp_preset(Graphics.PRESETS.high, Vector2i(3840, 2160), true)
	if float(hi.scale) < RenderBudget.SCALE_FLOOR - 0.001:
		return "a 4K frame was scaled to %.2f, below the floor" % float(hi.scale)
	if not hi.fsr or not hi.fxaa:
		return "a reduced frame must upscale with FSR and keep FXAA once MSAA is off"
	if RenderBudget.needs_budget("Apple M5 Max") or RenderBudget.needs_budget("Apple M3 Pro") or RenderBudget.needs_budget("Intel(R) Core(TM) i7"):
		return "Pro / Max chips and Intel must keep the preset"
	if not RenderBudget.needs_budget("Apple M2"):
		return "a base Apple chip gets the budget"
	return ""


func test_preset_applies_to_a_scene() -> String:
	# Headless runs neither renderer's screen-space effects, so they must stay off whatever the preset.
	var root := Node3D.new()
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = Environment.new()
	root.add_child(we)
	var rl := RunwayLights.new()
	rl.name = "RunwayLights"
	root.add_child(rl)
	add_child(root)
	var was: String = Graphics.preset
	Graphics.preset = "max"
	Graphics.apply_to_scene(root)
	var lamps := rl.real_light_count()
	var fp := Graphics.renderer() == "forward_plus"
	var env := we.environment
	var bad := env.ssil_enabled != fp or env.ssr_enabled != fp or env.ssao_enabled != fp
	Graphics.preset = was
	Graphics.apply_to_scene(get_tree().current_scene)
	root.free()
	if bad:
		return "SSAO / SSIL / SSR should follow the running renderer (%s)" % Graphics.renderer()
	var want: int = Graphics.PRESETS.max.real_lights if fp else 4
	return "" if lamps == want else "Max should get %d real apron lights, got %d" % [want, lamps]


func test_flight_uses_agx() -> String:
	var flight: Node = load("res://world/flight.tscn").instantiate()
	var env := (flight.get_node("WorldEnvironment") as WorldEnvironment).environment
	var ok := env.tonemap_mode == Environment.TONE_MAPPER_AGX
	flight.free()
	return "" if ok else "the flight environment should tone map with AgX"


func test_anisotropic_filtering_16x() -> String:
	var v := int(ProjectSettings.get_setting("rendering/textures/default_filters/anisotropic_filtering_level"))
	return "" if v == Viewport.ANISOTROPY_16X else "anisotropic filtering should be 16x, got %d" % v


func test_menus_list_every_preset() -> String:
	# Start-screen options page and the F10 menu: one button per preset, a note for each, and no
	# "restart to apply" while nothing was saved for the next start.
	var page := HBoxContainer.new()
	page.set_script(load("res://ui/menu/options_page.gd"))
	add_child(page)
	var names := page.find_children("*", "Button", true, false).map(func(b): return b.text)
	var notes: Dictionary = page.PRESET_NOTES
	var restart_shown: bool = page._restart_note.visible
	var res := page.find_children("*", "ResolutionRow", true, false)
	var res_items: int = res[0]._pick.item_count if res.size() == 1 else 0
	var res_auto: String = res[0]._pick.get_item_text(0) if res_items > 0 else ""
	page.free()
	if res_items < 2 or not res_auto.begins_with("Auto: "):
		return "the Graphics tab needs a Render resolution picker with Auto first (got %d items)" % res_items
	var f10 := PanelContainer.new()
	f10.set_script(load("res://ui/settings_menu.gd"))
	add_child(f10)
	var f10_names := f10.find_children("*", "Button", true, false).map(func(b): return b.text)
	f10.free()
	for p in Graphics.ORDER:
		if not p.capitalize() in names or not p.capitalize() in f10_names or not notes.has(p):
			return "%s missing from a menu or without a note" % p
	if Graphics.restart_needed() or restart_shown:
		return "no renderer was saved in a test run, so no restart should be asked for"
	return "" if "1.8 km" in notes.high else "the High note should give its real shadow distance"


func test_render_resolution_lists_sizes_for_the_screen() -> String:
	var uhd := RenderResolution.options(Vector2i(3840, 2160))
	var labels := uhd.map(func(o): return o.label)
	for want in ["3840×2160 (100%)", "2560×1440 (67%)", "1920×1080 (50%)", "1280×720 (33%)"]:
		if not want in labels:
			return "4K list misses %s: %s" % [want, labels]
	var air := RenderResolution.options(Vector2i(2560, 1664))  # 16:10, sizes keep the screen's shape
	if air[0].label != "2560×1664 (100%)" or not "1662×1080 (65%)" in air.map(func(o): return o.label):
		return "16:10 list should keep the screen's shape: %s" % [air.map(func(o): return o.label)]
	if RenderResolution.options(Vector2i(1920, 1080)).size() != 3:
		return "a 1080p screen lists native, 900p and 720p only"
	if RenderResolution.nearest(air, 0.5) != RenderResolution.nearest(air, 0.52):
		return "a choice saved on another screen lands on the nearest size"
	return ""


func test_render_resolution_overrides_auto() -> String:
	var hi: Dictionary = Graphics.PRESETS.high
	if RenderResolution.apply(hi, 0.0) != hi:
		return "Auto keeps the preset"
	var half := RenderResolution.apply(hi, 0.5)
	if not is_equal_approx(float(half.scale), 0.5) or not half.fsr:
		return "a fixed size sets the scale and upscales with FSR"
	var lo_native := RenderResolution.apply(Graphics.PRESETS.low, 1.0)
	if not is_equal_approx(float(lo_native.scale), 1.0) or lo_native.fsr or not lo_native.fxaa:
		return "native on Low draws full size without FSR and keeps FXAA"
	if not is_equal_approx(float(RenderResolution.apply(Graphics.PRESETS.max, 1.0).scale), 1.0):
		return "a fixed native size replaces Max's supersampling"
	return ""


func test_budget_frame_is_the_viewport_texture_not_the_doubled_window() -> String:
	# A 1600x900 pixel window on a Retina screen used to be read as 3200x1800 (window size taken as points) and every
	# preset was clamped to FSR2 at 0.7. The viewport texture is the frame that is drawn.
	if RenderBudget.pick_frame(Vector2i(1600, 900), 2.0, Vector2i(1600, 900)) != Vector2i(1600, 900):
		return "the texture size must win over the points heuristic"
	if RenderBudget.pick_frame(Vector2i(1512, 982), 2.0, Vector2i(3024, 1964)) != Vector2i(3024, 1964):
		return "a Retina backing texture is the frame"
	if RenderBudget.pick_frame(Vector2i(1600, 900), 2.0, Vector2i.ZERO) != Vector2i(3200, 1800):
		return "without a texture a small window on a scaled screen is in points"
	if RenderBudget.pick_frame(Vector2i(1920, 1080), 1.0, Vector2i.ZERO) != Vector2i(1920, 1080):
		return "a plain screen keeps the window size"
	var hi := RenderBudget.clamp_preset(Graphics.PRESETS.high, RenderBudget.pick_frame(Vector2i(1600, 900), 2.0, Vector2i(1600, 900)), true)
	return "" if is_equal_approx(float(hi.scale), 1.0) and not hi.fsr else "a 1.44 MP frame must not be scaled: %s" % [hi]
