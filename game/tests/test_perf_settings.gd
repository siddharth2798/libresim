extends Node
## Performance settings from the load-time / frame-time study: Medium draws edges with SMAA only and one cheap shadow
## split, the terrain casts no shadows below High, the ground tile cache is sized per preset, auto render
## resolution falls back to the frame time where the driver reports no GPU time, and model textures import
## VRAM-compressed with mipmaps (the C172 cockpit shares the exterior's identical atlases).


func test_medium_has_no_msaa_but_smaa() -> String:
	var m: Dictionary = Graphics.PRESETS.medium
	if int(m.msaa) != 0:
		return "Medium should not use MSAA (it cost about 14 ms of GPU on Mobile next to SMAA), msaa=%d" % int(m.msaa)
	if str(m.post_aa) != "smaa":
		return "Medium keeps SMAA as its edge filter"
	for p in ["high", "ultra", "max"]:
		if int(Graphics.PRESETS[p].msaa) < 1:
			return "%s keeps MSAA" % p
	return ""


## Two splits since 2026-11-25: with one, the aircraft lost its own shadow from about 40 m (tests/test_ground_shadow.gd).
## Measured on an Apple M4 (tools/bench.sh, medium / mobile): vabb_final_golden 8.68 ms vs 8.64 with one split,
## ghats_chase 7.33 vs 7.39, the same within noise.
func test_medium_shadows_are_two_splits_small_atlas_no_terrain() -> String:
	var m: Dictionary = Graphics.PRESETS.medium
	if int(m.pssm) != 1 or int(m.atlas) != 2048 or float(m.shadow) <= 0.0:
		return "Medium should draw sun shadows with two splits on a 2048 atlas: pssm=%d atlas=%d" % [int(m.pssm), int(m.atlas)]
	for p in Graphics.ORDER:
		var want: bool = p in ["high", "ultra", "max"]
		if bool(SceneryQuality.for_preset(p).terrain_shadow) != want:
			return "%s: terrain shadows should be %s" % [p, "on" if want else "off"]
	return ""


func test_scenery_quality_applies_shadows_and_cache_size() -> String:
	var root := Node3D.new()
	var t := Node3D.new()
	t.name = "Terrain"
	root.add_child(t)
	var mi := MeshInstance3D.new()
	t.add_child(mi)
	var b := Node3D.new()
	b.name = "Buildings"
	root.add_child(b)
	var bm := MeshInstance3D.new()
	b.add_child(bm)
	SceneryQuality.apply(root, "medium")
	var off := mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and SceneryQuality.mode_for(t) == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	SceneryQuality.apply(root, "high")
	var on := mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON and SceneryQuality.mode_for(t) == GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var bld := bm.cast_shadow == SceneryQuality.shadow_mode(bool(SceneryQuality.for_preset("high").bld_shadow))
	root.free()
	if not off or not on:
		return "terrain nodes (existing and new) should cast no shadows on Medium and cast them on High"
	return "" if bld else "building tiles follow the preset's bld_shadow"


func test_tile_cache_size_per_preset() -> String:
	var last := 0
	for p in Graphics.ORDER:
		var n := int(SceneryQuality.for_preset(p).tile_cache)
		if n < last:
			return "%s: the ground tile cache shrank from the preset below" % p
		last = n
	if int(SceneryQuality.for_preset("low").tile_cache) > 150 or int(SceneryQuality.for_preset("medium").tile_cache) > 150:
		return "Low / Medium should keep at most about 150 ground tiles per kind"
	if int(SceneryQuality.for_preset("high").tile_cache) < 300:
		return "High and up keep a roomy cache"
	var c := TerrainTileCache.new()
	var ok := c.max_entries == TerrainTileCache.MAX_ENTRIES
	c.max_entries = 120
	var store := {}
	var now := Time.get_ticks_msec()
	for i in 200:  # 200 ready entries: the first 150 unused for 10 s, the last 50 in use now
		store[Vector3i(0, i, 0)] = {"state": 1, "used": now - 10000 if i < 150 else now}
	c._now = now
	c._evict(store)
	var kept_live := true
	for i in range(150, 200):
		kept_live = kept_live and store.has(Vector3i(0, i, 0))
	if not ok:
		return "the cache starts at MAX_ENTRIES until a preset sets it"
	if store.size() != 90 or not kept_live:
		return "eviction should trim to 3/4 of max_entries (90) and never drop tiles in use, kept %d" % store.size()
	return ""


