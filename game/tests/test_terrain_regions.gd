extends RefCounted
## Terrain region packs (world/terrain_meta.gd, terrain_tile_cache.gd): meta merge,
## per-tile flags, ancestor imagery / land-class lookup, UV sub-rects, 6-root
## layout and the float32-safe shader pattern origin. Uses a synthetic data dir
## (FREESIM_DATA) so it runs without the real corridor data.

const N := 8  # synthetic heightmap tile_n
const LC_N := TerrainTileCache.IMG_N


func _dir() -> String:
	return OS.get_temp_dir().path_join("freesim_test_regions_%d" % OS.get_process_id())


func _write(rel: String, bytes: PackedByteArray) -> void:
	var p := _dir().path_join(rel)
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


func _h_tile(rel: String, metres: float) -> void:
	var b := PackedByteArray()
	b.resize((N + 1) * (N + 1) * 2)
	for i in (N + 1) * (N + 1):
		b.encode_u16(i * 2, roundi((metres + 100.0) / 0.1))
	_write("terrain/h/" + rel + ".r16", b)


## Land class with the west half 255 (water) and east half 7, so a lookup
## proves which tile and which sub-rect was sampled.
func _lc_tile(rel: String) -> void:
	var b := PackedByteArray()
	b.resize(LC_N * LC_N)
	for y in LC_N:
		for x in LC_N:
			b[y * LC_N + x] = 255 if x < LC_N / 2 else 7
	_write("terrain/lc/" + rel + ".r8.gz", b.compress(FileAccess.COMPRESSION_GZIP))


## Base: level 0 tile 0_0, level 1 tiles 0_0 and 1_0, level 2 with 6 roots
## (tx -1..0, ty -2..0). Region "test": level-0 tiles 2_0, 3_1 with heights only
## (flags 0), under base level-1 tile 1_0; 9_9 listed but has no file.
## Region "absent": tiles only, no files -> must not merge.
func _setup() -> void:
	var l2 := {}
	for ty in range(-2, 1):
		for tx in range(-1, 1):
			l2["%d_%d" % [tx, ty]] = [0.0, 10.0]
			_h_tile("2/%d_%d" % [tx, ty], 5.0)
	var meta := {"tile_n": N, "tile_size_m": 1000.0, "h_scale": 0.1, "h_offset": -100.0, "levels": [
		{"level": 0, "size_m": 1000.0, "tiles": {"0_0": [0.0, 10.0]}},
		{"level": 1, "size_m": 2000.0, "tiles": {"0_0": [0.0, 10.0], "1_0": [0.0, 50.0]}},
		{"level": 2, "size_m": 4000.0, "tiles": l2}]}
	_write("terrain/meta.json", JSON.stringify(meta).to_utf8_buffer())
	_h_tile("0/0_0", 1.0)
	_h_tile("1/0_0", 1.0)
	_h_tile("1/1_0", 20.0)
	_lc_tile("1/1_0")
	var reg := {"levels": [{"level": 0, "size_m": 1000.0, "tiles": {
		"2_0": [10.0, 30.0, 0], "3_1": [10.0, 30.0, 0], "9_9": [0.0, 1.0, 0], "0_0": [99.0, 99.0, 0]}}]}
	_write("terrain/meta_test.json", JSON.stringify(reg).to_utf8_buffer())
	_h_tile("0/2_0", 25.0)
	_h_tile("0/3_1", 25.0)
	var absent := {"levels": [{"level": 0, "size_m": 1000.0, "tiles": {"40_40": [0.0, 1.0, 0]}}]}
	_write("terrain/meta_absent.json", JSON.stringify(absent).to_utf8_buffer())


func _with_data(f: Callable) -> String:
	var old := OS.get_environment("FREESIM_DATA")
	_setup()
	OS.set_environment("FREESIM_DATA", _dir())
	var err: String = f.call()
	_rm(_dir())
	if old == "":
		OS.unset_environment("FREESIM_DATA")
	else:
		OS.set_environment("FREESIM_DATA", old)
	return err


func _rm(path: String) -> void:
	for d in DirAccess.get_directories_at(path):
		_rm(path.path_join(d))
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)


func test_regions_meta_merge_and_flags() -> String:
	return _with_data(func() -> String:
		var m := TerrainMeta.new()
		if m.regions != ["test"]:
			return "merged regions %s, want [test] (absent pack must be skipped)" % [m.regions]
		if not m.has_tile(0, 2, 0) or not m.has_tile(0, 3, 1):
			return "region tiles not merged"
		if m.has_tile(0, 9, 9):
			return "region tile without heightmap file was merged"
		if m.min_max(0, 0, 0) != Vector2(0, 10):
			return "region overrode a base tile"
		if m.flags(0, 2, 0) != 0 or m.flags(0, 0, 0) != 3 or m.flags(0, 5, 5) != 0:
			return "flags wrong: %d %d %d" % [m.flags(0, 2, 0), m.flags(0, 0, 0), m.flags(0, 5, 5)]
		var roots := m.roots()
		if roots.size() != 6:
			return "want 6 roots (level-2 ty -2..0), got %d" % roots.size()
		print("    regions %s, 6 roots, flags ok" % [m.regions])
		return "")


