extends RefCounted
## Camera aiming for tests/debug_showcase.gd scene definitions (tests/showcase_scenes.gd format):
##   cam = [forward, right, up] m from the aircraft in its heading frame, aimed at aim (same frame); agl: those
##   heights are above the ground under each point; frame_vehicle / on_follow: the frame is that ground vehicle's
##   or the follow-me car's; mode: cockpit | chase | orbit; look = [yaw_deg, pitch_deg]; fov; dist (orbit / chase).


## Aims the rig for scene `def`; returns the free-camera field of view to hold (degrees, 0 = the rig's own).
static func aim(f: Node, cam: CameraRig, def: Dictionary) -> float:
	var p: Vector3 = f.get_node("Fdm").position_enu()
	var h := Props.get_f("fdm/heading_rad", 0.0)
	if def.has("frame_vehicle"):  # frame = the ground vehicle of that kind nearest to the aircraft (AirportOps node "<kind>")
		var best: Node3D = null
		var bd := INF
		for n in f.get_node("AirportOps").find_children(str(def.frame_vehicle) + "*", "Node3D", true, false):
			var d := (n as Node3D).global_position.distance_to(FloatingOrigin.to_render(p))
			if d < bd:
				bd = d
				best = n
		if best != null:
			p = FloatingOrigin.to_world(best.global_position)
			h = -best.global_rotation.y
	if def.get("on_follow", false) and f.get_node("GroundOps")._follow != null:  # frame = the follow-me car's
		var car: FollowMeCar = f.get_node("GroundOps")._follow
		p = car.world_enu
		h = car.heading
	var fwd := Vector2(sin(h), cos(h))
	var right := Vector2(cos(h), -sin(h))
	if def.has("mode"):  # cockpit | chase | orbit
		cam.set_mode(["cockpit", "chase", "orbit"].find(def.mode))
	if def.has("cam"):
		var c: Array = def.cam
		var a: Array = def.get("aim", [0.0, 0.0, 0.0])
		var from := Vector3(p.x, p.y, p.z) + Vector3(fwd.x * c[0] + right.x * c[1], fwd.y * c[0] + right.y * c[1], c[2])
		var to := Vector3(p.x, p.y, p.z) + Vector3(fwd.x * a[0] + right.x * a[1], fwd.y * a[0] + right.y * a[1], a[2])
		if def.get("agl", false):  # cam / aim heights are metres above the ground under each point
			var cache: TerrainTileCache = f.get_node("Terrain").cache
			from.z = cache.height_at(from.x, from.y) + c[2]
			to.z = cache.height_at(to.x, to.y) + a[2]
		var d := to - from
		if cam.mode != CameraRig.Mode.FREE:
			cam.set_mode(CameraRig.Mode.FREE)
		cam._free_enu = from
		cam._look = Vector2(-atan2(d.x, d.y), atan2(d.z, Vector2(d.x, d.y).length()))
		cam._look_goal = cam._look
	elif def.has("look"):
		cam._look = Vector2(deg_to_rad(def.look[0]), deg_to_rad(def.look[1]))
		cam._look_goal = cam._look
	if def.has("dist"):
		cam._dist = float(def.dist)
	if def.has("fov"):  # cockpit zoom, or a fixed field of view for the free camera
		cam._fov_cockpit = float(def.fov)
		cam._fov_goal = float(def.fov)
		return float(def.fov)
	return 0.0


## Just before drawing: the camera rig sets its own 65 degrees every frame, and the model keeps the propeller
## turning slowly (a still blade across the view), so both are set here. fov 0 / prop_deg < 0: left alone.
static func pre_draw(f: Node, fov: float, prop_deg: float) -> void:
	var cam: CameraRig = f.get_node("Camera")
	if fov > 0.0 and cam.mode == CameraRig.Mode.FREE:
		cam.fov = fov
	var model: AircraftModel = f.get_node("Aircraft")
	if prop_deg >= 0.0 and model._pivots.has("prop"):
		model._pivots.prop[0].transform.basis = model._pivots.prop[1] * Basis(Vector3.RIGHT, deg_to_rad(prop_deg))
