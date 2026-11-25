extends Node
## Speed fix 5: runways and taxiways are built only near the aircraft (world/airport_builder.gd, airport_groups.gd), the
## taxiways of an airport are one merged mesh with one shared material (airport_cut.gd, UV2 = width, edge lines).
## The data tests use made-up airports; the builder tests need data/processed (skipped, passing, without it).

const FAR_ICAO := "VOCI"  # Kochi, ~950 km from Mumbai

var _qt: TerrainQuadtree
var _ab: AirportBuilder
var _vis_detail := 1.0
var _vis_on := true


func teardown() -> void:
	if _ab:
		_ab.free()
		_ab = null
	if _qt:
		_qt.free()
		_qt = null
	VisRanges.detail = _vis_detail
	VisRanges.enabled = _vis_on
	FloatingOrigin.set_origin(Vector2.ZERO)


func _have_data() -> bool:
	return FileAccess.file_exists(Paths.data("terrain/meta.json")) and FileAccess.file_exists(Paths.data("runways.json"))


## A builder on the real data, not built yet (wait: every airport now).
func _builder(wait := false) -> AirportBuilder:
	_vis_detail = VisRanges.detail
	_vis_on = VisRanges.enabled
	VisRanges.enabled = true
	VisRanges.detail = 1.0
	_qt = TerrainQuadtree.new()
	_qt.cache = TerrainTileCache.new()
	_ab = AirportBuilder.new()
	add_child(_ab)
	_ab.build(_qt, wait)
	return _ab


func _rw(icao: String) -> Dictionary:
	for r in _ab.data.runways:
		if r.airport == icao:
			return r
	return {}


func _at(icao: String) -> Vector3:
	var g := _ab.group(icao)
	return Vector3(g.centre.x, g.centre.y, g.h)


# --- made-up data: groups, ranges, the plan ---

const FAKE := {
	"runways": [
		{"airport": "AAAA", "width": 45.0, "length": 3000.0, "ends": [{"ident": "09", "x": 0.0, "y": 0.0, "h": 5.0}, {"ident": "27", "x": 3000.0, "y": 0.0, "h": 5.0}]},
		{"airport": "BBBB", "width": 20.0, "length": 900.0, "ends": [{"ident": "04", "x": 100000.0, "y": 0.0, "h": 50.0}, {"ident": "22", "x": 100600.0, "y": 600.0, "h": 50.0}]},
	],
	"taxiways": [
		{"width": 23.0, "width_known": true, "pts": [[200.0, 100.0], [200.0, 10.0], [200.0, 0.0]]},
		{"width": 15.0, "width_known": false, "pts": [[900.0, 100.0], [900.0, 40.0]]},
		{"width": 12.0, "width_known": true, "pts": [[100100.0, 100.0], [100100.0, 10.0]]},
		{"width": 15.0, "width_known": false, "pts": [[50000.0, 50000.0], [50100.0, 50000.0]]},
	],
}


func test_taxiways_go_to_the_nearest_airport_and_lone_ones_to_a_cell() -> String:
	var gs := AirportGroups.make(FAKE)
	var by := {}
	for g in gs:
		by[g.key] = g
	if by.size() != 3:
		return "AAAA, BBBB and one cell group expected, got %s" % [by.keys()]
	if by.AAAA.taxis.size() != 2 or by.BBBB.taxis.size() != 1:
		return "taxiways per airport: AAAA %d (want 2), BBBB %d (want 1)" % [by.AAAA.taxis.size(), by.BBBB.taxis.size()]
	var cell := ""
	for k in by:
		if k.begins_with("cell:"):
			cell = k
	if cell == "" or by[cell].taxis.size() != 1 or not by[cell].runways.is_empty():
		return "a taxiway 70 km from every runway forms a cell group of its own"
	if by.AAAA.leads.size() != 1:
		return "the taxiway ending on AAAA's runway gives one lead-on line, got %d" % by.AAAA.leads.size()
	if absf(by.AAAA.h - 5.0) > 0.01 or by.AAAA.radius < 1500.0:
		return "AAAA's circle should cover the runway (radius %.0f) at its height (%.1f)" % [by.AAAA.radius, by.AAAA.h]
	return ""


