extends Node
## Graphics Phase 2: draw distances by on-screen size (world/vis_ranges.gd, vis_chunks.gd), far stand-ins for jetways
## (world/jetway_standin.gd), and occlusion culling with run-time occluders (world/occluder_build.gd, occluder_rings.gd,
## occluder_jobs.gd, occlusion_rules.gd, hlod_director.gd).

const DockTest := preload("res://tests/test_jetway_dock.gd")

var _keep_detail := 1.0
var _keep_zoom := 1.0


func _init() -> void:
	_keep_detail = VisRanges.detail
	_keep_zoom = VisRanges.zoom


func teardown() -> void:
	VisRanges.detail = _keep_detail
	VisRanges.zoom = _keep_zoom
	for c in get_children():
		c.free()


func test_vis_range_is_where_an_object_shrinks_to_min_px() -> String:
	for size in [1.0, 3.0, 11.0]:
		var end := VisRanges.end_for(float(size))
		var px: float = size * 540.0 / tan(deg_to_rad(VisRanges.REF_FOV_DEG) * 0.5) / end  # pixels it covers there at 1080p
		if absf(px - VisRanges.MIN_PX) > 1e-3:
			return "%.0f m object: %.2f px at its range, want %.1f" % [size, px, VisRanges.MIN_PX]
	var jet := VisRanges.size_of(AABB(Vector3.ZERO, Vector3(30.0, 4.0, 3.5)))
	if absf(jet - sqrt(120.0)) > 1e-3:
		return "a 30 x 4 m jetway side should count as sqrt(120) m, got %.2f" % jet
	if VisRanges.end_for(jet) < 2000.0 or VisRanges.end_for(jet) > 5000.0:
		return "a jetway should be drawn to a few km on High (%.0f m)" % VisRanges.end_for(jet)
	return ""


func test_vis_ranges_scale_with_the_preset() -> String:
	var last := 0.0
	for p in Graphics.ORDER:
		var d := VisRanges.detail_for(float(Graphics.PRESETS[p].lod_k))
		if d <= last:
			return "%s: draw distances must grow with the preset (%.2f after %.2f)" % [p, d, last]
		last = d
	if VisRanges.detail_for(Graphics.PRESETS.low.lod_k) >= 1.0 or absf(VisRanges.detail_for(Graphics.PRESETS.high.lod_k) - 1.0) > 1e-6:
		return "Low must be shorter than High, and High is the base"
	var mi := MeshInstance3D.new()
	add_child(mi)
	VisRanges.zoom = 1.0
	VisRanges.set_range(mi, 1000.0)
	VisRanges.set_detail(get_tree(), Graphics.PRESETS.low.lod_k)
	var low := mi.visibility_range_end
	VisRanges.set_detail(get_tree(), Graphics.PRESETS.max.lod_k)
	var top := mi.visibility_range_end
	if not (low < 1000.0 and top > 1000.0):
		return "a 1000 m base range on Low / Max: %.0f / %.0f m (want shorter / longer)" % [low, top]
	if mi.visibility_range_fade_mode != GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF or mi.visibility_range_end_margin <= 0.0:
		return "ranged objects must fade out, not pop"
	return ""


func test_graphics_preset_change_reaches_the_ranges() -> String:
	var keep := Graphics.preset
	var mi := MeshInstance3D.new()
	add_child(mi)
	VisRanges.zoom = 1.0
	VisRanges.set_range(mi, 1000.0)
	Graphics.apply_to_scene(self)  # the preset hook: VisRanges.set_detail(lod_k)
	var want := 1000.0 * VisRanges.detail_for(float(Graphics.PRESETS[keep].lod_k))
	var got := mi.visibility_range_end
	return "" if absf(got - want) < 1e-3 else "preset %s: range %.0f m, want %.0f" % [keep, got, want]


func test_zoomed_camera_stretches_ranges() -> String:
	if VisRanges.zoom_for(60.0) != 1.0 or VisRanges.zoom_for(75.0) != 1.0:
		return "no stretch at or wider than the reference view"
	var tele := VisRanges.zoom_for(10.0)
	var need := tan(deg_to_rad(30.0)) / tan(deg_to_rad(5.0))
	if tele < need or tele > need * VisRanges.ZOOM_STEP:
		return "a 10 deg telephoto must stretch ranges by at least %.1f (got %.1f)" % [need, tele]
	return ""


