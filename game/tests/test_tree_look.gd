extends Node
## Trees G8 (docs/GRAPHICS-PLAN.md): region-correct species, hemi-octahedral impostor frames, near-mesh LODs, preset
## ranges and budgets, paved areas, floating-origin shifts, curvature in every tree shader, the season tint.


func _mix(n: float, g: float, wc: int) -> Array:
	var counts := []
	counts.resize(TreeSpecies.COUNT)
	counts.fill(0)
	for j in 50:
		for i in 50:
			counts[TreeSpecies.of(i, j, n, g, wc)] += 1
	return counts


func test_species_follow_land_cover_and_region() -> String:
	var konkan_village := _mix(-250000.0, 15.0, TreeSpecies.WC_BUILT)
	var ghat_forest := _mix(-100000.0, 700.0, TreeSpecies.WC_TREE)
	var deccan_scrub := _mix(0.0, 600.0, TreeSpecies.WC_SHRUB)
	var mumbai_town := _mix(40000.0, 10.0, TreeSpecies.WC_BUILT)
	var mangrove := _mix(-200000.0, 2.0, TreeSpecies.WC_MANGROVE)
	if konkan_village[TreeSpecies.PALM] < 0.35 * 2500 or konkan_village[TreeSpecies.SPREAD] < 0.25 * 2500:
		return "a Konkan village should be coconut palms and mango / banyan: %s" % [konkan_village]
	if ghat_forest[TreeSpecies.BROADLEAF] < 0.75 * 2500 or ghat_forest[TreeSpecies.PALM] > 0:
		return "the Ghat forest should be forest broadleaf without palms: %s" % [ghat_forest]
	if deccan_scrub[TreeSpecies.ACACIA] < 0.4 * 2500:
		return "Deccan shrubland should be mostly acacia scrub: %s" % [deccan_scrub]
	if mumbai_town[TreeSpecies.SPREAD] < mumbai_town[TreeSpecies.BROADLEAF] * 2:
		return "town trees should be mostly wide mango / peepal / banyan: %s" % [mumbai_town]
	if mangrove[TreeSpecies.PALM] + mangrove[TreeSpecies.ACACIA] + mangrove[TreeSpecies.SLIM] > 0:
		return "mangroves get no palms, scrub or casuarina: %s" % [mangrove]
	if _mix(-150000.0, 10.0, TreeSpecies.WC_CROP)[TreeSpecies.SLIM] == 0:
		return "the coastal strip should have some casuarina"
	return ""


func test_heights_keep_their_family_whatever_the_land_cover() -> String:
	for j in 30:
		for i in 30:
			var old_h := lerpf(6.0, 15.0, TreeSampler.hash3(i, j, 4))
			for wc in [0, 1, 2, 3, 4, 5, 6, 10]:
				var sh := TreeSpecies.shape(i, j, -200000.0, 40.0, wc)
				if int(sh[0]) in [TreeSpecies.BROADLEAF, TreeSpecies.SPREAD] and absf(sh[2] - old_h) > 1e-4:
					return "broadleaf / spread at %d,%d is %.2f m, the old height was %.2f m" % [i, j, sh[2], old_h]
				if sh[2] > TreeSpecies.MAX_HEIGHT or sh[2] < 5.0:
					return "height %.1f out of range" % sh[2]
	return ""


func test_octa_encode_decode_round_trip() -> String:
	for d in [Vector3.UP, Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0.3, 0.8, -0.5).normalized(), Vector3(-0.7, 0.1, 0.7).normalized()]:
		var back := TreeOcta.decode(TreeOcta.encode(d))
		if back.distance_to(d) > 1e-4:
			return "%s came back as %s" % [d, back]
	var e := TreeOcta.encode(Vector3(1, 0, 0))
	if absf(maxf(absf(e.x), absf(e.y)) - 1.0) > 1e-5:
		return "a horizontal view should land on the edge of the square, got %s" % e
	return ""


