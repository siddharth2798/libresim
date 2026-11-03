extends RefCounted
## Terrain detail materials (GRAPHICS-PLAN G6: tools/26_terrain_textures.py, terrain_detail.gdshaderinc) and the
## airport pavement mask (tools/27_pavement.py -> terrain/pv/0, terrain_pavement.gdshaderinc). Data tests pass
## quietly when the pavement data is not built on this machine.

const SHADER := "res://world/terrain.gdshader"
const TILE := 7680.0
const RN := 1920
const BIG := ["VABB", "VAPO", "VOCI", "VOGO", "VANM"]


func _tool(name: String) -> String:
	return FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../tools/" + name))


## asset ids of tools/26_terrain_textures.py LAYERS, in layer order
func _assets() -> Array:
	var out := []
	for m in RegEx.create_from_string("\\(\"(\\w+)\", \"(\\w+)\", \"").search_all(_tool("26_terrain_textures.py")):
		out.append(m.get_string(2))
	return out


func test_terrain_shader_compiles_with_detail_and_pavement() -> String:
	var names := []
	for u in (load(SHADER) as Shader).get_shader_uniform_list():
		names.append(u.name)
	if names.is_empty():
		return "terrain.gdshader did not compile"
	for n in ["det_mod", "det_nrm", "pv_tex", "pv_on", "ro_tex", "wc_tex"]:
		if not names.has(n):
			return "missing uniform %s" % n
	if (load(SHADER) as Shader).code.split("\n").size() >= 300:
		return "terrain.gdshader is 300 lines or more"
	return ""


func test_detail_arrays_have_one_layer_per_set() -> String:
	var ids := _assets()
	if ids.size() < 8:
		return "could not read LAYERS from tools/26_terrain_textures.py"
	var inc := FileAccess.get_file_as_string("res://world/terrain_detail.gdshaderinc")
	if not inc.contains("const int DET_LAYERS = %d;" % ids.size()):
		return "DET_LAYERS does not match the %d sets of the packing tool" % ids.size()
	for p in [TerrainDetail.MOD, TerrainDetail.NRM]:
		var t := load(p) as TextureLayered
		if t == null:
			return "%s does not load as a texture array" % p
		if t.get_layers() != ids.size() or t.get_width() != 1024:
			return "%s: %d layers of %d px, want %d of 1024" % [p, t.get_layers(), t.get_width(), ids.size()]
	var sh := load(SHADER) as Shader
	TerrainDetail.apply(sh)
	if sh.get_default_texture_parameter("det_mod") == null or sh.get_default_texture_parameter("det_nrm") == null:
		return "TerrainDetail.apply did not bind the arrays"
	return ""


func test_credits_and_licensing_list_every_texture() -> String:
	var credits := FileAccess.get_file_as_string("res://../CREDITS.md")
	if credits == "":
		credits = FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../CREDITS.md"))
	var lic := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../docs/LICENSING.md"))
	var src := FileAccess.get_file_as_string(TerrainDetail.SOURCES)
	for id in _assets():
		for doc in [["CREDITS.md", credits], ["docs/LICENSING.md", lic], ["SOURCES.md", src]]:
			if not doc[1].contains(id):
				return "%s does not list %s" % [doc[0], id]
	if not credits.contains("ambientcg.com") or not lic.contains("CC0"):
		return "credits / licensing must give the source (ambientcg.com) and the licence (CC0)"
	return ""


func test_pavement_constants_match_the_pipeline() -> String:
	var py := _tool("pavement_raster.py")
	var inc := FileAccess.get_file_as_string("res://world/terrain_pavement.gdshaderinc")
	if py == "":
		return ""
	if not py.contains("E_MIN, E_SPAN = -8.0, 16.0") or not inc.contains("f.r * 16.0 - 8.0"):
		return "edge distance encoding differs between pavement_raster.py and the shader"
	if not py.contains("D_MAX = 10.0") or not inc.contains("f.g * 20.0 - 10.0"):
		return "lead-in offset encoding differs between pavement_raster.py and the shader"
	return ""


func _pv(tx: int, ty: int, cache: Dictionary) -> Image:
	var key := Vector2i(tx, ty)
	if not cache.has(key):
		var p := Paths.data("terrain/pv/0/%d_%d.png" % [tx, ty])
		var img: Image = null
		if FileAccess.file_exists(p):
			img = Image.new()
			if img.load_png_from_buffer(FileAccess.get_file_as_bytes(p)) != OK:
				img = null
		cache[key] = img
	return cache[key]


func test_pavement_mask_covers_the_big_airports_stands() -> String:
	if not FileAccess.file_exists(Paths.data("terrain/pv/0/-8_4.png")):
		return ""
	var ops = Paths.load_json("airport_ops.json")
	if ops == null:
		return ""
	var cache := {}
	for icao in BIG:
		if not ops.has(icao):
			continue
		var n := 0
		var paved := 0
		for s in ops[icao].stands:
			var x := float(s.x)
			var y := float(s.y)
			var tx := floori(x / TILE)
			var ty := floori(y / TILE)
			var img := _pv(tx, ty, cache)
			n += 1
			if img == null:
				continue
			if img.get_format() != Image.FORMAT_RGBA8 or img.get_width() != RN:
				return "%d_%d.png is not a %d px RGBA8 image" % [tx, ty, RN]
			var px := clampi(int((x - tx * TILE) / TILE * RN), 0, RN - 1)
			var py := clampi(int((1.0 - (y - ty * TILE) / TILE) * RN), 0, RN - 1)
			var c := img.get_pixel(px, py)
			var surf := int(roundf(c.a * 255.0)) & 3
			if surf > 0 and c.r * 16.0 - 8.0 < 0.0 and c.g < 0.95:
				paved += 1
		if n > 0 and paved < n * 0.95:
			return "%s: only %d of %d stands are on pavement with a lead-in" % [icao, paved, n]
	return ""


func test_road_cache_loads_the_pavement_with_the_road_tile() -> String:
	if not FileAccess.file_exists(Paths.data("terrain/pv/0/-8_4.png")):
		return ""
	var r := TerrainRoads.new()
	r.texture(-8, 4)
	for i in 200:
		r.wait_all()
		r.process()
		if r.is_settled(-8, 4):
			break
	if r.pavement(-8, 4) == null:
		return "TerrainRoads did not load the VABB pavement mask"
	return ""
