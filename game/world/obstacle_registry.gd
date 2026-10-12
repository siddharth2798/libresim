class_name ObstacleRegistry
extends RefCounted
## Shared list of solids that are not streamed with the terrain: landmark terminal models,
## jetways, parked vehicles, masts, windsocks. Whoever draws the thing registers its record
## (ObstacleShapes.disc / poly / box / grid) under a group name and removes the group when it
## frees the node. Static: one registry per process, queried by FdmNode through FDM.obstacles.
## (Trees and OSM buildings stream their own collision data: Trees.near, Buildings.near.)

const CELL := 64.0  # spatial hash cell (m)

static var _cells := {}  # Vector2i -> Array of records
static var _groups := {}  # group -> Array of records
static var _corr_cells := {}  # same, for corridors (below)
static var _corr_groups := {}


static func add(group: String, rec: Dictionary) -> void:
	_insert(_cells, _groups, group, rec)


static func remove_group(group: String) -> void:
	_erase(_cells, _groups, group)


## Corridors: where the aircraft is meant to drive (taxiway centrelines, runways, stands). While the
## CG is inside one, "soft" solids (OSM buildings, trees: footprints are not survey-grade) are forgiven.
static func add_corridor(group: String, rec: Dictionary) -> void:
	_insert(_corr_cells, _corr_groups, group, rec)


static func remove_corridors(group: String) -> void:
	_erase(_corr_cells, _corr_groups, group)


static func in_corridor(e: float, n: float) -> bool:
	for rec in _corr_cells.get(Vector2i(floori(e / CELL), floori(n / CELL)), []):
		var lo: Vector2 = rec.lo
		var hi: Vector2 = rec.hi
		if e >= lo.x and e <= hi.x and n >= lo.y and n <= hi.y and Geometry2D.is_point_in_polygon(Vector2(e, n), rec.poly):
			return true
	return false


## Does a POLY record overlap any corridor?
static func overlaps_corridor(rec: Dictionary) -> bool:
	var lo: Vector2 = rec.lo
	var hi: Vector2 = rec.hi
	for cy in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
		for cx in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
			for c in _corr_cells.get(Vector2i(cx, cy), []):
				if c.lo.x <= hi.x and c.hi.x >= lo.x and c.lo.y <= hi.y and c.hi.y >= lo.y \
						and not Geometry2D.intersect_polygons(c.poly, rec.poly).is_empty():
					return true
	return false


static func _insert(cells: Dictionary, groups: Dictionary, group: String, rec: Dictionary) -> void:
	if not groups.has(group):
		groups[group] = []
	groups[group].append(rec)
	var lo: Vector2 = rec.lo
	var hi: Vector2 = rec.hi
	for cy in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
		for cx in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
			var k := Vector2i(cx, cy)
			if not cells.has(k):
				cells[k] = []
			cells[k].append(rec)


static func _erase(cells: Dictionary, groups: Dictionary, group: String) -> void:
	var recs: Array = groups.get(group, [])
	for rec in recs:
		var lo: Vector2 = rec.lo
		var hi: Vector2 = rec.hi
		for cy in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
			for cx in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
				var k := Vector2i(cx, cy)
				var arr: Array = cells.get(k, [])
				for i in range(arr.size() - 1, -1, -1):
					if arr[i].id == rec.id:
						arr.remove_at(i)
				if arr.is_empty():
					cells.erase(k)
	groups.erase(group)


static func clear() -> void:
	_cells.clear()
	_groups.clear()
	_corr_cells.clear()
	_corr_groups.clear()


static func count(group := "") -> int:
	if group != "":
		return _groups.get(group, []).size()
	var n := 0
	for g in _groups:
		n += _groups[g].size()
	return n


## Appends to out the records whose bounding box is within r of (east, north).
static func near(e: float, n: float, r: float, out: Array) -> void:
	if _cells.is_empty():
		return
	var cx0 := floori((e - r) / CELL)
	var cy0 := floori((n - r) / CELL)
	for cy in range(cy0, floori((n + r) / CELL) + 1):
		for cx in range(cx0, floori((e + r) / CELL) + 1):
			for rec in _cells.get(Vector2i(cx, cy), []):
				var lo: Vector2 = rec.lo
				var hi: Vector2 = rec.hi
				if lo.x > e + r or hi.x < e - r or lo.y > n + r or hi.y < n - r:
					continue
				# a record spanning several cells is reported from the first one the query shares with it
				if maxi(floori(lo.x / CELL), cx0) == cx and maxi(floori(lo.y / CELL), cy0) == cy:
					out.append(rec)
