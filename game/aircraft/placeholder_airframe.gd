class_name PlaceholderAirframe
extends Node3D
## Stand-in airframe of primitives for an aircraft without models/exterior.glb, sized from its
## config.json: wingspan / chord / aero reference point, horizontal tail arm and area, gear contact
## points (wheels), engine positions (one propeller or nacelle each). Ailerons, flaps, elevator and
## rudder move with the controls and propellers spin with their engine, so it flies plausibly
## until real art exists. Child of AircraftModel; positions are structural metres via the converter.

var _s: Callable  # structural point -> AircraftModel-local offset from the CG
var _white := StandardMaterial3D.new()
var _dark := StandardMaterial3D.new()
var _glass := StandardMaterial3D.new()
var _surfaces: Array = []  # [pivot, hinge axis, fcs field, sign]
var _props: Array = []     # [spinning node, Thruster]


func build(f: FDM, s: Callable) -> void:
	_s = s
	_white.albedo_color = Color(0.93, 0.93, 0.9)
	_white.roughness = 0.4
	_dark.albedo_color = Color(0.08, 0.08, 0.08)
	_glass.albedo_color = Color(0.15, 0.2, 0.25, 0.55)
	_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass.roughness = 0.1
	var m: Dictionary = f.cfg.metrics
	var span: float = m.wingspan_m
	var chord: float = m.chord_m
	var ref: Array = m.aero_ref_pt_m
	var k := span / 10.9  # fuselage sizes scale with the wingspan (10.9 m = a light single)
	var arm: float = m.get("htail_arm_m", 4.8 * k)
	var tail_x: float = ref[0] + arm
	var gear := _contacts(f.cfg, ref[2] - 2.0 * k)
	var zc := _lowest(gear) + 1.15 * k  # fuselage axis height
	var nose_x: float = ref[0] - 0.6 * arm
	for u in f.units:
		if u.thruster.diameter > 0.0:
			nose_x = minf(nose_x, u.pos.x + 0.05)
	var cabin_x := nose_x + 1.0 * k
	var cabin_end: float = ref[0] + 0.75 * k
	_box(Vector3(nose_x + 0.5 * k, 0, zc - 0.3 * k), Vector3(1.0 * k, 0.85 * k, 1.0 * k), _white)  # cowling
	_box(Vector3((cabin_x + cabin_end) * 0.5, 0, zc), Vector3(1.1 * k, 1.5 * k, cabin_end - cabin_x), _white)
	_box(Vector3((cabin_x + cabin_end) * 0.5, 0, zc + 0.45 * k), Vector3(1.12 * k, 0.55 * k, (cabin_end - cabin_x) * 0.65), _glass)
	_box(Vector3((cabin_end + tail_x) * 0.5, 0, zc - 0.1 * k), Vector3(0.5 * k, 0.75 * k, tail_x - cabin_end), _white)  # tail cone
	# wing with flap and aileron pairs on the trailing edge
	var wing := Vector3(ref[0] - 0.05 * k, 0, ref[2])
	_box(wing, Vector3(span, 0.11 * chord, chord), _white)
	var te := wing.x + chord * 0.5
	for side in [-1.0, 1.0]:
		_surface(Vector3(te - 0.28 * chord, side * 0.17 * span, wing.z), Vector3(0.24 * span, 0.06, 0.28 * chord), Vector3.RIGHT, "flap_deg", 1.0)
		_surface(Vector3(te - 0.25 * chord, side * 0.39 * span, wing.z), Vector3(0.18 * span, 0.06, 0.25 * chord), Vector3.RIGHT, "aileron", -side)
		if ref[2] > zc + 0.5 * k:  # high wing: a strut from the fuselage to the wing
			_strut(Vector3(ref[0], side * 0.55 * k, zc - 0.3 * k), Vector3(ref[0], side * 0.24 * span, wing.z))
	# tail: horizontal stabiliser + elevator, fin + rudder
	var hw := 0.31 * span
	var hc: float = m.get("htail_area_m2", 0.1 * span * chord) / hw
	_box(Vector3(tail_x, 0, zc), Vector3(hw, 0.08, hc), _white)
	_surface(Vector3(tail_x + hc * 0.5 - 0.6 * hc, 0, zc), Vector3(hw * 0.97, 0.06, 0.6 * hc), Vector3.RIGHT, "elevator", 1.0)
	_box(Vector3(tail_x - 0.1 * k, 0, zc + 0.75 * k), Vector3(0.08, 1.4 * k, 1.0 * k), _white)
	_surface(Vector3(tail_x + 0.4 * k, 0, zc + 0.7 * k), Vector3(0.06, 1.45 * k, 0.4 * k), Vector3.UP, "rudder", -1.0)
	for g in gear:
		_wheel(g, 0.2 * k, zc, k)
	for u in f.units:
		_engine(u, k)


