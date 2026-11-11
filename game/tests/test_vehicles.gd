extends Node
## The follow-me car's look maths (flash pattern, brake lamps, wheel spin, steering, body lean, ground
## tilt) and the procedural ground vehicles (world/ground_vehicles.gd, follow_me_car.gd): sizes,
## triangle budgets, the car following a path without NaNs. Logic: world/follow_me_logic.gd.


func test_vehicles_flash_alternates_with_double_flash() -> String:
	if FollowMeLogic.flash(0.03, 0) < 0.95 or FollowMeLogic.flash(0.03, 1) > 0.01:
		return "left lights at t=0.03, right does not: %.2f %.2f" % [FollowMeLogic.flash(0.03, 0), FollowMeLogic.flash(0.03, 1)]
	if FollowMeLogic.flash(0.63, 1) < 0.95 or FollowMeLogic.flash(0.63, 0) > 0.01:
		return "right lights half a period later"
	if FollowMeLogic.flash(0.20, 0) < 0.95 or FollowMeLogic.flash(0.12, 0) > 0.01:
		return "two flashes (0..70 ms, 160..230 ms) with a gap between"
	var on := 0.0
	for i in 1200:
		on += FollowMeLogic.flash(i * 0.001, 0)
	if on < 100.0 or on > 200.0:  # 140 ms of 1200
		return "duty %.0f ms of 1200" % on
	if absf(FollowMeLogic.flash(0.5, 0) - FollowMeLogic.flash(0.5 + FollowMeLogic.FLASH_PERIOD * 3, 0)) > 1e-4:
		return "not periodic"
	return ""


func test_vehicles_brake_lamps() -> String:
	if not FollowMeLogic.brake_on(0.0, 0.0, false):
		return "stopped: brake lamps on"
	if FollowMeLogic.brake_on(0.5, 6.0, false):
		return "accelerating: off"
	if not FollowMeLogic.brake_on(-1.0, 6.0, false):
		return "braking hard: on"
	if not FollowMeLogic.brake_on(-0.3, 6.0, true) or FollowMeLogic.brake_on(-0.3, 6.0, false):
		return "hysteresis: a gentle slow-down keeps the lamps on only once they are on"
	if FollowMeLogic.brake_on(-0.05, 6.0, true):
		return "off again when the deceleration eases"
	return ""


func test_vehicles_wheel_spin_and_steering() -> String:
	var r := FollowMeLogic.WHEEL_R
	var a := 0.0
	for i in 100:
		a = FollowMeLogic.spin(a, 5.0, r, 0.01)  # 5 m/s for 1 s
	var want := fposmod(5.0 / r, TAU)
	if absf(a - want) > 1e-4:
		return "spin after 5 m: %.3f, want %.3f" % [a, want]
	if FollowMeLogic.spin(0.0, 0.0, r, 1.0) != 0.0:
		return "no spin at rest"
	var s := FollowMeLogic.steer_angle(5.0, 0.4)  # right turn
	if s <= 0.0 or absf(s - atan(FollowMeLogic.WHEELBASE * 0.4 / 5.0)) > 1e-6:
		return "steer %.3f" % s
	if FollowMeLogic.steer_angle(5.0, -0.4) >= 0.0 or absf(FollowMeLogic.steer_angle(0.2, 5.0)) > 0.6:
		return "left turn negative, limited to the lock"
	return ""


func test_vehicles_heading_and_body_lean() -> String:
	if absf(FollowMeLogic.angle_diff(0.1, TAU - 0.1) + 0.2) > 1e-5:
		return "shortest way round"
	var h := FollowMeLogic.turn_toward(0.0, 1.0, 0.5, 0.2)
	if absf(h - 0.1) > 1e-6 or FollowMeLogic.turn_toward(0.0, 0.05, 0.5, 0.2) != 0.05:
		return "rate limit: %.3f" % h
	var t := FollowMeLogic.body_targets(2.0, 3.0)
	if t.x <= 0.0 or t.y <= 0.0 or t.x > 0.04 or t.y > 0.05:
		return "squat and lean out of a right turn, small: %s" % t
	if FollowMeLogic.body_targets(-2.0, -3.0).x >= 0.0:
		return "braking dives (negative pitch)"
	var st := Vector2(0.0, 0.0)
	for i in 300:
		st = FollowMeLogic.spring_step(st.x, st.y, 0.03, 9.0, 0.6, 1.0 / 60.0)
	if absf(st.x - 0.03) > 1e-3 or absf(st.y) > 1e-3:
		return "spring settles at its target: %s" % st
	var tilt := FollowMeLogic.ground_tilt(0.5, 0.0, 0.0, 0.19)
	if tilt.x <= 0.0 or tilt.y <= 0.0 or absf(tilt.x - atan2(0.5, FollowMeLogic.WHEELBASE)) > 1e-6:
		return "ground tilt: %s" % tilt
	return ""


