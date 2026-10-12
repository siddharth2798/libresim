extends RefCounted
## Collisions with trees, buildings, terminals, jetways, vehicles (fdm/obstacle_*.gd, world/obstacle_registry.gd):
## synthetic solids in the real FDM. The same checks run on the real world in tests/obstacle_probe.gd.

const KT := 0.514444
const GROUP := "test"


func _world(recs: Array) -> Callable:
	return func(e: float, n: float, r: float, _lo: float, _hi: float) -> Array:
		var out := []
		for o in recs:
			if o.lo.x <= e + r and o.hi.x >= e - r and o.lo.y <= n + r and o.hi.y >= n - r:
				out.append(o)
		return out


func _wall(e0: float, e1: float, n0: float, n1: float, top: float, soft := false, label := "a building") -> Dictionary:
	return ObstacleShapes.poly(PackedVector2Array([Vector2(e0, n0), Vector2(e1, n0), Vector2(e1, n1), Vector2(e0, n1)]), -5.0, top, label, soft)


## Level flight north (heading 0) from (e, 0) at alt m and kias.
func _fly(recs: Array, alt: float, kias := 80.0, e := 0.0, secs := 12.0) -> FDM:
	var h := FdmHarness.new()
	h.f.obstacles = _world(recs)
	h.f.set_airborne(0.0, e, alt, 0.0, kias * KT, 0.0)
	h.mode = "alt"
	h.target_alt = alt
	h.run(secs, func(): return h.f.damage.crashed)
	return h.f


## On the ground (heading north), gentle throttle, from (e, 0): taxi until something is hit.
func _taxi(recs: Array, e := 0.0, secs := 40.0, throttle := 0.3) -> FDM:
	var h := FdmHarness.new()
	var f := h.f
	f.obstacles = _world(recs)
	f.set_on_ground(0.0, e, 0.0)
	f.prop.rpm = 800.0
	f.engine.running = true
	f.engine.throttle = throttle
	h.mode = "none"
	h.run(secs, func(): return f.damage.crashed)
	return f


func _box_tris(x0: float, x1: float, y0: float, y1: float, z0: float, z1: float) -> PackedVector3Array:
	var c := [Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x0, y1, z0),
		Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1)]
	var out := PackedVector3Array()
	for q in [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]:
		for i in [0, 1, 2, 0, 2, 3]:
			out.append(c[q[i]])
	return out


func test_flying_into_trees_is_a_crash() -> String:
	var tree := ObstacleShapes.disc(Vector2(0, 400), 3.0, 0.0, 12.0, "trees", true)
	var f := _fly([tree], 8.0)
	if not f.damage.crashed or not f.damage.crash_reason.contains("hit trees"):
		return "no tree crash: %s" % f.damage.crash_reason
	if absf(f.pos_n - 400.0) > 12.0:
		return "crashed %.0f m from the tree" % (f.pos_n - 400.0)
	if f.damage.crash_reason.contains("(taxiing)") or not f.damage.crash_reason.contains(" kt"):
		return "reason text: " + f.damage.crash_reason
	return ""


func test_overflying_trees_and_buildings_is_not() -> String:
	var tree := ObstacleShapes.disc(Vector2(0, 400), 3.0, 0.0, 12.0, "trees", true)
	var f := _fly([tree, _wall(-20, 20, 600, 640, 30.0)], 45.0)
	return "" if not f.damage.crashed else "crashed 33 m above everything: " + f.damage.crash_reason


func test_flying_into_a_building_is_a_crash() -> String:
	var f := _fly([_wall(-20, 20, 400, 440, 30.0, true)], 20.0)
	if not f.damage.crashed or not f.damage.crash_reason.contains("hit a building"):
		return "no building crash: %s" % f.damage.crash_reason
	return ""


func test_roof_skim_hits_the_roof() -> String:
	# CG 0.2 m over a 20 m roof: the wheels are below it
	var f := _fly([_wall(-20, 20, 400, 440, 20.0)], 20.2)
	return "" if f.damage.crashed else "skimmed through a roof with the wheels in it"


func test_wing_clips_a_house_between_cg_and_wingtip() -> String:
	# a 4 m house 1..5 m right of the track: CG (0) and tip (5.6) are both outside, the wing is not
	var f := FDM.new()
	f.set_airborne(401.0, 0.0, 6.0, 0.0, 41.0, 0.0)
	f.obstacles = _world([_wall(1, 5, 400, 404, 8.0)])
	var hit := f.obstacle_collision.check(f, true)
	if hit.is_empty() or not hit.part.contains("right wing"):
		return "the wing is inside the house but hit = %s" % [hit]
	var flying := _fly([_wall(1, 5, 400, 404, 8.0)], 6.0)
	return "" if flying.damage.crashed else "flew through a house the wing passes over"


