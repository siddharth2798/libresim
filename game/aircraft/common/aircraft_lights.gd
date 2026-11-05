class_name AircraftLights
extends Node3D
## Exterior lights driven by Props controls/lights/* and bus power. Positions come from aircraft.json "lights";
## every list entry is one light:
##   nav     [{"pos": [x,y,z], "side": "left|right|tail", "color": "red|green|white", ...}]  red left tip / green
##           right tip (110 deg forward sectors), white tail (140 deg aft), LightLogic.nav_sector
##   beacon  flashing red anti-collision (fin top on a light aircraft, top + belly on an airliner)
##   strobe  double-flash white (wingtips, an airliner's tail cone too)
##   lamps   [{"switch", "pos", "energy", "range", "angle", "beam", "tilt", "yaw" | "aim", "skin", "pool"}]  spot lights:
##           landing / taxi / take-off / runway turn-off (light the world and the ground pool, LandingPool), logo and
##           wing / engine scan ("skin": true lights the aircraft's own skin, no ground pool)
## Entry keys (all optional but pos):
##   pos      structural metres (x aft, y right, z up)
##   switch   controls/lights/<switch>, or a list (lit when any is on); default nav / beacon / strobe / landing
##   lit      a Props bool that must also be true (e.g. systems/lights/landing_l_on: lamp extended)
##   gear     true: only while the gear is down and locked (fdm/gear_pos >= 0.98)
##   parent   model pivot name (glb node pivot_<name>): the light moves with that part
##   size     halo scale; bulb = bulb radius (m); range = skin-lighting omni range (m); omni_off = omni offset in render axes
##   tilt     lamp aim, deg down from the nose; yaw = deg right; aim = [x, y, z] structural direction (wins)
## Each point light = emissive bulb (day and night) + additive halo with a minimum pixel size (night only,
## world/light_point.gdshader) + a small shadowless OmniLight for the aircraft's own skin (AIRCRAFT_LAYER, off in
## daylight). A faint camera-side fill keeps the airframe readable in outside views.
## debug/lights_steady keeps beacons and strobes lit (screenshots). Timing: light_logic.gd; nodes: light_parts.gd.

const RED := Color(1.0, 0.08, 0.04)
const GREEN := Color(0.1, 1.0, 0.35)
const WHITE := Color(1.0, 0.97, 0.9)
const STROBE := Color(0.92, 0.95, 1.0)
const COLORS := {"red": RED, "green": GREEN, "white": WHITE, "strobe": STROBE, "lamp": Color(1.0, 0.93, 0.8)}
const SIDES := {"left": 0, "right": 1, "tail": 2}  # LightLogic.nav_sector index
## kind -> [default switch, default colour, halo size, omni range]
const KINDS := {"nav": ["nav", WHITE, 1.0, 2.5], "beacon": ["beacon", RED, 1.2, 2.5], "strobe": ["strobe", STROBE, 1.2, 7.0]}

var _lights: Array = []  # {kind, parts, sw, lit, gear, side}
var _follow: Array = []  # [follower Node3D, pivot Node3D, rest transform inverse]
var _fill: OmniLight3D
var _t := 0.0


## cfg = the aircraft's "lights" section (see the header); s converts structural metres to local; glb = the
## exterior model root (pivots for "parent"), null for the placeholder airframe.
func build(s: Callable, cfg: Dictionary, glb: Node3D = null) -> void:
	for kind in KINDS:
		for d in cfg.get(kind, []):
			var k: Array = KINDS[kind]
			var c: Color = COLORS.get(str(d.get("color", "")), k[1])
			var parts := LightParts.point(_holder(d, glb), s.call(_vec(d.pos)), c, float(d.get("size", k[2])),
				float(d.get("range", k[3])), _vec(d.get("omni_off", [0, 0.1, 0])), float(d.get("bulb", 0.06)))
			_lights.append(_entry(kind, parts, d, k[0]))
	for d in cfg.get("lamps", []):
		var dir := LightParts.tilt_yaw_dir(float(d.get("tilt", 10.0)), float(d.get("yaw", 0.0)))
		if d.has("aim"):
			var a := _vec(d.aim)
			dir = Vector3(a.y, a.z, a.x).normalized()  # structural -> render axes (as AircraftModel._s, no offset)
		var parts := LightParts.lamp(_holder(d, glb), s.call(_vec(d.pos)), dir, d)
		_lights.append(_entry("lamp", parts, d, "landing"))
	_fill = OmniLight3D.new()
	_fill.light_color = Color(0.72, 0.8, 1.0)
	_fill.omni_range = 26.0
	_fill.omni_attenuation = 0.6
	_fill.light_cull_mask = LightLogic.AIRCRAFT_LAYER
	_fill.light_specular = 0.2
	_fill.shadow_enabled = false
	_fill.visible = false
	add_child(_fill)


func _entry(kind: String, parts: Array, d: Dictionary, default_switch: String) -> Dictionary:
	var sw = d.get("switch", default_switch)
	return {"kind": kind, "parts": parts, "sw": sw if sw is Array else [sw], "lit": str(d.get("lit", "")),
		"gear": bool(d.get("gear", false)), "side": SIDES.get(str(d.get("side", "tail")), 2)}


