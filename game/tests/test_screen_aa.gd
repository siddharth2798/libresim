extends Node
## Screen-space edge smoothing (core/screen_aa.gd, Graphics._apply_viewport): every preset smooths edges with SMAA when no
## temporal method runs, never with a filter on top of TAA or FSR2, and old options files / preset specs still map.

var _keep_choice: Variant
var _keep_cli := ""


func _init() -> void:
	_keep_choice = UserOptions.get_v("edge_smoothing")
	_keep_cli = ScreenAA._cli


func teardown() -> void:
	UserOptions._v["edge_smoothing"] = _keep_choice  # in memory only: never the player's options.cfg
	ScreenAA._cli = _keep_cli
	for c in get_children():
		c.free()


## A viewport with preset `p` applied at `scale` on `renderer`; returns [screen_space_aa, use_taa, FSR2?].
func _apply(p: String, scale: float, renderer: String, choice := "Auto") -> Array:
	UserOptions._v["edge_smoothing"] = choice
	ScreenAA._cli = ""
	var vp := SubViewport.new()
	add_child(vp)
	Graphics._apply_viewport(vp, RenderScaler.at_scale(Graphics.PRESETS[p], scale), renderer == "forward_plus")
	var out := [vp.screen_space_aa, vp.use_taa, vp.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR2]
	vp.free()
	return out


func test_each_preset_smooths_edges_with_smaa_unless_taa_runs() -> String:
	var smaa := Viewport.SCREEN_SPACE_AA_SMAA
	for p in Graphics.ORDER:
		var spec: Dictionary = Graphics.PRESETS[p]
		if not ScreenAA.MODES.has(str(spec.get("post_aa", ""))):
			return "%s: post_aa must be smaa, fxaa or off" % p
		var r: Array = _apply(p, float(spec.scale), Graphics.preset_renderer(p))
		var want := Viewport.SCREEN_SPACE_AA_DISABLED if r[1] else smaa
		if r[0] != want:
			return "%s on its own renderer: screen_space_aa %d (TAA %s), want %d" % [p, r[0], r[1], want]
	for p in ["low", "medium", "high"]:
		if _apply(p, float(Graphics.PRESETS[p].scale), Graphics.preset_renderer(p))[0] != smaa:
			return "%s should use SMAA (it used FXAA or nothing before)" % p
	for p in ["ultra", "max"]:
		var r: Array = _apply(p, float(Graphics.PRESETS[p].scale), "forward_plus")
		if not r[1] or r[0] != Viewport.SCREEN_SPACE_AA_DISABLED:
			return "%s on Forward+ should smooth with TAA only" % p
	return ""


func test_never_a_screen_filter_on_top_of_taa_or_fsr2() -> String:
	for p in Graphics.ORDER:
		for scale in [0.7, 0.85, 1.0, 1.25]:
			for rend in ["mobile", "forward_plus"]:
				for choice in UserOptions.CHOICES.edge_smoothing:
					var r: Array = _apply(p, scale, rend, choice)
					if (r[1] or r[2]) and r[0] != Viewport.SCREEN_SPACE_AA_DISABLED:
						return "%s at %.2f on %s (%s): filter %d with TAA %s / FSR2 %s" % [p, scale, rend, choice, r[0], r[1], r[2]]
					if r[1] and r[2]:
						return "%s at %.2f: TAA together with FSR2" % [p, scale]
	ScreenAA._cli = "smaa"  # --aa= forces a filter, but still not on top of TAA
	if ScreenAA.filter_for(Graphics.PRESETS.ultra, true) != "off":
		return "--aa= must not stack a filter on TAA / FSR2"
	return ""


func test_ultra_on_mobile_falls_back_to_smaa() -> String:
	# Mobile has no TAA: a hand-picked renderer must not leave Ultra / Max without any post filter.
	for p in ["ultra", "max"]:
		var r: Array = _apply(p, 1.0, "mobile")
		if r[1] or r[0] != Viewport.SCREEN_SPACE_AA_SMAA:
			return "%s on Mobile: TAA %s, filter %d; want no TAA and SMAA" % [p, r[1], r[0]]
	return ""


func test_edge_smoothing_option_replaces_the_presets_filter() -> String:
	var want := {"Auto": Viewport.SCREEN_SPACE_AA_SMAA, "SMAA": Viewport.SCREEN_SPACE_AA_SMAA,
		"FXAA": Viewport.SCREEN_SPACE_AA_FXAA, "Off": Viewport.SCREEN_SPACE_AA_DISABLED}
	if UserOptions.CHOICES.edge_smoothing != want.keys():
		return "the option lists %s" % [UserOptions.CHOICES.edge_smoothing]
	for c in want:
		var got: int = _apply("medium", 0.85, "mobile", c)[0]
		if got != want[c]:
			return "Edge smoothing %s on Medium gave %d, want %d" % [c, got, want[c]]
	ScreenAA._cli = "off"  # --aa=off (benches) wins over the option
	if ScreenAA.filter_for(Graphics.PRESETS.low, false, "FXAA") != "off":
		return "--aa= should win over the option"
	return ""


func test_old_options_file_maps_to_the_preset_filter() -> String:
	# An options.cfg from before "edge_smoothing": the other keys load, the new one is Auto, so the preset's SMAA runs.
	var cf := ConfigFile.new()
	cf.set_value("options", "alt_unit", "m")
	cf.set_value("options", "bloom", false)
	var v := UserOptions.read(cf)
	if v.alt_unit != "m" or v.bloom != false or v.edge_smoothing != "Auto":
		return "old file read as %s / %s / %s" % [v.alt_unit, v.bloom, v.edge_smoothing]
	if UserOptions.read(null).edge_smoothing != "Auto":
		return "no options file should give Auto"
	if ScreenAA.filter_for(Graphics.PRESETS.low, false, v.edge_smoothing) != "smaa":
		return "Auto on Low should be SMAA"
	for odd in [null, "", "Ultra", 3, true]:  # hand edits / wrong types: Auto
		if ScreenAA.choice_filter(odd) != "":
			return "'%s' should read as Auto" % [odd]
	if ScreenAA.choice_filter("fxaa") != "fxaa" or ScreenAA.choice_filter("SMAA") != "smaa":
		return "filter names in either case should be accepted"
	return ""


func test_old_preset_spec_with_fxaa_flag_maps() -> String:
	# Specs written before post_aa carried "fxaa": true / false.
	if ScreenAA.filter_of({"fxaa": true}) != "smaa" or ScreenAA.filter_of({"fxaa": false}) != "off":
		return "fxaa true should map to SMAA (its replacement), false to off"
	if ScreenAA.filter_of({}) != "off" or ScreenAA.filter_of({"post_aa": "bogus"}) != ScreenAA.DEFAULT:
		return "no key is off, an unknown post_aa is the default"
	for p in Graphics.ORDER:
		if Graphics.PRESETS[p].has("fxaa"):
			return "%s still has the old fxaa key" % p
	return ""


func test_options_graphics_has_the_edge_smoothing_row() -> String:
	var page := OptionsGraphics.new()
	add_child(page)
	var found := false
	for c in page.find_children("*", "Label", true, false):
		found = found or (c as Label).text == "Edge smoothing"
	page.free()
	return "" if found else "Options > Graphics has no Edge smoothing row"
