extends Node
## Ground-tile helper maps (world/terrain_helper_maps.gd): full size at level 0, half above it, land class and
## WorldCover shrunk without blending classes, shore distance within a few metres of the full map, CPU copies only
## where landclass_at / worldcover_at read. Needs the generated data (VABB area).

const VABB := Vector2(-56000.0, 38500.0)  # world ENU (m), the Mumbai airport area


func _cache() -> TerrainTileCache:
	return TerrainTileCache.new()


## A texture source with land-class data at `level` over VABB, loaded synchronously (as a worker would).
func _load(c: TerrainTileCache, level: int) -> Array:
	var size := c.tmeta.level_size(level)
	var key := c.tmeta.tex_source(level, floori(VABB.x / size), floori(VABB.y / size), TerrainMeta.HAS_LC)
	if key == TerrainMeta.NONE or key.x != level:
		return []
	c._load_t(key, c.tmeta.flags(key.x, key.y, key.z))
	var item: Array = c._done.pop_back()
	return [key, item]


## Requests texture source `key` and lets the cache upload it (process() releases the worker task itself).
static func _ready_entry(c: TerrainTileCache, key: Vector3i) -> void:
	var e := c._request(c._t, key, 1)
	for i in 600:
		c.process()
		if e.state == 1:
			return
		OS.delay_msec(5)


static func _raw(c: TerrainTileCache, kind: String, key: Vector3i, n: int, ch: int) -> PackedByteArray:
	var p := Paths.data("terrain/%s/%d/%d_%d.%s.gz" % [kind, key.x, key.y, key.z, "rg8" if ch == 2 else "r8"])
	return FileAccess.get_file_as_bytes(p).decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)


func test_helper_map_bytes_per_tile() -> String:
	var c := _cache()
	var l0 := _load(c, 0)
	var l1 := _load(c, 1)
	if l0.is_empty() or l1.is_empty():
		return "no land-class tiles at levels 0 and 1 over VABB (generated data missing?)"
	var b0: int = l0[1][3].get_data_size() + l0[1][4].get_data_size() + l0[1][5].get_data_size()
	var b1: int = l1[1][3].get_data_size() + l1[1][4].get_data_size() + l1[1][5].get_data_size()
	if b0 > 768 * 768 * 4:
		return "level 0 helper maps should stay at 768² (2.36 MB), got %d bytes" % b0
	if b1 > 384 * 384 * 4:
		return "coarser helper maps should be at most 384² (0.59 MB per tile), got %d bytes" % b1
	return ""


func test_shrunk_classes_are_never_blended() -> String:
	var c := _cache()
	var l1 := _load(c, 1)
	if l1.is_empty():
		return "no level-1 land-class tile over VABB"
	var key: Vector3i = l1[0]
	for pair in [["lc", 3], ["wc", 4]]:
		var full := _raw(c, pair[0], key, 768, 1)
		var img: Image = l1[1][pair[1]]
		if full.size() != 768 * 768 or img == null or img.get_width() != 384:
			return "%s: expected a 768² file and a 384² map" % pair[0]
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 2000:
			var x := rng.randi_range(0, 383)
			var y := rng.randi_range(0, 383)
			var v := int(img.get_pixel(x, y).r * 255.0 + 0.5)
			var ok := false
			for dy in 2:
				for dx in 2:
					ok = ok or full[(y * 2 + dy) * 768 + x * 2 + dx] == v
			if not ok:
				return "%s value %d at %d,%d is not one of the four full-size texels it stands for" % [pair[0], v, x, y]
	return ""