func test_range_follows_the_runway_size_and_the_preset() -> String:
	var gs := AirportGroups.make(FAKE)
	var big: Dictionary = gs[0] if gs[0].key == "AAAA" else gs[1]
	var small: Dictionary = gs[1] if gs[0].key == "AAAA" else gs[0]
	var d0 := VisRanges.detail
	var on := VisRanges.enabled
	VisRanges.enabled = true
	VisRanges.detail = 1.0
	var rb := AirportGroups.range_m(big)
	var rs := AirportGroups.range_m(small)
	VisRanges.detail = 0.75
	var rb_low := AirportGroups.range_m(big)
	VisRanges.enabled = false
	var off := AirportGroups.range_m(big)
	VisRanges.detail = d0
	VisRanges.enabled = on
	var want := VisRanges.end_for(sqrt(3000.0 * 45.0))
	if absf(rb - want) > 1.0 or rb < 30000.0:
		return "a 3000 x 45 m runway is drawn from %.0f m, want its 3 px distance %.0f (tens of km)" % [rb, want]
	if rs >= rb:
		return "a 900 x 20 m airstrip (%.0f m) should be built nearer than the big airport (%.0f m)" % [rs, rb]
	if absf(rb_low - rb * 0.75) > 1.0:
		return "Low's detail 0.75 should shrink the range to %.0f, got %.0f" % [rb * 0.75, rb_low]
	if off != 0.0:
		return "--no-vis-ranges must mean always built (range 0), got %.0f" % off
	return ""


func test_plan_builds_nearest_first_and_frees_only_beyond_the_hysteresis() -> String:
	var ranges := [100.0, 100.0, 100.0, 100.0, 0.0]
	var ex := [90.0, 30.0, 105.0, 135.0, 1.0e6]
	var p := AirportGroups.plan(ex, ranges, [false, false, true, true, false])
	if p.build != [1, 0, 4]:
		return "wanted and unbuilt: nearest first, a range of 0 always wanted: %s" % [p.build]
	if p.free != [3]:
		return "built at 105 m (range 100, x1.3 = 130) stays, at 135 m goes: %s" % [p.free]
	var q := AirportGroups.plan([100.5], [100.0], [false])
	if not q.build.is_empty():
		return "not built yet and outside the range: nothing to build"
	return ""


# --- the builder on the real data ---

func test_only_the_start_airport_has_meshes_at_the_first_frame() -> String:
	if not _have_data():
		return ""
	var ab := _builder()
	ab.focus(_at("VABB"))
	var built := ab.built_keys()
	if not built.has("VABB"):
		return "the start airport must be built before the first frame (built: %s)" % [built]
	if built.has(FAR_ICAO) or ab.runway_material(TouchdownMarks.runway_key(_rw(FAR_ICAO))) != null:
		return "%s is 950 km away and must have no meshes" % FAR_ICAO
	if built.size() >= ab._groups.size():
		return "a start at Mumbai built all %d airports" % built.size()
	if ab.runway_material(TouchdownMarks.runway_key(_rw("VABB"))) == null:
		return "TouchdownMarks finds the runway of the airport you are at through runway_material()"
	if ab.busy() or ab.progress() < 1.0:
		return "the loader must not wait once the near airports are built"
	return ""