func test_auto_scale_without_gpu_time_uses_the_frame_time() -> String:
	var budget := RenderScaler.budget_ms(60.0)
	var dt := 1.0 / 60.0
	var sc := RenderScaler.new()
	sc.reset(1.0)
	for i in 60 * 30:  # vsync on, every frame keeps its slot: nothing is known about headroom, so hold
		sc.feed_any(0.0, budget, budget, true, dt)
	if not is_equal_approx(sc.scale, 1.0):
		return "frames that keep their vsync slot should not step down, got %.2f" % sc.scale
	for i in 60 * 10:  # one 600 ms hitch a second (loading) but otherwise on time: still hold
		sc.feed_any(0.0, 600.0 if i % 60 == 0 else budget, budget, true, dt)
	if not is_equal_approx(sc.scale, 1.0):
		return "loading hitches alone should not step down, got %.2f" % sc.scale
	var steps := 0
	for i in 60 * 10:  # 30 fps on a 60 Hz screen: every frame misses its slot
		if sc.feed_any(0.0, budget * 2.0, budget, true, dt):
			steps += 1
	if not is_equal_approx(sc.scale, RenderScaler.FLOOR) or steps != 3:
		return "missed vsync slots should step down to the floor, got %.2f after %d steps" % [sc.scale, steps]
	# a GPU that holds 0.8 but not 0.9: blind tries up, each failure doubles the wait, so no see-saw
	var ups := 0
	var t := 0.0
	var waits: Array[float] = []
	while t < 600.0:
		var slow := sc.scale > 0.85
		if sc.feed_any(0.0, budget * (1.4 if slow else 1.0), budget, true, dt) and sc.scale > 0.85:
			ups += 1
			waits.append(sc.blind_hold)
		t += dt
	if ups < 2 or ups > 6:
		return "over 10 min a scale that cannot hold should be retried a few times, not every few seconds: %d tries" % ups
	if sc.blind_hold <= RenderScaler.BLIND_UP_S:
		return "failed tries should lengthen the wait, still %.0f s" % sc.blind_hold
	var sc2 := RenderScaler.new()
	sc2.reset(1.0)
	for i in 60 * 5:
		sc2.feed_any(0.0, budget * 2.0, budget, false, dt)  # vsync off: the frame time is the load
	if sc2.scale > 0.95:
		return "with vsync off a slow frame time should step down too"
	for i in 60 * 60:
		sc2.feed_any(0.0, budget * 0.4, budget, false, dt)
	if not is_equal_approx(sc2.scale, 1.0):
		return "with vsync off and room again the scale comes back, got %.2f" % sc2.scale
	var sc3 := RenderScaler.new()
	sc3.reset(1.0)
	for i in 60 * 10:
		sc3.feed_any(budget * 0.3, budget * 2.0, budget, true, dt)  # a GPU reading wins over the frame time
	return "" if is_equal_approx(sc3.scale, 1.0) else "when the GPU time is there it decides, not the frame time"


