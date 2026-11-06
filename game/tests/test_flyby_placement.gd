extends Node
## The fly-by camera placement (ui/flyby_placement.gd): scaled by aircraft size and speed, clear of the ground,
## out of cloud when it can be, and every re-placement is a camera cut for the post effects.

const KT := 0.514444
const DT := 1.0 / 60.0


func _par(id: String) -> Dictionary:
	return FlybyPlacement.params(AircraftDef.load_def(id))


## Fly the aircraft straight from w at v past a camera placed for it, until the rig would re-place it.
## Returns {pass_s, closest_m, frac_close, frac_start, frac_min, cam, end_w, end_xf_prev}.
func _pass(p: Dictionary, w: Vector3, v: Vector3, env := {}) -> Dictionary:
	var r := FlybyPlacement.place(w, v, Vector2(v.x, v.y).normalized(), p, env)
	var cam: Vector3 = r.pos
	var out := {"pass_s": -1.0, "closest_m": INF, "frac_min": INF, "cam": cam}
	var t := 0.0
	var pos := w
	while t < 60.0:
		var d := cam.distance_to(pos)
		var fr := _frac(d, p)
		out.frac_min = minf(out.frac_min, fr)
		if t == 0.0:
			out.frac_start = fr
		if d < out.closest_m:
			out.closest_m = d
			out.pass_s = t
			out.frac_close = fr
		if FlybyPlacement.needs_replace(cam, pos, v, r.ahead_m, p):
			break
		pos += v * DT
		t += DT
	out.end_w = pos
	out.end_s = t
	return out


## Fraction of the frame height the aircraft's size covers at distance d with the fly-by zoom.
func _frac(d: float, p: Dictionary) -> float:
	return float(p.size_m) / (2.0 * d * tan(deg_to_rad(FlybyPlacement.fov_deg(d, p)) * 0.5))


func test_flyby_params_from_the_aircraft() -> String:
	var c := _par("c172")
	var a := _par("a320")
	if absf(c.size_m - 10.9) > 0.3 or a.size_m < 35.0 or a.size_m > 42.0:
		return "sizes: c172 %.1f m, a320 %.1f m" % [c.size_m, a.size_m]
	for id in AircraftDef.list_ids():
		var p := _par(id)
		for k in FlybyPlacement.DEFAULTS:
			if not p.has(k):
				return "%s: %s missing" % [id, k]
	var own := AircraftDef.make("probe", {"cameras": {"flyby": {"lead_s": 3.0}}}, "res://aircraft/c172")
	var po := FlybyPlacement.params(own)
	return "" if po.lead_s == 3.0 and po.side_sizes == FlybyPlacement.DEFAULTS.side_sizes else "aircraft.json cameras.flyby should override: %s" % po


## A 100 kt C172 and a 140 kt A320 pass the camera after a similar few seconds, each at its own scale.
func test_flyby_similar_pass_time_scaled_distance() -> String:
	var c := _pass(_par("c172"), Vector3(0, 0, 1000), Vector3(0, 100.0 * KT, 0))
	var a := _pass(_par("a320"), Vector3(0, 0, 1000), Vector3(0, 140.0 * KT, 0))
	print("    pass: c172 %.1f s at %.0f m, a320 %.1f s at %.0f m" % [c.pass_s, c.closest_m, a.pass_s, a.closest_m])
	if c.pass_s < 3.5 or c.pass_s > 6.5 or a.pass_s < 3.5 or a.pass_s > 6.5 or absf(c.pass_s - a.pass_s) > 1.0:
		return "pass times c172 %.1f s, a320 %.1f s" % [c.pass_s, a.pass_s]
	if c.closest_m < 15.0 or c.closest_m > 40.0:
		return "c172 closest %.0f m (old camera: ~26 m)" % c.closest_m
	return "" if a.closest_m > 2.5 * c.closest_m and a.closest_m < 150.0 else "a320 closest %.0f m" % a.closest_m


## Not too close, not a speck: at placement, at the pass and on the way out the size covers a sensible share.
func test_flyby_frame_share_over_speeds() -> String:
	for id in ["c172", "a320"]:
		var p := _par(id)
		for kt in [40.0, 70.0, 100.0, 140.0, 250.0]:
			var r := _pass(p, Vector3(0, 0, 1500), Vector3(30.0 * KT, kt * KT, -3.0))
			if r.frac_start < 0.12 or r.frac_close > 0.75 or r.frac_close < 0.25 or r.frac_min < 0.1:
				return "%s %d kt: frame share start %.2f, pass %.2f, min %.2f" % [id, kt, r.frac_start, r.frac_close, r.frac_min]
			if r.end_s > 30.0:
				return "%s %d kt: no re-placement within %.0f s" % [id, kt, r.end_s]
	return ""


