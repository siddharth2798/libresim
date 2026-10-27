extends Node
## Tree species / LOD0 meshes / impostor atlas, and the BLD2 building tiles and their night uniform.


func _species_counts(n: float, g: float) -> Array:
	var counts := [0, 0, 0, 0]
	for j in 40:
		for i in 40:
			counts[TreeSpecies.of(i, j, n, g)] += 1
	return counts


func test_palms_follow_region_and_elevation() -> String:
	var kerala := _species_counts(-900000.0, 10.0)
	var konkan := _species_counts(-200000.0, 15.0)
	var deccan := _species_counts(0.0, 600.0)
	if kerala[TreeSpecies.PALM] < 0.3 * 1600:
		return "Kerala lowland should be a third palms or more: %s" % [kerala]
	if konkan[TreeSpecies.PALM] < 0.2 * 1600:
		return "Konkan coast should have many palms: %s" % [konkan]
	if deccan[TreeSpecies.PALM] > 0.02 * 1600:
		return "the Deccan plateau should have almost no palms: %s" % [deccan]
	if deccan[TreeSpecies.ACACIA] < 0.1 * 1600:
		return "the dry plateau should have umbrella acacias: %s" % [deccan]
	return "" if kerala[TreeSpecies.BROADLEAF] > 0 else "broadleaf trees should remain everywhere"


func test_shape_is_deterministic_and_sized_per_species() -> String:
	for j in 20:
		for i in 20:
			var a := TreeSpecies.shape(i, j, -300000.0, 20.0)
			var b := TreeSpecies.shape(i, j, -300000.0, 20.0)
			if a != b:
				return "shape not deterministic at %d,%d" % [i, j]
			var sp := int(a[0])
			if sp < 0 or sp >= TreeSpecies.COUNT or int(a[1]) < 0 or int(a[1]) >= TreeSpecies.VARIANTS:
				return "bad species / variant %s" % [a]
			if a[2] > TreeSpecies.MAX_HEIGHT or a[2] < 4.0 or a[3] < 1.0:
				return "tree size out of range %s" % [a]
			var aspect: float = a[3] / a[2]
			var want: float = TreeSpecies.ASPECT[sp]
			if aspect < want * 0.5 or aspect > want * 1.7:
				return "species %d aspect %.2f far from the atlas sprite's %.2f" % [sp, aspect, want]
	return ""


func test_palm_collision_disc_is_narrower_than_the_crown() -> String:
	var r := TreeSpecies.hit_radius(TreeSpecies.PALM, 9.0)
	var b := TreeSpecies.hit_radius(TreeSpecies.BROADLEAF, 9.0)
	return "" if r < b and r > 0.5 else "palm disc %.1f vs broadleaf %.1f" % [r, b]


func test_lod0_meshes_are_small_and_unit_sized() -> String:
	for sp in TreeSpecies.COUNT:
		var m := TreeMeshes.build(sp)
		var tris := TreeMeshes.triangle_count(m)
		if tris < 150 or tris > 700:
			return "species %d has %d triangles (want a few hundred)" % [sp, tris]
		var box := m.get_aabb()
		if box.position.y < -0.05 or box.end.y > 1.1 or box.size.x > 1.3 or box.size.x < 0.1:
			return "species %d bounds %s are not unit tree sized" % [sp, box]
	return ""


func test_atlas_bakes_in_headless_with_a_placeholder() -> String:
	var atlas := TreeAtlas.new()
	var got := []
	atlas.baked.connect(func(a, n): got.append([a, n]))
	add_child(atlas)
	var ok := got.size() == 1 and got[0][0] != null and atlas.ready_ok
	atlas.queue_free()
	return "" if ok else "the atlas should report baked at once without a renderer"


func test_tree_shaders_expose_the_lod_handover() -> String:
	for p in ["res://world/tree.gdshader", "res://world/tree_mesh.gdshader"]:
		var names := []
		for u in (load(p) as Shader).get_shader_uniform_list():
			names.append(u.name)
		if not names.has("lod_r") or not names.has("lod_band"):
			return "%s lacks lod_r / lod_band: %s" % [p, names]
	return ""


func _write_tile(path: String, bld2: bool) -> void:
	var b := PackedByteArray()
	b.append_array("BLD2".to_ascii_buffer() if bld2 else "BLD1".to_ascii_buffer())
	var head := PackedByteArray()
	head.resize(8)
	head.encode_u32(0, 3)
	head.encode_u32(4, 3)
	b.append_array(head)
	b.append_array(PackedVector3Array([Vector3(0, 0, 0), Vector3(5, 0, 0), Vector3(0, 0, -5)]).to_byte_array())
	b.append_array(PackedByteArray([200, 180, 160, 12, 200, 180, 160, 12, 200, 180, 160, 12]))
	if bld2:
		b.append_array(PackedByteArray([44, 1, 0, 0, 44, 1, 0, 255, 44, 1, 200, 255]))
	b.append_array(PackedInt32Array([0, 1, 2]).to_byte_array())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(b.compress(FileAccess.COMPRESSION_GZIP))


func test_buildings_load_bld2_and_the_old_bld1_layout() -> String:
	var dir := OS.get_user_data_dir().path_join("bld_test")
	DirAccess.make_dir_recursive_absolute(dir)
	_write_tile(dir.path_join("7_7.bin"), true)
	_write_tile(dir.path_join("8_7.bin"), false)
	var bl := Buildings.new()
	bl._dir = dir
	bl._load(Vector2i(7, 7))
	bl._load(Vector2i(8, 7))
	var err := ""
	if bl._done.size() != 2:
		err = "expected 2 meshes, got %d" % bl._done.size()
	else:
		for item in bl._done:
			var fmt: int = (item[1] as ArrayMesh).surface_get_format(0)
			if not (fmt & Mesh.ARRAY_FORMAT_CUSTOM0) or not (fmt & Mesh.ARRAY_FORMAT_CUSTOM1):
				err = "tile %s lacks CUSTOM0 / CUSTOM1" % [item[0]]
	DirAccess.remove_absolute(dir.path_join("7_7.bin"))
	DirAccess.remove_absolute(dir.path_join("8_7.bin"))
	DirAccess.remove_absolute(dir)
	bl.free()
	return err


func test_building_windows_light_up_only_at_night() -> String:
	var bl := Buildings.new()
	bl._mat.shader = preload("res://world/building.gdshader")
	add_child(bl)
	Props.set_v("environment/sun_elev_deg", 40.0)
	bl._process(0.0)
	var day: float = bl._mat.get_shader_parameter("night")
	Props.set_v("environment/sun_elev_deg", -12.0)
	bl._process(0.0)
	var night: float = bl._mat.get_shader_parameter("night")
	Props.set_v("environment/sun_elev_deg", 30.0)
	bl.queue_free()
	return "" if day == 0.0 and night == 1.0 else "night uniform: day %.2f night %.2f" % [day, night]
