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


func test_vehicles_meshes_sizes_and_budgets() -> String:
	var wants := {"fuel_truck": Vector3(3.1, 3.4, 8.8), "gpu": Vector3(1.5, 2.0, 4.0), "baggage_tug": Vector3(1.6, 2.5, 3.3),
		"baggage_cart": Vector3(1.8, 2.2, 4.4), "apron_bus": Vector3(3.2, 3.4, 12.8), "fire_truck": Vector3(3.2, 3.8, 10.4),
		"pushback_tug": Vector3(2.7, 2.8, 5.6)}
	for k in GroundVehicles.KINDS:
		var m := GroundVehicles.mesh(k)
		var n := GroundVehicles.triangles(k)
		if n < 300 or n > 9000:
			return "%s: %d triangles (budget 300..9000)" % [k, n]
		var a := m.get_aabb()
		var w: Vector3 = wants[k]
		if a.size.x > w.x or a.size.y > w.y or a.size.z > w.z or a.size.z < w.z * 0.6 or a.position.y < -0.05 or a.position.y > 0.05:
			return "%s: bounds %s (want up to %s, standing on y=0)" % [k, a.size, w]
		var node := GroundVehicles.make(k)
		var kids := node.get_child_count()
		node.free()
		if kids != 1:
			return "%s: one mesh instance per vehicle" % k
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
			car.queue_free()
			return "NaN at step %d" % i
	var braking := car.brake
	var steered := worst > 0.05
	var final_h := car.heading
	var up := absf(car.world_enu.z - 3.0)
	car.queue_free()
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