## The camera stands above the ground (and obstacles) with a margin, and not behind a hill.
func test_flyby_terrain_clearance() -> String:
	for id in ["c172", "a320"]:
		var p := _par(id)
		# low approach over rising ground: 40 m above a 1 % upslope
		var slope := {"height": func(e: float, n: float) -> float: return 100.0 + 0.01 * n}
		var w := Vector3(0, 0, 140.0)
		var r := FlybyPlacement.place(w, Vector3(0, 70.0, -3.7), Vector2(0, 1), p, slope)
		var g: float = slope.height.call(r.pos.x, r.pos.y)
		if r.pos.z < g + FlybyPlacement.MARGIN_M:
			return "%s: camera %.1f m, ground %.1f m" % [id, r.pos.z, g]
		# on the runway (0 m AGL): never below the ground
		var flat := {"height": func(_e: float, _n: float) -> float: return 10.0}
		r = FlybyPlacement.place(Vector3(0, 0, 12.0), Vector3(0, 30.0, 0), Vector2(0, 1), p, flat)
		if r.pos.z < 10.0 + FlybyPlacement.MARGIN_M:
			return "%s on the runway: camera %.1f m" % [id, r.pos.z]
		# a ridge 400 m high east of the track (aircraft at 300 m): the camera goes west, in clear view
		var ridge := {"height": func(e: float, _n: float) -> float: return 400.0 if e > 20.0 else 0.0}
		r = FlybyPlacement.place(Vector3(0, 0, 300.0), Vector3(0, 60.0, 0), Vector2(0, 1), p, ridge)
		if r.pos.x > 0.0 or r.score > 10.0:
			return "%s: should stand west of the ridge, at %s (score %.1f)" % [id, r.pos, r.score]
		# a building 60 m tall under the preferred spot: lifted above its roof
		var obs := {"height": flat.height, "obstacle_top": func(_e: float, _n: float) -> float: return 70.0}
		r = FlybyPlacement.place(Vector3(0, 0, 40.0), Vector3(0, 50.0, 0), Vector2(0, 1), p, obs)
		if r.pos.z < 70.0 + FlybyPlacement.MARGIN_M:
			return "%s: camera %.1f m inside a 70 m obstacle top" % [id, r.pos.z]
	return ""


## Cloud on one side of the track: the camera takes the clear side; cloud everywhere still gives a position.
func test_flyby_avoids_cloud() -> String:
	var p := _par("a320")
	var east := {"cloud": func(q: Vector3) -> float: return 0.8 if q.x > 0.0 else 0.0}
	var r := FlybyPlacement.place(Vector3(0, 0, 2000), Vector3(0, 100.0, 0), Vector2(0, 1), p, east)
	if r.pos.x > 0.0:
		return "should stand on the clear (west) side: %s" % r.pos
	var everywhere := {"cloud": func(_q: Vector3) -> float: return 1.0}
	r = FlybyPlacement.place(Vector3(0, 0, 2000), Vector3(0, 100.0, 0), Vector2(0, 1), p, everywhere)
	return "" if r.has("pos") and r.pos.distance_to(Vector3(0, 0, 2000)) > 50.0 else "no position in solid cloud"


## The cockpit eye dips when the vertical load rises, and it comes back once the load is 1 g again.
func test_cockpit_eye_dips_on_a_firm_touchdown() -> String:
	var s := Vector2.ZERO
	for i in 20:
		s = CameraRig.seat_step(s.x, s.y, 1.8, 1.0 / 60.0)
	if s.x > -0.008 or s.x < -0.045:
		return "a 1.8 g touchdown should drop the eye a couple of centimetres, got %.3f m" % s.x
	for i in 180:
		s = CameraRig.seat_step(s.x, s.y, 1.0, 1.0 / 60.0)
	if absf(s.x) > 0.004:
		return "the eye should settle back near the design point, got %.3f m" % s.x
	return ""


## Chase distance eases with speed. A long frame at constant speed must not change it, and one frame of a speed jump must not either.
func test_chase_camera_does_not_zoom_on_a_hitch() -> String:
	var back := Vector3(0, 0, 1)
	var held := CameraRig.chase_step(back, 10.0, back, 120.0, 12.0, 0.25)
	if absf(held.trail - 10.0) > 0.05:
		return "a 250 ms hitch at constant speed moved the trail by %.2f m" % (held.trail - 10.0)
	var jumped := CameraRig.chase_step(back, 10.0, back, 230.0, 12.0, 1.0 / 60.0)
	if jumped.trail > 10.4:
		return "one frame at jet speed zoomed the trail to %.2f m" % jumped.trail
	var turn := CameraRig.chase_step(back, 10.0, Vector3(1, 0, 0), 120.0, 12.0, 1.0 / 60.0)
	if turn.back.distance_to(Vector3(1, 0, 0)) < 0.5:
		return "the chase heading snapped through a 90 deg turn in one frame"
	return ""


## A re-placement moves the camera far enough in one frame that PostFxRules.is_cut (motion blur, TAA history) sees a cut.
func test_flyby_replacement_is_a_cut() -> String:
	for id in ["c172", "a320"]:
		var p := _par(id)
		for kt in [5.0, 40.0, 100.0, 140.0, 300.0]:
			var v := Vector3(0, kt * KT, 0)
			var r := _pass(p, Vector3(0, 0, 1000), v)
			var w: Vector3 = r.end_w
			var nxt := FlybyPlacement.place(w, v, Vector2(0, 1), p)
			var a := Transform3D.IDENTITY.looking_at(w - r.cam, Vector3.UP).translated(r.cam)
			var b := Transform3D.IDENTITY.looking_at(w - nxt.pos, Vector3.UP).translated(nxt.pos)
			a.origin = r.cam
			b.origin = nxt.pos
			if not PostFxRules.is_cut(a, b, DT):
				return "%s %d kt: re-placement %.0f m is not a cut" % [id, kt, r.cam.distance_to(nxt.pos)]
	return ""
