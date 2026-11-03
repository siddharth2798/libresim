extends Node
## Jetway docking: the cab's hood face meets the aircraft's L1 door (world/jetway_pose.gd, jetway_docks.gd,
## jetway_rig.gd, GroundParams.door_tip): pose maths, the rest layout (no scale clamp), which jetway serves which
## gate, the glb's parts really ending where the pose says (measured on the instanced meshes) and the solids
## that come and go while the jetway extends.

const GROUP := "ops:JWTEST"


static func a320() -> AircraftDef:
	return AircraftDef.make("a320_dock_fixture", {"name": "A320 dock fixture",
		"ground": {"cg_to_door_m": 11.3, "door_y_m": -1.95, "door_height_m": 3.65, "height_m": 11.8}}, "res://aircraft/c172")


static func _gate(x: float, y: float, hd: float) -> Dictionary:
	return {"ref": "G1", "x": x, "y": y, "heading_deg": hd, "kind": "gate", "jetbridge": true, "src": "bridge"}


static func _right(hd_deg: float) -> Vector2:
	var hd := deg_to_rad(hd_deg)
	return Vector2(cos(hd), -sin(hd))


## The jetway rig for a way (terminal, cab) and a gate, in the tree under `host`, plus the candidates.
func _rig(host: Node, terminal: Vector2, cab: Vector2, st: Dictionary, def: AircraftDef) -> JetwayRig:
	var ways := [{"terminal": terminal, "cab": cab}]
	var dy := func(_t: Vector2, _tip: Vector2) -> float: return 3.65 - JetwayPose.FLOOR_Y
	var rig := JetwayRig.new()
	rig.setup((load("res://world/models/vehicles/jetway.glb") as PackedScene).instantiate(), terminal, cab,
		JetwayDocks.candidates(0, ways, [st], dy, def))
	rig.position = Vector3(terminal.x, 0.0, -terminal.y)
	host.add_child(rig)
	return rig


# --- data and maths -----------------------------------------------------------------

func test_jetway_dock_door_y_defaults_and_a320_data() -> String:
	var c := AircraftDef.load_def("c172")
	if GroundParams.dockable(c) or GroundParams.ground(c).door_y_m != 0.0:
		return "the C172 must not dock (no door_height_m) and has door_y_m 0"
	var a := AircraftDef.load_def("a320")
	if not GroundParams.dockable(a) or absf(float(GroundParams.ground(a).door_y_m) + 1.95) > 0.01:
		return "the A320 docks and has its L1 door 1.95 m to the left (door_y_m %s)" % GroundParams.ground(a).get("door_y_m")
	return ""


func test_jetway_dock_door_tip_is_left_of_the_centre_line() -> String:
	var def := a320()
	for hd in [0.0, 90.0, 217.0]:
		var st := _gate(100.0, 200.0, hd)
		var rel := GroundParams.door_tip(st, def) - Vector2(100.0, 200.0)
		var want := -1.95 - GroundParams.DOOR_GAP_M
		if absf(rel.dot(_right(hd)) - want) > 1e-4 or absf(rel.dot(Vector2(sin(deg_to_rad(hd)), cos(deg_to_rad(hd))))) > 1e-4:
			return "heading %.0f: tip %s from the stand, want %.2f m along the right vector and 0 ahead" % [hd, rel, want]
	return ""


func test_jetway_pose_rest_stops_short_of_the_drawn_cab_and_docking_has_no_clamp() -> String:
	for length in [12.0, 22.0, 40.0, 65.0]:
		var t := Vector2(10.0, -5.0)
		var cab: Vector2 = t + Vector2.from_angle(0.7) * float(length)
		var r := JetwayPose.rest(t, cab)
		var want := t + Vector2.from_angle(0.7) * maxf(float(length) - JetwayPose.REST_BACK_M, JetwayPose.MIN_LEN + JetwayPose.CAB_LEN)
		if r.has("xscale") or JetwayPose.tip_of(t, r).distance_to(want) > 0.01:
			return "a %.0f m bridge: rest hood at %s, want %s (REST_BACK_M short of the cab end, never scaled)" % [length, JetwayPose.tip_of(t, r), want]
		# docked: no clamp, the hood is exactly where asked, even 60 m out
		var far := t + Vector2.from_angle(0.7) * float(length) * 0.9
		var p := JetwayPose.docked(t, far, Vector2.from_angle(0.7), 0.0)
		if not p.is_empty() and JetwayPose.tip_of(t, p).distance_to(far) > 0.001:
			return "docked pose %.0f m out misses its tip" % (float(length) * 0.9)
	return ""