func test_octa_frame_selection_by_view_angle() -> String:
	var n := TreeOcta.N
	for j in n:
		for i in n:
			var sel: Array = TreeOcta.select(TreeOcta.frame_dir(i, j))
			if Vector2i(sel[0][0], sel[0][1]) != Vector2i(i, j) or absf(sel[0][2] - 1.0) > 1e-4:
				return "the view along frame (%d, %d) picked %s" % [i, j, sel]
	var top := TreeOcta.nearest(Vector3.UP)
	if absf(top.x - (n - 1) * 0.5) > 0.6 or absf(top.y - (n - 1) * 0.5) > 0.6:
		return "the view from above should pick a middle frame, got %s" % top
	for side in [Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-0.6, 0, -0.8)]:
		var f := TreeOcta.nearest(side)
		if not (f.x in [0, n - 1] or f.y in [0, n - 1]):
			return "a side view should pick a horizon (edge) frame, got %s" % f
	for d in [Vector3(0.2, 0.5, 0.3).normalized(), Vector3(-0.9, 0.2, 0.1).normalized(), Vector3(0.05, 0.99, -0.1).normalized()]:
		var sel: Array = TreeOcta.select(d)
		var sum := 0.0
		for f in sel:
			if f[2] < -1e-6 or f[0] < 0 or f[0] >= n or f[1] < 0 or f[1] >= n:
				return "bad frame %s for %s" % [f, d]
			if absf(f[0] - sel[0][0]) > 1 or absf(f[1] - sel[0][1]) > 1:
				return "frames %s are not neighbours" % [sel]
			sum += f[2]
		if absf(sum - 1.0) > 1e-5:
			return "weights sum to %.4f" % sum
		if Vector2i(sel[0][0], sel[0][1]).distance_to(TreeOcta.nearest(d)) > 1.5:
			return "the heaviest frame should be next to the nearest one"
	return ""


func test_octa_basis_is_smooth_and_right_handed() -> String:
	var n := TreeOcta.N
	for j in n:
		for i in n:
			var d := TreeOcta.frame_dir(i, j)
			var ax: Array = TreeOcta.basis(d)
			var r: Vector3 = ax[0]
			var u: Vector3 = ax[1]
			if absf(r.length() - 1.0) > 1e-4 or absf(u.length() - 1.0) > 1e-4 or absf(r.dot(u)) > 1e-4 or r.cross(u).distance_to(d) > 1e-4:
				return "frame (%d, %d) axes are not an orthonormal right-handed set" % [i, j]
			if i + 1 < n:
				var r2: Vector3 = TreeOcta.basis(TreeOcta.frame_dir(i + 1, j))[0]
				if rad_to_deg(r.angle_to(r2)) > 35.0:
					return "image axes jump %.0f deg between frames (%d, %d) and (%d, %d)" % [rad_to_deg(r.angle_to(r2)), i, j, i + 1, j]
	var side: Array = TreeOcta.basis(Vector3(0, 0, 1))
	return "" if (side[1] as Vector3).distance_to(Vector3.UP) < 1e-4 else "the side view from +z should be upright"


func test_octa_shader_twin_matches() -> String:
	var src := FileAccess.get_file_as_string("res://world/tree_octa.gdshaderinc")
	if not src.contains("const float OCTA_N = %d.0;" % TreeOcta.N):
		return "tree_octa.gdshaderinc must use N = %d like TreeOcta" % TreeOcta.N
	for k in ["right = vec3(1.0 - d.x * d.x * k, -d.x, -d.x * d.z * k);", "up = vec3(d.x * d.z * k, d.z, d.z * d.z * k - 1.0);",
			"return vec2(p.x + p.y, p.x - p.y);"]:
		if not src.contains(k):
			return "tree_octa.gdshaderinc lost '%s' (TreeOcta twin)" % k
	return ""


func test_lod_ranges_per_preset() -> String:
	var last_px := 0
	for p in Graphics.ORDER:
		var s: Dictionary = Graphics.PRESETS[p]
		var q := TreeQuality.of(p)
		var detail: float = s.tree_lod * q.detail
		if p == "low" and (s.tree_lod != 0.0 or detail != 0.0):
			return "Low draws impostors only"
		if detail > s.tree_lod * 0.5 or s.tree_lod >= s.trees:
			return "%s: detail %.0f m, near %.0f m, impostors %.0f m are out of order" % [p, detail, s.tree_lod, s.trees]
		if q.atlas_px < last_px:
			return "the atlas frame should not shrink with a higher preset (%s)" % p
		last_px = q.atlas_px
		if q.blend != (s.renderer == "forward_plus"):
			return "%s: frame blending should be on exactly on the Forward+ presets" % p
	var tr := Trees.new()
	TreeQuality.apply(tr, Graphics.PRESETS["ultra"], "ultra")
	var ok: bool = tr.atlas_px == TreeQuality.of("ultra").atlas_px and tr.blend_frames and absf(tr.detail_radius - 60.0) < 0.01 and tr.lod_radius == 150.0
	tr.free()
	return "" if ok else "TreeQuality.apply did not set the Ultra numbers on Trees"


