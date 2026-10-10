class_name C172Model
extends Node3D
## C172 exterior. Uses models/exterior.glb (FlightGear c172p converted by
## tools/blender/convert_c172p.py, GPL-2.0-or-later, c172p team) when present,
## else a placeholder built from primitives. Origin = CG; -Z = nose, +X = right wing, +Y = up. Part positions are given in
## JSBSim structural metres (x aft, y right, z up) and converted with _s().
## Animates the propeller, control surfaces and flaps from Props.

var fdm_node: FdmNode
var cockpit: Cockpit
var _cg := Vector3.ZERO
var _prop: Node3D
var _surfaces := {}  # name -> [Node3D pivot, axis Vector3]
var _white := StandardMaterial3D.new()
var _stripe := StandardMaterial3D.new()
var _dark := StandardMaterial3D.new()
var _glass := StandardMaterial3D.new()
var _pivots := {}  # glb mode: name -> [Node3D, base Basis]

const GLB := "res://aircraft/c172/models/exterior.glb"


func build(node: FdmNode) -> void:
	fdm_node = node
	_cg = node.fdm.mb.cg
	_white.albedo_color = Color(0.93, 0.93, 0.9)
	_white.roughness = 0.4
	_stripe.albedo_color = Color(0.1, 0.25, 0.6)
	_dark.albedo_color = Color(0.08, 0.08, 0.08)
	_glass.albedo_color = Color(0.15, 0.2, 0.25, 0.55)
	_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass.roughness = 0.1
	if ResourceLoader.exists(GLB):
		_build_glb()
	else:
		_build_boxes()
	var e: Array = node.fdm.cfg.metrics.eyepoint_m
	cockpit = Cockpit.new()
	add_child(cockpit)
	cockpit.build(self, _s(Vector3(e[0], e[1], e[2])))
	var lights := AircraftLights.new()
	add_child(lights)
	lights.build(_s)


## FlightGear model frame (x aft, y right, z up, origin = VRP) exported Y-up by glTF:
## glb axes are (X aft, Y up, Z left) -> ours (X right, Y up, Z aft).
func _build_glb() -> void:
	var inst: Node3D = (load(GLB) as PackedScene).instantiate()
	inst.transform = fg_transform()
	add_child(inst)
	for n in ["aileron_L", "aileron_R", "elevator_L", "elevator_R", "rudder", "flaps", "prop"]:
		var pv := inst.find_child("pivot_" + n, true, false) as Node3D
		if pv:
			_pivots[n] = [pv, pv.transform.basis]
	fix_glass(inst)


## FlightGear glass uses an effect shader; make it a clear, slightly reflective pane.
static func fix_glass(root: Node) -> void:
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.85, 0.92, 0.95, 0.1)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic_specular = 0.9
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		for i in m.get_surface_count():
			var mat := m.surface_get_material(i)
			if mat and mat.resource_name.to_lower().contains("glas"):
				(mi as MeshInstance3D).set_surface_override_material(i, glass)


## Transform placing a FlightGear-frame glb (origin = VRP) in this node.
func fg_transform() -> Transform3D:
	var v: Array = fdm_node.fdm.cfg.metrics.vrp_m
	return Transform3D(Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)), _s(Vector3(v[0], v[1], v[2])))


## FlightGear model-frame point (x aft, y right, z up, from VRP) -> local.
func fg_to_local(p: Vector3) -> Vector3:
	var v: Array = fdm_node.fdm.cfg.metrics.vrp_m
	return _s(p + Vector3(v[0], v[1], v[2]))


func _build_boxes() -> void:
	# fuselage: cabin box + tapering tail cone + cowling
	_box(Vector3(0.6, 0.0, 0.7), Vector3(1.1, 1.5, 2.4), _white)  # cabin (roof meets the wing)
	_box(Vector3(-0.75, 0.0, 0.35), Vector3(1.0, 0.85, 0.8), _white)  # cowling
	_box(Vector3(3.6, 0.0, 0.55), Vector3(0.5, 0.75, 3.6), _white)  # tail cone
	_box(Vector3(0.75, 0.0, 1.15), Vector3(1.12, 0.55, 1.6), _glass)  # windows band
	_box(Vector3(2.2, 0.0, 0.45), Vector3(1.13, 0.12, 4.0), _stripe)  # side stripe
	# wing (high wing) with flaps and ailerons as pivots on the trailing edge
	_box(Vector3(1.05, 0.0, 1.5), Vector3(11.0, 0.16, 1.45), _white)
	for side in [-1.0, 1.0]:
		_surface("flap_%d" % side, Vector3(1.85, side * 1.9, 1.45), Vector3(2.6, 0.08, 0.38), Vector3(1, 0, 0))
		_surface("aileron_%d" % side, Vector3(1.85, side * 4.3, 1.45), Vector3(2.0, 0.08, 0.35), Vector3(1, 0, 0))
		_strut(Vector3(1.2, side * 0.55, 0.0), Vector3(1.2, side * 2.6, 1.42))
		_strut(Vector3(1.48, side * 0.55, -0.05), Vector3(1.48, side * 1.09, -0.15))
		_wheel(Vector3(1.48, side * 1.09, -0.39 + 0.21))
	_wheel(Vector3(-0.17, 0.0, -0.5 + 0.19), 0.19)
	_strut(Vector3(-0.3, 0.0, 0.0), Vector3(-0.17, 0.0, -0.3))
	# tail: horizontal stabiliser + elevator, fin + rudder
	_box(Vector3(5.75, 0.0, 0.62), Vector3(3.4, 0.08, 0.75), _white)
	_surface("elevator", Vector3(6.15, 0.0, 0.62), Vector3(3.3, 0.06, 0.45), Vector3(1, 0, 0))
	_box(Vector3(5.6, 0.0, 1.35), Vector3(0.08, 1.4, 1.0), _white)
	_surface("rudder", Vector3(6.15, 0.0, 1.3), Vector3(0.06, 1.45, 0.4), Vector3(0, 1, 0))
	# propeller: spinner + two blades
	_prop = Node3D.new()
	_prop.position = _s(Vector3(-1.28, 0.0, 0.35))
	add_child(_prop)
	var sp := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02; cone.bottom_radius = 0.17; cone.height = 0.35
	sp.mesh = cone
	sp.rotation_degrees = Vector3(-90, 0, 0)
	sp.material_override = _white
	_prop.add_child(sp)
	var blade := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.9, 0.12, 0.02)
	blade.mesh = bm
	blade.material_override = _dark
	_prop.add_child(blade)


