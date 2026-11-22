extends Node
## Ground cover (world/ground_cover*.gd, GroundRoads) and the palm parts (docs/GRAPHICS-PLAN.md G8).


class FlatCache extends TerrainTileCache:
	var lc := 0
	var wc := 3

	func landclass_at(_e: float, _n: float) -> int:
		return lc

	func worldcover_at(_e: float, _n: float) -> int:
		return wc

	func height_at(_e: float, _n: float) -> float:
		return 20.0


func _cover(lc: int, wc: int, paved: int) -> GroundCover:
	var tq := TerrainQuadtree.new()
	var c := FlatCache.new()
	c.lc = lc
	c.wc = wc
	tq.cache = c
	var gc := GroundCover.new()
	gc.terrain = tq
	gc.step = 1.6
	gc.surface.fixed = paved  # 1 = everything paved, 0 = nothing
	gc.roads.tile_m = gc.surface.tile_m
	return gc


func _no_roads(gc: GroundCover, k: Vector2i) -> void:
	gc.roads._tiles[Vector2i(floori((k.x + 0.5) * GroundCover.CELL / gc.roads.tile_m), floori((k.y + 0.5) * GroundCover.CELL / gc.roads.tile_m))] = null


func _plants(gc: GroundCover, k: Vector2i) -> int:
	_no_roads(gc, k)
	var n := 0
	for b in gc.cell_buffers(k):
		n += (b as PackedFloat32Array).size() / 16
	return n


func _free(gc: GroundCover) -> void:
	gc.surface.finish()
	gc.roads.finish()
	gc.terrain.free()
	gc.free()


func test_cover_kinds_follow_land_cover() -> String:
	var counts := {}
	for wc in [1, 2, 3, 4, 6, 8, 0]:
		var c := [0, 0, 0]
		for j in 40:
			for i in 40:
				var k := GroundCoverRules.pick(i, j, 200 if wc == 1 else 0, wc, 50.0)
				if k.x >= 0:
					c[k.x] += 1
		counts[wc] = c
	if counts[1][GroundCoverRules.FERN] < 400 or counts[1][GroundCoverRules.GRASS] > 0:
		return "forest floor should be ferns and shrubs, no grass: %s" % [counts[1]]
	if counts[3][GroundCoverRules.GRASS] < 800 or counts[4][GroundCoverRules.GRASS] < 500:
		return "grassland and farmland should be grass: %s %s" % [counts[3], counts[4]]
	if counts[2][GroundCoverRules.SHRUB] == 0:
		return "shrubland should have bushes: %s" % [counts[2]]
	if counts[8] != [0, 0, 0] or counts[0] != [0, 0, 0]:
		return "nothing on water or without WorldCover data: %s %s" % [counts[8], counts[0]]
	if GroundCoverRules.pick(1, 1, 255, 3, 10.0) != GroundCoverRules.NONE:
		return "nothing on land-class water"
	var dry := 0
	for j in 20:
		for i in 20:
			dry += GroundCoverRules.pick(i, j, 0, 3, 650.0).y
	return "" if dry > 100 else "plateau grass should be dry (%d)" % dry


func test_cover_stays_off_paved_ground_and_water() -> String:
	var k := Vector2i(40, 40)
	var open := _cover(0, 3, 0)
	var paved := _cover(0, 3, 1)
	var water := _cover(255, 8, 0)
	var n_open := _plants(open, k)
	var n_paved := _plants(paved, k)
	var n_water := _plants(water, k)
	TreeClear.add(Vector2(k) * GroundCover.CELL - Vector2(50, -12), Vector2(k) * GroundCover.CELL + Vector2(80, 12), 6.0)
	var ribbon := _cover(0, 3, 0)
	var n_runway := _plants(ribbon, k)
	_free(ribbon)
	TreeClear.clear()
	var road := _cover(0, 3, 0)
	var img := Image.create(16, 16, false, Image.FORMAT_LA8)
	img.fill(Color(0.0, 0.0, 0.0, 7.0 / 255.0))  # L 0 = 6 m inside a residential road everywhere
	road.roads._tiles[Vector2i(floori((k.x + 0.5) * GroundCover.CELL / road.roads.tile_m), floori((k.y + 0.5) * GroundCover.CELL / road.roads.tile_m))] = img
	var n_road := 0
	for b in road.cell_buffers(k):
		n_road += (b as PackedFloat32Array).size() / 16
	for g in [open, paved, water, road]:
		_free(g)
	if n_open < 50:
		return "open grassland cell has only %d plants" % n_open
	if n_paved != 0 or n_water != 0 or n_road != 0:
		return "plants on pavement (%d), water (%d) or a road (%d)" % [n_paved, n_water, n_road]
	return "" if n_runway < n_open else "a runway ribbon through the cell should clear plants (%d of %d)" % [n_runway, n_open]


