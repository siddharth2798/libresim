class_name VisChunks
extends RefCounted
## A MultiMesh spread over a whole airport (lamp masts, lamp frames) has one draw distance, measured to the middle of the
## airport, which says nothing about any one mast. cells() sorts the items into CELL-metre cells so each cell is built as
## its own MultiMeshInstance3D with its own VisRanges range: the size rule for its largest item plus the cell's half
## diagonal (the item farthest from the cell middle keeps at least its own range). Cells also let the camera's frustum
## skip whole parts of the airport.

const CELL := 400.0  # m


## items grouped by cell of pos.call(item) -> Vector2 (east, north); groups in a stable order.
static func cells(items: Array, pos: Callable, cell := CELL) -> Array:
	var by := {}
	for it in items:
		var p: Vector2 = pos.call(it)
		var k := Vector2i(floori(p.x / cell), floori(p.y / cell))
		if not by.has(k):
			by[k] = []
		by[k].append(it)
	var keys := by.keys()
	keys.sort()
	return keys.map(func(k): return by[k])


## Base range (High, unzoomed) of a cell whose largest item has this size (VisRanges.size_of).
static func cell_range(size_m: float, cell := CELL) -> float:
	return VisRanges.end_for(size_m) + cell * 0.71


## Lamp masts / poles (ApronLightLayout records {p, h, kind}): the size of the largest (a mast is 0.84 m across at the
## foot, a pole 0.3 m; ApronFloodlights._poles).
static func mast_size(lights: Array) -> float:
	var s := 0.0
	for m in lights:
		var w := 0.84 if m.kind == "mast" else 0.3
		s = maxf(s, sqrt(float(m.h) * w))
	return s