func test_tag_tree_ranges_dressing_by_size_and_spares_windsocks() -> String:
	var root := Node3D.new()
	add_child(root)
	var gpu := GroundVehicles.make("gpu", 1.0, 0.3, false)
	root.add_child(gpu)
	var sock := MeshInstance3D.new()
	sock.mesh = CylinderMesh.new()
	sock.set_meta("no_vis_range", true)
	root.add_child(sock)
	VisRanges.detail = 1.0
	VisRanges.zoom = 1.0
	VisRanges.tag_tree(root)
	var body := gpu.get_node("Body") as GeometryInstance3D
	var ground := gpu.get_node("Ground") as GeometryInstance3D
	if body.visibility_range_end <= 0.0 or body.visibility_range_end >= 4000.0:
		return "a GPU should be ranged by its size (well under its old 4 km): %.0f m" % body.visibility_range_end
	if ground.visibility_range_end > 450.0 + 1e-3:
		return "a shorter range its builder set (ground decal 450 m) must stand: %.0f m" % ground.visibility_range_end
	return "" if sock.visibility_range_end == 0.0 else "windsocks are always drawn"


func test_vis_chunks_give_each_cell_its_own_range() -> String:
	var lights := []
	for i in 12:
		lights.append({"p": Vector2(i * 110.0, i * 20.0), "h": 25.0 if i % 2 == 0 else 12.0, "kind": "mast" if i % 2 == 0 else "pole"})
	var groups := VisChunks.cells(lights, func(m): return m.p)
	var n := 0
	for g in groups:
		n += g.size()
	if groups.size() < 3 or n != 12:
		return "1.3 km of masts should split into several 400 m cells with every mast kept (%d cells, %d masts)" % [groups.size(), n]
	var size := VisChunks.mast_size(lights)
	if absf(size - sqrt(25.0 * 0.84)) > 1e-4:
		return "the biggest mast decides a cell's size (%.2f)" % size
	return "" if VisChunks.cell_range(size) > VisRanges.end_for(size) + 250.0 else "a cell's range must cover its farthest mast"


## A jetway away from the player's aircraft hands its parts to a one-box stand-in; a jetway out at the player's
## aircraft is always drawn in full: no range, no stand-in, at any preset.
func test_jetway_at_the_aircraft_is_always_drawn() -> String:
	var def := DockTest.a320()
	var host := Node3D.new()
	add_child(host)
	var st := DockTest._gate(700.0, 700.0, 90.0)
	var far_st := DockTest._gate(-900.0, 300.0, 90.0)
	var dock := _rig(host, Vector2(680.0, 724.0), Vector2(700.0, 702.0), st, def)
	var idle := _rig(host, Vector2(-920.0, 324.0), Vector2(-900.0, 302.0), far_st, def)
	var cg: Vector2 = dock.cands[0].cg
	Props.set_v("fdm/position_enu", Vector3(cg.x, cg.y, 0.0))
	Props.set_v("fdm/groundspeed_mps", 0.0)
	dock.start(null, "0", 0.0)
	idle.start(null, "1", 0.0)
	Props.set_v("fdm/position_enu", Vector3.ZERO)
	var s_dock := JetwayStandin.attach(dock)
	var s_idle := JetwayStandin.attach(idle)
	if s_dock == null or s_idle == null:
		return "every jetway gets a stand-in"
	if not s_idle.visible or s_idle.visibility_range_begin <= 0.0 or s_idle.visibility_range_end <= s_idle.visibility_range_begin:
		return "an idle jetway's box: drawn from %.0f to %.0f m" % [s_idle.visibility_range_begin, s_idle.visibility_range_end]
	for gi in idle.find_children("*", "GeometryInstance3D", true, false):
		if gi != s_idle and (gi as GeometryInstance3D).visibility_parent.is_empty():
			return "an idle jetway's part %s should hand over to the stand-in" % gi.name
	for p in ["low", "max"]:
		VisRanges.set_detail(get_tree(), Graphics.PRESETS[p].lod_k)
		if s_dock.visible:
			return "%s: the docked jetway's stand-in must be off" % p
		for gi in dock.find_children("*", "GeometryInstance3D", true, false):
			var g := gi as GeometryInstance3D
			if g != s_dock and (not g.visibility_parent.is_empty() or g.visibility_range_end > 0.0 or g.visibility_range_begin > 0.0):
				return "%s: docked jetway part %s has a draw distance" % [p, g.name]
	return ""


func _rig(host: Node, terminal: Vector2, cab: Vector2, st: Dictionary, def: AircraftDef) -> JetwayRig:
	var dy := func(_t: Vector2, _tip: Vector2) -> float: return 3.65 - JetwayPose.FLOOR_Y
	var rig := JetwayRig.new()
	rig.setup((load("res://world/models/vehicles/jetway.glb") as PackedScene).instantiate(), terminal, cab,
		JetwayDocks.candidates(0, [{"terminal": terminal, "cab": cab}], [st], dy, def))
	rig.position = Vector3(terminal.x, 0.0, -terminal.y)
	host.add_child(rig)
	return rig
