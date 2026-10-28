extends RefCounted
## Ground operations that depend on the aircraft (aircraft.json "ground" / "pushback": pushback path,
## corridors, stand placement, stand and runway choice, follow-me gap, taxi advice, tug size), on the
## C172 (its defaults must be the constants the code used before they were data) and on an A320-sized
## aircraft built in code (a fixture: the real A320 data comes with its own aircraft folder).

const GROUP := "corridor:P6TEST"


## A320-sized: 37.6 m long, 34.1 m span, 11.8 m tall, door 12.5 m ahead of the CG, nose gear 11 m ahead.
static func a320() -> AircraftDef:
	return AircraftDef.make("a320_fixture", {"name": "A320 fixture",
		"ground": {"tow_ahead_m": 16.0, "ahead_m": 19.5, "behind_m": 19.0, "across_m": 18.3, "height_m": 11.8,
			"cg_to_door_m": 12.5, "door_height_m": 3.0, "nose_gear_m": 11.0, "taxi_half_m": 15.0, "max_taxi_kt": 20.0,
			"hold_short_m": 80.0, "min_runway_m": 1800.0, "stand_class": "gate", "tug_scale": 1.7,
			"service": {"gpu": [2.0, -4.0], "fuel": [-8.0, 20.0]}},
		"pushback": {"straight_m": 45.0, "radius_m": 30.0, "speed_mps": 1.8}}, "res://aircraft/c172")


static func c172() -> AircraftDef:
	return AircraftDef.load_def("c172")


static func _stands() -> Array:
	return [{"ref": "GA1", "x": 0.0, "y": 0.0, "heading_deg": 0.0, "kind": "remote", "jetbridge": false, "src": "synth"},
		{"ref": "Bay 5", "x": 100.0, "y": 0.0, "heading_deg": 0.0, "kind": "remote", "jetbridge": false, "src": "osm"},
		{"ref": "Gate 2", "x": 200.0, "y": 0.0, "heading_deg": 90.0, "kind": "gate", "jetbridge": true, "src": "bridge"}]


# --- the C172's defaults are the old constants -------------------------------------

func test_ground_ops_c172_defaults_are_the_old_constants() -> String:
	var def := c172()
	var g := GroundParams.ground(def)
	var want := {"tow_ahead_m": 3.2, "ahead_m": 3.3, "behind_m": 7.4, "across_m": 6.7, "height_m": 2.5,
		"cg_to_door_m": 0.0, "taxi_half_m": 8.0, "follow_gap_m": 35.0, "hold_short_m": 40.0, "stand_class": "any", "tug_scale": 1.0}
	for k in want:
		if g[k] != want[k]:
			return "c172 ground.%s = %s, want %s" % [k, g[k], want[k]]
	var pb := GroundParams.pushback(def)
	if pb.straight_m != PushbackPath.STRAIGHT or pb.radius_m != PushbackPath.RADIUS or pb.speed_mps != 1.4 \
			or PushbackPath.STRAIGHT != 30.0 or PushbackPath.RADIUS != 18.0:
		return "c172 pushback %s" % [pb]
	if GroundParams.max_taxi_kt(def) != 0.0 or GroundParams.jetway_clear_m(def) != 2.5 or GroundParams.follow_gap_m(def) != 35.0:
		return "c172 taxi limit / jetway clearance / follow gap"
	if OpsCorridors.TAXI_HALF != 8.0 or def.section("ground").has("min_runway_m"):
		return "TAXI_HALF / min_runway_m changed"
	for st in _stands():
		if GroundParams.cg_at_stand(st, def) != Vector2(st.x, st.y):
			return "c172 CG must sit on the stand point of %s" % st.ref
	var ds := PushbackPath.samples(pb.straight_m, pb.radius_m, true)
	var old := [0.0, 10.0, 20.0, 30.0]
	for k in 5:
		old.append(30.0 + 18.0 * PI / 2.0 * k / 4.0)
	if ds.size() != old.size():
		return "c172 corridor samples %d, want %d" % [ds.size(), old.size()]
	for i in ds.size():
		if absf(ds[i] - old[i]) > 1e-4:
			return "c172 corridor sample %d = %.3f, want %.3f" % [i, ds[i], old[i]]
	if GroundChoice.runway_score(3.0, 1500.0, 0.0) != 3.0 + 1.5 or GroundChoice.runway_score(3.0, 1500.0) != 4.5:
		return "c172 runway score must stay headwind + length / 1000"
	return ""


