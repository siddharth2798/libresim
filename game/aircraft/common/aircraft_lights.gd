class_name AircraftLights
extends Node3D
## Exterior lights driven by Props controls/lights/* and bus power:
## nav (red left tip, green right tip, white tail), beacon (red, fin top, flashing),
## strobes (white wingtip double-flash), taxi + landing spot lights (cowling).
## Positions come from aircraft.json "lights" (AircraftDef): every list entry is a light,
##   nav     [{"pos": [x,y,z], "side": "left|right|tail", "color": "red|green|white", "size", "range", "omni_off"}]
##   beacon  [{...}]  flashing red (an airliner has two)      strobe  [{...}]  double-flash white
##   lamps   [{"switch": "landing|taxi", "pos", "energy", "range", "angle", "beam", "tilt"}]  spot lights
## pos = structural metres (x aft, y right, z up); omni_off = offset of the skin-lighting omni in local
## render axes (x right, y up, z aft); size = halo scale; range = omni range (m); tilt = deg down from the nose.
## Each light = emissive bulb (day and night) + additive halo billboard with a minimum
## pixel size (world/light_point.gdshader, night only) + a small shadowless OmniLight that
## lights the aircraft's own skin (AIRCRAFT_LAYER only, off in daylight). A faint
## camera-side fill keeps the airframe readable against dark terrain in outside views.
## Rules and timing: light_logic.gd. Built by AircraftModel with its structural->local converter.

const HALO_SHADER := preload("res://world/light_point.gdshader")
const BEAM_SHADER := preload("res://aircraft/common/light_beam.gdshader")
const RED := Color(1.0, 0.08, 0.04)
const GREEN := Color(0.1, 1.0, 0.35)
const WHITE := Color(1.0, 0.97, 0.9)
const STROBE := Color(0.92, 0.95, 1.0)
const LAMP := Color(1.0, 0.93, 0.8)
const COLORS := {"red": RED, "green": GREEN, "white": WHITE, "strobe": STROBE, "lamp": LAMP}
const SIDES := {"left": 0, "right": 1, "tail": 2}  # LightLogic.nav_sector index

var _nav: Array = []      # [bulb, halo material, omni, side index for LightLogic.nav_sector]
var _strobes: Array = []  # [bulb, halo material, omni]
var _beacons: Array = []
var _lamps: Array = []    # [SpotLight3D, halo material, beam material, bulb, beam, LandingPool, switch name]
var _fill: OmniLight3D
var _t := 0.0


## cfg = the aircraft's "lights" section (see the header); s converts structural metres to local.
func build(s: Callable, cfg: Dictionary) -> void:
	for d in cfg.get("nav", []):
		var pt := _light(s, d, WHITE, 1.0, 2.5)
		pt.append(SIDES.get(str(d.get("side", "tail")), 2))
		_nav.append(pt)
	for d in cfg.get("beacon", []):
		_beacons.append(_light(s, d, RED, 1.2, 2.5))
	for d in cfg.get("strobe", []):
		_strobes.append(_light(s, d, STROBE, 1.2, 7.0))
	for d in cfg.get("lamps", []):
		var lamp := _lamp(s.call(_vec(d.pos)), float(d.get("energy", 10.0)), float(d.get("range", 300.0)),
			float(d.get("angle", 20.0)), float(d.get("beam", 20.0)), float(d.get("tilt", 10.0)))
		lamp.append(str(d.get("switch", "landing")))
		_lamps.append(lamp)
	_fill = OmniLight3D.new()
	_fill.light_color = Color(0.72, 0.8, 1.0)
	_fill.omni_range = 26.0
	_fill.omni_attenuation = 0.6
	_fill.light_cull_mask = LightLogic.AIRCRAFT_LAYER
	_fill.light_specular = 0.2
	_fill.shadow_enabled = false
	_fill.visible = false
	add_child(_fill)


func _vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _light(s: Callable, d: Dictionary, default_color: Color, size: float, rng: float) -> Array:
	var c: Color = COLORS.get(str(d.get("color", "")), default_color)
	return _point(s.call(_vec(d.pos)), c, float(d.get("size", size)), float(d.get("range", rng)), _vec(d.get("omni_off", [0, 0.1, 0])))


## Put every mesh under `root` on the aircraft render layer (lit by the omni lights here).
static func tag_exterior(root: Node) -> void:
	for gi in root.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).layers = LightLogic.AIRCRAFT_LAYER


func _point(p: Vector3, c: Color, size: float, rng: float, omni_off: Vector3) -> Array:
	var bulb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	bulb.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = c * 0.3
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.0
	bulb.material_override = m
	bulb.position = p
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bulb)
	var hm := _halo_mat(1.0)
	var ls := LightSet.new()
	ls.add(p.x, -p.z, p.y, c, Vector2.ZERO, 4.0, 0.0, false, 0.0, size)
	add_child(ls.make_instance(hm, "halo"))
	var o := OmniLight3D.new()
	o.position = p + omni_off
	o.light_color = c
	o.omni_range = rng
	o.omni_attenuation = 1.2
	o.light_cull_mask = LightLogic.AIRCRAFT_LAYER
	o.light_specular = 0.3
	o.shadow_enabled = false
	o.visible = o.light_energy > 0.01
	add_child(o)
	return [bulb, hm, o]


