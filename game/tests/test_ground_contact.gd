extends Node
## The ground the FDM stands on is the ground that is drawn (docs/TYRE-CONTACT-PLAN.md): at sample points on
## runways, taxiways, aprons (stands) and grass at VABB / VAPO / VOCI, TerrainTileCache.height_at (FDM gear,
## ground ops) equals the finest terrain mesh (TerrainMesh triangles over the level-0 heightmap, the same
## diagonal) and the pavement ribbons (AirportBuilder) within 1 cm. Before the fix: bilinear FDM ground up to
## ~20 cm off the drawn triangles on grass, pavement drawn 12 cm above it.
## Needs data/processed (like test_apron_flat); skipped (passes) without terrain data.

const AIRPORTS := ["VABB", "VAPO", "VOCI"]
const TOL := 0.01

var _builder: AirportBuilder
var _qt: TerrainQuadtree
static var _anti := -1  # cached _diag_is_anti()


func teardown() -> void:
	if _builder:
		_builder.free()
		_builder = null
	if _qt:
		_qt.free()
		_qt = null


func _have_data() -> bool:
	return FileAccess.file_exists(Paths.data("terrain/meta.json")) and FileAccess.file_exists(Paths.data("runways.json"))


## The terrain mesh's own split of a grid cell, read from TerrainMesh's index buffer (not assumed): true when
## the cell's first triangle is (i,j) (i,j+1) (i+1,j), i.e. the diagonal runs (i+1,j)-(i,j+1).
static func _diag_is_anti() -> bool:
	var idx: PackedInt32Array = TerrainMesh.build().surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	var w := TerrainMesh.GRID + 1
	var tri := [idx[0], idx[1], idx[2]]
	return tri.has(0) and tri.has(w) and tri.has(1)


## Height of the drawn finest terrain (level -2 nodes: one grid cell per heightmap texel) at ENU (e, n).
static func tri_height(cache: TerrainTileCache, e: float, n: float) -> float:
	var size: float = cache.tmeta.tile_size_m
	var tx := floori(e / size)
	var ty := floori(n / size)
	cache.height_at(e, n)  # loads the CPU tile
	var b: PackedByteArray = cache._cpu_heights.get(Vector2i(tx, ty), PackedByteArray())
	if b.is_empty():
		return 0.0
	var res := size / cache.tile_n
	var fx := (e - tx * size) / res
	var fy := (n - ty * size) / res
	var i := clampi(floori(fx), 0, cache.tile_n - 1)
	var j := clampi(floori(fy), 0, cache.tile_n - 1)
	var u := fx - i
	var v := fy - j
	var w := cache.tile_n + 1
	var h := func(a: int, c: int) -> float: return b.decode_u16(((j + c) * w + i + a) * 2) * cache.h_scale + cache.h_offset
	if _anti < 0:
		_anti = 1 if _diag_is_anti() else 0
	assert(_anti == 1)
	if u + v <= 1.0:
		return h.call(0, 0) + (h.call(1, 0) - h.call(0, 0)) * u + (h.call(0, 1) - h.call(0, 0)) * v
	return h.call(1, 1) + (h.call(0, 1) - h.call(1, 1)) * (1.0 - u) + (h.call(1, 0) - h.call(1, 1)) * (1.0 - v)


## Height of the topmost pavement ribbon (runway / taxiway / lead-on geometry, before shader offsets) at (e, n), or NAN.
func _ribbon_height(e: float, n: float) -> float:
	var best := NAN
	for it in _builder._items:
		var mi: MeshInstance3D = it[0]
		var anc: Vector3 = it[1]
		var lx := e - anc.x
		var lz := -(n - anc.y)
		var bb := mi.mesh.get_aabb()
		if lx < bb.position.x or lx > bb.end.x or lz < bb.position.z or lz > bb.end.z:
			continue
		var a: Array = mi.mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var k := 0
		while k < ix.size():
			var p0 := vs[ix[k]]
			var p1 := vs[ix[k + 1]]
			var p2 := vs[ix[k + 2]]
			k += 3
			var d := (p1.z - p2.z) * (p0.x - p2.x) + (p2.x - p1.x) * (p0.z - p2.z)
			if absf(d) < 1e-9:
				continue
			var l0 := ((p1.z - p2.z) * (lx - p2.x) + (p2.x - p1.x) * (lz - p2.z)) / d
			var l1 := ((p2.z - p0.z) * (lx - p2.x) + (p0.x - p2.x) * (lz - p2.z)) / d
			var l2 := 1.0 - l0 - l1
			if l0 >= -1e-5 and l1 >= -1e-5 and l2 >= -1e-5:
				var hy := l0 * p0.y + l1 * p1.y + l2 * p2.y + anc.z
				best = hy if is_nan(best) else maxf(best, hy)
	return best