func test_jetway_pose_docked_hits_the_tip_and_faces_the_door() -> String:
	for ang in [0.0, 1.0, 2.5, -2.0]:
		var t := Vector2(-40.0, 12.0)
		var c := Vector2.from_angle(ang)
		var tip := t + Vector2(31.0, 6.0)
		var p := JetwayPose.docked(t, tip, c, 0.2)
		if p.is_empty():
			continue  # too twisted: refused, see the next test
		if JetwayPose.tip_of(t, p).distance_to(tip) > 0.001 or absf(JetwayPose.angle_diff(p.cab_yaw, ang)) > 1e-6:
			return "cab dir %.1f: tip %s want %s, cab_yaw %.3f" % [ang, JetwayPose.tip_of(t, p), tip, p.cab_yaw]
	return ""


func test_jetway_pose_refuses_what_cannot_dock() -> String:
	var t := Vector2.ZERO
	if not JetwayPose.docked(t, Vector2(30, 0), Vector2(-1, 0), 0.0).is_empty():
		return "a cab turned 180 degrees off the tunnel must be refused"
	if not JetwayPose.docked(t, Vector2(6, 0), Vector2(1, 0), 0.0).is_empty():
		return "a tunnel shorter than MIN_LEN must be refused"
	if not JetwayPose.docked(t, Vector2(95, 0), Vector2(1, 0), 0.0).is_empty():
		return "a tunnel longer than MAX_LEN must be refused"
	if JetwayPose.docked(t, Vector2(30, 0), Vector2(0.5, -0.8), 0.0).is_empty():
		return "a 58 degree cab swing is fine"
	return ""


# --- which jetway serves which gate -------------------------------------------------

func test_jetway_docks_candidates_nearest_reach_and_aircraft() -> String:
	var def := a320()
	var st := _gate(0.0, 0.0, 90.0)  # nose east; left = north; the door tip at (0, 2.1)
	var dy := func(_t: Vector2, _tip: Vector2) -> float: return 0.0
	var near := {"terminal": Vector2(-3.0, 30.0), "cab": Vector2(1.0, 8.0)}  # 6 m off the tip, OSM-like
	var far := {"terminal": Vector2(60.0, 60.0), "cab": Vector2(60.0, 40.0)}
	var out := JetwayDocks.candidates(0, [near, far], [st], dy, def)
	if out.size() != 1 or out[0].stand != "G1" or JetwayPose.tip_of(near.terminal, out[0].pose).distance_to(GroundParams.door_tip(st, def)) > 0.01:
		return "the near jetway must dock to G1's door tip: %s" % [out]
	if not JetwayDocks.candidates(1, [near, far], [st], dy, def).is_empty():
		return "the far jetway is not the gate's nearest"
	if not JetwayDocks.candidates(0, [{"terminal": Vector2(-3.0, 60.0), "cab": Vector2(0.0, 40.0)}], [st], dy, def).is_empty():
		return "a jetway whose cab end is more than REACH_M from the door must stay at rest"
	if not JetwayDocks.candidates(0, [near, far], [st], dy, AircraftDef.load_def("c172")).is_empty():
		return "the C172 does not dock"
	var cg: Vector2 = out[0].cg
	if JetwayDocks.occupied(out, cg, 0.0, false) != 0 or JetwayDocks.occupied(out, cg + Vector2(3.5, 0), 0.0, false) != -1:
		return "occupied(): parked on the CG point yes, 3.5 m off no"
	if JetwayDocks.occupied(out, cg + Vector2(3.5, 0), 0.0, true) != 0 or JetwayDocks.occupied(out, cg, 3.0, true) != -1:
		return "occupied(): once docked it tolerates 3.5 m off but not moving at 3 m/s"
	return ""


# --- the glb's parts really end where the pose says --------------------------------

## ENU position of the hood face centre and the cab floor height of a placed rig.
func _hood(rig: JetwayRig) -> Array:
	var hood: MeshInstance3D = rig.find_child("Hood", true, false)
	var bb := hood.get_aabb()
	var face := hood.global_transform * Vector3(bb.end.x, bb.position.y + bb.size.y * 0.5, bb.position.z + bb.size.z * 0.5)
	var floor_pt := hood.global_transform * Vector3(bb.end.x, bb.position.y, bb.position.z + bb.size.z * 0.5)
	return [Vector2(face.x, -face.z), floor_pt.y]


