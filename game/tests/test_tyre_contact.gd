extends Node
## Tyres stand on the ground (docs/TYRE-CONTACT-PLAN.md, G4 / G5): every aircraft (AircraftDef.list_ids(), and a
## placeholder airframe for one without a model) rests on its gear in the FDM; the exterior model's lowest tyre
## vertex at each wheel contact is within 2 cm of the ground (not sunk by the static spring compression, not
## floating), on flat ground and on a slope. Before: C172 nose tyre 3 cm up, mains 0.5 cm in; A320 mains 3 cm in.

const TOL := 0.02
const R := 0.8  # m around a contact's ground point: the tyre (A320 main bogie: two wheels +-0.45 m)

var _nodes: Array[Node] = []


func teardown() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()


## FDM of def resting on ground(n, e) at the origin, brakes on, settled.
func _rest(def: AircraftDef, ground: Callable) -> FDM:
	var f := FDM.new(def)
	f.ground_height = ground
	f.set_on_ground(0.0, 0.0, deg_to_rad(30.0))
	f.gear.brake_left = 1.0
	f.gear.brake_right = 1.0
	for i in 1200:
		f.step(1.0 / 120.0)
	return f


## {contact name: lowest (vertex height - ground under it), m} for the exterior meshes near each wheel contact.
func _clearances(def: AircraftDef, ground: Callable) -> Dictionary:
	var f := _rest(def, ground)
	var node := FdmNode.new()
	node.fdm = f
	_nodes.append(node)
	var m := AircraftModel.new()
	add_child(m)
	_nodes.append(m)
	m.build(node)
	node._snap()  # render_transform() = the FDM's pose
	m._process(0.0)
	var ext: Node3D = m._glb if m._glb else m._airframe
	var out := {}
	for c in f.gear.contacts:
		if not c.wheel:
			continue
		var p := Vector3(f.pos_n, f.pos_e, f.pos_d) + Basis(f.q) * f.mb.body_of(c.pos)  # NED
		var low := INF
		for mi in ext.find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).mesh == null or not (mi as MeshInstance3D).is_visible_in_tree():
				continue
			var xf: Transform3D = mi.global_transform
			for si in mi.mesh.get_surface_count():
				for v in mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
					var w := FloatingOrigin.to_world(xf * v)  # ENU
					if Vector2(w.x - p.y, w.y - p.x).length() < R:
						low = minf(low, w.z - float(ground.call(w.y, w.x)))
		out[c.name] = low
	return out


func _check(def: AircraftDef, ground: Callable, label: String) -> String:
	var cl := _clearances(def, ground)
	var line := PackedStringArray()
	for k in cl:
		line.append("%s %+.3f" % [k, cl[k]])
	print("    %s %s tyre bottom - ground: %s" % [def.id, label, ", ".join(line)])
	for k in cl:
		if not is_finite(cl[k]):
			return "%s %s: no model vertex near the %s contact" % [def.id, label, k]
		if cl[k] < -TOL:
			return "%s %s: %s tyre sinks %.3f m into the ground" % [def.id, label, k, -cl[k]]
		if cl[k] > TOL:
			return "%s %s: %s tyre floats %.3f m above the ground" % [def.id, label, k, cl[k]]
	return ""


func test_a320_oleo_slides_and_the_hinge_stays() -> String:
	var f := _rest(AircraftDef.load_def("a320"), func(_n: float, _e: float) -> float: return 0.0)
	var node := FdmNode.new()
	node.fdm = f
	_nodes.append(node)
	var m := AircraftModel.new()
	add_child(m)
	_nodes.append(m)
	m.build(node)
	node._snap()
	var ext: Node3D = m._glb
	var hinge := ext.find_child("pivot_gear_main_L", true, false) as Node3D
	var tube := ext.find_child("MLGSlidingTubeAxleL", true, false) as Node3D
	if hinge == null or tube == null:
		return "A320 gear pivot or sliding tube missing"
	var hinge0 := hinge.position
	var tube0 := tube.position
	m._process(0.0)
	var hinge_d := hinge.position.distance_to(hinge0)
	var tube_d := tube.position.distance_to(tube0)
	print("    oleo: hinge moved %.4f m, sliding tube %.3f m" % [hinge_d, tube_d])
	if hinge_d > 0.002:
		return "the retraction hinge moved %.3f m with the oleo" % hinge_d
	if tube_d < 0.05:
		return "the sliding tube did not compress (%.3f m)" % tube_d
	return ""


func test_every_aircraft_tyres_on_flat_ground() -> String:
	var err := ""
	for id in AircraftDef.list_ids():
		var e := _check(AircraftDef.load_def(id), func(_n: float, _e: float) -> float: return 0.0, "flat")
		err = e if err == "" else err
	return err


func test_every_aircraft_tyres_on_a_slope() -> String:
	var err := ""
	for id in AircraftDef.list_ids():
		var e := _check(AircraftDef.load_def(id), func(n: float, e: float) -> float: return 0.025 * e - 0.015 * n, "slope")
		err = e if err == "" else err
	return err


## An aircraft without an exterior model gets the placeholder airframe: its wheels follow the compression too.
func test_placeholder_tyres_on_ground() -> String:
	var src := AircraftDef.load_def("c172")
	var def := AircraftDef.make("placeholder", {"name": "placeholder", "files": {"exterior": "models/none.glb"}}, src.dir, src.config().duplicate(true))
	return _check(def, func(_n: float, _e: float) -> float: return 0.0, "flat")