## Gear contact points (structural metres), BOGEY entries of config.gear; fallback if there are none.
func _contacts(cfg: Dictionary, fallback_z: float) -> Array:
	var out := []
	for g in cfg.get("gear", []):
		if str(g.get("type", "")) == "BOGEY":
			out.append(Vector3(g.pos_m[0], g.pos_m[1], g.pos_m[2]))
	return out if not out.is_empty() else [Vector3(0, 0, fallback_z)]


func _lowest(pts: Array) -> float:
	var z := INF
	for p in pts:
		z = minf(z, p.z)
	return z


func _engine(u: PowerUnit, k: float) -> void:
	if u.thruster.diameter > 0.0:  # propeller: spinner + two blades
		var prop := Node3D.new()
		prop.position = _s.call(u.pos)
		add_child(prop)
		var sp := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.02 * k
		cone.bottom_radius = 0.16 * k
		cone.height = 0.35 * k
		sp.mesh = cone
		sp.rotation_degrees = Vector3(-90, 0, 0)
		sp.material_override = _white
		prop.add_child(sp)
		var blade := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(u.thruster.diameter, 0.12, 0.02)
		blade.mesh = bm
		blade.material_override = _dark
		prop.add_child(blade)
		_props.append([prop, u.thruster])
		return
	var nac := MeshInstance3D.new()  # jet: a nacelle, no moving parts
	var cm := CylinderMesh.new()
	cm.top_radius = 0.35 * k
	cm.bottom_radius = 0.3 * k
	cm.height = 1.8 * k
	nac.mesh = cm
	nac.material_override = _white
	nac.position = _s.call(u.pos + Vector3(0.7 * k, 0, 0))
	nac.rotation_degrees = Vector3(90, 0, 0)
	add_child(nac)


func _box(center: Vector3, size_xyz: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size_xyz  # (span along X, height Y, length Z)
	mi.mesh = b
	mi.material_override = mat
	mi.position = _s.call(center)
	add_child(mi)


## A control surface hinged at its leading edge `hinge`, extending aft. Positive rotation about +X
## moves a trailing edge down, about +Y moves it right; `drive` is the FlightControls field.
func _surface(hinge: Vector3, size_xyz: Vector3, axis: Vector3, drive: String, sign_: float) -> void:
	var pivot := Node3D.new()
	pivot.position = _s.call(hinge)
	add_child(pivot)
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size_xyz
	mi.mesh = b
	mi.material_override = _white
	mi.position = Vector3(0, 0, size_xyz.z * 0.5)
	pivot.add_child(mi)
	_surfaces.append([pivot, axis, drive, sign_])


func _strut(a: Vector3, b: Vector3) -> void:
	var pa: Vector3 = _s.call(a)
	var pb: Vector3 = _s.call(b)
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.03
	c.bottom_radius = 0.03
	c.height = pa.distance_to(pb)
	mi.mesh = c
	mi.material_override = _white
	add_child(mi)
	mi.look_at_from_position((pa + pb) * 0.5, pb, Vector3.FORWARD if absf((pb - pa).normalized().y) > 0.99 else Vector3.UP)
	mi.rotate_object_local(Vector3.RIGHT, PI / 2)


## Wheel at a gear contact point (the tyre bottom) and a strut up to the fuselage.
func _wheel(contact: Vector3, r: float, zc: float, k: float) -> void:
	var center := contact + Vector3(0, 0, r)
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = 0.7 * r
	mi.mesh = c
	mi.material_override = _dark
	mi.position = _s.call(center)
	mi.rotation_degrees = Vector3(0, 0, 90)
	add_child(mi)
	_strut(Vector3(contact.x, signf(contact.y) * minf(absf(contact.y), 0.55 * k), zc - 0.45 * k), center + Vector3(0, 0, r * 0.7))


## Move the surfaces with the controls and spin the propellers (called every frame).
func animate(f: FDM, dt: float) -> void:
	for s in _surfaces:
		var v: float = deg_to_rad(f.fcs.flap_deg) if s[2] == "flap_deg" else float(f.fcs.get(s[2]))
		(s[0] as Node3D).rotation = (s[1] as Vector3) * v * s[3]
	for p in _props:
		(p[0] as Node3D).rotate_object_local(Vector3.FORWARD, (p[1] as Thruster).rpm / 60.0 * TAU * dt * 0.13)
