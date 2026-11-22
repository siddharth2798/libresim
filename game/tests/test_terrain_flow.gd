extends RefCounted
## Terrain and the wind (world/terrain_flow.gd): ridge lift with the full U . grad(h) at the surface decaying on the
## ridge scale, lee waves downwind of an escarpment with the wavelength 2 pi U / N (none upwind, none in light wind),
## a rotor under the first crest, smooth along the path.

const STEP := TerrainFlow.WAVE_STEP


func test_ridge_lift_is_full_at_the_surface_and_decays_on_the_ridge_scale() -> String:
	var wind := Vector2(10.0, 0.0)  # 10 m/s toward the east
	var slope := Vector2(0.2, 0.0)  # rising to the east: windward
	var s0 := TerrainFlow.ridge_lift(wind, slope, 0.0)
	var s1 := TerrainFlow.ridge_lift(wind, slope, TerrainFlow.RIDGE_L)
	var lee := TerrainFlow.ridge_lift(wind, -slope, 0.0)
	print("    10 m/s up a 0.2 slope: %.2f m/s at the surface, %.2f at %.0f m, lee %.2f" % [s0, s1, TerrainFlow.RIDGE_L, lee])
	if absf(s0 - 2.0) > 1e-6 or absf(s1 - 2.0 / exp(1.0)) > 1e-3 or absf(lee + 2.0) > 1e-6:
		return "ridge lift %.3f / %.3f / lee %.3f, want 2.0 / %.3f / -2.0" % [s0, s1, lee, 2.0 / exp(1.0)]
	return "" if TerrainFlow.ridge_lift(wind, slope, 1000.0) > 0.9 else "still about half strength 1 km up a 1.5 km ridge scale"


## Profile upwind of an aircraft s m downwind of an escarpment `drop` m high (high ground upwind), a 2 km ramp.
static func _escarpment(s: float, drop := 800.0) -> PackedFloat64Array:
	var prof := PackedFloat64Array()
	for k in int(TerrainFlow.WAVE_REACH / STEP) + 1:
		prof.append(drop * smoothstep(s - 1000.0, s + 1000.0, k * STEP))
	return prof


func test_lee_waves_downwind_with_the_right_wavelength() -> String:
	var u := 15.0
	var lam := TerrainFlow.wavelength(u)
	var ws := []
	for i in 300:  # 0-30 km downwind
		ws.append(TerrainFlow.lee_wave(_escarpment(i * 100.0), STEP, u, 1.0, 0.01, 1500.0).x)
	var peaks := []
	for i in range(1, 299):
		if ws[i] > ws[i - 1] and ws[i] >= ws[i + 1] and ws[i] > 0.3:
			peaks.append(i * 100.0)
	var top: float = ws.max()
	var bottom: float = ws.min()
	print("    15 m/s over an 800 m escarpment: wavelength %.1f km (theory %.1f), lift %.1f m/s, sink %.1f m/s, crests at %s m" % [
		(peaks[1] - peaks[0]) / 1000.0 if peaks.size() > 1 else 0.0, lam / 1000.0, top, bottom, peaks])
	if peaks.size() < 2 or absf((peaks[1] - peaks[0]) / lam - 1.0) > 0.15:
		return "wave crests at %s m, want about %.0f m apart" % [peaks, lam]
	if top < 1.0 or top > 5.0 or bottom > -1.0:
		return "wave lift %.2f / sink %.2f m/s, want 1-5" % [top, bottom]
	# upwind of the escarpment (flat ground upwind of the aircraft), and in light wind: nothing
	var flat := PackedFloat64Array()
	flat.resize(_escarpment(0.0).size())
	flat.fill(800.0)
	if TerrainFlow.lee_wave(flat, STEP, u, 1.0, 0.01, 1500.0) != Vector2.ZERO:
		return "waves over flat ground upwind of the drop"
	if TerrainFlow.lee_wave(_escarpment(lam * 0.5), STEP, 4.0, 1.0, 0.01, 1500.0) != Vector2.ZERO:
		return "waves in a 4 m/s wind"
	if TerrainFlow.lee_wave(_escarpment(lam * 0.5), STEP, u, 0.2, 0.01, 1500.0).x != 0.0:
		return "waves with the wind almost along the ridge"
	# rotor: low down under the first crest, not high up, not far downwind
	var rotor := TerrainFlow.lee_wave(_escarpment(0.4 * lam), STEP, u, 1.0, 0.01, 300.0).y
	var high := TerrainFlow.lee_wave(_escarpment(0.4 * lam), STEP, u, 1.0, 0.01, 2500.0).y
	var far := TerrainFlow.lee_wave(_escarpment(2.0 * lam), STEP, u, 1.0, 0.01, 300.0).y
	return "" if rotor > 0.5 and high == 0.0 and far < 0.1 else "rotor %.2f low, %.2f high, %.2f far downwind" % [rotor, high, far]


## The full update over a north-south escarpment (high to the west) in a westerly: waves east of it, smooth along the path.
func test_lee_waves_in_flight_are_smooth_and_only_downwind() -> String:
	var ground := func(e: float, _n: float) -> float: return 800.0 * (1.0 - smoothstep(-1000.0, 1000.0, e))
	var aloft := Vector2(15.0, 0.0)  # toward the east
	var tf := TerrainFlow.new()
	var dt := 1.0 / 120.0
	var worst := 0.0
	var prev := INF
	var best := 0.0
	for i in int(40000.0 / 0.5):  # 0.5 m per tick (60 m/s), 40 km eastward from 20 km west of the edge
		var e := -20000.0 + i * 0.5
		tf.update(dt, ground, Vector3(e, 0.0, 1500.0), 1500.0 - ground.call(e, 0.0), aloft, aloft)
		if prev != INF:
			worst = maxf(worst, absf(tf.wave - prev))
		prev = tf.wave
		if e < -3000.0 and absf(tf.wave) > 1e-6:
			return "lee wave %.2f m/s upwind of the escarpment (%.0f m)" % [tf.wave, e]
		best = maxf(best, absf(tf.wave))
	print("    in flight east over the escarpment: strongest wave %.2f m/s, biggest change per tick %.4f m/s" % [best, worst])
	return "" if best > 1.0 and worst < 0.02 else "wave %.2f m/s, per-tick change %.4f" % [best, worst]
