extends RefCounted
## M4 integration tests: the FDM on real terrain/runway data.


func _runway(airport: String) -> Dictionary:
	var data: Dictionary = Paths.load_json("runways.json")
	var best := {}
	for r in data.runways:
		if r.airport == airport and (best.is_empty() or r.length > best.length):
			best = r
	return best


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