func test_tail_and_fin_are_solid() -> String:
	# parked, with a wall 5.8 .. 8 m behind the CG: only the stabilizer / rudder / fin are inside it
	var f := FDM.new()
	f.set_on_ground(0.0, 0.0, 0.0)
	f.obstacles = _world([_wall(-2, 2, -8, -5.8, 4.0)])
	var hit := f.obstacle_collision.check(f, true)
	if hit.is_empty() or not (hit.part.contains("stabilizer") or hit.part.contains("fin")):
		return "tail inside a wall: %s" % [hit]
	return ""


func test_no_tunnelling_at_vd() -> String:
	var mast := ObstacleShapes.disc(Vector2(0, 600), 0.6, 0.0, 40.0, "a floodlight mast")
	var wall := _wall(-30, 30, 600, 600.5, 40.0)
	for rec in [mast, wall]:
		var f := _fly([rec], 15.0, 180.0, 0.0, 12.0)
		if not f.damage.crashed or f.pos_n > 625.0 or not f.damage.crash_reason.contains(" hit "):
			return "185 kt through %s (crashed %s at n=%.0f: %s)" % [rec.label, f.damage.crashed, f.pos_n, f.damage.crash_reason]
	return ""


func test_tall_obstacle_beside_a_cliff_is_hit() -> String:
	# ground 1000 m below: the old gate (agl < 400 m) never looked
	var h := FdmHarness.new()
	h.f.ground_height = func(_n: float, _e: float) -> float: return -1000.0
	h.f.obstacles = _world([_wall(-20, 20, 300, 340, 60.0)])
	h.f.set_airborne(0.0, 0.0, 20.0, 0.0, 80.0 * KT, 0.0)
	h.mode = "alt"
	h.target_alt = 20.0
	h.run(10.0, func(): return h.f.damage.crashed)
	return "" if h.f.damage.crashed else "agl gate: flew into a building 1000 m above the ground"


func test_terminal_raster_and_canopy() -> String:
	var verts := _box_tris(-30, 30, 100, 130, 0, 15)  # hall
	verts.append_array(_box_tris(-30, 30, 200, 230, 7.9, 8.1))  # canopy on posts (no walls)
	var rec := SolidGrid.build(verts, 0.0, "the terminal")
	if rec.is_empty():
		return "no raster"
	if ObstacleShapes.segment_hits(Vector3(0, 90, 1), Vector3(0, 99, 1), rec):
		return "hit air in front of the hall"
	if not ObstacleShapes.segment_hits(Vector3(0, 90, 1), Vector3(0, 110, 1), rec):
		return "ground-level segment went into the hall wall"
	if not ObstacleShapes.segment_hits(Vector3(0, 90, 10), Vector3(0, 110, 10), rec):
		return "segment inside the hall not hit"
	if ObstacleShapes.segment_hits(Vector3(0, 190, 1), Vector3(0, 240, 1), rec):
		return "a C172-height segment hit the canopy 8 m up"
	if not ObstacleShapes.segment_hits(Vector3(0, 190, 8), Vector3(0, 240, 8), rec):
		return "the canopy slab itself is not solid"
	return ""


func test_taxiing_into_the_terminal_crashes_low_speed() -> String:
	var rec := SolidGrid.build(_box_tris(-40, 40, 80, 120, 0, 15), 0.0, "the terminal")
	ObstacleRegistry.add(GROUP, rec)
	var f := _taxi([rec])
	ObstacleRegistry.remove_group(GROUP)
	if not f.damage.crashed:
		return "taxied through the terminal (n=%.0f)" % f.pos_n
	var r := f.damage.crash_reason
	if not r.contains("hit the terminal") or not r.ends_with("(taxiing)"):
		return "reason: " + r
	return ""


func test_taxiing_into_a_building_or_vehicle_crashes() -> String:
	var f := _taxi([_wall(-20, 20, 60, 70, 8.0, true)])
	if not f.damage.crashed or not f.damage.crash_reason.contains("(taxiing)"):
		return "no taxi crash into a wall: %s" % f.damage.crash_reason
	var truck := ObstacleShapes.box(Vector2(0, 60), 3.9, 1.2, 0.0, -0.5, 3.0, "a parked vehicle (fuel truck)")
	f = _taxi([truck])
	if not f.damage.crashed or not f.damage.crash_reason.contains("hit a parked vehicle"):
		return "no crash into a parked vehicle: %s" % f.damage.crash_reason
	return ""


