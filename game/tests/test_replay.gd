extends RefCounted
## Instant replay (systems/replay_buffer.gd, replay_channels.gd, replay.gd): ring
## buffer capacity and wrap-around, interpolation, precision far from the origin,
## and take_control resuming the FDM with the recorded motion.

const KT := 0.514444


func _kinds() -> PackedByteArray:
	return PackedByteArray([ReplayBuffer.K_LERP, ReplayBuffer.K_STEP, ReplayBuffer.K_ANG_RAD, ReplayBuffer.K_ANG_DEG,
		ReplayBuffer.K_QUAT, ReplayBuffer.K_QUAT_REST, ReplayBuffer.K_QUAT_REST, ReplayBuffer.K_QUAT_REST])


func _row(x: float, step: float, ang: float, deg: float, q: Quaternion) -> PackedFloat32Array:
	return PackedFloat32Array([x, step, ang, deg, q.x, q.y, q.z, q.w])


func test_replay_buffer_wraps() -> String:
	var b := ReplayBuffer.new(_kinds(), 10.0, 20.0)  # 200 frames
	if b.capacity != 200:
		return "capacity %d, expected 200" % b.capacity
	for i in 450:
		b.push(i * 0.05, float(i), 0.0, 0.0, _row(i, 0, 0, 0, Quaternion.IDENTITY))
	print("    450 pushes into 200 frames: size %d, span %.2f..%.2f s, %d B" % [b.size(), b.start_time(), b.end_time(), b.memory_bytes()])
	if b.size() != 200:
		return "size %d after wrap" % b.size()
	if not is_equal_approx(b.start_time(), 250 * 0.05) or not is_equal_approx(b.end_time(), 449 * 0.05):
		return "wrong span after wrap: %.3f..%.3f" % [b.start_time(), b.end_time()]
	for i in 200:
		if not is_equal_approx(b.time_at(i), (250 + i) * 0.05):
			return "frame %d out of order" % i
	var s := b.sample(300 * 0.05)
	if absf(s.ch[0] - 300.0) > 1e-3 or absf(s.pos[0] - 300.0) > 1e-9:
		return "sample after wrap returned %.3f / %.3f" % [s.ch[0], s.pos[0]]
	b.truncate_after(400 * 0.05)
	if not is_equal_approx(b.end_time(), 20.0) or b.size() != 151:
		return "truncate: end %.2f size %d" % [b.end_time(), b.size()]
	b.push(20.05, 1.0, 0.0, 0.0, _row(0, 0, 0, 0, Quaternion.IDENTITY))
	if b.size() != 152:
		return "push after truncate"
	b.clear()
	return "" if b.size() == 0 and b.sample(1.0).is_empty() else "clear failed"


func test_replay_interpolation() -> String:
	var b := ReplayBuffer.new(_kinds(), 1.0, 20.0)
	var qa := Quaternion(Vector3.UP, 0.0)
	var qb := Quaternion(Vector3.UP, 1.0)
	b.push(0.0, 0.0, 10.0, 100.0, _row(10.0, 0.0, deg_to_rad(170.0), 350.0, qa))
	b.push(1.0, 4.0, 20.0, 200.0, _row(20.0, 1.0, deg_to_rad(-170.0), 10.0, qb))
	var s := b.sample(0.25)
	var errs := []
	if absf(s.pos[0] - 1.0) > 1e-9 or absf(s.pos[1] - 12.5) > 1e-9 or absf(s.pos[2] - 125.0) > 1e-9:
		errs.append("position lerp %s" % [s.pos])
	if absf(s.ch[0] - 12.5) > 1e-4:
		errs.append("lerp %.3f" % s.ch[0])
	if s.ch[1] != 0.0 or b.sample(1.0).ch[1] != 1.0:
		errs.append("step held wrong")
	if absf(wrapf(rad_to_deg(s.ch[2]) - 175.0, -180.0, 180.0)) > 1e-3:  # 170 -> -170 goes through 180
		errs.append("angle rad %.2f deg" % rad_to_deg(s.ch[2]))
	if absf(wrapf(s.ch[3] - 355.0, -180.0, 180.0)) > 1e-3:  # 350 -> 10 goes through 0
		errs.append("angle deg %.2f" % s.ch[3])
	var q := Quaternion(s.ch[4], s.ch[5], s.ch[6], s.ch[7])
	if absf(q.get_angle() - 0.25) > 1e-4 or absf(q.length() - 1.0) > 1e-5:
		errs.append("slerp angle %.4f" % q.get_angle())
	var c := b.sample(-5.0)  # clamped to the ends
	if c.ch[0] != 10.0 or b.sample(9.0).ch[0] != 20.0:
		errs.append("clamping")
	print("    t=0.25: pos %s lerp %.2f ang %.1f/%.1f deg slerp %.3f rad" % [
		s.pos, s.ch[0], rad_to_deg(s.ch[2]), s.ch[3], q.get_angle()])
	return "; ".join(errs)