static func _vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


## The node a light hangs from: this one, or a follower of the model pivot named by d.parent.
func _holder(d: Dictionary, glb: Node3D) -> Node3D:
	var pname := str(d.get("parent", ""))
	if pname == "" or glb == null:
		return self
	var pv := glb.find_child("pivot_" + pname, true, false) as Node3D
	if pv == null:
		push_warning("AircraftLights: no pivot_%s in the model; the light stays on the airframe" % pname)
		return self
	for f in _follow:
		if f[1] == pv:
			return f[0]
	var fl := Node3D.new()
	fl.name = "follow_" + pname
	add_child(fl)
	_follow.append([fl, pv, _in_parent(pv).affine_inverse()])
	return fl


## Transform of n in this node's parent space (the model), walking up the tree (works before entering it).
func _in_parent(n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var stop := get_parent()
	while n != null and n != stop:
		t = n.transform * t
		n = n.get_parent() as Node3D
	return transform.affine_inverse() * t


## Put every mesh under `root` on the aircraft render layer (lit by the omni lights here).
static func tag_exterior(root: Node) -> void:
	for gi in root.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).layers = LightLogic.AIRCRAFT_LAYER


## Camera azimuth around the aircraft (deg, 0 = ahead, +90 = right) and distance.
func _view() -> Vector2:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector2(180.0, 20.0)
	var d := global_transform.affine_inverse() * cam.global_position
	return Vector2(rad_to_deg(atan2(d.x, -d.z)), d.length())


func _drive(pt: Array, on: float, bulb_e: float, halo_lv: float, omni_e: float) -> void:
	(pt[0].material_override as StandardMaterial3D).emission_energy_multiplier = bulb_e * on
	(pt[1] as ShaderMaterial).set_shader_parameter("level", halo_lv * on)
	var o: OmniLight3D = pt[2]
	if o != null:
		o.light_energy = omni_e * on
		o.visible = o.light_energy > 0.01


## Is this light's switch on, its bus powered, its own condition met (and its gear leg down)?
func _is_on(e: Dictionary, pw: bool, gear_down: bool) -> bool:
	if not pw or (e.gear and not gear_down) or (e.lit != "" and not Props.get_b(e.lit)):
		return false
	for sw in e.sw:
		if Props.get_b("controls/lights/" + str(sw)):
			return true
	return false


func _process(dt: float) -> void:
	_t += dt
	for f in _follow:  # lights on a moving part: the pivot's motion since its rest pose
		(f[0] as Node3D).transform = _in_parent(f[1]) * f[2]
	var night := LightLogic.night_factor(Props.get_f("environment/sun_elev_deg", 30.0))
	var pw := Props.get_b("systems/electrical/powered", true)
	var steady := Props.get_b("debug/lights_steady")
	var gear_down := Props.get_f("fdm/gear_pos", 1.0) >= 0.98
	var v := _view()
	var agl := Props.get_f("fdm/agl_m", 100.0)
	var bcn := 1.0 if steady else LightLogic.beacon_level(_t)
	var stb := 1.0 if steady or LightLogic.strobe_on(_t) else 0.0
	var cam := get_viewport().get_camera_3d()
	for e in _lights:
		var on := 1.0 if _is_on(e, pw, gear_down) else 0.0
		match e.kind:
			"nav":
				_drive(e.parts, on, 4.0, night * LightLogic.nav_sector(e.side, v.x), (0.4 if e.side == 2 else 1.4) * night)
			"beacon":
				_drive(e.parts, on * bcn, 8.0, 0.15 + 0.85 * night, 0.6 * night)
			"strobe":
				_drive(e.parts, on * stb, 30.0, 0.4 + 1.6 * night, 6.0 * night)
			"lamp":
				_drive_lamp(e.parts, on > 0.0, night, agl, cam)
	# camera-side fill: soft and cool, outside views only
	_fill.visible = night > 0.0 and v.y > 4.0 and cam != null
	if _fill.visible:
		var to_cam := (cam.global_position - global_position).normalized()
		_fill.global_position = global_position + to_cam * 7.0 + Vector3.UP * 5.0
		_fill.light_energy = 0.25 * night


## lp = LightParts.lamp(): the halo shows when the camera looks into the lamp.
func _drive_lamp(lp: Array, on: bool, night: float, agl: float, cam: Camera3D) -> void:
	var sp: SpotLight3D = lp[0]
	sp.visible = on
	var facing := 0.0
	if cam != null and on:
		var mount: Node3D = lp[6]
		var d := (mount.global_transform.affine_inverse() * cam.global_position).normalized()
		facing = pow(maxf(-d.z, 0.0), 3.0)
	(lp[3].material_override as StandardMaterial3D).emission_energy_multiplier = 4.0 if on else 0.0
	(lp[1] as ShaderMaterial).set_shader_parameter("level", night * 1.3 * facing if on else 0.0)
	if lp[2] != null:
		(lp[2] as ShaderMaterial).set_shader_parameter("intensity", 0.012 * night if on else 0.0)
		lp[4].visible = on and night > 0.0
	if lp[5] != null:
		(lp[5] as LandingPool).place(global_transform, agl, LandingPool.pool_level(on, night, agl))
