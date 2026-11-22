class_name TerrainHeights
extends RefCounted
## Terrain height (m) anywhere in the world without a flight scene (the start screen's route profile and checks). Reads
## the heightmap tiles (terrain/h/<level>/<tx>_<ty>.r16, layout in tools/02_dem_tiles.py) synchronously from the finest
## level that covers the point (level 0 near the airports, the coarse outer ring further out), interpolated bilinearly,
## rows from the south edge as TerrainTileCache.height_at reads them. Keeps at most MAX_TILES tiles. 0 m (sea level)
## where no tile covers the point; covers() tells the two apart. shared() is the one instance the menu uses.

const MAX_TILES := 48

static var _shared: TerrainHeights

var meta: TerrainMeta
var _tiles := {}  # Vector3i(level, tx, ty) -> PackedByteArray


static func shared() -> TerrainHeights:
	if _shared == null:
		_shared = TerrainHeights.new()
	return _shared


func _init() -> void:
	meta = TerrainMeta.new()


## The finest tile (level, tx, ty) covering world (east, north); TerrainMeta.NONE when none does.
func source(east: float, north: float) -> Vector3i:
	if meta.levels.is_empty():
		return TerrainMeta.NONE
	var size: float = meta.tile_size_m
	return meta.height_source(0, floori(east / size), floori(north / size))


func covers(east: float, north: float) -> bool:
	return source(east, north) != TerrainMeta.NONE


func height_at(east: float, north: float) -> float:
	var k := source(east, north)
	if k == TerrainMeta.NONE:
		return 0.0
	var b: PackedByteArray = _tiles.get(k, PackedByteArray())
	var w: int = meta.tile_n + 1
	if b.is_empty():
		b = FileAccess.get_file_as_bytes(Paths.data("terrain/h/%d/%d_%d.r16" % [k.x, k.y, k.z]))
		if b.size() != w * w * 2:
			return 0.0
		if _tiles.size() >= MAX_TILES:
			_tiles.erase(_tiles.keys()[0])  # oldest inserted
		_tiles[k] = b
	var size := meta.level_size(k.x)
	var res := size / meta.tile_n
	var fx := (east - k.y * size) / res
	var fy := (north - k.z * size) / res
	var i := clampi(floori(fx), 0, meta.tile_n - 1)
	var j := clampi(floori(fy), 0, meta.tile_n - 1)
	var u := clampf(fx - i, 0.0, 1.0)
	var v := clampf(fy - j, 0.0, 1.0)
	var h00 := b.decode_u16((j * w + i) * 2)
	var h10 := b.decode_u16((j * w + i + 1) * 2)
	var h01 := b.decode_u16(((j + 1) * w + i) * 2)
	var h11 := b.decode_u16(((j + 1) * w + i + 1) * 2)
	var hv := lerpf(lerpf(h00, h10, u), lerpf(h01, h11, u), v)
	return hv * meta.h_scale + meta.h_offset
