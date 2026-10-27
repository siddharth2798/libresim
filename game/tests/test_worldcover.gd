extends RefCounted
## ESA WorldCover class tiles (tools/19_worldcover.py -> terrain/wc/<L>/<tx>_<ty>.r8.gz, codes 0..11)
## and their runtime loading (terrain_tile_cache.gd: same source tile as the land class).
## Uses the generated data; each test passes quietly when the data is not built on this machine.

const N := TerrainTileCache.IMG_N
const NAMES := ["nodata", "tree", "shrub", "grass", "crop", "built", "bare", "snow", "water", "wetland", "mangrove", "moss"]
const VAPO := Vector2(54856.0, -18505.0)  # world ENU (m), data/processed/airports.json
const VABB := Vector2(-55997.0, 37576.0)


func _have_data() -> bool:
	return DirAccess.dir_exists_absolute(Paths.data("terrain/wc/0")) and DirAccess.dir_exists_absolute(Paths.data("terrain/lc/0"))


func _read(kind: String, level: int, tx: int, ty: int) -> PackedByteArray:
	var p := Paths.data("terrain/%s/%d/%d_%d.r8.gz" % [kind, level, tx, ty])
	if not FileAccess.file_exists(p):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(p).decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)


## Class histogram (12 bins) in a (2r)^2 m window around a world point, from the level-0 wc tiles.
func _histogram(c: Vector2, r: float) -> PackedInt32Array:
	var h := PackedInt32Array()
	h.resize(12)
	var size := 7680.0
	var step := 20.0
	var cache := {}
	var x := c.x - r
	while x <= c.x + r:
		var y := c.y - r
		while y <= c.y + r:
			var tx := floori(x / size)
			var ty := floori(y / size)
			var key := Vector2i(tx, ty)
			if not cache.has(key):
				cache[key] = _read("wc", 0, tx, ty)
			var b: PackedByteArray = cache[key]
			if b.size() == N * N:
				var px := clampi(int((x - tx * size) / size * N), 0, N - 1)
				var py := clampi(int((1.0 - (y - ty * size) / size) * N), 0, N - 1)
				h[b[py * N + px]] += 1
			y += step
		x += step
	return h


func _share(h: PackedInt32Array, cls: int) -> float:
	var t := 0
	for v in h:
		t += v
	return float(h[cls]) / maxf(t, 1)


func test_wc_tile_for_every_sampled_lc_tile() -> String:
	if not _have_data():
		return ""
	var checked := 0
	var levels := 0
	for level in 7:
		var dir := Paths.data("terrain/lc/%d" % level)
		if not DirAccess.dir_exists_absolute(dir):
			continue
		levels += 1
		var files := DirAccess.get_files_at(dir)
		files.sort()
		for i in range(0, files.size(), maxi(1, files.size() / 12)):
			var wc := FileAccess.get_file_as_bytes(Paths.data("terrain/wc/%d/%s" % [level, files[i]])).decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
			if wc.size() != N * N:
				return "level %d tile %s has lc but no valid wc tile (%d bytes)" % [level, files[i], wc.size()]
			var top := 0
			for v in wc:
				top = maxi(top, v)
			if top > 11:
				return "level %d tile %s: class code %d > 11" % [level, files[i], top]
			checked += 1
	if checked < 14:
		return "only %d tiles checked over %d levels" % [checked, levels]
	print("    %d sampled tiles over %d levels: wc exists, codes 0..11" % [checked, levels])
	return ""


func test_wc_shares_around_pune_and_mumbai() -> String:
	if not _have_data():
		return ""
	var pune := _histogram(VAPO, 4000.0)
	if _share(pune, 5) <= 0.01:
		return "built-up share near VAPO %.3f, want > 1%%" % _share(pune, 5)
	if _share(pune, 4) + _share(pune, 3) < 0.05:
		return "no cropland / grass near VAPO (%.2f)" % (_share(pune, 4) + _share(pune, 3))
	var mumbai := _histogram(VABB, 4000.0)
	if _share(mumbai, 5) < 0.2:
		return "built-up share near VABB %.2f, want > 0.2" % _share(mumbai, 5)
	var sea := _histogram(Vector2(-67000.0, 5000.0), 1500.0)  # Arabian Sea, west of Mumbai
	if _share(sea, 1) > 0.01 or _share(sea, 8) + _share(sea, 0) < 0.95:
		return "open sea should be water / nodata, got tree %.2f water %.2f" % [_share(sea, 1), _share(sea, 8)]
	var parts := PackedStringArray()
	for i in [1, 3, 4, 5, 8]:
		parts.append("%s %d%%" % [NAMES[i], roundi(_share(pune, i) * 100.0)])
	print("    around VAPO: %s; VABB built-up %d%%" % [", ".join(parts), roundi(_share(mumbai, 5) * 100.0)])
	return ""


func test_wc_texture_shares_the_lc_source() -> String:
	if not _have_data():
		return ""
	var c := TerrainTileCache.new()
	var keys := [Vector3i(0, 7, -3), Vector3i(0, -7, 4), Vector3i(1, 3, -2), Vector3i(3, 0, 0)]
	for k in keys:
		if not c.has_tile(k.x, k.y, k.z):
			continue
		var t := {}
		for i in 600:
			c.process()
			t = c.get_tile(k.x, k.y, k.z)
			if not t.is_empty():
				break
			OS.delay_msec(5)
		if t.is_empty():
			c.wait_all()
			return "tile %s never became ready" % k
		if not t.has("wctex") or t.wctex == null:
			c.wait_all()
			return "tile %s has no wctex" % k
		var wc: ImageTexture = t.wctex
		if t.lc_src != TerrainMeta.NONE and wc.get_width() != N:
			c.wait_all()
			return "tile %s: wc texture %d px wide with lc source %s" % [k, wc.get_width(), t.lc_src]
		if t.lc_src != TerrainMeta.NONE and t.lctex.get_size() != wc.get_size():
			c.wait_all()
			return "tile %s: wc and lc textures differ in size" % k
	c.wait_all()
	return ""