func test_a_far_airport_appears_when_approached_and_goes_when_far_with_hysteresis() -> String:
	if not _have_data():
		return ""
	var ab := _builder()
	ab.focus(_at("VABB"))
	var g := ab.group("VABB")
	var rng := AirportGroups.range_m(g)
	var ground: float = g.h
	# just inside the range: built (sync_all stands for the worker having caught up)
	var cam := Vector3(g.centre.x + g.radius + rng * 0.9, g.centre.y, ground)
	ab.update(cam, true)
	if not ab.built_keys().has("VABB"):
		return "VABB should stay built 0.9 x range away"
	cam.x = g.centre.x + g.radius + rng * 1.15
	ab.update(cam, true)
	if not ab.built_keys().has("VABB"):
		return "between range and range x 1.3 nothing is freed (hysteresis), or it flickers at the boundary"
	cam.x = g.centre.x + g.radius + rng * 1.4
	ab.update(cam, true)
	if ab.built_keys().has("VABB"):
		return "VABB must be freed beyond 1.3 x range"
	if ab.runway_material(TouchdownMarks.runway_key(_rw("VABB"))) != null:
		return "a freed airport keeps its runway materials"
	ab.focus(_at(FAR_ICAO))  # fly to Kochi
	if not ab.built_keys().has(FAR_ICAO) or ab.built_keys().has("VABB"):
		return "approaching %s builds it (and VABB stays gone): %s" % [FAR_ICAO, ab.built_keys()]
	ab.update(Vector3(g.centre.x + g.radius + rng * 0.9, g.centre.y, ground), true)
	if not ab.built_keys().has("VABB"):
		return "VABB is built again when approached"
	return ""


func test_far_groups_stream_in_a_few_nodes_a_frame_nearest_first() -> String:
	if not _have_data():
		return ""
	var ab := _builder()
	var here := _at("VABB")
	FloatingOrigin.set_origin(Vector2(here.x, here.y))  # no camera in the test: _process checks from the origin
	ab.focus(here)
	var near := ab.built_keys().size()
	var want := ab._want.duplicate()
	if want.is_empty():
		return "airports farther than 15 km but within their range should be queued for the worker (the Mumbai region has several)"
	var first: String = ab._groups[want[0]].key
	var t0 := Time.get_ticks_msec()
	var biggest := 0
	var before := ab._items.size()
	while ab._stream.inflight >= 0 or not ab._spawn.is_empty() or ab._want.any(func(i): return ab._state[i] == 0):
		ab._process(0.016)
		biggest = maxi(biggest, ab._items.size() - before)
		before = ab._items.size()
		OS.delay_msec(2)
		if Time.get_ticks_msec() - t0 > 60000:
			return "the worker never finished"
	if ab.built_keys().size() <= near or not ab.built_keys().has(first):
		return "the nearest queued airport %s should be built after the worker ran (built %s)" % [first, ab.built_keys()]
	if biggest > AirportBuilder.NODES_PER_FRAME:
		return "%d nodes in one frame; the budget is %d" % [biggest, AirportBuilder.NODES_PER_FRAME]
	return ""


func test_freed_runway_gets_its_tyre_marks_back_when_built_again() -> String:
	if not _have_data():
		return ""
	var ab := _builder()
	ab.focus(_at("VABB"))
	var r := _rw("VABB")
	var key := TouchdownMarks.runway_key(r)
	var marks := TouchdownMarks.new()
	marks.airports = ab
	var a := Vector2(r.ends[0].x, r.ends[0].y)
	var u := (Vector2(r.ends[1].x, r.ends[1].y) - a).normalized()
	var p := a + u * 400.0
	marks.add(p.x, p.y, atan2(u.x, u.y), 0.8)
	var mat: ShaderMaterial = ab.runway_material(key)
	if mat == null or int(mat.get_shader_parameter("mark_count")) != 1:
		marks.free()
		return "the touchdown at the airport you are at marks its runway material"
	ab.focus(_at(FAR_ICAO))  # VABB freed
	if ab.runway_material(key) != null:
		marks.free()
		return "VABB's runway should be gone"
	ab.focus(_at("VABB"))  # and back
	var mat2: ShaderMaterial = ab.runway_material(key)
	var ok := mat2 != null and int(mat2.get_shader_parameter("mark_count")) == 1
	marks.free()
	return "" if ok else "the new runway material of a rebuilt runway must carry the saved tyre marks"