## Real-world sizes (with mirrors, beacons, drawbars): refueller 20 kL on a three-axle chassis, Cobus-type
## apron bus 13.9 x 3.0 m, Panther-type 6x6 crash tender 11.9 x 3.0 m, towbarless tug (size 1), baggage
## tractor / cart, towable GPU, hydrant dispenser. LOD 0 budget per vehicle; generated LODs must exist.
func test_vehicles_meshes_sizes_and_budgets() -> String:
	var wants := {"fuel_truck": [Vector3(2.4, 3.1, 8.6), Vector3(3.1, 3.5, 9.6)], "hydrant_dispenser": [Vector3(2.2, 2.6, 6.6), Vector3(2.9, 3.1, 7.6)],
		"gpu": [Vector3(1.2, 1.4, 3.2), Vector3(1.6, 1.9, 4.0)], "baggage_tug": [Vector3(1.3, 1.9, 2.7), Vector3(1.6, 2.4, 3.3)],
		"baggage_cart": [Vector3(1.4, 1.8, 3.6), Vector3(1.8, 2.2, 4.4)], "apron_bus": [Vector3(2.9, 2.9, 13.6), Vector3(3.7, 3.3, 14.4)],
		"fire_truck": [Vector3(2.9, 3.4, 11.6), Vector3(3.8, 3.8, 13.0)], "pushback_tug": [Vector3(1.6, 1.3, 4.0), Vector3(2.4, 1.8, 4.8)]}
	for k in GroundVehicles.KINDS:
		var m := GroundVehicles.mesh(k)
		var n := GroundVehicles.triangles(k)
		if n < 1500 or n > 14000:
			return "%s: %d triangles (budget 1500..14000 at LOD 0)" % [k, n]
		var lods: Array = RenderingServer.mesh_get_surface(m.get_rid(), 0).get("lods", [])
		if lods.size() < 2:
			return "%s: %d LODs generated (want 2+)" % [k, lods.size()]
		var a := m.get_aabb()
		var lo: Vector3 = wants[k][0]
		var hi: Vector3 = wants[k][1]
		if a.size.x < lo.x or a.size.y < lo.y or a.size.z < lo.z or a.size.x > hi.x or a.size.y > hi.y or a.size.z > hi.z \
				or a.position.y < -0.05 or a.position.y > 0.05:
			return "%s: bounds %s (want %s..%s, standing on y=0)" % [k, a.size, lo, hi]
		var node := GroundVehicles.make(k, 1.0, 0.5, true)
		var body := node.get_node_or_null("Body") as MeshInstance3D
		var ground := node.get_node_or_null("Ground") as MeshInstance3D
		var kids := node.get_child_count()
		var ok := body != null and ground != null and ground.has_meta("no_solid") and body.mesh == m
		var lamps := float(body.get_instance_shader_parameter("lamps")) if body else 0.0
		node.free()
		if kids != 2 or not ok:
			return "%s: a Body mesh instance (shared mesh) and a Ground decal (not solid) per vehicle" % k
		if lamps != 1.0:
			return "%s: working flag reaches the shader" % k
	return ""


