class_name TerrainHelperMaps
extends RefCounted
## Size rules for the ground tiles' helper maps (TerrainTileCache._load_t, on a worker): land class (R8, 255 water,
## 1..200 tree density; the shader samples it bilinear), WorldCover class (R8, categorical; the shader reads it with
## texelFetch only) and shore distance / openness (RG8, smooth; bilinear). The files stay 768² per tile at every level.
## Level 0 (7.68 km tiles, the ground within ~10 km) keeps them at full size: that is where the detail textures,
## shore foam and sand are drawn. Coarser levels (15 km tiles and up, drawn beyond ~10 km) keep half: the satellite
## image already carries the look there, and every helper map shrinks from 2.36 MB to 0.59 MB per tile.
## Land class and WorldCover shrink by nearest texel (no class ID is ever blended into another); the shore distance
## bilinear (it is a distance field).
## CPU copies (landclass_at / worldcover_at for trees, ground cover, the FDM's surface checks) are kept only for the
## tiles those lookups read: level 0, or the coarser tile standing in where level 0 has no mask (cpu_source).

const FULL := 768
const COARSE_DIV := 2


## Texel size of the helper maps at `level` (FULL at level 0, FULL / COARSE_DIV above).
static func size_for(level: int) -> int:
	return FULL if level <= 0 else FULL / COARSE_DIV


## Shrinks the helper maps of a tile at `level` in place (null entries are left alone).
static func shrink(level: int, lc: Image, wc: Image, sd: Image) -> void:
	var n := size_for(level)
	for img in [lc, wc]:
		if img != null and img.get_width() != n:
			img.resize(n, n, Image.INTERPOLATE_NEAREST)
	if sd != null and sd.get_width() != n:
		sd.resize(n, n, Image.INTERPOLATE_BILINEAR)


## True when landclass_at / worldcover_at read texture source `key` (level, tx, ty): it is a level-0 tile, or the
## ancestor TerrainMeta.tex_source picks for the level-0 tile at its own corner (a region without level-0 masks).
static func cpu_source(tmeta: TerrainMeta, key: Vector3i) -> bool:
	if key.x <= 0:
		return true
	var k := 1 << key.x
	return tmeta.tex_source(0, key.y * k, key.z * k, TerrainMeta.HAS_LC) == key


## Video memory of the helper maps of one texture entry (bytes), for budgets and tests.
static func gpu_bytes(e: Dictionary) -> int:
	var b := 0
	for f in ["lctex", "wctex", "sdtex"]:
		var t = e.get(f)
		if t is Texture2D:
			var w: int = t.get_width()
			b += w * t.get_height() * (2 if f == "sdtex" else 1)
	return b