func test_nosewheel_alone_stops_at_a_wall() -> String:
	# a 0.25 m kerb-like wall: only the wheels touch it
	var f := _taxi([_wall(-20, 20, 60, 70, 0.25)])
	return "" if f.damage.crashed and f.damage.crash_reason.contains("wheel") else "wheels went through a 0.25 m wall: " + f.damage.crash_reason


func test_parked_aircraft_next_to_a_building_does_not_crash() -> String:
	# stand data: the right wing overlaps a (soft) OSM footprint at spawn, the aircraft sits still ...
	var h := FdmHarness.new()
	var f := h.f
	f.obstacles = _world([_wall(3, 8, -2, 2, 6.0, true)])
	f.set_on_ground(0.0, 0.0, 0.0)
	f.prop.rpm = 800.0
	h.mode = "none"
	h.run(3.0)
	if f.damage.crashed:
		return "parked: " + f.damage.crash_reason
	# ... and leaves it: rolling away is fine
	f.engine.running = true
	f.engine.throttle = 0.3
	h.run(25.0, func(): return f.damage.crashed or f.pos_n > 40.0)
	return "" if not f.damage.crashed else "driving away from the overlap: " + f.damage.crash_reason


func test_taxiway_corridor_forgives_footprints_but_not_terminals() -> String:
	var edge := ObstacleShapes.box(Vector2(0, 100), 150.0, 8.0, 0.0, 0.0, 0.0, "")
	ObstacleRegistry.add_corridor(GROUP, edge)
	var near_wall := _wall(4, 12, 60, 70, 8.0, true)  # an OSM footprint 4 m right of the centreline
	var hard := SolidGrid.build(_box_tris(-3, 3, 150, 160, 0, 10), 0.0, "the terminal")
	var results := []
	for variant in [[[near_wall], true], [[near_wall], false], [[hard], true]]:
		var h := FdmHarness.new()
		var f := h.f
		f.obstacles = _world(variant[0])
		if variant[1]:
			f.in_corridor = ObstacleRegistry.in_corridor
		f.set_on_ground(0.0, 0.0, 0.0)
		f.prop.rpm = 800.0
		f.engine.running = true
		f.engine.throttle = 0.3
		h.mode = "none"
		h.run(40.0, func(): return f.damage.crashed)
		results.append(f.damage.crashed)
	ObstacleRegistry.remove_corridors(GROUP)
	if results != [false, true, true]:
		return "in corridor / outside / terminal in corridor: crashed = %s (want false, true, true)" % [results]
	return ""


func test_ops_corridors_and_dressing() -> String:
	var ops := {"stands": [{"x": 0.0, "y": 0.0, "heading_deg": 0.0, "ref": "1"}],
		"taxi": {"nodes": {"a": [100.0, 100.0], "b": [300.0, 100.0]}, "edges": [["a", "b", "A", 1, "taxiway"]]}}
	OpsCorridors.register("TEST", ops, [])
	var bad := []
	if not ObstacleRegistry.in_corridor(200.0, 100.0):
		bad.append("taxiway centreline")
	if ObstacleRegistry.in_corridor(200.0, 125.0):
		bad.append("25 m beside a taxiway")
	if not ObstacleRegistry.in_corridor(0.0, -20.0):
		bad.append("behind the stand (pushback)")
	if OpsSolids.add_pole(GROUP, Vector2(200.0, 104.0), 0.5, 6.0, 0.0, "a windsock"):
		bad.append("windsock on the taxiway kept")
	if not OpsSolids.add_pole(GROUP, Vector2(200.0, 130.0), 0.5, 6.0, 0.0, "a windsock"):
		bad.append("windsock off the taxiway dropped")
	ObstacleRegistry.remove_group(GROUP)
	OpsCorridors.unregister("TEST")
	if ObstacleRegistry.in_corridor(200.0, 100.0):
		bad.append("corridor not removed")
	return "" if bad.is_empty() else "; ".join(bad)


func test_registry_groups_and_cells() -> String:
	var big := _wall(-200, 200, 10, 20, 5.0)  # spans many 64 m cells
	ObstacleRegistry.add(GROUP, big)
	ObstacleRegistry.add(GROUP, ObstacleShapes.disc(Vector2(500, 500), 2.0, 0.0, 5.0, "trees"))
	var out := []
	ObstacleRegistry.near(0.0, 15.0, 150.0, out)
	var n1 := out.size()
	out.clear()
	ObstacleRegistry.near(-150.0, 15.0, 5.0, out)
	var n2 := out.size()
	ObstacleRegistry.remove_group(GROUP)
	out.clear()
	ObstacleRegistry.near(0.0, 15.0, 150.0, out)
	if n1 != 1 or n2 != 1 or not out.is_empty() or ObstacleRegistry.count(GROUP) != 0:
		return "near() %d %d, after removal %d" % [n1, n2, out.size()]
	return ""


