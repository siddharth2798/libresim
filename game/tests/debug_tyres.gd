extends Node
## Debug: do the tyres of any aircraft stand on the drawn ground (docs/TYRE-CONTACT-PLAN.md)? Starts the flight
## scene with its usual options, optionally moves the aircraft onto grass or a slope, lets it settle on its gear,
## prints each wheel's tyre bottom - ground (terrain / FDM ground under the vertices), then saves close-ups of
## every wheel and far zoomed views to --shots=<dir> as <tag>_<view>.png and quits.
##   godot --path game --rendering-method forward_plus --resolution 1920x1080 --audio-driver Dummy \
##     res://tests/debug_tyres.tscn -- --aircraft=c172 --airport=VABB --stand --clean --quality=ultra --tod=12 \
##     --shots=<dir> --tag=c172_stand [--place=grass|slope] [--far]
var f: Node
var _shots := ""
var _tag := "tyres"
var _place := ""
var _far := false
var _fov := 0.0
var _views: Array = []  # [name, eye ENU, target ENU, fov]


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots = a.substr(8)
		elif a.begins_with("--tag="):
			_tag = a.substr(6)
		elif a.begins_with("--place="):
			_place = a.substr(8)
		elif a == "--far":
			_far = true
	DirAccess.make_dir_recursive_absolute(_shots)
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)
	RenderingServer.frame_pre_draw.connect(func():
		var cam: CameraRig = f.get_node("Camera")
		if _fov > 0.0 and cam.mode == CameraRig.Mode.FREE:
			cam.fov = _fov)
	_run.call_deferred()


func _wait(s: float) -> void:
	var t := 0.0
	while t < s:
		await get_tree().process_frame
		t += get_process_delta_time()


func _run() -> void:
	await _wait(2.0)
	var fn: FdmNode = f.get_node("Fdm")
	Props.set_v("controls/parking_brake", true)
	if _place != "":
		var p := fn.position_enu()
		var hd := Props.get_f("fdm/heading_rad", 0.0)
		var spot := _spot(Vector2(p.x, p.y), hd)
		print("PLACE %s at %s (slope %.1f %%)" % [_place, spot[0], spot[1] * 100.0])
		fn.place_on_ground(spot[0].x, spot[0].y, rad_to_deg(hd))
	await _wait(6.0)  # settle on the gear springs
	fn.paused = true
	_report()
	_make_views()
	var cam: CameraRig = f.get_node("Camera")
	cam.set_mode(CameraRig.Mode.FREE)
	for v in _views:
		cam._free_enu = v[1]
		var d: Vector3 = v[2] - v[1]
		cam._look = Vector2(-atan2(d.x, d.y), atan2(d.z, Vector2(d.x, d.y).length()))
		cam._look_goal = cam._look
		_fov = v[3]
		await _wait(4.0 if v == _views[0] else 2.5)
		get_viewport().get_texture().get_image().save_png(_shots.path_join("%s_%s.png" % [_tag, v[0]]))
		print("SHOT ", v[0])
	get_tree().quit()


## Wheel contacts: [[name, ENU of the contact's ground point]].
func _wheels() -> Array:
	var fdm: FDM = f.get_node("Fdm").fdm
	var out := []
	for c in fdm.gear.contacts:
		if c.wheel:
			var p: Vector3 = Basis(fdm.q) * fdm.mb.body_of(c.pos)  # NED from the CG
			var n: float = fdm.pos_n + p.x
			var e: float = fdm.pos_e + p.y
			out.append([c.name, Vector3(e, n, fdm.ground_height.call(n, e))])
	return out


func _report() -> void:
	var fdm: FDM = f.get_node("Fdm").fdm
	var m: AircraftModel = f.get_node("Aircraft")
	var cache: TerrainTileCache = f.get_node("Terrain").cache
	print("AIRCRAFT %s pitch %.2f roll %.2f compression %s" % [fdm.def.id, rad_to_deg(fdm.euler().y), rad_to_deg(fdm.euler().x), fdm.gear.compression])
	var ext: Node3D = m.get("_glb") if m.get("_glb") else (m._airframe if m._airframe else m.get_child(0))
	for w in _wheels():
		var low := INF
		for mi in ext.find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).mesh == null or not (mi as MeshInstance3D).is_visible_in_tree():
				continue
			var xf: Transform3D = mi.global_transform
			for si in mi.mesh.get_surface_count():
				for v in mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
					var q := FloatingOrigin.to_world(xf * v)
					if Vector2(q.x - w[1].x, q.y - w[1].y).length() < 0.8:
						low = minf(low, q.z - cache.height_at(q.x, q.y))
		print("TYRE %-10s bottom - ground %+.3f m (negative = sunk into the terrain / FDM ground)" % [w[0], low])