## Every kind has wheels with their hub in CUSTOM0 (the shader rolls them), a steering front axle, and the
## lamps the night light points need; carts and the GPU have no beacon, the rest do.
func test_vehicles_wheels_and_lamps_recorded() -> String:
	for k in GroundVehicles.KINDS:
		var ws := GroundVehicles.wheels(k)
		var steer := 0
		for w in ws:
			steer += 1 if w[3] else 0
		if ws.size() < 4 or steer != 2:
			return "%s: %d wheels, %d steering (want 4+ and one steering pair)" % [k, ws.size(), steer]
		var arr := GroundVehicles.mesh(k).surface_get_arrays(0)
		var c: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM0]
		var hubs := 0
		var beacon := 0
		for i in range(3, c.size(), 4):
			hubs += 1 if c[i] > 0.0 and c[i] < 50.0 else 0
			beacon += 1 if c[i] >= VehicleGeo.BEACON else 0
		if hubs < 200:
			return "%s: only %d wheel vertices carry a hub" % [k, hubs]
		var kinds := {}
		for l in GroundVehicles.lamps(k):
			kinds[l[0]] = true
		var want_beacon: bool = not k in ["baggage_cart", "gpu"]
		if want_beacon != kinds.has("beacon") or want_beacon != (beacon > 0):
			return "%s: beacon %s (lamps %s, lens pivots %d)" % [k, want_beacon, kinds.keys(), beacon]
		if k != "baggage_cart" and not kinds.has("tail"):
			return "%s: tail lamps" % k
	var lp := VehicleLamps.new()
	lp.add("fire_truck", Transform3D(Basis(Vector3.UP, 0.5), Vector3(10, 0, 5)), 0.2)
	if lp.beacons.count != 5 or lp.lamps.count != 4:  # two light bars (two lenses each), the rear beacon; head + tail
		return "fire truck light points: %d beacons, %d lamps" % [lp.beacons.count, lp.lamps.count]
	var s1 := GroundVehicles.seed_at(Vector2(1200.5, -340.25))
	if s1 != GroundVehicles.seed_at(Vector2(1200.5, -340.25)) or s1 < 0.0 or s1 >= 1.0 or s1 == GroundVehicles.seed_at(Vector2(1210.5, -340.25)):
		return "seed: stable per place, 0..1, different between places"
	return ""


## A driving vehicle (the pushback tug) rolls its wheels by the distance along its axis and steers into turns.
func test_vehicles_motion_rolls_and_steers() -> String:
	var v := GroundVehicles.make("pushback_tug", 1.5, 0.3, true, true) as VehicleMotion
	if v == null:
		return "moving vehicle root is a VehicleMotion"
	add_child(v)
	for i in 60:  # 1 s forward (-z) at 3 m/s
		v.advance(Vector3(0, 0, -0.05), 0.0, 1.0 / 60.0)
	var fwd := v.turn
	for i in 120:  # reverse while turning left (yaw +)
		v.advance(Vector3(0, 0, 0.05), 0.004, 1.0 / 60.0)
	var steer_rev := v.steer
	v.advance(Vector3(0, 0, -5000.0), 0.0, 1.0 / 60.0)  # a floating-origin shift: no roll
	var after := v.turn
	v.free()
	if absf(fwd - 3.0 / 1.5) > 1e-3:
		return "rolled %.3f model metres, want 2.0" % fwd
	if absf(after - (fwd - 6.0 / 1.5)) > 1e-3:
		return "reversing unrolls, a jump is ignored: %.3f" % after
	if steer_rev <= 0.02:  # reversing into a left yaw = wheels to the right
		return "steer while reversing left: %.3f" % steer_rev
	return ""