func test_mesh_lod_switch_has_hysteresis() -> String:
	if TreeLod.mesh_lod(10.0, 60.0, 1) != 0 or TreeLod.mesh_lod(100.0, 60.0, 0) != 1:
		return "near cells draw LOD0, far ones LOD1"
	if TreeLod.mesh_lod(60.0, 60.0, 0) != 0 or TreeLod.mesh_lod(60.0, 60.0, 1) != 1:
		return "inside the band the cell keeps its LOD"
	if TreeLod.cell_distance(Vector2(40, 40), Vector2i(0, 0)) != 0.0 or absf(TreeLod.cell_distance(Vector2(-30, 40), Vector2i(0, 0)) - 30.0) > 1e-4:
		return "cell distance is to the nearest point of the cell"
	# LOD0 detail is gone (fully shrunk) before the cell can switch: shader shrinks between 0.7 and 1.0 x detail_r
	var lod0 := TreeMeshes.build(TreeSpecies.BROADLEAF, 0).surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0] as PackedFloat32Array
	var lod1 := TreeMeshes.build(TreeSpecies.BROADLEAF, 1).surface_get_arrays(0)[Mesh.ARRAY_CUSTOM0] as PackedFloat32Array
	var marked := [0, 0]
	for k in range(3, lod0.size(), 4):
		marked[0] += 1 if lod0[k] > 0.5 else 0
	for k in range(3, lod1.size(), 4):
		marked[1] += 1 if lod1[k] > 0.5 else 0
	return "" if marked[0] > 0 and marked[1] == 0 else "LOD0 must mark its detail (%d) and LOD1 have none (%d)" % marked


func test_trees_stay_off_roads_runways_and_water() -> String:
	for j in 60:
		for i in 60:
			if not TreeSampler.cell_tree(i, j, 0, Trees.PX, 1.4).is_empty() or not TreeSampler.cell_tree(i, j, 255, Trees.PX, 1.4).is_empty():
				return "cell %d,%d: a tree on land class 0 (roads, runways, aprons, buildings) or water" % [i, j]
	var rw = Paths.load_json("runways.json")
	if rw == null:
		return ""  # no generated data: the rule above is the whole check
	TreeClear.ensure_loaded()
	var cache := TerrainTileCache.new()
	var smp := TreeSampler.new(cache)
	var tm := cache.tmeta
	var checked := 0
	for r in (rw if rw is Array else rw.get("runways", [])):
		var a := Vector2(r.ends[0].x, r.ends[0].y)
		var b := Vector2(r.ends[1].x, r.ends[1].y)
		var hw := float(r.width) * 0.5
		var dir := (b - a).normalized()
		var side := Vector2(dir.y, -dir.x)
		for t in range(0, int(a.distance_to(b)), 25):
			for o in range(-int(hw) - 10, int(hw) + 11, 10):
				var p := a + dir * t + side * o
				var ci := floori(p.x / Trees.PX)
				var cj := floori(p.y / Trees.PX)
				var src := tm.tex_source(0, floori(p.x / tm.tile_size_m), floori(p.y / tm.tile_size_m), TerrainMeta.HAS_LC)
				if src == TerrainMeta.NONE:
					continue
				var lc := smp._mask_bytes(smp._lc, "lc", src)
				if lc.is_empty():
					continue
				var ss := tm.level_size(src.x)
				var c := Vector2((ci + 0.5) * Trees.PX, (cj + 0.5) * Trees.PX)
				var px := clampi(int((c.x - src.y * ss) / ss * TerrainTileCache.IMG_N), 0, TerrainTileCache.IMG_N - 1)
				var py := clampi(int((1.0 - (c.y - src.z * ss) / ss) * TerrainTileCache.IMG_N), 0, TerrainTileCache.IMG_N - 1)
				var tr := TreeSampler.cell_tree(ci, cj, lc[py * TerrainTileCache.IMG_N + px], Trees.PX, 1.4)
				checked += 1
				if not tr.is_empty() and not TreeClear.blocked(tr[0], tr[1]) and absf((Vector2(tr[0], tr[1]) - a).dot(side)) < hw:
					return "%s: a tree stands on the runway at (%.0f, %.0f)" % [r.airport, tr[0], tr[1]]
	if checked == 0 and not rw.is_empty():
		return "no runway point had a land-class tile"
	TreeClear.add(Vector2(0, 0), Vector2(100, 0), 10.0)  # the rule itself: a trunk on a ribbon is refused, beside it not
	var ok := TreeClear.blocked(50.0, 5.0) and not TreeClear.blocked(50.0, 40.0)
	TreeClear.clear()  # drop the test ribbon (reloaded from the data on next use)
	return "" if ok else "TreeClear does not keep the ribbon clear"


