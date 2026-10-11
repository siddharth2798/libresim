class_name AirportLights
extends RefCounted
## Builds the complete aerodrome lighting of one airport as a Node3D: runway lights,
## approach lights, PAPIs, taxiway lights, stop bars and apron floodlights. One
## MultiMesh per material group; positions relative to the airport anchor (ENU).
## mats: group name -> material (see RunwayLights.GROUPS) plus "pool".

const BIG_AIRPORT_TAXIWAYS := 20  # more taxiways than this: green centreline lights
const MIN_LIT_LEN := 600.0

var root: Node3D
var papis: Array = []  # [[ident, units]] for read-outs
var masts: Array = []  # Vector2 ENU of floodlight masts
var counts := {}  # group -> light count


## Runway descriptor used by the layouts. ils_rwys: idents of runway ends with an ILS;
## gs: ident -> ENU Vector2 of the glide-slope antenna.
static func describe(rw: Dictionary, ils_rwys: Array, gs := {}) -> Dictionary:
	var e0: Dictionary = rw.ends[0]
	var e1: Dictionary = rw.ends[1]
	var a := Vector2(e0.x, e0.y)
	var b := Vector2(e1.x, e1.y)
	var L := a.distance_to(b)
	var ils := [str(e0.ident) in ils_rwys, str(e1.ident) in ils_rwys]
	var gs_dist := [-1.0, -1.0]
	for i in 2:
		var id := str(rw.ends[i].ident)
		if gs.has(id):
			var t := a if i == 0 else b
			var d := (b - a) / L * (1.0 if i == 0 else -1.0)
			gs_dist[i] = (gs[id] - t).dot(d)
	return {"a": a, "b": b, "len": L, "width": float(rw.width), "u": (b - a) / L,
		"idents": [str(e0.ident), str(e1.ident)], "ils": ils, "gs_dist": gs_dist,
		"instrument": ils[0] or ils[1] or L >= 1800.0, "centreline": ils[0] or ils[1] or L >= 2000.0}


## Lit runways: ICAO-coded airports (not strips like IN-xxxx), at least MIN_LIT_LEN long.
static func is_lit(icao: String, rw: Dictionary) -> bool:
	return not icao.begins_with("IN-") and float(rw.length) >= MIN_LIT_LEN


func build(icao: String, runways: Array, taxiways: Array, ils: Array, ops: Dictionary,
		hf: Callable, mats: Dictionary) -> Node3D:
	root = Node3D.new()
	root.name = "lights_" + icao
	var lit := runways.filter(func(rw): return is_lit(icao, rw))
	if lit.is_empty():
		return root
	var anchor := Vector2(lit[0].ends[0].x, lit[0].ends[0].y)
	root.set_meta("anchor", anchor)
	var sets := {}
	for g in mats:
		if g != "pool":
			sets[g] = LightSet.new(anchor)
	var ils_rwys := []
	var gs := {}
	for e in ils:
		if e.airport == icao:
			ils_rwys.append(str(e.runway))
			gs[str(e.runway)] = Vector2(e.gs.x, e.gs.y)
	var rs := []
	var boxes := []
	for rw in lit:
		var r := describe(rw, ils_rwys, gs)
		rs.append(r)
		RunwayLightLayout.build(r, hf, sets.rwy)
		for i in 2:
			ApproachLights.build(r, i, hf, sets.app, sets.flash)
			var u := Papi.units(r, i, hf, r.gs_dist[i])
			if not u.is_empty():
				Papi.add_units(u, sets.papi, boxes)
				papis.append([r.idents[i], u])
	var tl := TaxiwayLights.new(taxiways, rs, ops.get("stands", []))
	var centre := taxiways.size() > BIG_AIRPORT_TAXIWAYS
	for ti in taxiways.size():
		tl.taxiway(taxiways, ti, centre, hf, sets.taxi)
	for hp in ops.get("holds", []):
		tl.hold(Vector2(hp.x, hp.y), hf, sets.stop)
	masts = ApronFloodlights.masts(ops.get("stands", []))
	ApronFloodlights.add_heads(masts, hf, sets.flood)
	for g in sets:
		counts[g] = sets[g].count
		var mi: MultiMeshInstance3D = sets[g].make_instance(mats[g], g)
		if mi:
			root.add_child(mi)
	var hs := Papi.housings(boxes, anchor)
	if hs:
		root.add_child(hs)
	for m in ApronFloodlights.meshes(masts, hf, anchor, mats.get("pool")):
		root.add_child(m)
	return root