func test_vehicles_follow_me_car_shape_and_motion() -> String:
	var car := FollowMeCar.new()
	add_child(car)
	var a := car._shell.get_aabb()
	if a.size.z < 4.8 or a.size.z > 5.4 or a.size.x < 1.8 or a.size.x > 2.3 or a.size.y < 1.7 or a.size.y > 2.6:
		return "pickup bounds %s (about 5 x 1.9 x 1.8 plus the roof board)" % a.size
	var tris := FollowMeShell.triangles(car._shell) + 4 * FollowMeShell.triangles(car._wheel)
	if tris > 9000:
		return "follow-me car has %d triangles" % tris
	var hf := func(_x: float, _y: float) -> float: return 3.0
	var pe := 100.0
	var pn := 50.0
	var hdg := 0.0
	var worst := 0.0
	for i in 600:  # 10 s: straight north, a 90 degree right turn east, then a stop
		var v := 7.0 if i < 400 else 0.0
		if i >= 200:
			hdg = PI / 2
		pe += sin(hdg) * v / 60.0
		pn += cos(hdg) * v / 60.0
		car.place(pe, pn, hdg, 1.0 / 60.0, hf)
		worst = maxf(worst, absf(car.steer))
		if is_nan(car.position.x) or is_nan(car.speed) or is_nan(car.heading):
			car.free()
			return "NaN at step %d" % i
	var braking := car.brake
	var steered := worst > 0.05
	var final_h := car.heading
	var up := absf(car.world_enu.z - 3.0)
	car.free()
	if not steered:
		return "front wheels steered in the turn: max %.3f" % worst
	if absf(FollowMeLogic.angle_diff(final_h, PI / 2)) > 0.1:
		return "heading follows the route: %.2f" % final_h
	if not braking:
		return "stopped: brake lamps on"
	if up > 0.01:
		return "car stands on the ground height: %.3f" % up
	return ""


## The jetway model must have no coincident faces (cab door drawn on its back wall flickered: z-fighting).
## Triangle samples (centroid, near each corner) of one that lie on another's plane and inside it.
func test_vehicles_jetway_has_no_coplanar_faces() -> String:
	var root: Node = load("res://world/models/vehicles/jetway.glb").instantiate()
	var tris: Array = []  # [normal, d, [a, b, c]] in model space
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var arr: PackedVector3Array = (mi as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = (mi as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
		for k in range(0, idx.size(), 3):
			var v := [arr[idx[k]], arr[idx[k + 1]], arr[idx[k + 2]]]
			var n: Vector3 = (v[1] - v[0]).cross(v[2] - v[0])
			if n.length() > 1e-9:
				n = n.normalized()
				tris.append([n, n.dot(v[0]), v])
	root.free()
	var bad := 0
	for i in tris.size():
		var a: Array = tris[i]
		var c: Vector3 = (a[2][0] + a[2][1] + a[2][2]) / 3.0
		for j in tris.size():
			var b: Array = tris[j]
			if i == j or absf((a[0] as Vector3).dot(b[0])) < 0.9995 or absf(b[0].dot(c) - b[1]) > 0.005:
				continue
			if _inside(c, b[2]):
				bad += 1
				break
	if bad > 0:
		return "%d jetway triangles lie on another triangle's plane (z-fighting)" % bad
	return ""


func _inside(p: Vector3, t: Array) -> bool:
	var n: Vector3 = (t[1] - t[0]).cross(t[2] - t[0])
	for k in 3:
		if n.dot((t[(k + 1) % 3] - t[k]).cross(p - t[k])) < -1e-9:
			return false
	return true


func _exit_tree() -> void:
	GroundVehicles.release()
	FollowMeCar.release()


func test_vehicles_beacon_flash_ramps_over_frames() -> String:
	# At 80 rpm and 25 fps the beam turns 0.34 rad per frame. The flash toward the eye must rise and fall over several
	# frames (no step of more than 40 % of the peak), yet stay a clear flash (peak 2.5, dark a quarter turn away).
	var peak := VehicleLamps.beacon_flash(0.0)
	if absf(peak - 2.5) > 1e-6 or VehicleLamps.beacon_flash(PI * 0.5) > 1e-6:
		return "peak %.2f, quarter turn %.3f" % [peak, VehicleLamps.beacon_flash(PI * 0.5)]
	var step := VehicleLamps.BEACON_RAD_S / 25.0
	var worst := 0.0
	var a := -PI
	while a < PI:
		worst = maxf(worst, absf(VehicleLamps.beacon_flash(a + step) - VehicleLamps.beacon_flash(a)))
		a += 0.01
	if worst > 0.4 * peak:
		return "the flash jumps %.2f of %.2f in one frame" % [worst, peak]
	var frames := 0
	a = -PI
	while a < PI:
		if VehicleLamps.beacon_flash(a) > 0.1 * peak:
			frames += 1
		a += step
	return "" if frames >= 3 else "the flash is visible for %d frames only" % frames