## Sample points: {"runway": [...], "taxiway": [...], "apron": [...], "grass": [...]} (Vector2 ENU).
func _samples(icao: String) -> Dictionary:
	var out := {"runway": [], "taxiway": [], "apron": [], "grass": []}
	var near: Array[Vector2] = []
	for r in _builder.data.runways:
		if r.airport != icao:
			continue
		var a := Vector2(r.ends[0].x, r.ends[0].y)
		var b := Vector2(r.ends[1].x, r.ends[1].y)
		near.append((a + b) * 0.5)
		var u := (b - a).normalized()
		var s := Vector2(u.y, -u.x)
		for t in [0.1, 0.23, 0.37, 0.5, 0.61, 0.77, 0.9]:
			for x in [0.0, 0.17, -0.31, 0.44]:
				out.runway.append(a.lerp(b, t) + s * x * float(r.width))
			for g in [1.0, -1.0]:
				out.grass.append(a.lerp(b, t) + s * g * (float(r.width) * 0.5 + 47.0))
	for tw in _builder.data.taxiways:
		var p0 := Vector2(tw.pts[0][0], tw.pts[0][1])
		if near.all(func(c): return c.distance_to(p0) > 4000.0):
			continue
		for i in range(0, tw.pts.size() - 1, 2):
			var a := Vector2(tw.pts[i][0], tw.pts[i][1])
			var b := Vector2(tw.pts[i + 1][0], tw.pts[i + 1][1])
			var s := (b - a).normalized().orthogonal()
			out.taxiway.append(a.lerp(b, 0.43) + s * 0.27 * minf(tw.width, 23.0))
	var ops = Paths.load_json("airport_ops.json")
	if ops is Dictionary and ops.has(icao):
		for s in ops[icao].stands:
			out.apron.append(Vector2(s.x, s.y) + Vector2(3.7, -2.1))
	return out


func _build() -> void:
	_qt = TerrainQuadtree.new()
	_qt.cache = TerrainTileCache.new()
	_builder = AirportBuilder.new()
	var t := Time.get_ticks_msec()
	_builder.build(_qt, true)
	print("    airport ribbons built in %d ms (%d meshes)" % [Time.get_ticks_msec() - t, _builder._items.size()])


func _stat(name: String, d: Array[float]) -> String:
	d.sort()
	return "%s n=%d max %.3f p50 %.3f" % [name, d.size(), d[-1] if not d.is_empty() else 0.0, d[d.size() >> 1] if not d.is_empty() else 0.0]


## FDM ground (height_at) == the drawn finest terrain triangles, everywhere (pavement, apron, grass).
func test_fdm_ground_is_the_drawn_terrain() -> String:
	if not _have_data():
		return ""
	_build()
	var err := ""
	for icao in AIRPORTS:
		var sm := _samples(icao)
		for cat in sm:
			var d: Array[float] = []
			for p in sm[cat]:
				d.append(absf(_qt.cache.height_at(p.x, p.y) - tri_height(_qt.cache, p.x, p.y)))
			print("    %s %s" % [icao, _stat(cat + " |fdm - terrain mesh|", d)])
			if not d.is_empty() and d[-1] > TOL and err == "":
				err = "%s %s: FDM ground is %.3f m off the drawn terrain" % [icao, cat, d[-1]]
	return err


## Runway / taxiway ribbons lie on the FDM ground (no lift, following the terrain across their width).
func test_pavement_is_at_fdm_ground() -> String:
	if not _have_data():
		return ""
	_build()
	var err := ""
	for icao in AIRPORTS:
		var sm := _samples(icao)
		for cat in ["runway", "taxiway"]:
			var d: Array[float] = []
			for p in sm[cat]:
				var r := _ribbon_height(p.x, p.y)
				if not is_nan(r):
					d.append(absf(r - _qt.cache.height_at(p.x, p.y)))
			print("    %s %s" % [icao, _stat(cat + " |ribbon - fdm|", d)])
			if d.size() < 5 and err == "":
				err = "%s %s: only %d samples on a ribbon" % [icao, cat, d.size()]
			elif d[-1] > TOL and err == "":
				err = "%s %s: pavement drawn %.3f m off the FDM ground" % [icao, cat, d[-1]]
	return err