func test_replay_far_precision() -> String:
	var b := ReplayBuffer.new(_kinds(), 2.0, 20.0)
	var e0 := -400000.0
	var n0 := 400000.0
	for i in 40:
		var t := i * 0.05
		b.push(t, e0 + 50.0 * t + 0.001 * i, n0 - 30.0 * t, 1500.0, _row(0, 0, 0, 0, Quaternion.IDENTITY))
	var t := 0.725  # halfway between frames 14 and 15
	var p := b.position_at(t)
	var want_e := e0 + 50.0 * t + 0.001 * 14.5
	var want_n := n0 - 30.0 * t
	var s := b.sample(t)
	var err := maxf(absf(s.pos[0] - want_e), absf(s.pos[1] - want_n))
	var v := b.velocity_estimate(t)
	print("    at (-400 km, 400 km): position error %.9f m, velocity (%.3f, %.3f) m/s" % [err, v.x, v.y])
	if err > 1e-6:
		return "position error %.9f m at 400 km" % err
	if absf(v.x - 50.02) > 1e-3 or absf(v.y + 30.0) > 1e-3:
		return "velocity estimate %s" % [v]
	return "" if absf(p.y - want_n) < 0.1 else "position_at %s" % [p]


func test_replay_take_control() -> String:
	var h := FdmHarness.new(2300.0)
	var f := h.f
	f.set_airborne(380000.0, -420000.0, 1000.0, deg_to_rad(40.0), 100 * KT)
	f.prop.rpm = 2400.0
	f.trim_level(100 * KT)
	h.mode = "alt"
	h.target_alt = 1000.0
	var node := FdmNode.new()
	node.fdm = f
	_sync_controls(f)
	var r := Replay.new()
	r.setup(node)
	var truth := {}  # recording clock (ms) -> NED velocity
	var tick := 1.0 / 120.0
	for i in 1200:  # 10 s at 120 Hz, 2 FDM sub-steps per tick
		f.fcs.roll = 0.3 if i > 400 and i < 700 else 0.0  # a turn: the velocity changes
		h.run(tick)
		node._publish()
		r.record_tick(tick)
		truth[int(roundf(r.clock * 1000.0))] = f.velocity_ned()
	var live_n := f.pos_n
	if not r.start_replay(5.0):
		return "start_replay refused (%d frames)" % r.buffer.size()
	if node.replaying != true or not Props.get_b("replay/active"):
		return "replay flags not set"
	var at := r.t
	var key := int(roundf(at * 1000.0))
	if not truth.has(key):
		return "replay start %.3f s is not a recorded tick" % at
	var want: Vector3 = truth[key]
	var est := r.velocity_estimate_ned(at)
	r.seek(at)
	r.take_control()
	var got := f.velocity_ned()
	print("    %d frames, take control at %.2f s of %.2f: v true %s, applied %s, track estimate %s m/s" % [
		r.buffer.size(), at, 10.0, want, got, est])
	if node.replaying or r.active:
		return "still replaying after take_control"
	if (got - want).length() > 1.0:
		return "applied velocity off by %.2f m/s" % (got - want).length()
	if (est - want).length() > 1.0:
		return "track velocity estimate off by %.2f m/s" % (est - want).length()
	if r.buffer.end_time() > at + 1e-6:
		return "buffer not truncated at take control"
	if absf(f.pos_n - live_n) < 100.0:
		return "aircraft not moved back to the replay point"
	var kias0 := f.cas / KT
	h.run(5.0)  # keeps flying
	var kias := f.cas / KT
	print("    at take control %.0f KIAS; 5 s later %.0f KIAS, alt %.0f m" % [kias0, kias, f.altitude()])
	node.free()
	r.free()
	if f.damage.crashed or kias < 60.0 or kias > 140.0:
		return "aircraft not flying normally after take control (%.0f KIAS)" % kias
	return ""


func test_replay_exit_restores_live() -> String:
	var h := FdmHarness.new(2300.0)
	var f := h.f
	f.set_airborne(0.0, 0.0, 800.0, 0.0, 95 * KT)
	f.trim_level(95 * KT)
	var node := FdmNode.new()
	node.fdm = f
	var r := Replay.new()
	r.setup(node)
	_sync_controls(f)
	for i in 600:
		h.run(1.0 / 120.0)
		node._publish()
		r.record_tick(1.0 / 120.0)
	var n := f.pos_n
	var q := f.q
	var v := f.v_b
	Props.set_v("engine/rpm", 2345.0)
	r.start_replay(4.0)
	var moved := absf(f.pos_n - n)
	r.seek_relative(1.0)
	r.stop_replay()
	var ok := f.pos_n == n and f.q == q and f.v_b == v and not node.replaying
	print("    replay moved the aircraft %.0f m back; exit restored live state: %s, rpm prop %.0f" % [moved, ok, Props.get_f("engine/rpm")])
	node.free()
	r.free()
	if moved < 50.0:
		return "replay did not move the aircraft"
	return "" if ok and Props.get_f("engine/rpm") == 2345.0 else "live state not restored on exit"


## The harness sets the FDM directly; mirror its levers into controls/* like the keyboard would.
func _sync_controls(f: FDM) -> void:
	Props.set_v("controls/throttle", f.engine.throttle)
	Props.set_v("controls/mixture", f.engine.mixture)
	Props.set_v("controls/pitch_trim", f.fcs.pitch_trim)
	Props.set_v("controls/flaps", f.fcs.flap_cmd)