func test_trees_do_not_move_at_an_origin_shift() -> String:
	var keep := FloatingOrigin.origin
	var tr := Trees.new()
	var lod := TreeLod.new()
	var mi := MultiMeshInstance3D.new()
	var mi2 := MultiMeshInstance3D.new()
	tr._chunks[Vector2i(3, -2)] = mi
	tr._place(mi, Vector2i(3, -2))
	lod._cells[Vector2i(-7, 4)] = [mi2]
	lod._place(mi2, Vector2i(-7, 4))
	var w1 := FloatingOrigin.to_world(mi.position)
	var w2 := FloatingOrigin.to_world(mi2.position)
	FloatingOrigin.set_origin(keep + Vector2(5000.0, -5000.0))
	tr._reposition()
	lod._reposition()
	var err := ""
	if FloatingOrigin.to_world(mi.position).distance_to(w1) > 1e-3 or FloatingOrigin.to_world(mi2.position).distance_to(w2) > 1e-3:
		err = "a tree chunk or near-tree cell moved in the world at the origin shift"
	FloatingOrigin.set_origin(keep)
	for p in ["res://world/tree.gdshader", "res://world/tree_mesh.gdshader"]:
		var src := FileAccess.get_file_as_string(p)
		if src.contains("wp.x * 0.05") or src.contains("wp.z * 0.07"):
			err = "%s phases its sway by the render position: it would jump at an origin shift" % p
	mi.free()
	mi2.free()
	tr.free()
	lod.free()
	return err


func test_every_tree_shader_bends_with_the_curvature() -> String:
	var found := 0
	for f in DirAccess.get_files_at("res://world"):
		if not f.begins_with("tree") or not f.ends_with(".gdshader") or f == "tree_bake.gdshader":
			continue  # the bake draws in its own world at startup, never in the scene
		found += 1
		var p := "res://world/" + f
		var src := FileAccess.get_file_as_string(p)
		if not Curvature.SHADERS.has(p) or not src.contains("curvature.gdshaderinc") or not src.contains("curve_drop("):
			return "%s draws trees in the world but is not bent with the curvature" % p
	return "" if found >= 2 else "expected the impostor and near-mesh shaders"


func test_tree_budget_per_preset() -> String:
	var last := {}
	for p in Graphics.ORDER:
		var b := TreeQuality.budget(p)
		if not last.is_empty() and (b.impostors < last.impostors or b.near_tris < last.near_tris):
			return "%s costs less than the preset below it: %s vs %s" % [p, b, last]
		last = b
	var ultra := TreeQuality.budget("ultra")
	var old_tris := PI * 150.0 * 150.0 * 0.8 * 1.2 / 100.0 * 600.0  # 4 lumpy species, ~600 triangles each
	if ultra.near_tris > old_tris:
		return "Ultra near-mesh triangles %d exceed the old budget %d" % [ultra.near_tris, old_tris]
	if TreeQuality.budget("low").near_tris != 0:
		return "Low draws no near meshes"
	# atlas memory without any block compression (the worst case): about the old 11 MB on Low / Medium
	for lim in [["low", 11.5], ["medium", 14.0], ["high", 25.0], ["max", 25.0]]:
		if TreeQuality.budget(lim[0]).atlas_mb > lim[1]:
			return "%s atlas %.1f MB exceeds %.1f MB" % [lim[0], TreeQuality.budget(lim[0]).atlas_mb, lim[1]]
	return ""


func test_low_and_medium_budgets() -> String:
	var low := TreeQuality.budget("low")
	var med := TreeQuality.budget("medium")
	var old_low_impostors := int(PI * 1200.0 * 1200.0 * 0.8 * 0.5 / 100.0)
	if low.impostors > old_low_impostors or TreeQuality.of("low").blend or TreeQuality.of("medium").blend:
		return "Low keeps the old impostor count (%d) and both take one frame: %s" % [old_low_impostors, low]
	var old_med_tris := PI * 90.0 * 90.0 * 0.8 * 0.8 / 100.0 * 600.0
	if med.near_tris > old_med_tris:
		return "Medium near-mesh triangles %d exceed the old %d" % [med.near_tris, old_med_tris]
	return ""


func test_season_dryness_follows_the_monsoon() -> String:
	if TreeLook.dryness(225.0) > 0.15 or TreeLook.dryness(120.0) < 0.9:
		return "August should be green (%.2f) and late April dry (%.2f)" % [TreeLook.dryness(225.0), TreeLook.dryness(120.0)]
	if absf(TreeLook.dryness(0.0) - TreeLook.dryness(365.0)) > 1e-4:
		return "the year should wrap"
	for d in 365:
		if absf(TreeLook.dryness(d + 1.0) - TreeLook.dryness(float(d))) > 0.08:
			return "dryness jumps at day %d" % d
	var src := FileAccess.get_file_as_string("res://world/tree_tint.gdshaderinc")
	var nums := []
	for v in TreeLook.DRY_RESPONSE:
		nums.append(str(v))
	return "" if src.contains("float[5](%s)" % ", ".join(nums)) else "tree_tint.gdshaderinc dry response differs from TreeLook.DRY_RESPONSE"