func test_cover_is_stable_across_an_origin_shift() -> String:
	var keep := FloatingOrigin.origin
	var gc := _cover(0, 3, 0)
	var k := Vector2i(-12, 30)
	_no_roads(gc, k)
	var bufs := gc.cell_buffers(k)
	var mi := MultiMeshInstance3D.new()
	gc._cells[k] = [mi]
	gc._place(mi, k)
	var w := FloatingOrigin.to_world(mi.position)
	FloatingOrigin.set_origin(keep + Vector2(5000.0, 5000.0))
	gc._reposition()
	var moved := FloatingOrigin.to_world(mi.position).distance_to(w)
	var again := gc.cell_buffers(k)
	FloatingOrigin.set_origin(keep)
	gc._cells.clear()
	mi.free()
	_free(gc)
	if moved > 1e-3:
		return "a ground cover cell moved %.3f m in the world at the shift" % moved
	if bufs != again:
		return "a cell's plants must not depend on the origin (built again after the shift they differ)"
	var src := FileAccess.get_file_as_string("res://world/ground_cover.gdshader")
	return "" if src.contains("INSTANCE_CUSTOM.a * 6.2831853") and not src.contains("wp.x") else "the sway must be phased by the seed"


func test_cover_counts_per_preset() -> String:
	var last := -1
	for p in Graphics.ORDER:
		var b := TreeQuality.cover_budget(p)
		if p == "low" and b != Vector2i.ZERO:
			return "Low has no ground cover"
		if b.x < last:
			return "%s has less ground cover than the preset below" % p
		last = b.x
	if TreeQuality.of("medium").cover > 25.0 or TreeQuality.of("high").cover < 30.0 or TreeQuality.of("max").cover > 70.0:
		return "radii: Medium short, High and up 30-70 m"
	if TreeQuality.cover_budget("max").y > 120000 or TreeQuality.cover_budget("medium").y > 12000:
		return "ground cover triangles over budget: %s / %s" % [TreeQuality.cover_budget("medium"), TreeQuality.cover_budget("max")]
	return ""


func test_palm_has_its_parts() -> String:
	var a := TreeMeshes.build(TreeSpecies.PALM, 0).surface_get_arrays(0)
	var cols: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var ringed := 0
	var green := 0
	var dead := 0
	var nuts := 0
	for i in cols.size():
		var c := cols[i]
		if absf(c.a - 0.1) < 0.01:
			ringed += 1
		elif c.a > 0.9:
			if c.r > c.g * 1.2:
				dead += 1
			else:
				green += 1
		elif c.a < 0.01 and verts[i].y > 0.78 and verts[i].y < 0.84:
			nuts += 1
	if ringed < 20 or green < 100 or dead < 10 or nuts < 20:
		return "palm: ringed trunk %d, green fronds %d, dead fronds %d, coconut verts %d" % [ringed, green, dead, nuts]
	var slim: PackedVector2Array = TreeMeshes.build(TreeSpecies.SLIM, 0).surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var needles := 0
	for t in slim:
		needles += 1 if Vector2i(floori(t.x * TreeParts.ATLAS.x - 1e-4), floori(t.y * TreeParts.ATLAS.y - 1e-4)) == TreeParts.CELL_NEEDLE else 0
	return "" if needles > 40 else "casuarina should hang needle strands (%d card corners)" % needles