# --- pushback path from data ---------------------------------------------------------

func test_ground_ops_pushback_path_from_data() -> String:
	var pb := GroundParams.pushback(a320())
	var len := PushbackPath.length(pb.straight_m, pb.radius_m)
	if absf(len - (45.0 + 30.0 * PI / 2.0)) > 1e-4:
		return "A320 path length %.2f" % len
	var p0 := Vector2(10.0, 20.0)  # heading north, tail south: 45 m straight back, then a right swing of radius 30
	var end := PushbackPath.pose(p0, 0.0, 1.0, len, pb.straight_m, pb.radius_m)
	if (end[0] as Vector2).distance_to(p0 + Vector2(30.0, -75.0)) > 1e-3 or absf(end[1] + PI / 2.0) > 1e-6:
		return "A320 right pushback ends at %s heading %.3f" % [end[0], end[1]]
	var mid := PushbackPath.pose(p0, 0.0, -1.0, 45.0, pb.straight_m, pb.radius_m)
	if (mid[0] as Vector2).distance_to(p0 + Vector2(0.0, -45.0)) > 1e-3:
		return "A320 straight part ends at %s" % [mid[0]]
	var prev: Vector2 = p0
	var s := 0.0
	while s < len:
		s += 0.25
		var q: Vector2 = PushbackPath.pose(p0, 0.0, 1.0, s, pb.straight_m, pb.radius_m)[0]
		if prev.distance_to(q) > 0.26:
			return "A320 path jumps at s=%.2f" % s
		prev = q
	var ds := PushbackPath.samples(pb.straight_m, pb.radius_m, true)
	for i in range(1, ds.size()):
		if ds[i] - ds[i - 1] > 10.0 + 1e-6:
			return "corridor samples %.1f m apart" % (ds[i] - ds[i - 1])
	return ""


# --- corridors ------------------------------------------------------------------------

func test_ground_ops_corridor_covers_the_wingspan() -> String:
	var ops := {"stands": [{"x": 0.0, "y": 0.0, "heading_deg": 0.0, "ref": "1"}],
		"taxi": {"nodes": {"a": [100.0, 100.0], "b": [300.0, 100.0]}, "edges": [["a", "b", "A", 1, "taxiway"]]}}
	var bad := []
	OpsCorridors.register("P6TEST", ops, [], c172())
	if ObstacleRegistry.in_corridor(17.0, 0.0):
		bad.append("C172: a 34 m span point 17 m off the stand centre must be outside")
	if ObstacleRegistry.in_corridor(200.0, 100.0 + 12.0):
		bad.append("C172: 12 m beside a taxiway must be outside")
	OpsCorridors.register("P6TEST", ops, [], a320())
	for pt in [Vector2(17.0, 0.0), Vector2(-17.0, 0.0), Vector2(17.0, -10.0), Vector2(0.0, 18.0), Vector2(0.0, -19.0)]:
		if not ObstacleRegistry.in_corridor(pt.x, pt.y):
			bad.append("A320: wingtip / nose / tail point %s outside the stand corridor" % pt)
	var pb := GroundParams.pushback(a320())
	var len := PushbackPath.length(pb.straight_m, pb.radius_m)
	for side in [1.0, -1.0]:
		for f in [0.3, 0.6, 0.9, 1.0]:  # the swept CG path and the wingtips beside it
			var pose := PushbackPath.pose(Vector2.ZERO, 0.0, side, len * f, pb.straight_m, pb.radius_m)
			var q: Vector2 = pose[0]
			var hd: float = pose[1]
			var tip := q + Vector2(cos(hd), -sin(hd)) * 17.0
			if not ObstacleRegistry.in_corridor(q.x, q.y) or not ObstacleRegistry.in_corridor(tip.x, tip.y):
				bad.append("A320 pushback (side %.0f, %.0f %%): CG or wingtip outside the corridor" % [side, f * 100.0])
	if not ObstacleRegistry.in_corridor(200.0, 100.0 + 12.0) or ObstacleRegistry.in_corridor(200.0, 100.0 + 20.0):
		bad.append("A320 taxiway corridor must be 15 m (+ the small margin) wide")
	OpsCorridors.unregister("P6TEST")
	return "" if bad.is_empty() else "; ".join(bad)


