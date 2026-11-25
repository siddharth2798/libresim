class_name AirportCut
extends RefCounted
## Cuts one airport group (AirportGroups) into surface arrays: one ribbon per runway (its own material, bake and tyre
## marks), ONE merged mesh for all the airport's taxiways and ONE for its lead-on lines. The taxiway mesh keeps each
## ribbon's width and "paint the edges" flag in UV2 (strip.gdshaderinc), so a single shared material draws them all.
## Pure and thread-safe when the cache is used by one thread only (AirportBuilder's worker, or the main thread).

const TAXI_MAX_W := 23.0  # a taxiway ribbon is drawn at most this wide (pushback_fit.gd DRAWN_MAX)
const LEAD_W := 1.0


## {runways: [{rec, arrays, anchor, along}], taxi: {arrays, anchor, area} or {}, lead: {...} or {}}. anchor = ENU
## (x, y of a lattice point, ground height there): the mesh vertices are metres from it.
static func cut(g: Dictionary, cache: TerrainTileCache) -> Dictionary:
	var res := cache.tmeta.tile_size_m / cache.tile_n
	var out := {"runways": [], "taxi": {}, "lead": {}}
	for r in g.runways:
		var a := Vector2(r.ends[0].x, r.ends[0].y)
		var b := Vector2(r.ends[1].x, r.ends[1].y)
		var o := GroundDrape.snap(a.x, a.y, res)
		var anchor := Vector3(o.x, o.y, cache.height_at(a.x, a.y))
		var tris := PackedVector2Array()
		var uvs := PackedVector2Array()
		var along := GroundDrape.strip([a - o, b - o], float(r.width), tris, uvs)
		var arr := GroundDrape.arrays(tris, uvs, anchor.x, anchor.y, anchor.z, cache.height_at, res)
		if not arr.is_empty():
			out.runways.append({"rec": r, "arrays": arr, "anchor": anchor, "along": along})
	var taxi: Array = []
	for tw in g.taxis:
		var pts: Array[Vector2] = []
		for p in tw.pts:
			pts.append(Vector2(p[0], p[1]))
		var known := bool(tw.get("width_known", absf(float(tw.width) - 15.0) > 0.01))
		taxi.append([pts, minf(float(tw.width), TAXI_MAX_W), known])
	out.taxi = merged(taxi, g.centre, cache, res)
	var lead: Array = []
	for run in g.leads:
		lead.append([run, LEAD_W, false])
	out.lead = merged(lead, g.centre, cache, res)
	return out


## One mesh for ribbons [[pts Array[Vector2] ENU, width m, edge lines]], vertices from the lattice point at `centre`.
## UV2 = (width, 1 or 0 edge lines). {} when nothing is left.
static func merged(ribbons: Array, centre: Vector2, cache: TerrainTileCache, res: float) -> Dictionary:
	if ribbons.is_empty():
		return {}
	var o := GroundDrape.snap(centre.x, centre.y, res)
	var anchor := Vector3(o.x, o.y, cache.height_at(centre.x, centre.y))
	var tris := PackedVector2Array()
	var uvs := PackedVector2Array()
	var uvs2 := PackedVector2Array()
	var total := 0.0
	for rb in ribbons:
		var pts: Array = rb[0]
		if pts.size() < 2:
			continue
		var local: Array = []
		for p in pts:
			local.append(p - o)
		var n0 := tris.size()
		total += GroundDrape.strip(local, rb[1], tris, uvs) * rb[1]
		var tag := Vector2(rb[1], 1.0 if rb[2] else 0.0)
		for i in tris.size() - n0:
			uvs2.append(tag)
	var arr := GroundDrape.arrays(tris, uvs, anchor.x, anchor.y, anchor.z, cache.height_at, res, uvs2)
	if arr.is_empty():
		return {}
	return {"arrays": arr, "anchor": anchor, "area": total}
