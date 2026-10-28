extends RefCounted
## Road / river ribbons and shore data (tools/20_roads_rivers.py -> terrain/ro/0/*.png, tools/21_shore.py ->
## terrain/sd/<L>/*.rg8.gz) and their runtime loading (terrain_roads.gd, terrain_tile_cache.gd).
## Data tests pass quietly when the data is not built on this machine.

const N := TerrainTileCache.IMG_N
const RN := 1920
const TILE := 7680.0
const SHADER_INC := "res://world/terrain_roads.gdshaderinc"


func _ro_path(tx: int, ty: int) -> String:
	return Paths.data("terrain/ro/0/%d_%d.png" % [tx, ty])


func _have_data() -> bool:
	return FileAccess.file_exists(_ro_path(-8, 4))


func _load_ro(tx: int, ty: int) -> Image:
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(_ro_path(tx, ty))) != OK:
		return null
	return img


## (e metres from the ribbon edge, class) at world ENU (east, north), nearest texel.
func _at(img: Image, tx: int, ty: int, x: float, y: float) -> Vector2:
	var px := clampi(int((x - tx * TILE) / TILE * RN), 0, RN - 1)
	var py := clampi(int((1.0 - (y - ty * TILE) / TILE) * RN), 0, RN - 1)
	var p := img.get_pixel(px, py)
	return Vector2(p.r * 40.8 - 6.0, roundf(p.a * 255.0))


func test_shader_half_widths_match_the_pipeline() -> String:
	var py := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../tools/road_raster.py"))
	if py == "":
		return ""
	var m := RegEx.create_from_string("KIND_HW = \\[([^\\]]*)\\]").search(py)
	var sh := RegEx.create_from_string("RO_HW\\[14\\] = float\\[14\\]\\(([^)]*)\\)").search(FileAccess.get_file_as_string(SHADER_INC))
	if m == null or sh == null:
		return "could not find KIND_HW / RO_HW"
	var kind := m.get_string(1).split(",")
	var drawn := sh.get_string(1).split(",")
	# shader table is indexed by class = kind + 1 (class 0 = none)
	if drawn.size() != kind.size() + 1:
		return "RO_HW has %d entries, KIND_HW %d" % [drawn.size(), kind.size()]
	for i in kind.size():
		var want := maxf(float(kind[i]), 2.2)
		if absf(float(drawn[i + 1]) - want) > 1e-3:
			return "class %d: shader half-width %s, pipeline %.2f" % [i + 1, drawn[i + 1].strip_edges(), want]
	return ""


func test_ro_tile_is_la8_with_ribbons_and_no_roads_on_runways() -> String:
	if not _have_data():
		return ""
	var img := _load_ro(-8, 4)
	if img == null or img.get_format() != Image.FORMAT_LA8 or img.get_width() != RN or img.get_height() != RN:
		return "VABB tile is not a 1920 px LA8 image"
	var road := 0
	var inside := 0
	for y in range(0, RN, 3):
		for x in range(0, RN, 3):
			var p := img.get_pixel(x, y)
			if p.a > 0.0:
				road += 1
				if p.r * 40.8 - 6.0 < 0.0:
					inside += 1
	if inside < 2000:
		return "only %d sampled texels inside a ribbon in the VABB tile" % inside
	# VABB runway 14/32 (data/processed/runways.json): the road mask must stay off it
	var a := Vector2(-55064.8, 36660.3)
	var b := Vector2(-57119.0, 38665.0)
	var bad := 0
	for i in range(1, 40):
		var q := a.lerp(b, i / 40.0)
		var s := _at(img, -8, 4, q.x, q.y)
		if s.y > 0.0 and s.x < 0.0:
			bad += 1
	if bad > 0:
		return "%d of 39 runway centreline samples lie inside a road ribbon" % bad
	print("    VABB tile: %d inside-ribbon samples, runway clear" % inside)
	return ""