## Close-ups of every wheel from outboard / ahead, plus (--far) zoomed views from 1.5 and 4.5 km.
func _make_views() -> void:
	var fdm: FDM = f.get_node("Fdm").fdm
	var k := clampf(float(fdm.cfg.metrics.wingspan_m) / 11.0, 1.0, 3.3)
	var hd := Props.get_f("fdm/heading_rad", 0.0)
	var fwd := Vector3(sin(hd), cos(hd), 0.0)
	var right := Vector3(cos(hd), -sin(hd), 0.0)
	var cg: Vector3 = f.get_node("Fdm").position_enu()
	for w in _wheels():
		var g: Vector3 = w[1]
		var lat := right * signf((g - cg).dot(right))
		if absf((g - cg).dot(right)) < 0.5:  # a centre wheel: from the side, a little ahead
			lat = right * -1.0 + fwd * 0.6
		var aim := g + Vector3(0, 0, 0.12 * k)
		var eye: Vector3 = aim + lat.normalized() * 6.5 * k
		eye.z = g.z + 1.6  # the free camera stays 1.5 m above the ground
		_views.append([w[0].to_lower(), eye, aim, rad_to_deg(2.0 * atan(1.1 * k / eye.distance_to(aim)))])
	var mains := _wheels().filter(func(w): return absf((w[1] - cg).dot(right)) > 0.5)
	if not mains.is_empty():
		var g: Vector3 = mains[0][1]
		var lat := right * signf((g - cg).dot(right))
		var me: Vector3 = g - fwd * 11.0 * k + lat * 4.0 * k
		me.z = g.z + 1.6
		_views.append(["mains_low", me, g + Vector3(0, 0, 0.3 * k), rad_to_deg(2.0 * atan(2.5 * k / me.distance_to(g)))])
		if _far:
			for d in [1500.0, 4500.0]:
				var eye: Vector3 = g + (lat * 0.8 - fwd * 0.6).normalized() * d
				eye.z = f.get_node("Terrain").height_at(eye.x, eye.y) + 30.0
				eye.z = maxf(eye.z, g.z + 30.0)
				_views.append(["far%d" % int(d), eye, g + Vector3(0, 0, 0.5 * k), maxf(rad_to_deg(2.0 * atan(5.0 * k / d)), 1.3)])  # Camera3D: >= 1 degree


## --place: grass = beside the runway / stand; slope = the steepest unpaved ground within 1.5 km.
## Returns [Vector2 ENU, slope].
func _spot(p: Vector2, hd: float) -> Array:
	var t: TerrainQuadtree = f.get_node("Terrain")
	var ab: AirportBuilder = f.get_node("Airports")
	var right := Vector2(cos(hd), -sin(hd))
	if _place == "grass":
		for off in [95.0, -95.0, 130.0, -130.0, 170.0]:
			var q: Vector2 = p + right * off
			if not _paved(ab, q):
				return [q, _slope(t, q)]
		return [p + right * 95.0, 0.0]
	var best := [p + right * 95.0, -1.0]
	for r in [150.0, 300.0, 500.0, 800.0, 1100.0, 1500.0]:
		for i in 36:
			var q: Vector2 = p + Vector2.from_angle(TAU * i / 36.0) * r
			var s := _slope(t, q)
			if s > best[1] and s < 0.12 and not _paved(ab, q) and t.cache.landclass_at(q.x, q.y) != 255:
				best = [q, s]
	return best


func _slope(t: TerrainQuadtree, q: Vector2) -> float:
	var sx := (t.height_at(q.x + 15.0, q.y) - t.height_at(q.x - 15.0, q.y)) / 30.0
	var sy := (t.height_at(q.x, q.y + 15.0) - t.height_at(q.x, q.y - 15.0)) / 30.0
	var s := Vector2(sx, sy).length()
	for d in [Vector2(20, 0), Vector2(-20, 0), Vector2(0, 20), Vector2(0, -20)]:  # roughly planar around
		var e := Vector2(t.height_at(q.x + d.x, q.y + d.y) - t.height_at(q.x, q.y), 0.0).x
		if absf(e - (sx * d.x + sy * d.y)) > 0.5:
			return 0.0
	return s


func _paved(ab: AirportBuilder, q: Vector2) -> bool:
	for r in ab.data.runways:
		var a := Vector2(r.ends[0].x, r.ends[0].y)
		var b := Vector2(r.ends[1].x, r.ends[1].y)
		if Geometry2D.get_closest_point_to_segment(q, a, b).distance_to(q) < float(r.width) * 0.5 + 40.0:
			return true
	for tw in ab.data.taxiways:
		for i in tw.pts.size() - 1:
			var a := Vector2(tw.pts[i][0], tw.pts[i][1])
			var b := Vector2(tw.pts[i + 1][0], tw.pts[i + 1][1])
			if Geometry2D.get_closest_point_to_segment(q, a, b).distance_to(q) < 40.0:
				return true
	return false