func test_auto_scale_does_not_step_down_a_cpu_bound_frame_and_recovers() -> String:
	# No GPU time (Metal, Compatibility): Medium on Mobile is CPU-bound, so 30 fps on a 60 Hz screen from 25 ms of CPU
	# work must not walk the scale down 0.85 -> 0.75 -> 0.7 for nothing; a scale lowered while the GPU really was the
	# limit comes back once the frames are CPU-limited again; vsync off too.
	var budget := RenderScaler.budget_ms(60.0)
	var dt := 1.0 / 30.0
	var sc := RenderScaler.new()
	sc.reset(0.85)
	for i in 30 * 30:
		sc.feed_any(0.0, budget * 2.0, budget, true, dt, 25.0)
	if not is_equal_approx(sc.scale, 0.85):
		return "a CPU-bound frame (25 ms CPU, 33 ms frame) should not step down, got %.2f" % sc.scale
	for i in 30 * 10:  # GPU-bound: 8 ms of CPU, every slot missed
		sc.feed_any(0.0, budget * 2.0, budget, true, dt, 8.0)
	if not is_equal_approx(sc.scale, RenderScaler.FLOOR):
		return "GPU-bound frames (8 ms CPU) still step down to the floor, got %.2f" % sc.scale
	for i in 30 * 90:  # CPU-bound again: the lowered scale buys nothing
		sc.feed_any(0.0, budget * 2.0, budget, true, dt, 28.0)
	if not is_equal_approx(sc.scale, 0.85):
		return "with CPU-bound frames the scale should climb back to the preset's 0.85, got %.2f" % sc.scale
	var nv := RenderScaler.new()
	nv.reset(1.0)
	for i in 40 * 30:  # vsync off, 25 ms frames, 23 ms of them CPU
		nv.feed_any(0.0, 25.0, budget, false, 1.0 / 40.0, 23.0)
	if not is_equal_approx(nv.scale, 1.0):
		return "vsync off: a CPU-bound frame should not step down either, got %.2f" % nv.scale
	if RenderScaler.cpu_bound(-1.0, 33.0, budget, true) or not RenderScaler.cpu_bound(20.0, 33.3, budget, true):
		return "no CPU reading is never CPU-bound; 20 ms of CPU needs the same two slots as a 33 ms frame"
	return ""


## Textures the livery and registration painters repaint at run time (aircraft.json "texture" keys) stay Lossless:
## the painted copy is an uncompressed ImageTexture anyway, and block compression would put artefacts into its base.
func test_model_textures_import_vram_compressed_with_mipmaps() -> String:
	var bad: Array[String] = []
	var painted := {}
	for id in ["c172", "a320"]:
		_painted(JSON.parse_string(FileAccess.get_file_as_string("res://aircraft/%s/aircraft.json" % id)), "res://aircraft/" + id, painted)
	if not painted.has("res://aircraft/c172/models/exterior_fuselage.png"):
		return "the C172 fuselage atlas is a livery texture"
	# 2D label art drawn on a canvas (small text, sampled 1:1), not a 3D model texture
	painted[FcuLcdDraw.ART] = true
	painted[FcuLcdDraw.ART_TRK] = true
	for dir in ["res://aircraft/c172/models", "res://aircraft/a320/models", "res://world/models/vehicles"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".png.import") and not painted.has(dir.path_join(f.trim_suffix(".import"))):
				var cf := ConfigFile.new()
				if cf.load(dir.path_join(f)) != OK:
					continue
				if int(cf.get_value("params", "compress/mode", 0)) != 2 or not bool(cf.get_value("params", "mipmaps/generate", false)):
					bad.append(f)
				elif f.contains("-normal") and int(cf.get_value("params", "compress/normal_map", 0)) != 1:
					bad.append(f + " (normal map mode)")
	if not bad.is_empty():
		return "3D model textures should be VRAM-compressed with mipmaps: %s" % ", ".join(bad)
	var imp := ConfigFile.new()
	imp.load("res://aircraft/c172/models/interior.glb.import")
	if str(imp.get_value("params", "import_script/path", "")) != "res://aircraft/common/share_textures_import.gd":
		return "the C172 cockpit glb should share the exterior's identical textures (import script)"
	if not ClassDB.class_exists("EditorScenePostImport"):  # an export template: the import script cannot load, nothing to check
		return ""
	var share = load("res://aircraft/common/share_textures_import.gd")
	var cache := {}
	var others: Array[String] = ["exterior_"]
	var dir := "res://aircraft/c172/models"
	if share.shared_path(dir.path_join("interior_panel.png"), dir, "interior_", others, cache) != dir.path_join("exterior_panel.png"):
		return "interior_panel.png is byte-identical to exterior_panel.png and should map to it"
	if share.shared_path(dir.path_join("interior_yoke.png"), dir, "interior_", others, cache) != "":
		return "a texture only the cockpit has keeps its own file"
	return ""


func _painted(v: Variant, dir: String, out: Dictionary) -> void:
	if v is Dictionary:
		for k in v:
			if k == "texture" and v[k] is String:
				out[dir.path_join(v[k])] = true
			else:
				_painted(v[k], dir, out)
	elif v is Array:
		for x in v:
			_painted(x, dir, out)
