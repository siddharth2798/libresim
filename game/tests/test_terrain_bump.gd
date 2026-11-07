extends RefCounted
## Visual terrain bump (G9): amplitude versus preset, distance and the pavement flag.
## The flight-model height path is the height tiles (TerrainQuadtree.height_at), not this offset.


func test_bump_amplitude_rules() -> String:
	if TerrainBump.amplitude_m("low", 0.0, false) != 0.0:
		return "low must be 0"
	if TerrainBump.amplitude_m("medium", 0.0, false) != 1.0:
		return "medium must be half of the 2 m peak"
	var full: PackedStringArray = PackedStringArray(["high", "ultra", "max"])
	for q in full:
		var name: String = q
		if TerrainBump.amplitude_m(name, 0.0, false) != TerrainBump.PEAK_M:
			return "%s must be the 2 m peak" % name
		if TerrainBump.amplitude_m(name, 0.0, true) != 0.0:
			return "%s on pavement must be 0" % name
	if TerrainBump.amplitude_m("medium", 100.0, true) != 0.0:
		return "pavement must be 0 on medium too"
	if TerrainBump.amplitude_m("high", TerrainBump.FAR_M, false) != 0.0:
		return "at 2 km the bump must be 0"
	if TerrainBump.amplitude_m("high", TerrainBump.FAR_M + 500.0, false) != 0.0:
		return "beyond 2 km the bump must be 0"
	if TerrainBump.amplitude_m("high", TerrainBump.FULL_M, false) != TerrainBump.PEAK_M:
		return "inside 1 km the high bump must still be full"
	var mid: float = TerrainBump.amplitude_m("high", 1500.0, false)
	if absf(mid - 1.0) > 0.001:
		return "1500 m should be half of the high peak, got %s" % mid
	if TerrainBump.amplitude_m("medium", 1500.0, false) != 0.5:
		return "medium at 1500 m should be a quarter of the 2 m peak"
	if TerrainBump.amplitude_m("nope", 0.0, false) != 0.0:
		return "an unknown preset must be 0"
	if TerrainBump.peak_m("low") != 0.0 or TerrainBump.peak_m("medium") != 1.0 or TerrainBump.peak_m("max") != 2.0:
		return "preset peaks drifted"
	return ""


func test_bump_is_visual_only() -> String:
	var shader := FileAccess.get_file_as_string("res://world/terrain.gdshader")
	var inc := FileAccess.get_file_as_string("res://world/terrain_bump.gdshaderinc")
	if shader.split("\n").size() >= 300:
		return "terrain.gdshader is 300 lines or more"
	if not shader.contains("terrain_bump.gdshaderinc") or not shader.contains("terrain_bump("):
		return "the terrain shader does not apply the bump"
	if not shader.contains("h_at(") or not shader.contains("curve_local(MODEL_MATRIX, -bump.x)"):
		return "height must still come from h_at, with the bump added along world up"
	if not inc.contains("%.1f" % TerrainBump.FAR_M) or not inc.contains("%.1f" % TerrainBump.FULL_M):
		return "shader fade distances drifted from TerrainBump"
	if not inc.contains("/ 0.875"):
		return "noise must be normalised so the peak stays inside the amplitude"
	if not inc.contains("pv_on < 0.5 && ro_on < 0.5"):
		return "the shader must not displace when the pavement mask is not bound"
	if not inc.contains("cls > 0") or not inc.contains(">= 0.88"):
		return "roads and water must force the bump to 0"
	var cache := FileAccess.get_file_as_string("res://world/terrain_tile_cache.gd")
	var tree := FileAccess.get_file_as_string("res://world/terrain_quadtree.gd")
	if cache.contains("terrain_bump") or cache.contains("bump_amp"):
		return "the height-tile cache must not know about the visual bump"
	var fn := tree.substr(tree.find("func height_at"))
	fn = fn.substr(0, fn.find("\nfunc "))
	if fn.contains("bump") or not fn.contains("cache.height_at"):
		return "TerrainQuadtree.height_at must stay a height-tile lookup"
	if TerrainMesh.GRID != 64:
		return "the shared mesh must stay 64 (the bump does not subdivide it)"
	return ""