func test_jetway_rig_hood_face_is_at_the_door_tip_and_the_floor_at_the_sill() -> String:
	var def := a320()
	var host := Node3D.new()
	add_child(host)
	var msg := ""
	# synthetic-like (cab exactly at the tip offset) and OSM-like (cab 6 m ahead, 3.7 m left of the stand point)
	for case in [[_gate(300.0, -80.0, 160.0), Vector2(4.0, 5.0)], [_gate(-50.0, 20.0, 33.0), Vector2(6.0, 3.7)]]:
		var st: Dictionary = case[0]
		var hd := deg_to_rad(float(st.heading_deg))
		var fwd := Vector2(sin(hd), cos(hd))
		var sp := Vector2(st.x, st.y)
		var off: Vector2 = case[1]
		var cab: Vector2 = sp + fwd * off.x - _right(float(st.heading_deg)) * off.y
		var terminal: Vector2 = cab - _right(float(st.heading_deg)) * 24.0 - fwd * 3.0
		var rig := _rig(host, terminal, cab, st, def)
		if rig.cands.size() != 1:
			msg = "gate %s: no dock candidate" % st.ref
		else:
			rig.apply(rig.cands[0].pose)
			var h := _hood(rig)
			var tip := GroundParams.door_tip(st, def)
			if (h[0] as Vector2).distance_to(tip) > 0.1:
				msg = "hood face %.2f m from the door tip (want < 0.1)" % (h[0] as Vector2).distance_to(tip)
			elif absf(float(h[1]) - 3.65) > 0.05:
				msg = "cab floor at %.2f m, door sill 3.65 m" % float(h[1])
		rig.queue_free()
		if msg != "":
			break
	host.queue_free()
	return msg


# --- solids and the move ------------------------------------------------------------

func test_jetway_rig_extends_to_the_parked_aircraft_and_retracts_when_it_leaves() -> String:
	var def := a320()
	var host := Node3D.new()
	add_child(host)
	var st := _gate(500.0, 500.0, 0.0)
	var cab := Vector2(500.0, 500.0) + Vector2(-9.0, 4.0)
	var rig := _rig(host, Vector2(488.0, 520.0), cab, st, def)
	var solids := OpsSolids.new(GROUP)
	Props.set_v("fdm/position_enu", Vector3(900.0, 900.0, 0.0))
	Props.set_v("fdm/groundspeed_mps", 0.0)
	rig.start(solids, "0", 0.0)
	var msg := ""
	if rig.progress != 0.0 or ObstacleRegistry.count(GROUP + ":jw0") == 0:
		msg = "no aircraft: the jetway rests and is solid (progress %.2f, records %d)" % [rig.progress, ObstacleRegistry.count(GROUP + ":jw0")]
	var cg: Vector2 = rig.cands[0].cg
	Props.set_v("fdm/position_enu", Vector3(cg.x, cg.y, 0.0))
	for i in 40:
		rig._process(0.25)
	if msg == "" and (absf(rig.progress - 1.0) > 1e-4 or rig.docked_stand != "G1" or ObstacleRegistry.count(GROUP + ":jw0") != 0):
		msg = "parked at the gate: docked and not solid (progress %.2f, stand '%s', records %d)" % [rig.progress, rig.docked_stand, ObstacleRegistry.count(GROUP + ":jw0")]
	Props.set_v("fdm/position_enu", Vector3(cg.x, cg.y - 30.0, 0.0))
	for i in 40:
		rig._process(0.25)
	if msg == "" and (absf(rig.progress) > 1e-4 or ObstacleRegistry.count(GROUP + ":jw0") == 0):
		msg = "aircraft gone: retracted and solid again (progress %.2f)" % rig.progress
	Props.set_v("fdm/position_enu", Vector3.ZERO)
	solids.clear()
	host.queue_free()
	return msg


