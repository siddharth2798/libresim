class_name TreeSampler
extends RefCounted
## Worker-thread side of Trees: generates one chunk's MultiMesh buffer straight from the
## land-class (.r8.gz) and level-0 height (.r16) files, so no per-tree script work runs on
## the main thread (it used to: 2 chunks x 2304 landclass_at + height_at calls per frame,
## 20-90 ms hitches). Placement is identical to Trees.tree_top_at (same hashes, same
## bilinear heights as TerrainTileCache.height_at). File caches are mutex-guarded.

const MAX_CACHED := 24

var _tile_size: float
var _tile_n: int
var _h_scale: float
var _h_offset: float
var _img_n: int
var _mutex := Mutex.new()
var _lc := {}  # Vector3i source tile -> PackedByteArray (IMG_N^2, row 0 = north) or empty
var _h := {}  # Vector2i level-0 tile -> PackedByteArray (r16) or empty


func _init(cache: TerrainTileCache) -> void:
	_tile_size = cache.tmeta.tile_size_m
	_tile_n = cache.tile_n
	_h_scale = cache.h_scale
	_h_offset = cache.h_offset
	_img_n = TerrainTileCache.IMG_N


static func hash3(x: int, y: int, k: int) -> float:
	return float(posmod((x * 73856093) ^ (y * 19349663) ^ (k * 83492791), 100003)) / 100003.0


## Worker thread. src: land-class source tile (TerrainMeta.tex_source, looked up on the main
## thread) and its size in metres. Returns MultiMesh.buffer data (12 xform + 4 custom floats
## per tree), positions relative to the chunk's SW corner.
func build(x0: float, y0: float, chunk: float, px: float, src: Vector3i, src_size: float, density: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var lc := _lc_bytes(src)
	if lc.is_empty():
		return out
	var n := int(chunk / px)
	var sx0 := src.y * src_size
	var sy0 := src.z * src_size
	for j in n:
		for i in n:
			var e := x0 + (i + 0.5) * px
			var no := y0 + (j + 0.5) * px
			var cx := clampi(int((e - sx0) / src_size * _img_n), 0, _img_n - 1)
			var cy := clampi(int((1.0 - (no - sy0) / src_size) * _img_n), 0, _img_n - 1)
			var v := lc[cy * _img_n + cx]
			if v == 0 or v == 255:
				continue
			var gi := int(e / px)
			var gj := int(no / px)
			if hash3(gi, gj, 1) > v / 200.0 * 0.8 * density:
				continue
			var tx := e + (hash3(gi, gj, 2) - 0.5) * px * 0.8
			var ty := no + (hash3(gi, gj, 3) - 0.5) * px * 0.8
			var h := height_at(tx, ty)
			var height := lerpf(6.0, 15.0, hash3(gi, gj, 4))
			var width := height * lerpf(0.55, 0.85, hash3(gi, gj, 5))
			var b := Basis(Vector3.UP, hash3(gi, gj, 6) * TAU).scaled(Vector3(width, height, width))
			out.append_array([b.x.x, b.y.x, b.z.x, tx - x0,
				b.x.y, b.y.y, b.z.y, h - 0.3,
				b.x.z, b.y.z, b.z.z, -(ty - y0),
				hash3(gi, gj, 7), hash3(gi, gj, 8), hash3(gi, gj, 9), hash3(gi, gj, 10)])
	return out


## Same bilinear interpolation of level-0 samples as TerrainTileCache.height_at.
func height_at(east: float, north: float) -> float:
	var tx := floori(east / _tile_size)
	var ty := floori(north / _tile_size)
	var b := _h_bytes(Vector2i(tx, ty))
	if b.is_empty():
		return 0.0
	var res := _tile_size / _tile_n
	var fx := (east - tx * _tile_size) / res
	var fy := (north - ty * _tile_size) / res
	var i := clampi(floori(fx), 0, _tile_n - 1)
	var j := clampi(floori(fy), 0, _tile_n - 1)
	var u := fx - i
	var v := fy - j
	var w := _tile_n + 1
	var h00 := b.decode_u16((j * w + i) * 2)
	var h10 := b.decode_u16((j * w + i + 1) * 2)
	var h01 := b.decode_u16(((j + 1) * w + i) * 2)
	var h11 := b.decode_u16(((j + 1) * w + i + 1) * 2)
	return lerpf(lerpf(h00, h10, u), lerpf(h01, h11, u), v) * _h_scale + _h_offset


func _lc_bytes(src: Vector3i) -> PackedByteArray:
	_mutex.lock()
	var b = _lc.get(src)
	_mutex.unlock()
	if b != null:
		return b
	var p := Paths.data("terrain/lc/%d/%d_%d.r8.gz" % [src.x, src.y, src.z])
	var out := PackedByteArray()
	if FileAccess.file_exists(p):
		out = FileAccess.get_file_as_bytes(p).decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
		if out.size() != _img_n * _img_n:
			out = PackedByteArray()
	_store(_lc, src, out)
	return out


func _h_bytes(k: Vector2i) -> PackedByteArray:
	_mutex.lock()
	var b = _h.get(k)
	_mutex.unlock()
	if b != null:
		return b
	var p := Paths.data("terrain/h/0/%d_%d.r16" % [k.x, k.y])
	var out := PackedByteArray()
	if FileAccess.file_exists(p):
		out = FileAccess.get_file_as_bytes(p)
		if out.size() != (_tile_n + 1) * (_tile_n + 1) * 2:
			out = PackedByteArray()
	_store(_h, k, out)
	return out


func _store(d: Dictionary, k: Variant, v: PackedByteArray) -> void:
	_mutex.lock()
	if d.size() >= MAX_CACHED:
		d.erase(d.keys()[0])  # oldest inserted
	d[k] = v
	_mutex.unlock()