func _halo_mat(gain: float) -> ShaderMaterial:
	var hm := ShaderMaterial.new()
	hm.shader = HALO_SHADER
	hm.set_shader_parameter("level", 0.0)
	hm.set_shader_parameter("gain", 2.5 * gain)
	hm.set_shader_parameter("base_m", 0.35)
	hm.set_shader_parameter("min_px", 3.0)
	hm.set_shader_parameter("max_m", 30.0)
	hm.set_shader_parameter("halo", 0.45)
	return hm


func _lamp(p: Vector3, energy: float, rng: float, angle: float, beam_len: float, tilt: float) -> Array:
	var l := SpotLight3D.new()
	l.position = p
	l.rotation_degrees = Vector3(-tilt, 0.0, 0.0)  # down from the nose (-Z): pool ahead on the ground roll
	l.light_color = LAMP
	l.light_energy = energy
	l.spot_range = rng
	l.spot_angle = angle
	l.spot_angle_attenuation = 1.5
	l.spot_attenuation = 0.45
	l.light_cull_mask = 0xFFFFF & ~LightLogic.AIRCRAFT_LAYER
	l.shadow_enabled = false
	l.visible = false
	add_child(l)
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = tan(deg_to_rad(angle)) * beam_len * 0.8
	cm.bottom_radius = 0.06
	cm.height = beam_len
	cm.radial_segments = 16
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	beam.mesh = cm
	var bm := ShaderMaterial.new()
	bm.shader = BEAM_SHADER
	bm.set_shader_parameter("length_m", beam_len)
	bm.set_shader_parameter("color", LAMP)
	beam.material_override = bm
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3(0, 0, -beam_len * 0.5))
	beam.visible = false
	l.add_child(beam)
	var pt := _point(p + Vector3(0, 0, -0.05), LAMP, 1.3, 1.0, Vector3.ZERO)
	pt[2].queue_free()  # the spot itself does the lighting
	var pool := LandingPool.new()
	var wide := angle > 20.0
	pool.setup(3.0 if wide else 8.0, 35.0 if wide else 90.0, 26.0 if wide else 16.0, 0.16 if wide else 0.24, p.x)
	add_child(pool)
	return [l, pt[1], bm, pt[0], beam, pool]


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
	o.light_energy = omni_e * on
	o.visible = o.light_energy > 0.01


func _process(dt: float) -> void:
	_t += dt
	var night := LightLogic.night_factor(Props.get_f("environment/sun_elev_deg", 30.0))
	var pw := Props.get_b("systems/electrical/powered", true)
	var v := _view()
	var agl := Props.get_f("fdm/agl_m", 100.0)
	var nav := 1.0 if pw and Props.get_b("controls/lights/nav") else 0.0
	for n in _nav:
		_drive(n, nav, 4.0, night * LightLogic.nav_sector(n[3], v.x), (0.4 if n[3] == 2 else 1.4) * night)
	var bcn := LightLogic.beacon_level(_t) if pw and Props.get_b("controls/lights/beacon") else 0.0
	for b in _beacons:
		_drive(b, bcn, 8.0, 0.15 + 0.85 * night, 0.6 * night)
	var stb := 1.0 if pw and Props.get_b("controls/lights/strobe") and LightLogic.strobe_on(_t) else 0.0
	for st in _strobes:
		_drive(st, stb, 30.0, 0.4 + 1.6 * night, 6.0 * night)
	for lp in _lamps:
		var on := pw and Props.get_b("controls/lights/" + lp[6])
		var sp: SpotLight3D = lp[0]
		sp.visible = on
		var facing := pow(maxf(cos(deg_to_rad(v.x)), 0.0), 3.0)
		(lp[3].material_override as StandardMaterial3D).emission_energy_multiplier = 6.0 if on else 0.0
		(lp[1] as ShaderMaterial).set_shader_parameter("level", night * 1.3 * facing if on else 0.0)
		(lp[2] as ShaderMaterial).set_shader_parameter("intensity", 0.012 * night if on else 0.0)
		lp[4].visible = on and night > 0.0
		(lp[5] as LandingPool).place(global_transform, agl, LandingPool.pool_level(on, night, agl))
	# camera-side fill: soft and cool, outside views only
	_fill.visible = night > 0.0 and v.y > 4.0
	if _fill.visible:
		var cam := get_viewport().get_camera_3d()
		var to_cam := (cam.global_position - global_position).normalized()
		_fill.global_position = global_position + to_cam * 7.0 + Vector3.UP * 5.0
		_fill.light_energy = 0.25 * night