func test_hull_covers_the_airframe() -> String:
	var hull := ObstacleHull.new()
	var f := FDM.new()
	var r := hull.radius(f.mb)
	var pts := hull.world_points(f.mb, Basis(f.q), 0.0, 0.0, 0.0)
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var parts := ", ".join(hull.names)
	for need in ["propeller", "nose", "right wingtip", "left wingtip", "tail fin", "right stabilizer", "right main wheel", "left main wheel", "nose wheel", "wing strut"]:
		if not parts.contains(need):
			return "hull has no '%s'" % need
	if hi.x - lo.x < 11.0 or hi.y - lo.y < 8.0 or r < 6.0 or r > 8.5:
		return "hull span %.1f x length %.1f radius %.1f" % [hi.x - lo.x, hi.y - lo.y, r]
	return ""


func test_building_collision_tiles_and_landmark_footprints() -> String:
	var polys: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(10, 10), Vector2(30, 10), Vector2(30, 30), Vector2(10, 30)]),
		PackedVector2Array([Vector2(500, 500), Vector2(520, 500), Vector2(520, 520), Vector2(500, 520)])]
	var ring := PackedVector2Array([Vector2(490, 490), Vector2(530, 490), Vector2(530, 530), Vector2(490, 530)])
	var tile := BuildingCollision.make_tile(polys, PackedFloat32Array([0.0, 0.0]), PackedFloat32Array([12.0, 20.0]), [ring] as Array[PackedVector2Array])
	var bc := BuildingCollision.new("res://does_not_exist")
	bc.set_tile(Vector2i(0, 0), tile)
	var out := []
	bc.near(20.0, 20.0, 3.0, out)
	var a := out.size()
	out.clear()
	bc.near(510.0, 510.0, 3.0, out)  # drawn as a landmark terminal model: no footprint
	if a != 1 or not out.is_empty() or bc.top_at(20.0, 20.0) != 12.0 or bc.top_at(40.0, 20.0) != -INF or bc.top_at(510.0, 510.0) != -INF:
		return "near %d / landmark %d / tops %.0f %.0f %.0f" % [a, out.size(), bc.top_at(20.0, 20.0), bc.top_at(40.0, 20.0), bc.top_at(510.0, 510.0)]
	return ""


func test_tree_collision_is_the_drawn_tree() -> String:
	# the rule is shared by the renderer and the collision, and works in every quadrant (it used to
	# break for negative east / north: int() truncates toward zero, hashes and positions differed)
	var tq := TerrainQuadtree.new()
	tq.cache = StubCache.new()
	var trees := Trees.new()
	trees.terrain = tq
	var bad := ""
	for cell in [Vector2i(5, 7), Vector2i(-5, 7), Vector2i(5, -7), Vector2i(-6, -9)]:
		var t := TreeSampler.cell_tree(cell.x, cell.y, 200, Trees.PX, 1.0)
		for k in 40:  # find a cell with a tree nearby
			if not t.is_empty():
				break
			cell += Vector2i(1, 0)
			t = TreeSampler.cell_tree(cell.x, cell.y, 200, Trees.PX, 1.0)
		if t.is_empty():
			bad = "no tree found"
			break
		var out := []
		trees.near(t[0], t[1], 1.0, 0.0, out)
		if out.is_empty() or (out[0].c as Vector2).distance_to(Vector2(t[0], t[1])) > 0.01 or absf(out[0].top - (50.0 + t[2] * 0.9)) > 0.01:
			bad = "cell %s: tree at (%.1f, %.1f) not found by Trees.near" % [cell, t[0], t[1]]
			break
	tq.free()
	trees.free()
	return bad


func test_pushback_path_is_continuous_and_ends_sideways() -> String:
	var p0 := Vector2(100.0, 200.0)
	var prev := PushbackPath.pose(p0, 0.5, 1.0, 0.0)[0] as Vector2
	var s := 0.0
	while s < PushbackPath.length():
		s += 0.1
		var p := PushbackPath.pose(p0, 0.5, 1.0, s)
		if prev.distance_to(p[0]) > 0.11:
			return "jump at s=%.1f" % s
		prev = p[0]
	var end := PushbackPath.pose(p0, 0.5, -1.0, PushbackPath.length())
	if absf(wrapf(end[1] - (0.5 + PI / 2.0), -PI, PI)) > 1e-6:
		return "end heading %.3f" % end[1]
	return ""


class StubCache extends TerrainTileCache:
	func landclass_at(_e: float, _n: float) -> int:
		return 200

	func height_at(_e: float, _n: float) -> float:
		return 50.0
