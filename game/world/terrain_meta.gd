class_name TerrainMeta
extends RefCounted
## Terrain tile index: terrain/meta.json (base pyramid) merged with every
## terrain/meta_<region>.json (extra tiles at levels 0-2, e.g. a coastal corridor).
## Tile entry = [min_h, max_h, flags]; flags bit 1 = imagery (img/), bit 2 = land
## class (lc/); a missing flags element means 3. A tile without imagery or land
## class borrows it from its nearest ancestor that has it, on a UV sub-rectangle.
## Region tiles are only merged when their heightmap file is present, so the game
## runs without a region data pack.

const HAS_IMG := 1
const HAS_LC := 2
const NONE := Vector3i(-999, 0, 0)  # "no source tile" sentinel

var tile_n: int
var h_scale: float
var h_offset: float
var tile_size_m: float
var levels: Array = []  # index = level: {size_m, tiles: {"tx_ty": [min, max, flags?]}}
var regions: Array[String] = []  # merged region names (meta_<name>.json)
var _src_cache := {}  # Vector4i(level, tx, ty, bit) -> Vector3i


func _init(dir_rel := "terrain") -> void:
	var base = Paths.load_json(dir_rel.path_join("meta.json"))
	if base == null:
		base = {"tile_n": 256, "h_scale": 0.1, "h_offset": -100.0, "tile_size_m": 7680.0, "levels": []}
	tile_n = int(base.tile_n)
	h_scale = base.h_scale
	h_offset = base.h_offset
	tile_size_m = base.tile_size_m
	for lv in base.levels:
		_merge_level(lv, int(lv.get("level", levels.size())), "", false)
	var files := DirAccess.get_files_at(Paths.data(dir_rel))
	files.sort()
	for f in files:
		if f.begins_with("meta_") and f.ends_with(".json"):
			var r = Paths.load_json(dir_rel.path_join(f))
			if r is Dictionary and r.has("levels"):
				var added := 0
				for lv in r.levels:
					added += _merge_level(lv, int(lv.level), dir_rel, true)
				if added > 0:
					regions.append(f.trim_prefix("meta_").trim_suffix(".json"))


## Adds a level's tiles; base tiles win over region tiles with the same key.
## check_files: only add tiles whose heightmap exists (region packs may be absent).
func _merge_level(lv: Dictionary, level: int, dir_rel: String, check_files: bool) -> int:
	while levels.size() <= level:
		levels.append({"size_m": tile_size_m * pow(2.0, levels.size()), "tiles": {}})
	var dst: Dictionary = levels[level].tiles
	var n := 0
	for k in lv.tiles:
		if dst.has(k):
			continue
		if check_files and not FileAccess.file_exists(Paths.data(dir_rel.path_join("h/%d/%s.r16" % [level, k]))):
			continue
		dst[k] = lv.tiles[k]
		n += 1
	return n


func level_size(level: int) -> float:
	return tile_size_m * pow(2.0, level)


func has_tile(level: int, tx: int, ty: int) -> bool:
	return level >= 0 and level < levels.size() and levels[level].tiles.has("%d_%d" % [tx, ty])


func min_max(level: int, tx: int, ty: int) -> Vector2:
	if level < 0 or level >= levels.size():
		return Vector2.ZERO
	var mm = levels[level].tiles.get("%d_%d" % [tx, ty], [0.0, 0.0])
	return Vector2(mm[0], mm[1])


## Flags bitmask of an existing tile (0 if the tile is absent).
func flags(level: int, tx: int, ty: int) -> int:
	if level < 0 or level >= levels.size():
		return 0
	var e = levels[level].tiles.get("%d_%d" % [tx, ty])
	if e == null:
		return 0
	return int(e[2]) if e.size() > 2 else HAS_IMG | HAS_LC


## Nearest tile at or above `level` (clamped to >= 0) covering (tx, ty) at `level`
## that has the `bit` texture; NONE if no ancestor has it.
func tex_source(level: int, tx: int, ty: int, bit: int) -> Vector3i:
	var ck := Vector4i(level, tx, ty, bit)
	var hit = _src_cache.get(ck)
	if hit != null:
		return hit
	var res := NONE
	for l in range(maxi(level, 0), levels.size()):
		var d := 1 << (l - level)
		var sx := floori(float(tx) / d)
		var sy := floori(float(ty) / d)
		if flags(l, sx, sy) & bit:
			res = Vector3i(l, sx, sy)
			break
	_src_cache[ck] = res
	return res


## Nearest existing tile at or above `level` (clamped to >= 0); NONE if none.
func height_source(level: int, tx: int, ty: int) -> Vector3i:
	for l in range(maxi(level, 0), levels.size()):
		var d := 1 << (l - level)
		var s := Vector3i(l, floori(float(tx) / d), floori(float(ty) / d))
		if has_tile(s.x, s.y, s.z):
			return s
	return NONE


## Quadtree roots: every top-level tile, plus any tile with no ancestor at all.
func roots() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var top := levels.size() - 1
	for l in range(top, -1, -1):
		for k in levels[l].tiles:
			var p: PackedStringArray = k.split("_")
			var tx := int(p[0])
			var ty := int(p[1])
			if l == top or height_source(l + 1, floori(tx / 2.0), floori(ty / 2.0)) == NONE:
				out.append(Vector3i(l, tx, ty))
	return out


## UV sub-rectangle of node (level, tx, ty) inside the texture of source tile src
## (an ancestor or itself): Vector3(u_off, v_off, scale). v is measured from the
## north edge (image row 0), so v_off is the node's SW corner: 1 - sub.y / span.
static func sub_rect(node: Vector3i, src: Vector3i) -> Vector3:
	if src == NONE:
		return Vector3(0.0, 1.0, 1.0)
	var span := 1 << (src.x - node.x)
	var sub := Vector2i(node.y - src.y * span, node.z - src.z * span)
	return Vector3(float(sub.x) / span, 1.0 - float(sub.y) / span, 1.0 / span)
