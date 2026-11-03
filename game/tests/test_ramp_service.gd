extends RefCounted
## The ramp crew around a parked aircraft (world/ramp_points.gd, ramp_layout.gd, ramp_crew.gd), for every
## aircraft in AircraftDef.list_ids(): each service vehicle is there, clear of the airframe (keep-out shapes
## and the FDM's own hull segments), of the other vehicles and of solids in the way, close to its
## service point; the crew comes when the aircraft is parked and clears away before it moves.

const GROUP := "ramp:RTEST"
const TOL := {"tug": 7.0, "gpu": 4.0, "fuel": 9.0, "cargo": 7.0, "bus": 8.0}  # m from footprint to its service point


static func _stands() -> Array:
	return [{"ref": "G1", "x": 0.0, "y": 0.0, "heading_deg": 0.0, "kind": "gate", "jetbridge": true},
		{"ref": "R7", "x": 300.0, "y": -40.0, "heading_deg": 117.0, "kind": "remote", "jetbridge": false},
		{"ref": "GA2", "x": -250.0, "y": 90.0, "heading_deg": 271.0, "kind": "remote", "jetbridge": false}]


func teardown() -> void:
	ObstacleRegistry.remove_group(GROUP)
	ObstacleRegistry.remove_group("block:RTEST")
	GroundVehicles.release()


## The services each aircraft should get on a stand, from its own ramp points.
static func _wanted(rp: Dictionary, gate: bool) -> Dictionary:
	var w := {"tug": 1 if rp.tug else 0, "gpu": 1 if rp.gpu != null else 0, "fuel": 1 if rp.refuel != null else 0,
		"cargo": 3 * rp.cargo.size(), "bus": 1 if (not gate and rp.big and not rp.doors.is_empty()) else 0}
	return w


func test_ramp_every_aircraft_gets_its_crew() -> String:
	for id in AircraftDef.list_ids():
		var def := AircraftDef.load_def(id)
		var rp := RampPoints.of(def)
		for st in _stands():
			var got := {}
			for v in RampLayout.plan(def, st):
				got[v.service] = int(got.get(v.service, 0)) + 1
			var want := _wanted(rp, st.jetbridge)
			for k in want:
				if int(got.get(k, 0)) != want[k]:
					return "%s at %s: %d %s vehicles, want %d (got %s)" % [id, st.ref, got.get(k, 0), k, want[k], got]
		if rp.big and (rp.gpu == null or rp.refuel == null or rp.cargo.size() < 2):
			return "%s: an airliner gets ground power, fuel and both holds" % id
	return ""


## Stand frame [f, r, up] of the aircraft's hull segments (ObstacleHull: what the FDM tests for a collision).
static func _hull(def: AircraftDef) -> Array:
	var hull := ObstacleHull.new(def)
	var mb := MassBalance.new(def.config())
	var gz := INF
	for g in def.config().gear:
		gz = minf(gz, float(g.pos_m[2]))
	var out := []
	for i in hull.count():
		var a: Vector3 = hull._a[i]
		var b: Vector3 = hull._b[i]
		out.append([Vector3(mb.cg.x - a.x, a.y, a.z - gz), Vector3(mb.cg.x - b.x, b.y, b.z - gz), hull.names[i]])
	return out


func test_ramp_vehicles_clear_of_the_airframe_and_each_other() -> String:
	for id in AircraftDef.list_ids():
		var def := AircraftDef.load_def(id)
		var parts := RampPoints.keep_out(RampPoints.of(def))
		var hull := _hull(def)
		for st in _stands():
			var vs := RampLayout.plan(def, st)
			for i in vs.size():
				var v: Dictionary = vs[i]
				var r_in := INF
				for p in v.local:
					r_in = minf(r_in, absf(p.y))
				for part in parts:
					if v.top < RampPoints.low_at(part, r_in):
						continue
					if not Geometry2D.intersect_polygons(v.local, part.poly).is_empty():
						return "%s at %s: %s overlaps the %s" % [id, st.ref, v.kind, part.part]
				var rec := ObstacleShapes.poly(v.local, -0.5, float(v.top), "")
				for s in hull:
					if ObstacleShapes.segment_hits(s[0], s[1], rec):
						return "%s at %s: %s touches the hull (%s)" % [id, st.ref, v.kind, s[2]]
				for j in range(i + 1, vs.size()):
					if not Geometry2D.intersect_polygons(v.local, vs[j].local).is_empty():
						return "%s at %s: %s overlaps %s" % [id, st.ref, v.kind, vs[j].kind]
	return ""


func test_ramp_vehicles_at_their_service_points() -> String:
	for id in AircraftDef.list_ids():
		var def := AircraftDef.load_def(id)
		for st in _stands():
			var near := {}  # service point -> distance of the nearest vehicle of its item (a train: its first cart)
			for v in RampLayout.plan(def, st):
				var pt := Vector2(v.point[0], v.point[1])
				var d := 0.0 if Geometry2D.is_point_in_polygon(pt, v.local) else INF
				for i in 4:
					d = minf(d, Geometry2D.get_closest_point_to_segment(pt, v.local[i], v.local[(i + 1) % 4]).distance_to(pt))
				var key := "%s %s" % [v.service, pt]
				near[key] = minf(float(near.get(key, INF)), d)
				if RampLayout.to_world(st, Vector2(v.f, v.r), def).distance_to(v.pos) > 0.01:
					return "%s: world position does not follow the stand frame" % id
			for key in near:
				if near[key] > TOL[key.split(" ")[0]]:
					return "%s at %s: %s %.1f m from its service point (tolerance %.0f)" % [id, st.ref, key, near[key], TOL[key.split(" ")[0]]]
	return ""


