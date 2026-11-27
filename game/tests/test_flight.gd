extends RefCounted
## M4 integration tests: the FDM on real terrain/runway data.


func _runway(airport: String) -> Dictionary:
	var data: Dictionary = Paths.load_json("runways.json")
	var best := {}
	for r in data.runways:
		if r.airport == airport and (best.is_empty() or r.length > best.length):
			best = r
	return best


## Paused or crashed, the FDM holds, and the rendered pose must hold too: render_transform() lerps from the previous tick's
## pose by the physics interpolation fraction, so the held ticks must bring the previous pose up to the current one
## (before, the last two live poses stayed apart and the aircraft and camera wobbled with the frame fraction).
func test_held_fdm_render_pose_is_still() -> String:
	var snap: Dictionary = Props._p.duplicate(true)
	var node := FdmNode.new()
	node.fdm = FDM.new()
	var f := node.fdm
	f.set_airborne(100.0, 200.0, 900.0, 0.3, 50.0)
	var err := ""
	# "zero step": Engine.time_scale 0 (the --freeze of debug_flicker / debug_perf) calls with delta 0; a zero FDM step
	# turned the attitude into NaN, so it holds like a pause
	for why in ["paused", "crashed", "zero step"]:
		node._prev_pos = PackedFloat64Array([f.pos_e - 0.4, f.pos_n - 0.4, -f.pos_d + 0.1])  # the tick before: 0.4 m back
		node._prev_q = f.q * Quaternion(Vector3.UP, 0.01)
		node.paused = why == "paused"
		f.damage.crashed = why == "crashed"
		node._physics_process(0.0 if why == "zero step" else 1.0 / 120.0)
		var cur := PackedFloat64Array([f.pos_e, f.pos_n, -f.pos_d])
		if not f.q.is_finite() or is_nan(f.pos_e + f.pos_n + f.pos_d):
			err = "%s: the FDM state is no longer finite (q %s)" % [why, f.q]
			break
		if node._prev_pos != cur or not node._prev_q.is_equal_approx(f.q):
			err = "%s: previous pose %s / %s, current %s / %s: the render pose keeps lerping between them" % [
				why, node._prev_pos, node._prev_q, cur, f.q]
			break
	f.damage.crashed = false
	node.free()
	Props._p = snap
	return err


## Parking brake set on a 3 % slope, engine at a fast idle, a 6 m/s quartering wind: a stopped braked tyre is held by static
## friction (GearGround._hold), so over a minute the aircraft does not move. The old zero-at-zero-speed friction crept.
func test_parking_brake_holds_on_a_slope() -> String:
	var h := FdmHarness.new()
	var f := h.f
	f.ground_height = func(n: float, e: float) -> float: return -0.03 * n + 0.01 * e  # downhill to the north and west
	f.set_on_ground(0.0, 0.0, 0.0)
	h.mode = "none"
	f.gear.brake_left = 1.0
	f.gear.brake_right = 1.0
	f.prop.rpm = 1000.0
	f.engine.throttle = 0.15
	f.wind_ned = Vector3(-4.0, -4.5, 0.0)  # from the south-east (tail-quartering)
	h.run(3.0)  # settle on the gear
	var p0 := Vector2(f.pos_n, f.pos_e)
	var peak := [0.0]
	h.run(60.0, func():
		peak[0] = maxf(peak[0], Vector2(f.pos_n, f.pos_e).distance_to(p0))
		return false)
	var moved := Vector2(f.pos_n, f.pos_e).distance_to(p0)
	print("    parking brake on a 3 %% slope, %.0f RPM, 6 m/s wind: moved %.4f m in 60 s (peak %.4f m)" % [f.prop.rpm, moved, peak[0]])
	if moved > 0.02 or peak[0] > 0.03:
		return "crept %.3f m in 60 s with the parking brake set (peak %.3f m)" % [moved, peak[0]]
	f.gear.brake_left = 0.0  # brake off: it rolls downhill again
	f.gear.brake_right = 0.0
	h.run(10.0)
	var rolled := Vector2(f.pos_n, f.pos_e).distance_to(p0)
	if rolled < 0.5:
		return "brake off on the slope: rolled only %.3f m in 10 s (the hold must release)" % rolled
	return ""


func test_m4_takeoff_juhu() -> String:
	var cache := TerrainTileCache.new()
	var r := _runway("VAJJ")
	if r.is_empty():
		return "no VAJJ runway in runways.json"
	var e0: Dictionary = r.ends[0]
	var hdg := deg_to_rad(float(e0.heading_true))
	var fwd := Vector2(sin(hdg), cos(hdg))
	var start := Vector2(e0.x, e0.y) + fwd * 25.0
	var h := FdmHarness.new(2300.0)
	var f := h.f
	f.ground_height = func(n: float, e: float) -> float: return cache.height_at(e, n)
	f.set_on_ground(start.y, start.x, hdg)
	h.mode = "none"
	f.prop.rpm = 800.0
	h.run(2.0)
	var settle_agl := f.agl
	f.engine.throttle = 1.0
	f.fcs.flap_cmd = 1
	var max_off := [0.0]
	var lift := [-1.0]
	h.run(60.0, func():
		var p := Vector2(f.pos_e, f.pos_n) - start
		var off := p.x * fwd.y - p.y * fwd.x  # cross-track (m)
		max_off[0] = maxf(max_off[0], absf(off))
		var hdg_err := wrapf(f.euler().z - hdg, -PI, PI)
		f.fcs.yaw = clampf(-4.0 * hdg_err - 0.08 * off, -1.0, 1.0)  # pedal: hold centreline
		f.fcs.pitch = 0.55 if h.kcas() > 52.0 else 0.0
		if not f.gear.wow and f.agl > 3.0:
			lift[0] = p.dot(fwd)
			return true
		return false)
	print("    settled at AGL %.2f m, airborne after %.0f m, max centreline offset %.1f m" % [settle_agl, lift[0], max_off[0]])
	if lift[0] < 0.0:
		return "did not get airborne"
	if lift[0] > float(r.length) - 25.0:
		return "ran off the end of the runway (%.0f m of %.0f)" % [lift[0], r.length]
	if max_off[0] > 8.0:
		return "left the centreline by %.1f m" % max_off[0]
	return ""