func test_a_save_at_another_airport_builds_it_before_drawing() -> String:
	var sit := FileAccess.get_file_as_string("res://core/situation.gd")
	var flight := FileAccess.get_file_as_string("res://world/flight.gd")
	if not sit.contains("apt_rw.focus(enu)"):
		return "Situation.apply must build the runways of the loaded position (AirportBuilder.focus)"
	if not flight.contains("airports.focus(fdm_node.position_enu())"):
		return "flight.gd must build the start airport's runways before the first frame"
	if not FileAccess.get_file_as_string("res://world/touchdown_marks.gd").contains("runway_built"):
		return "TouchdownMarks must re-apply its marks when a runway is built again"
	return ""


func test_taxiways_are_one_mesh_per_airport_with_the_same_coverage() -> String:
	if not _have_data():
		return ""
	var ab := _builder(true)
	var data: Dictionary = ab.data
	var expect := 0.0
	var widths := {}
	for tw in data.taxiways:
		var pts: Array = []
		for p in tw.pts:
			pts.append(Vector2(p[0], p[1]))
		var tris := PackedVector2Array()
		var uvs := PackedVector2Array()
		var w := minf(float(tw.width), 23.0)
		GroundDrape.strip(pts, w, tris, uvs)
		expect += _area(tris)
		widths[snappedf(w, 0.01)] = true
	var got := 0.0
	var taxi_nodes := 0
	var seen := {}
	for it in ab._items:
		var mi: MeshInstance3D = it[0]
		if mi.material_override == ab._taxi_mat:
			taxi_nodes += 1
			var a: Array = mi.mesh.surface_get_arrays(0)
			if a[Mesh.ARRAY_TEX_UV2] == null:
				return "the merged taxiway mesh keeps each ribbon's width in UV2"
			for v in a[Mesh.ARRAY_TEX_UV2]:
				seen[snappedf(v.x, 0.01)] = true
			got += _mesh_area(a)
	var groups_with_taxis := 0
	for g in ab._groups:
		groups_with_taxis += 1 if not g.taxis.is_empty() else 0
	if taxi_nodes != groups_with_taxis:
		return "%d taxiway meshes for %d airports with taxiways: one merged mesh each" % [taxi_nodes, groups_with_taxis]
	if absf(got - expect) > expect * 0.002:
		return "merged taxiway area %.0f m2, the separate ribbons covered %.0f m2" % [got, expect]
	for w in widths:
		if not seen.has(w):
			return "a taxiway width of %.2f m went missing from the merged mesh" % w
	if ab._taxi_mat.render_priority != 0 or ab._lead_mat.render_priority != 0:
		return "taxiway and lead-on materials keep the default draw order (the apron light pools draw over them)"
	return ""


func _area(tris: PackedVector2Array) -> float:
	var s := 0.0
	for i in range(0, tris.size() - 2, 3):
		s += absf((tris[i + 1] - tris[i]).cross(tris[i + 2] - tris[i])) * 0.5
	return s


func _mesh_area(a: Array) -> float:
	var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var s := 0.0
	for k in range(0, ix.size() - 2, 3):
		var p0 := Vector2(vs[ix[k]].x, vs[ix[k]].z)
		s += absf((Vector2(vs[ix[k + 1]].x, vs[ix[k + 1]].z) - p0).cross(Vector2(vs[ix[k + 2]].x, vs[ix[k + 2]].z) - p0)) * 0.5
	return s


func test_a_floating_origin_shift_moves_every_node_with_it() -> String:
	if not _have_data():
		return ""
	var ab := _builder()
	var here := _at("VABB")
	FloatingOrigin.set_origin(Vector2(here.x, here.y))
	ab.focus(here)
	if ab._items.is_empty():
		return "nothing built"
	var before := []
	for it in ab._items:
		before.append((it[0] as MeshInstance3D).position)
	FloatingOrigin.set_origin(Vector2(here.x + 5000.0, here.y - 5000.0))
	for k in ab._items.size():
		var it: Array = ab._items[k]
		var mi: MeshInstance3D = it[0]
		if mi.position.distance_to(FloatingOrigin.to_render(it[1])) > 1e-3:
			return "node %d is not at its anchor after the shift" % k
		if mi.position.distance_to(before[k] + Vector3(-5000.0, 0.0, -5000.0)) > 1e-3:
			return "node %d jumped at the shift (should move by the origin step only)" % k
	return ""