func test_ramp_a320_layout_is_the_real_one() -> String:
	var def := AircraftDef.load_def("a320")
	var by := {}
	for v in RampLayout.plan(def, _stands()[0]):
		if not by.has(v.kind):
			by[v.kind] = v
	if not by.has("hydrant_dispenser") or by.has("fuel_truck"):
		return "a contact gate fuels the A320 from the hydrant"
	if by.gpu.r <= 0.0 or by.gpu.f < 10.0:
		return "GPU at the nose, right side (f %.1f r %.1f)" % [by.gpu.f, by.gpu.r]
	if by.hydrant_dispenser.r < 6.0:
		return "dispenser under the right wing, outboard of the engine (r %.1f)" % by.hydrant_dispenser.r
	if by.pushback_tug.f < 16.0 or absf(by.pushback_tug.r) > 0.5:
		return "tug ahead of the nose on the centre line (f %.1f r %.1f)" % [by.pushback_tug.f, by.pushback_tug.r]
	for v in RampLayout.plan(def, _stands()[0]):
		if v.kind.begins_with("baggage") and v.r <= 0.0:
			return "baggage trains on the right side (the cargo doors)"
	return ""


func test_ramp_vehicles_avoid_solids_in_the_way() -> String:
	var def := AircraftDef.load_def("a320")
	var st: Dictionary = _stands()[0]
	var free := RampLayout.plan(def, st)
	var tug := {}
	for v in free:
		if v.kind == "pushback_tug":
			tug = v
	ObstacleRegistry.add("block:RTEST", ObstacleShapes.disc(tug.pos, 2.0, -1.0, 10.0, "a wall"))
	var crew := RampCrew.new()
	var blocked := func(poly: PackedVector2Array, top: float) -> bool: return crew.blocked(poly, top, [])
	var vs := RampLayout.plan(def, st, blocked)
	crew.free()
	for v in vs:
		if Geometry2D.intersect_polygons(v.poly, ObstacleShapes.box(tug.pos, 2.0, 2.0, 0.0, 0.0, 0.0, "").poly).size() > 0:
			return "%s placed into the solid" % v.kind
	return "" if vs.size() >= free.size() - 1 else "a solid in the tug's spot drops more than the tug (%d of %d)" % [vs.size(), free.size()]


func test_ramp_crew_comes_when_parked_and_clears_before_moving() -> String:
	var ops := AirportOps.new()
	var st: Dictionary = _stands()[1]
	ops.data = {"RTEST": {"stands": [st], "taxi": {"nodes": {}, "edges": []}}}
	ops._built = {"RTEST": Node3D.new()}
	var crew := RampCrew.new()
	crew.setup(ops)
	var cg := GroundParams.cg_at_stand(st)
	var keep := {}
	for k in ["fdm/wow", "fdm/groundspeed_mps", "controls/parking_brake", "fdm/position_enu", "fdm/heading_rad", "engine/running", "engine/count", "engines/1/running"]:
		keep[k] = Props.get_v(k, null)
	Props.set_v("fdm/wow", true)
	Props.set_v("fdm/groundspeed_mps", 0.0)
	Props.set_v("controls/parking_brake", true)
	Props.set_v("engine/count", 1)
	Props.set_v("engines/1/running", false)
	Props.set_v("engine/running", false)
	Props.set_v("fdm/position_enu", Vector3(cg.x, cg.y, 0.0))
	Props.set_v("fdm/heading_rad", deg_to_rad(float(st.heading_deg)))
	var msg := ""
	crew._process(1.0)
	if crew.placed.is_empty() or ObstacleRegistry.count(GROUP) != crew.placed.size():
		msg = "parked, brake set, engines off: the crew is there and solid (%d, %d records)" % [crew.placed.size(), ObstacleRegistry.count(GROUP)]
	Props.set_v("engines/1/running", true)
	crew._process(1.0)
	if msg == "" and (not crew.placed.is_empty() or ObstacleRegistry.count(GROUP) != 0):
		msg = "an engine started: the crew clears away"
	Props.set_v("engines/1/running", false)
	crew._process(1.0)
	Props.set_v("controls/parking_brake", false)
	crew._process(1.0)
	if msg == "" and not crew.placed.is_empty():
		msg = "brake released (pushback next): the crew clears away"
	Props.set_v("controls/parking_brake", true)
	Props.set_v("fdm/position_enu", Vector3(cg.x + 8.0, cg.y, 0.0))
	crew._process(1.0)
	if msg == "" and not crew.placed.is_empty():
		msg = "off the stand point: no crew"
	for k in keep:
		if keep[k] != null:
			Props.set_v(k, keep[k])
	crew.clear()
	crew.free()
	ops._built.RTEST.free()
	ops.free()
	return msg