func test_ribbon_edges_are_crisp_signed_distances() -> String:
	if not _have_data():
		return ""
	var img := _load_ro(-1, 0)
	if img == null:
		return ""
	# along any row, e changes by at most ~RES per texel (it is a distance field), and ribbons exist
	var worst := 0.0
	var crossings := 0
	for y in range(100, RN, 97):
		var prev := 1e9
		for x in range(RN):
			var p := img.get_pixel(x, y)
			var e := p.r * 40.8 - 6.0
			if prev < 1e8:
				worst = maxf(worst, absf(e - prev))
				if (e < 0.0) != (prev < 0.0) and p.a > 0.0:
					crossings += 1
			prev = e
	if worst > 4.4:
		return "distance field jumps by %.2f m between neighbouring texels" % worst
	if crossings < 20:
		return "only %d ribbon edges found in the sampled rows" % crossings
	return ""


func test_roads_cache_loads_a_tile_and_settles_missing_ones() -> String:
	if not _have_data():
		return ""
	var r := TerrainRoads.new()
	if r.texture(-8, 4) != null:
		r.wait_all()
		return "texture is available before it was loaded"
	r.texture(5000, 5000)  # no such tile
	var tex: Texture2D = null
	for i in 600:
		r.process()
		tex = r.texture(-8, 4)
		if tex != null and r.is_settled(5000, 5000):
			break
		OS.delay_msec(5)
	r.wait_all()
	if tex == null:
		return "tile never loaded"
	if tex.get_width() != RN:
		return "texture is %d px wide" % tex.get_width()
	if r.has_data(5000, 5000) or not r.is_settled(5000, 5000):
		return "a missing tile should settle without a texture"
	return ""


func test_sd_tiles_match_the_water_mask() -> String:
	var sdp := Paths.data("terrain/sd/0/-8_4.rg8.gz")
	var lcp := Paths.data("terrain/lc/0/-8_4.r8.gz")
	if not FileAccess.file_exists(sdp) or not FileAccess.file_exists(lcp):
		return ""
	var sd := FileAccess.get_file_as_bytes(sdp).decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	var lc := FileAccess.get_file_as_bytes(lcp).decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	if sd.size() != N * N * 2 or lc.size() != N * N:
		return "bad sizes sd %d lc %d" % [sd.size(), lc.size()]
	var wet_ok := 0
	var wet := 0
	var dry_ok := 0
	var dry := 0
	var open_max := 0
	for i in range(0, N * N, 7):
		var d := int(sd[i * 2]) - 128
		if lc[i] == 255:
			wet += 1
			wet_ok += 1 if d >= 0 else 0
			open_max = maxi(open_max, sd[i * 2 + 1])
		else:
			dry += 1
			dry_ok += 1 if d <= 0 else 0
	if wet < 100 or dry < 100:
		return "the VABB coast tile should have both water (%d) and land (%d)" % [wet, dry]
	if float(wet_ok) / wet < 0.97 or float(dry_ok) / dry < 0.97:
		return "shore sign disagrees with the mask: water %d/%d, land %d/%d" % [wet_ok, wet, dry_ok, dry]
	if open_max < 150:
		return "open sea off Mumbai should read as open (max %d)" % open_max
	return ""


func test_tile_cache_provides_an_sd_texture() -> String:
	if not FileAccess.file_exists(Paths.data("terrain/sd/0/-8_4.rg8.gz")):
		return ""
	var c := TerrainTileCache.new()
	var t := {}
	for i in 600:
		c.process()
		t = c.get_tile(0, -8, 4)
		if not t.is_empty():
			break
		OS.delay_msec(5)
	c.wait_all()
	if t.is_empty() or not t.has("sdtex") or t.sdtex == null:
		return "tile has no sdtex"
	if t.lc_src != TerrainMeta.NONE and t.sdtex.get_size() != t.lctex.get_size():
		return "sd and lc textures differ in size"
	return ""
