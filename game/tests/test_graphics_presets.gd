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
	page.free()
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
