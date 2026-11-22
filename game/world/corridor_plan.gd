class_name CorridorPlan
extends RefCounted
## The corridor boxes of one airport (OpsCorridors), worked out in two halves so a far airport can be planned on a
## worker thread (CorridorBook):
##   job()     main thread: reads the aircraft (AircraftDef, GroundParams) and copies what the plan needs.
##   compute() any thread: pure maths on the job's own copies (PushbackFit with pave off, PushbackPath), no shared state.
##   insert()  main thread: the boxes go into ObstacleRegistry under "corridor:<icao>".
## A box is 5 floats in a PackedFloat64Array: centre east, centre north, half length, half width, heading (rad).

const STRIDE := 5
const _Fit := preload("res://world/pushback_fit.gd")


## ops: one airport of airport_ops.json; runways: its runways.json entries; def: the aircraft (null = the current one).
static func job(icao: String, ops: Dictionary, runways: Array, def: AircraftDef = null) -> Dictionary:
	var d := def if def != null else AircraftDef.current()
	var fp := d.section_or("ground", OpsCorridors.FOOTPRINT)
	var stands := []
	for s in ops.get("stands", []):
		stands.append([GroundParams.cg_at_stand(s, d), deg_to_rad(float(s.heading_deg))])  # the CG sits behind a gate's door point
	var wheels := _Fit.wheels(d)
	if wheels.is_empty():
		wheels = PackedVector2Array([Vector2(2.0, 0.0)])  # unused with pave off; keeps plan() off the aircraft
	var rws := []
	for r in runways:
		rws.append([Vector2(r.ends[0].x, r.ends[0].y), Vector2(r.ends[1].x, r.ends[1].y), float(r.width) * 0.5 + OpsCorridors.RUNWAY_MARGIN])
	return {"icao": icao, "stands": stands, "taxi": (ops.get("taxi", {}) as Dictionary).duplicate(true), "runways": rws,
		"pb": GroundParams.pushback(d).duplicate(true), "wheels": wheels, "ahead": float(fp.ahead_m), "behind": float(fp.behind_m),
		"across": float(fp.across_m), "taxi_half": float(fp.get("taxi_half_m", OpsCorridors.TAXI_HALF))}


## Every stand's footprint along both pushback swings, every taxi edge, every runway strip. Same boxes, same order
## as the single-pass registration had.
static func compute(j: Dictionary) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var ahead: float = j.ahead
	var behind: float = j.behind
	var taxi: Dictionary = j.taxi
	var segs := _Fit.segments(taxi)  # once per airport, not once per stand
	var memo := {}  # a stand's target taxiway, shared by its two sides
	for st in j.stands:
		var p0: Vector2 = st[0]
		var h0: float = st[1]
		for side in [1.0, -1.0]:
			var fit: Dictionary = _Fit.plan(p0, h0, taxi, side, j.pb, null, true, false, j.wheels, segs, memo)
			for dist in PushbackPath.samples(fit.straight, fit.radius, true, fit.turn):
				var pose := PushbackPath.pose(p0, h0, fit.side, dist, fit.straight, fit.radius, fit.turn)
				var hd: float = pose[1]
				var c: Vector2 = pose[0] + Vector2(sin(hd), cos(hd)) * ((ahead - behind) * 0.5)
				out.append_array([c.x, c.y, (ahead + behind) * 0.5, j.across, hd])
	var nodes: Dictionary = taxi.get("nodes", {})
	for e in taxi.get("edges", []):
		var a := Vector2(nodes[e[0]][0], nodes[e[0]][1])
		var b := Vector2(nodes[e[1]][0], nodes[e[1]][1])
		_strip(out, a, b, 30.0 if e[4] == "runway" else float(j.taxi_half), 4.0)
	for r in j.runways:
		_strip(out, r[0], r[1], r[2], 0.0)
	return out


## For WorkerThreadPool: the result goes into `into.boxes` (the caller reads it after the task completes).
static func compute_into(j: Dictionary, into: Dictionary) -> void:
	into.boxes = compute(j)


static func _strip(out: PackedFloat64Array, a: Vector2, b: Vector2, half: float, extra: float) -> void:
	var d := b - a
	if d.length() < 0.5:
		return
	var c := (a + b) * 0.5
	out.append_array([c.x, c.y, d.length() * 0.5 + extra, half, atan2(d.x, d.y)])


## Boxes [from, to) (box indices) into the registry. Returns the number of boxes in `boxes`.
static func insert(icao: String, boxes: PackedFloat64Array, from := 0, to := -1) -> int:
	var n := boxes.size() / STRIDE
	var group := "corridor:" + icao
	for i in range(from, n if to < 0 else mini(to, n)):
		var k := i * STRIDE
		ObstacleRegistry.add_corridor(group, ObstacleShapes.box(Vector2(boxes[k], boxes[k + 1]), boxes[k + 2], boxes[k + 3], boxes[k + 4], 0.0, 0.0, ""))
	return n