func test_regions_ancestor_source_and_subrect() -> String:
	return _with_data(func() -> String:
		var m := TerrainMeta.new()
		var img := m.tex_source(0, 3, 1, TerrainMeta.HAS_IMG)
		if img != Vector3i(1, 1, 0):
			return "level-0 corridor tile imagery source %s, want (1,1,0)" % img
		if m.tex_source(0, 0, 0, TerrainMeta.HAS_LC) != Vector3i(0, 0, 0):
			return "a tile with its own land class must use it"
		# virtual level -2 node inside corridor tile 3_1: heights from L0, imagery from L1
		var node := Vector3i(-2, 13, 6)
		if m.height_source(node.x, node.y, node.z) != Vector3i(0, 3, 1):
			return "height source %s" % m.height_source(node.x, node.y, node.z)
		var r := TerrainMeta.sub_rect(node, m.tex_source(node.x, node.y, node.z, TerrainMeta.HAS_IMG))
		# span 8 (L1 -> L-2); sub = (13 - 8, 6 - 0) = (5, 6)
		if not r.is_equal_approx(Vector3(5.0 / 8.0, 1.0 - 6.0 / 8.0, 1.0 / 8.0)):
			return "sub-rect %s" % r
		if TerrainMeta.sub_rect(Vector3i(0, 3, 1), Vector3i(1, 1, 0)) != Vector3(0.5, 0.5, 0.5):
			return "L0 NE child of L1 should be u 0.5, v 0.5 (from north), scale 0.5"
		if TerrainMeta.sub_rect(Vector3i(1, 1, 0), Vector3i(1, 1, 0)) != Vector3(0.0, 1.0, 1.0):
			return "self sub-rect must be the whole texture"
		if TerrainMeta.sub_rect(Vector3i(-1, -1, -1), Vector3i(0, -1, -1)) != Vector3(0.5, 0.5, 0.5):
			return "negative-index sub-rect wrong"
		print("    L-2 node in corridor -> img from L1, sub-rect %s" % r)
		return "")


func test_regions_cache_borrows_ancestor_textures() -> String:
	return _with_data(func() -> String:
		var c := TerrainTileCache.new()
		var a := {}
		var b := {}
		for i in 400:
			c.process()
			a = c.get_tile(0, 2, 0)
			b = c.get_tile(0, 3, 1)
			if not a.is_empty() and not b.is_empty():
				break
			OS.delay_msec(5)
		if a.is_empty() or b.is_empty():
			return "corridor tiles never became ready"
		if a.lc_src != Vector3i(1, 1, 0) or a.img_src != Vector3i(1, 1, 0):
			return "sources %s %s" % [a.img_src, a.lc_src]
		if a.lctex != b.lctex:
			return "siblings must share the ancestor's land-class texture"
		if a.htex == b.htex:
			return "heights must be per tile"
		if c._t.size() != 1:
			return "want one texture entry (shared ancestor), got %d" % c._t.size()
		# landclass_at falls back to the ancestor, on the right sub-rect:
		# L1 tile 1_0 spans east 2000..4000; west half water(255), east half 7.
		var w := -1
		var e := -1
		for i in 200:
			c.process()
			w = c.landclass_at(2500.0, 500.0)
			e = c.landclass_at(3500.0, 1500.0)
			if w >= 0 and e >= 0:
				break
			OS.delay_msec(5)
		if w != 255 or e != 7:
			return "landclass_at via ancestor: west %d (want 255) east %d (want 7)" % [w, e]
		if absf(c.height_at(2500.0, 500.0) - 25.0) > 0.2:
			return "height_at in corridor tile %.2f, want 25" % c.height_at(2500.0, 500.0)
		print("    shared ancestor textures, landclass water/7 = %d/%d" % [w, e])
		return "")


func test_regions_pattern_origin_float32_safe() -> String:
	var base := Vector2.ZERO
	var worst := 0.0
	var jumps := 0
	# fly ~1000 km south-south-east in 5 km origin shifts
	for i in 220:
		var o := Vector2(snappedf(i * 1100.0, 5000.0), -i * 5000.0)
		var nb := FloatingOrigin.wrap_base(o, base)
		if nb != base:
			jumps += 1
		base = nb
		worst = maxf(worst, maxf(absf(o.x - base.x), absf(o.y - base.y)))
	if worst > FloatingOrigin.PATTERN_WRAP:
		return "pattern origin reached %.0f m" % worst
	if fmod(base.x, FloatingOrigin.PATTERN_WRAP) != 0.0:
		return "wrap base not on the grid"
	if jumps > 25:
		return "too many pattern jumps: %d over 1100 km" % jumps
	print("    max |pattern_origin| %.0f m (float32 step %.4f m), %d re-snaps over 1100 km" % [worst, worst / 8388608.0, jumps])
	return ""