func test_ground_ops_gate_corridor_starts_at_the_cg() -> String:
	# a gate's point is the door: the A320's CG (and its corridor) is 12.5 m behind it
	var gate := {"x": 500.0, "y": 500.0, "heading_deg": 90.0, "jetbridge": true, "ref": "G"}
	var ops := {"stands": [gate], "taxi": {"nodes": {}, "edges": []}}
	OpsCorridors.register("P6TEST", ops, [], a320())
	var behind := ObstacleRegistry.in_corridor(500.0 - 12.5 - 15.0, 500.0)  # the aft fuselage
	var ahead := ObstacleRegistry.in_corridor(500.0 + 30.0, 500.0)  # in the terminal: not covered
	OpsCorridors.unregister("P6TEST")
	return "" if behind and not ahead else "aft fuselage in corridor %s, 30 m past the door %s" % [behind, ahead]


# --- stands ---------------------------------------------------------------------------

func test_ground_ops_cg_to_door_placement() -> String:
	var a := a320()
	var gate: Dictionary = _stands()[2]  # heading east
	var p := GroundParams.cg_at_stand(gate, a)
	if p.distance_to(Vector2(200.0 - 12.5, 0.0)) > 1e-4:
		return "A320 CG at the gate %s, want 12.5 m behind the door" % p
	var bay: Dictionary = _stands()[1]
	if GroundParams.cg_at_stand(bay, a) != Vector2(100.0, 0.0):
		return "a remote bay's point stays the CG"
	var d := GroundParams.door_point(bay, a)  # north heading: the door is ahead of the CG
	if d.distance_to(Vector2(100.0, 12.5)) > 1e-4 or GroundParams.door_point(gate, a) != Vector2(200.0, 0.0):
		return "door point %s" % d
	return ""


func test_ground_ops_stand_classes_and_offer() -> String:
	var st := _stands()
	var cls := st.map(func(s): return GroundChoice.stand_class(s))
	if cls != ["ga", "remote", "gate"]:
		return "stand classes %s" % [cls]
	var names := func(a: Array) -> Array: return a.map(func(s): return s.ref)
	if names.call(GroundChoice.offered(st, "gate")) != ["Gate 2", "Bay 5"]:
		return "gate offer %s" % [names.call(GroundChoice.offered(st, "gate"))]
	if names.call(GroundChoice.offered(st, "ga")) != ["GA1", "Bay 5"]:
		return "ga offer %s" % [names.call(GroundChoice.offered(st, "ga"))]
	if names.call(GroundChoice.offered(st, "any")) != ["GA1", "Bay 5", "Gate 2"]:
		return "any keeps every stand in order"
	if names.call(GroundChoice.offered([st[0]], "gate")) != ["GA1"]:
		return "when nothing suits, everything is offered"
	if GroundChoice.default_stand(st, "gate").ref != "Gate 2" or GroundChoice.default_stand(st, "ga").ref != "GA1" \
			or GroundChoice.default_stand(st, "any").ref != "Gate 2":  # "any" = the legacy first jetbridge gate
		return "default stands gate/ga/any"
	if GroundChoice.default_stand([st[0], st[1]], "any").ref != "GA1":
		return "any without a gate = the first stand"
	return ""


func test_ground_ops_find_stand_and_taxi_penalty() -> String:
	var ops := AirportOps.new()
	ops.data = {"XX": {"stands": _stands()}}
	var legacy: String = ops.find_stand("XX", "", "any").ref
	var ga: String = ops.find_stand("XX", "", "ga").ref
	var named: String = ops.find_stand("XX", "bay5", "gate").ref
	ops.free()
	if legacy != "Gate 2" or ga != "GA1" or named != "Bay 5":
		return "find_stand any/ga/by ref = %s / %s / %s" % [legacy, ga, named]
	var st := _stands()
	if GroundChoice.taxi_penalty(st[2], "any") != 400.0 or GroundChoice.taxi_penalty(st[1], "any") != 0.0:
		return "legacy: a jetbridge gate carries +400 m"
	if GroundChoice.taxi_penalty(st[2], "gate") != 0.0 or GroundChoice.taxi_penalty(st[0], "gate") < 400.0:
		return "airliner: gates first, GA tie-downs out"
	return ""