func test_jetway_rig_starts_docked_when_the_aircraft_is_already_there() -> String:
	var def := a320()
	var host := Node3D.new()
	add_child(host)
	var st := _gate(700.0, 700.0, 90.0)
	var rig := _rig(host, Vector2(700.0, 700.0) + Vector2(-20.0, 24.0), Vector2(700.0, 702.0), st, def)
	var cg: Vector2 = rig.cands[0].cg
	Props.set_v("fdm/position_enu", Vector3(cg.x, cg.y, 0.0))
	Props.set_v("fdm/groundspeed_mps", 0.0)
	var solids := OpsSolids.new(GROUP)
	rig.start(solids, "0", 0.0)
	var ok: bool = absf(rig.progress - 1.0) < 1e-4 and ObstacleRegistry.count(GROUP + ":jw0") == 0
	Props.set_v("fdm/position_enu", Vector3.ZERO)
	solids.clear()
	host.queue_free()
	return "" if ok else "a parked aircraft at start: the jetway is docked at once (progress %.2f)" % rig.progress


## A rig at rest (an aircraft that does not dock, the C172), measured on the instanced meshes: the hood face is where
## JetwayPose.rest says, the cab is not scaled, the rotunda's fixed stub points along `back` (toward the building)
## whatever the tunnel does, and the support's wheels stand on the ground under the girder, also when pitched.
func test_jetway_rig_rest_layout_stub_and_wheels() -> String:
	var host := Node3D.new()
	add_child(host)
	var msg := ""
	for case in [[Vector2(100.0, 50.0), Vector2(100.0, 80.0), Vector2(0.0, -1.0)], [Vector2(-30.0, 10.0), Vector2(-3.0, 40.0), Vector2(1.0, 0.0)],
			[Vector2(0.0, 0.0), Vector2(60.0, 20.0), Vector2.ZERO]]:
		var t: Vector2 = case[0]
		var cab: Vector2 = case[1]
		var back: Vector2 = case[2]
		var rig := JetwayRig.new()
		rig.setup((load("res://world/models/vehicles/jetway.glb") as PackedScene).instantiate(), t, cab, [], back)
		rig.position = Vector3(t.x, 0.0, -t.y)
		host.add_child(rig)
		rig.ground_at = func(_e: float, _n: float) -> float: return 0.0
		rig.start(null, "0", 0.0)
		var h := _hood(rig)
		var hood := rig.find_child("Hood", true, false) as Node3D
		var rot := rig.find_child("Rotunda1", true, false) as MeshInstance3D
		var bb := rot.get_aabb()
		var se := rot.global_transform * Vector3(bb.position.x, bb.get_center().y, bb.get_center().z)
		var want_back := back if back != Vector2.ZERO else (t - cab).normalized()
		var stub := (Vector2(se.x, -se.z) - t).normalized()
		var bogie := rig.find_child("SupportBogie", true, false) as MeshInstance3D
		var low := INF
		for i in 8:
			low = minf(low, (bogie.global_transform * bogie.get_aabb().get_endpoint(i)).y)
		if (h[0] as Vector2).distance_to(JetwayPose.tip_of(t, rig.rest)) > 0.1:
			msg = "way %s -> %s: rest hood face %s, the pose says %s" % [t, cab, h[0], JetwayPose.tip_of(t, rig.rest)]
		elif not hood.global_transform.basis.get_scale().is_equal_approx(Vector3.ONE):
			msg = "the cab is scaled at rest: %s" % hood.global_transform.basis.get_scale()
		elif stub.distance_to(want_back) > 0.02:
			msg = "the rotunda stub points %s, want %s" % [stub, want_back]
		elif absf(low) > 0.02:
			msg = "the wheels are %.2f m off the ground at rest" % low
		else:
			rig.apply({"yaw": rig.rest.yaw + 0.3, "len": 20.0, "cab_yaw": rig.rest.yaw, "pitch": 0.06})
			low = INF
			for i in 8:
				low = minf(low, (bogie.global_transform * bogie.get_aabb().get_endpoint(i)).y)
			var stub2 := (Vector2((rot.global_transform * Vector3(bb.position.x, 0, 0)).x, -(rot.global_transform * Vector3(bb.position.x, 0, 0)).z) - t).normalized()
			if absf(low) > 0.02 or stub2.distance_to(want_back) > 0.02:
				msg = "turned and pitched 3.4 deg: wheels %.2f m off the ground, stub %s (want %s)" % [low, stub2, want_back]
		rig.queue_free()
		if msg != "":
			break
	host.queue_free()
	return msg
