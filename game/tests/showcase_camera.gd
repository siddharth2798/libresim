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


## Before a scene's screenshot: "" when the camera was placed, else why not. The graphics audit once saved two
## pictures from under the ground (low_ground, cloud_tops): a script error had stopped the flight scene's _ready
## before the aircraft was placed and the camera rig set up, so the camera stayed at its default spot.
static func view_error(f: Node, cam: CameraRig) -> String:
	var t := cam.global_transform
	var eye := FloatingOrigin.to_world(t.origin) if t.is_finite() else Vector3(NAN, NAN, NAN)
	var ground := NAN
	var cache: TerrainTileCache = f.get_node("Terrain").cache
	if cache != null and eye.is_finite():
		ground = cache.height_at(eye.x, eye.y)
	return eye_error(t, eye.z, ground, cam.aircraft != null)


## The checks of view_error on plain values: the rig set up, a finite transform, the eye not under the ground
## (ground NAN: unknown, not checked). UNDER_M of slack for the low light-check cameras beside a parked aircraft.
const UNDER_M := 0.25
static func eye_error(t: Transform3D, eye_up: float, ground: float, rig_ready: bool) -> String:
	if not rig_ready:
		return "the camera rig was never set up (the flight scene stopped early: see the script errors above)"
	if not t.is_finite():
		return "the camera transform is not finite"
	if is_finite(ground) and eye_up < ground - UNDER_M:
		return "the camera is %.1f m under the ground" % (ground - eye_up)
	return ""


## A scene definition's camera keys (tests/showcase_scenes.gd format): "" when usable, else what is wrong. cam / aim
## are 3 finite numbers, apart (the aim gives a direction); the eye is above the ground: up >= 0 with "agl" or on a
## ground start, and above the ground by the start height on an air start. look: 2 finite numbers, pitch within
## +-90 deg. fov in (1, 120) deg, dist > 0.
static func def_error(def: Dictionary) -> String:
	var setup: Dictionary = def.get("setup", {})
	if def.has("cam"):
		var c: Array = def.cam
		var a: Array = def.get("aim", [0.0, 0.0, 0.0])
		if c.size() != 3 or a.size() != 3 or not (c + a).all(func(x): return (x is float or x is int) and is_finite(float(x))):
			return "cam %s / aim %s must be 3 finite numbers each" % [c, a]
		if Vector3(c[0], c[1], c[2]).distance_to(Vector3(a[0], a[1], a[2])) < 1.0:
			return "cam %s and aim %s are less than 1 m apart: no view direction" % [c, a]
		var up := float(c[2])
		if setup.get("start", Session.DEFAULT.start) == "air" and not def.get("agl", false):
			var ft := float(setup.get("air_ft", Session.DEFAULT.air_ft))
			up += ft * 0.3048
			if up < 10.0:
				return "cam %s is only %.0f m above the ground on a %.0f ft air start" % [c, up, ft]
		elif up < 0.0:
			return "cam %s is under the ground (up < 0)" % [c]
	if def.has("look"):
		var l: Array = def.look
		if l.size() != 2 or not l.all(func(x): return is_finite(float(x))) or absf(float(l[1])) > 90.0:
			return "look %s must be [yaw_deg, pitch_deg] with pitch within +-90" % [l]
	if def.has("fov") and (float(def.fov) <= 1.0 or float(def.fov) >= 120.0):
		return "fov %s out of (1, 120)" % def.fov
	if def.has("dist") and not float(def.dist) > 0.0:
		return "dist %s must be > 0" % def.dist
	return ""