func test_shore_distance_error_is_small() -> String:
	var c := _cache()
	var l1 := _load(c, 1)
	if l1.is_empty():
		return "no level-1 tile over VABB"
	var key: Vector3i = l1[0]
	var full := _raw(c, "sd", key, 768, 2)
	var half: Image = l1[1][5]
	if full.size() != 768 * 768 * 2 or half == null:
		return "no shore-distance map for the level-1 VABB tile"
	var errs: Array[float] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 4000:
		var u := rng.randf_range(0.01, 0.99)
		var v := rng.randf_range(0.01, 0.99)
		var f := full[(int(v * 768) * 768 + int(u * 768)) * 2]
		var hx := u * 384.0 - 0.5
		var hy := v * 384.0 - 0.5
		var x0 := clampi(floori(hx), 0, 383)
		var y0 := clampi(floori(hy), 0, 383)
		var x1 := mini(x0 + 1, 383)
		var y1 := mini(y0 + 1, 383)
		var tx := clampf(hx - x0, 0.0, 1.0)
		var ty := clampf(hy - y0, 0.0, 1.0)
		var s := lerpf(lerpf(half.get_pixel(x0, y0).r, half.get_pixel(x1, y0).r, tx), lerpf(half.get_pixel(x0, y1).r, half.get_pixel(x1, y1).r, tx), ty) * 255.0
		errs.append(absf(s - f))
	errs.sort()
	var mean := 0.0
	for e in errs:
		mean += e
	mean /= errs.size()
	if mean > 3.0 or errs[int(errs.size() * 0.99)] > 16.0:
		return "half-size shore distance off by %.1f m on average, %.1f m at the 99th percentile (level 1, 20 m texels)" % [mean, errs[int(errs.size() * 0.99)]]
	return ""


func test_cpu_copies_only_where_lookups_read() -> String:
	var c := _cache()
	var size := c.tmeta.level_size(0)
	var k0 := c.tmeta.tex_source(0, floori(VABB.x / size), floori(VABB.y / size), TerrainMeta.HAS_LC)
	if k0 == TerrainMeta.NONE:
		return "no land-class source over VABB"
	if not TerrainHelperMaps.cpu_source(c.tmeta, k0):
		return "the level-0 tile under VABB serves landclass_at"
	var k1 := c.tmeta.tex_source(1, floori(VABB.x / size / 2.0), floori(VABB.y / size / 2.0), TerrainMeta.HAS_LC)
	if k1 != TerrainMeta.NONE and k1.x == 1 and k0.x == 0 and TerrainHelperMaps.cpu_source(c.tmeta, k1):
		return "a level-1 tile over level-0 data should keep no CPU copy"
	# through the cache: upload both and look at the entries
	for key in [k0, k1]:
		if key == TerrainMeta.NONE:
			continue
		_ready_entry(c, key)
	var e0: Dictionary = c._t.get(k0, {})
	var e1: Dictionary = c._t.get(k1, {}) if k1 != TerrainMeta.NONE else {}
	if e0.get("lcimg") == null or e0.get("wcimg") == null:
		return "level-0 entries keep their CPU land-class and WorldCover images"
	if k1.x == 1 and k0.x == 0 and (e1.get("lcimg") != null or e1.get("wcimg") != null):
		return "coarser entries drop the CPU copies"
	return ""


func test_trees_and_ground_cover_read_the_same_classes() -> String:
	var c := _cache()
	var size := c.tmeta.level_size(0)
	var key := c.tmeta.tex_source(0, floori(VABB.x / size), floori(VABB.y / size), TerrainMeta.HAS_LC)
	if key == TerrainMeta.NONE or key.x != 0:
		return "no level-0 land class over VABB"
	var lc := _raw(c, "lc", key, 768, 1)
	var wc := _raw(c, "wc", key, 768, 1)
	_ready_entry(c, key)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 500:
		var e := (key.y + rng.randf_range(0.0, 0.999)) * size
		var n := (key.z + rng.randf_range(0.001, 1.0)) * size
		var px := clampi(int((e - key.y * size) / size * 768), 0, 767)
		var py := clampi(int((1.0 - (n - key.z * size) / size) * 768), 0, 767)
		if c.landclass_at(e, n) != lc[py * 768 + px] or c.worldcover_at(e, n) != wc[py * 768 + px]:
			return "landclass_at / worldcover_at at %.0f, %.0f differ from the full-size files" % [e, n]
	return ""
