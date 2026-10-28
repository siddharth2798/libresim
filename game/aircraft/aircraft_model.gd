class_name AircraftModel
extends Node3D
## Exterior of the current aircraft (AircraftDef): models/exterior.glb when present (e.g. the FlightGear
## c172p converted by tools/blender/convert_c172p.py, GPL-2.0-or-later), else a PlaceholderAirframe
## sized from config.json. Origin = CG; -Z = nose, +X = right wing, +Y = up. Positions of parts are
## JSBSim structural metres (x aft, y right, z up) converted with _s(). Animates control surfaces and
## propellers from the FDM. Also builds the cockpit, the lights and the reflection probe.
##
## aircraft.json "model" (code defaults = the values below, so a glb with FlightGear-style pivot names
## needs nothing):
##   origin_m    [x, y, z] structural position of the glb's origin (default metrics.vrp_m)
##   surfaces    {pivot name: {"drive": fcs field, "sign": 1 | -1}}; glb nodes are "pivot_<name>"
##               (hinge on +X: positive moves the trailing edge down). drive = elevator | aileron |
##               rudder (rad) or flap_deg (degrees, converted)
##   propellers  [{"pivot": name, "engine": unit index (0 = engine 1), "sign": +-1, "visual_rate": f}]
##               spins pivot_<name> about its +X by sign * rpm/60 * TAU * dt * visual_rate
## The glb frame is FlightGear's model frame (x aft, y right, z up) exported Y-up by glTF.

const DEFAULTS := {
	"surfaces": {
		"aileron_L": {"drive": "aileron", "sign": 1.0}, "aileron_R": {"drive": "aileron", "sign": -1.0},
		"elevator_L": {"drive": "elevator", "sign": -1.0}, "elevator_R": {"drive": "elevator", "sign": -1.0},
		"rudder": {"drive": "rudder", "sign": -1.0}, "flaps": {"drive": "flap_deg", "sign": 1.0},
	},
	"propellers": [{"pivot": "prop", "engine": 0, "sign": -1.0, "visual_rate": 0.13}],
}

var fdm_node: FdmNode
var def: AircraftDef
var cockpit: Cockpit
var _cg := Vector3.ZERO
var _model := {}  # "model" section over DEFAULTS
var _airframe: PlaceholderAirframe
var _pivots := {}  # glb mode: surface name -> [Node3D, base Basis]
var _props: Array = []  # glb mode: [Node3D, engine index, sign, visual rate]


func build(node: FdmNode) -> void:
	fdm_node = node
	def = node.fdm.def if node.fdm.def != null else AircraftDef.current()
	_model = def.section_or("model", DEFAULTS)
	_cg = node.fdm.mb.cg
	var glb := def.path("exterior")
	if ResourceLoader.exists(glb):
		_build_glb(glb)
	else:
		_airframe = PlaceholderAirframe.new()
		add_child(_airframe)
		_airframe.build(node.fdm, _s)
	AircraftLights.tag_exterior(self)  # exterior on its own render layer for its lights
	var e: Array = node.fdm.cfg.metrics.eyepoint_m
	cockpit = Cockpit.new()
	add_child(cockpit)
	cockpit.build(self, _s(Vector3(e[0], e[1], e[2])))
	var lights := AircraftLights.new()
	add_child(lights)
	lights.build(_s, def.section("lights"))
	ReflectionRig.attach(self)  # reflection probe: surroundings on the glass and paint (reflection_rig.gd)


func _build_glb(path: String) -> void:
	var inst: Node3D = (load(path) as PackedScene).instantiate()
	inst.transform = fg_transform()
	add_child(inst)
	for n in _model.surfaces:
		var pv := inst.find_child("pivot_" + n, true, false) as Node3D
		if pv:
			_pivots[n] = [pv, pv.transform.basis]
	for p in _model.propellers:
		var pv := inst.find_child("pivot_" + str(p.pivot), true, false) as Node3D
		if pv:
			_props.append([pv, int(p.get("engine", 0)), float(p.get("sign", -1.0)), float(p.get("visual_rate", 0.13))])
	fix_glass(inst, true)
	lift_tyres(inst)


## FlightGear glass uses an effect shader; make it a clear, slightly reflective pane.
## rain: draw rain drops / streaks on it (aircraft/common/windshield_rain.gdshader, outer skin only).
## Tyres are black rubber: against dark asphalt at night they vanish. A faint constant
## glow (a few percent, invisible in daylight) keeps them a readable dark grey, and the
## taxi / landing lights and the aircraft fill light do the rest.
static func lift_tyres(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(i)
			if mat is BaseMaterial3D and mat.resource_name == "wheel_mat":
				var d := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
				d.emission_enabled = true
				d.emission = Color(0.2, 0.2, 0.215)
				d.emission_energy_multiplier = 1.0
				d.roughness = 0.55
				m.set_surface_override_material(i, d)


static func fix_glass(root: Node, rain := false) -> void:
	var glass := ShaderMaterial.new()
	glass.shader = preload("res://aircraft/common/glass.gdshader")
	if rain:
		var drops := ShaderMaterial.new()
		drops.shader = preload("res://aircraft/common/windshield_rain.gdshader")
		glass.next_pass = drops
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		for i in m.get_surface_count():
			var mat := m.surface_get_material(i)
			if mat and mat.resource_name.to_lower().contains("glas"):
				(mi as MeshInstance3D).set_surface_override_material(i, glass)


## Structural position of the glb's origin (m): model.origin_m, else the config's visual reference point.
func _origin() -> Vector3:
	var v: Array = _model.get("origin_m", fdm_node.fdm.cfg.metrics.vrp_m)
	return Vector3(v[0], v[1], v[2])


## Transform placing a FlightGear-frame glb (origin = VRP) in this node.
func fg_transform() -> Transform3D:
	return Transform3D(Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)), _s(_origin()))


## FlightGear model-frame point (x aft, y right, z up, from VRP) -> local.
func fg_to_local(p: Vector3) -> Vector3:
	return _s(p + _origin())


## JSBSim structural point -> local render offset from the CG.
func _s(p: Vector3) -> Vector3:
	return Vector3(p.y - _cg.y, p.z - _cg.z, p.x - _cg.x)


func _process(dt: float) -> void:
	if fdm_node == null:
		return
	transform = fdm_node.render_transform()
	if _airframe:
		_airframe.animate(fdm_node.fdm, dt)
	else:
		_animate_glb(fdm_node.fdm, dt)


## Signs come from each hinge axis direction (see convert_c172p.py HINGES): +angle about the
## pivot's +X moves the trailing edge down (ailerons, flaps), up (elevators, axis runs
## outboard->inboard reversed), right (rudder); the aircraft's model.surfaces carries them.
func _animate_glb(f: FDM, dt: float) -> void:
	for k in _pivots:
		var s: Dictionary = _model.surfaces[k]
		var drive := str(s.drive)
		var v: float = deg_to_rad(f.fcs.flap_deg) if drive == "flap_deg" else float(f.fcs.get(drive))
		_pivots[k][0].transform.basis = _pivots[k][1] * Basis(Vector3.RIGHT, v * float(s.get("sign", 1.0)))
	for p in _props:
		if p[1] < f.units.size():
			(p[0] as Node3D).rotate_object_local(Vector3.RIGHT, p[2] * f.units[p[1]].thruster.rpm / 60.0 * TAU * dt * p[3])
