class_name LightParts
extends RefCounted
## Node builders for AircraftLights: a point light (emissive bulb + additive halo + small skin-lighting omni) and a
## lamp (spot light + bulb + halo + faint visible beam + ground pool). Everything is added under `parent` at
## positions in that parent's space (render axes: x right, y up, z aft).

const HALO_SHADER := preload("res://aircraft/common/light_halo.gdshader")
const BEAM_SHADER := preload("res://aircraft/common/light_beam.gdshader")
const LAMP := Color(1.0, 0.93, 0.8)


## -> [bulb, halo material, omni (null when rng <= 0)]. bulb_r = bulb radius (m), size = halo scale.
static func point(parent: Node3D, p: Vector3, c: Color, size: float, rng: float, omni_off: Vector3, bulb_r := 0.06) -> Array:
	var bulb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = bulb_r
	sm.height = bulb_r * 2.0
	sm.radial_segments = 16
	sm.rings = 8
	bulb.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = c * 0.3
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.0
	bulb.material_override = m
	bulb.position = p
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(bulb)
	var hm := halo_mat()
	var ls := LightSet.new()
	ls.add(p.x, -p.z, p.y, c, Vector2.ZERO, 4.0, 0.0, false, 0.0, size)
	parent.add_child(ls.make_instance(hm, "halo"))
	var o: OmniLight3D = null
	if rng > 0.0:
		o = OmniLight3D.new()
		o.position = p + omni_off
		o.light_color = c
		o.omni_range = rng
		o.omni_attenuation = 1.2
		o.light_cull_mask = LightLogic.AIRCRAFT_LAYER
		o.light_specular = 0.3
		o.shadow_enabled = false
		o.light_energy = 0.0
		o.visible = false
		parent.add_child(o)
	return [bulb, hm, o]


static func halo_mat() -> ShaderMaterial:
	var hm := ShaderMaterial.new()
	hm.shader = HALO_SHADER
	hm.set_shader_parameter("level", 0.0)
	hm.set_shader_parameter("gain", 2.5)
	hm.set_shader_parameter("base_m", 0.25)
	hm.set_shader_parameter("min_px", 3.0)
	hm.set_shader_parameter("max_m", 30.0)
	hm.set_shader_parameter("halo", 0.45)
	return hm


## A spot lamp at p shining along `dir` (unit, parent space). d = the aircraft.json entry: energy, range, angle,
## beam (visible cone length, 0 = none), skin (lights the aircraft's own skin, e.g. logo / wing scan lights; no ground
## pool), pool (ground pool, default: not skin), bulb (radius m), size (halo scale).
## -> [SpotLight3D, halo material, beam material or null, bulb, beam or null, LandingPool or null, mount].
static func lamp(parent: Node3D, p: Vector3, dir: Vector3, d: Dictionary) -> Array:
	var angle := float(d.get("angle", 20.0))
	var beam_len := float(d.get("beam", 20.0))
	var skin := bool(d.get("skin", false))
	var mount := Node3D.new()  # -Z along the beam
	mount.position = p
	mount.basis = aim_basis(dir)
	parent.add_child(mount)
	var l := SpotLight3D.new()
	l.light_color = LAMP
	l.light_energy = float(d.get("energy", 10.0))
	l.spot_range = float(d.get("range", 300.0))
	l.spot_angle = angle
	l.spot_angle_attenuation = 1.5
	l.spot_attenuation = 0.45 if not skin else 1.0
	l.light_cull_mask = LightLogic.AIRCRAFT_LAYER if skin else 0xFFFFF & ~LightLogic.AIRCRAFT_LAYER
	l.light_specular = 0.25 if skin else 0.5
	l.shadow_enabled = false
	l.visible = false
	mount.add_child(l)
	var beam: MeshInstance3D = null
	var bm: ShaderMaterial = null
	if beam_len > 0.0:
		beam = MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = tan(deg_to_rad(angle)) * beam_len * 0.8
		cm.bottom_radius = 0.06
		cm.height = beam_len
		cm.radial_segments = 16
		cm.rings = 1
		cm.cap_top = false
		cm.cap_bottom = false
		beam.mesh = cm
		bm = ShaderMaterial.new()
		bm.shader = BEAM_SHADER
		bm.set_shader_parameter("length_m", beam_len)
		bm.set_shader_parameter("color", LAMP)
		beam.material_override = bm
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3(0, 0, -beam_len * 0.5))
		beam.visible = false
		mount.add_child(beam)
	var pt := point(mount, Vector3.ZERO, LAMP, float(d.get("size", 0.9)), 0.0, Vector3.ZERO, float(d.get("bulb", 0.06)))
	var pool: LandingPool = null
	if bool(d.get("pool", not skin)):
		pool = LandingPool.new()
		var wide := angle > 20.0
		pool.setup(3.0 if wide else 8.0, 35.0 if wide else 90.0, 26.0 if wide else 16.0, 0.16 if wide else 0.24, p.x)
		pool.yaw = atan2(dir.x, -dir.z)
		parent.add_child(pool)
	return [l, pt[1], bm, pt[0], beam, pool, mount]


## Basis whose -Z points along dir (render axes), keeping +Y as close to up as possible.
static func aim_basis(dir: Vector3) -> Basis:
	var f := dir.normalized()
	if f.length() < 0.5:
		return Basis.IDENTITY
	var up := Vector3.UP if absf(f.dot(Vector3.UP)) < 0.98 else Vector3.BACK
	return Basis.looking_at(f, up)


## Lamp direction in render axes from tilt (deg down from the nose) and yaw (deg, + = to the right).
static func tilt_yaw_dir(tilt_deg: float, yaw_deg: float) -> Vector3:
	var t := deg_to_rad(tilt_deg)
	var y := deg_to_rad(yaw_deg)
	return Vector3(sin(y) * cos(t), -sin(t), -cos(y) * cos(t))