func test_ground_ops_runway_minimum() -> String:
	var need := float(GroundParams.ground(a320()).min_runway_m)
	var short := GroundChoice.runway_score(8.0, 1200.0, need)  # headwind does not make it long enough
	var long_ := GroundChoice.runway_score(-5.0, 2000.0, need)
	if short >= long_:
		return "a 1200 m runway (%.1f) must rank below a 2000 m one (%.1f) for a 1800 m aircraft" % [short, long_]
	if GroundChoice.runway_score(0.0, 1200.0, need) <= GroundChoice.runway_score(0.0, 900.0, need) - 0.0 - 1.0:
		return "among too-short runways the longer still wins"
	return ""


# --- taxi, follow-me, tug ----------------------------------------------------------------

func test_ground_ops_follow_gap_hold_and_jetway_height() -> String:
	var a := a320()
	if absf(GroundParams.follow_gap_m(a) - 44.5) > 1e-4:
		return "A320 follow gap %.1f, want nose offset + 25 = 44.5" % GroundParams.follow_gap_m(a)
	var own := AircraftDef.make("x", {"ground": {"follow_gap_m": 60.0}}, "res://aircraft/c172")
	if GroundParams.follow_gap_m(own) != 60.0:
		return "an explicit follow_gap_m wins"
	if GroundParams.ground(a).hold_short_m != 80.0 or GroundParams.jetway_clear_m(a) != 3.0:
		return "hold_short_m / door_height_m"
	if TaxiBannerLogic.hold_short_due(70.0, true, false, 80.0) != true or TaxiBannerLogic.hold_short_due(70.0, true, false):
		return "hold short: due at 70 m only with an 80 m distance"
	return ""


func test_ground_ops_taxi_speed_advice() -> String:
	var adv := TaxiAdvice.new()
	var kt := 0.514444
	if adv.tick(1.0, 40.0 * kt, 0.0) != "" or adv.tick(1.0, 15.0 * kt, 20.0) != "":
		return "no note without a limit or under it"
	var first := adv.tick(1.0, 26.0 * kt, 20.0)
	if first == "" or not "26" in first or not "20" in first:
		return "over the limit: note '%s'" % first
	if adv.tick(1.0, 26.0 * kt, 20.0) != "":
		return "the note must not repeat at once"
	adv.tick(1.0, 10.0 * kt, 20.0)  # slowed down: armed again, but the cooldown runs
	if adv.tick(1.0, 26.0 * kt, 20.0) != "":
		return "cooldown"
	if adv.tick(31.0, 26.0 * kt, 20.0) == "":
		return "a new note after the cooldown"
	return ""


func test_ground_ops_service_offsets_and_tug_scale() -> String:
	var own: Dictionary = GroundParams.ground(a320()).service
	if own.gpu != [2.0, -4.0] or own.has("bus") or GroundParams.ground(c172()).has("service"):
		return "service offsets: A320 gives gpu and fuel, the C172 none (legacy offsets)"
	if AirportOps.SERVICE.gpu != [1.0, -5.0] or AirportOps.SERVICE.baggage != [-12.0, 9.0] or AirportOps.SERVICE.bus != [0.0, 16.0]:
		return "legacy service offsets changed"
	var t := GroundVehicles.make("pushback_tug", float(GroundParams.ground(a320()).tug_scale))
	var big: float = (t.get_child(0) as MeshInstance3D).scale.x
	var t1 := GroundVehicles.make("pushback_tug")
	var one: float = (t1.get_child(0) as MeshInstance3D).scale.x
	t.free()
	t1.free()
	GroundVehicles.release()
	return "" if absf(big - 1.7) < 1e-6 and one == 1.0 else "tug scale %.2f / default %.2f" % [big, one]
