class_name TreeClear
extends RefCounted
## Runway ribbons (runways.json, plus SHOULDER_M of paved shoulder each side) where no tree may stand, whatever the
## land-class mask says (tools/11 burns OSM aeroways into it, but a strip that only runways.json knows, such as a
## helipad recorded with a runway, would otherwise get trees). Used by every tree path with the same answer:
## TreeSampler.build (worker threads: the index is built once on the main thread, then only read), TreeLod and the
## collision discs (Trees._tree_cell). Loaded lazily from the generated data; empty without it.

const SHOULDER_M := 7.5
const CELL := 500.0  # index cell (m)

static var _cells := {}  # Vector2i -> Array of [a: Vector2, b: Vector2, half width]
static var _loaded := false


## Main thread, before any worker asks (Trees._ready).
static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var rw = Paths.load_json("runways.json")
	if rw == null:
		return
	for r in (rw if rw is Array else rw.get("runways", [])):
		add(Vector2(r.ends[0].x, r.ends[0].y), Vector2(r.ends[1].x, r.ends[1].y), float(r.width) * 0.5 + SHOULDER_M)


static func add(a: Vector2, b: Vector2, hw: float) -> void:
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * hw
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * hw
	for cy in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
		for cx in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
			var k := Vector2i(cx, cy)
			if not _cells.has(k):
				_cells[k] = []
			_cells[k].append([a, b, hw])


## True if a tree trunk at world (east, north) would stand on a runway or its shoulder.
static func blocked(e: float, n: float) -> bool:
	var segs = _cells.get(Vector2i(floori(e / CELL), floori(n / CELL)))
	if segs == null:
		return false
	var p := Vector2(e, n)
	for s in segs:
		var a: Vector2 = s[0]
		var ab: Vector2 = s[1] - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		if p.distance_to(a + ab * t) < s[2]:
			return true
	return false


static func clear() -> void:
	_cells.clear()
	_loaded = false