## JSBSim structural point -> local render offset from the CG.
func _s(p: Vector3) -> Vector3:
	return Vector3(p.y - _cg.y, p.z - _cg.z, p.x - _cg.x)


func _box(center: Vector3, size_xyz: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size_xyz  # (span along X, height Y, length Z)
	mi.mesh = b
	mi.material_override = mat
	mi.position = _s(center)
	add_child(mi)
	return mi


func _surface(name: String, hinge: Vector3, size_xyz: Vector3, axis: Vector3) -> void:
	var pivot := Node3D.new()
	pivot.position = _s(hinge - Vector3(size_xyz.z * 0.5, 0, 0))  # hinge line = leading edge
	add_child(pivot)
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size_xyz
	mi.mesh = b
	mi.material_override = _white
	mi.position = Vector3(0, 0, size_xyz.z * 0.5)
	pivot.add_child(mi)
	_surfaces[name] = [pivot, axis]


func _strut(a: Vector3, b: Vector3) -> void:
	var pa := _s(a)
	var pb := _s(b)
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.03; c.bottom_radius = 0.03; c.height = pa.distance_to(pb)
	mi.mesh = c
	mi.material_override = _white
	add_child(mi)
	mi.look_at_from_position((pa + pb) * 0.5, pb, Vector3.FORWARD if absf((pb - pa).normalized().y) > 0.99 else Vector3.UP)
	mi.rotate_object_local(Vector3.RIGHT, PI / 2)


func _wheel(center: Vector3, r := 0.21) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r; c.bottom_radius = r; c.height = 0.14
	mi.mesh = c
	mi.material_override = _dark
	mi.position = _s(center)
	mi.rotation_degrees = Vector3(0, 0, 90)
	add_child(mi)


func _process(_dt: float) -> void:
	if fdm_node == null:
		return
	transform = fdm_node.render_transform()
	var f := fdm_node.fdm
	if not _pivots.is_empty():
		_animate_glb(f)
		return
	_prop.rotate_object_local(Vector3.FORWARD, f.prop.rpm / 60.0 * TAU * get_process_delta_time() * 0.13)
	var c := f.fcs
	# positive rotation about +X moves a trailing edge down; about +Y moves it right
	_deflect("elevator", c.elevator)  # JSBSim +elevator = trailing edge down
	_deflect("rudder", -c.rudder)  # JSBSim +rudder = trailing edge left
	_deflect("aileron_1", -c.aileron)  # right roll: right aileron up
	_deflect("aileron_-1", c.aileron)
	_deflect("flap_1", deg_to_rad(c.flap_deg))
	_deflect("flap_-1", deg_to_rad(c.flap_deg))


func _deflect(name: String, angle: float) -> void:
	var s: Array = _surfaces[name]
	(s[0] as Node3D).rotation = s[1] * angle


## Signs derived from each hinge axis direction (see convert_c172p.py HINGES):
## +angle about the pivot's +X moves the trailing edge down (ailerons, flaps),
## up (elevators, axis runs outboard->inboard reversed), right (rudder).
func _animate_glb(f: FDM) -> void:
	var c := f.fcs
	var turn := {"aileron_L": c.aileron, "aileron_R": -c.aileron, "elevator_L": -c.elevator,
		"elevator_R": -c.elevator, "rudder": -c.rudder, "flaps": deg_to_rad(c.flap_deg)}
	for k in turn:
		if _pivots.has(k):
			_pivots[k][0].transform.basis = _pivots[k][1] * Basis(Vector3.RIGHT, turn[k])
	if _pivots.has("prop"):
		var pv: Node3D = _pivots.prop[0]
		pv.rotate_object_local(Vector3.RIGHT, -f.prop.rpm / 60.0 * TAU * get_process_delta_time() * 0.13)
