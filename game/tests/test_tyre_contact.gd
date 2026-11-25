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
	var link := ext.find_child("MLGTorqueLinkL1", true, false) as Node3D
	if link == null:
		return "A320 torque link missing"
	var hinge0 := hinge.position
	var tube0 := tube.position
	var link_basis := link.basis
	m._process(0.0)
	var hinge_d := hinge.position.distance_to(hinge0)
	var tube_d := tube.position.distance_to(tube0)
	var folded := link.basis.get_rotation_quaternion().angle_to(link_basis.get_rotation_quaternion())
	print("    oleo: hinge moved %.4f m, sliding tube %.3f m, torque link folded %.1f deg" % [hinge_d, tube_d, rad_to_deg(folded)])
	if hinge_d > 0.002:
		return "the retraction hinge moved %.3f m with the oleo" % hinge_d
	if tube_d < 0.05:
		return "the sliding tube did not compress (%.3f m)" % tube_d
	if folded < deg_to_rad(8.0):
		return "the torque link did not fold with the oleo (%.1f deg)" % rad_to_deg(folded)
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


## Bank-angle tests. {moving gear node name: its offset from the unraised pose (parent frame, m)} for an aircraft
## airborne (FDM compression 0) or resting on the ground (`rested`), rolled to roll_deg with the FDM's attitude.
func _offsets(def: AircraftDef, roll_deg: float, rested := false) -> Dictionary:
	var f: FDM
	if rested:
		f = _rest(def, func(_n: float, _e: float) -> float: return 0.0)
	else:
		f = FDM.new(def)
		f.set_airborne(0.0, 0.0, 600.0, 0.0, 80.0)
	var e := f.euler()
	f.q = FDM.euler_to_quat(deg_to_rad(roll_deg), e.y, e.z)
	var node := FdmNode.new()
	node.fdm = f
	var m := AircraftModel.new()
	add_child(m)
	m.build(node)
	node._snap()
	m._process(0.0)
	var out := {}
	for g in m._tyres._groups:
		for e2 in g[1]:
			out["%s/%s" % [g[0], (e2[0] as Node3D).name]] = (e2[0] as Node3D).position - (e2[1] as Vector3)
	m.free()  # one model alive at a time
	node.free()
	return out


## The user's report: banking hard with the gear out moved the wheels off the struts. The raise that keeps tyres on
## the ground was applied along the world's vertical, and measured as if the wheel were upright, so at 45 to 75 degrees
## of bank the bogie slid 0.3 to 0.8 m sideways in the air. In the air nothing may move with the attitude.
func test_gear_stays_put_in_the_air_when_banked() -> String:
	for id in AircraftDef.list_ids():
		var def := AircraftDef.load_def(id)
		var level := _offsets(def, 0.0)
		if level.is_empty():
			return "%s: no gear parts found" % id
		var worst := 0.0
		for r in [45.0, 75.0, 90.0, -60.0]:
			var o := _offsets(def, r)
			for k in level:
				var d: float = (o[k] - level[k]).length()
				worst = maxf(worst, d)
				if d > 0.005:
					return "%s: %s moved %.3f m at %d deg of bank (level %s, banked %s)" % [id, k, d, int(r), level[k], o[k]]
		print("    %s airborne, banked up to 90 deg: largest gear part move %.4f m, %d parts" % [id, worst, level.size()])
	return ""


## On the ground a few degrees of bank (a crosswind landing) may nudge the leg, but never by more than the one
## contact point per bogie can explain (a few cm), and always within the hard bound (SLACK_M).
func test_gear_on_the_ground_banked_a_little() -> String:
	for id in AircraftDef.list_ids():
		var def := AircraftDef.load_def(id)
		var level := _offsets(def, 0.0, true)
		for r in [3.0, 20.0]:
			var o := _offsets(def, r, true)
			var lim: float = 0.08 if absf(r) < 10.0 else 0.16
			for k in level:
				var d: float = (o[k] - level[k]).length()
				if d > lim:
					return "%s: %s moved %.3f m at %d deg of bank on the ground (limit %.2f)" % [id, k, d, int(r), lim]
	return ""


## The compression the legs are drawn with is the FDM's: zero for a wheel in the air, whatever the bank and the load.
func test_compression_is_zero_in_a_hard_banked_turn() -> String:
	var f := FDM.new(AircraftDef.load_def("a320"))
	f.set_airborne(0.0, 0.0, 600.0, 0.0, 80.0)
	f.q = FDM.euler_to_quat(deg_to_rad(75.0), 0.05, 0.0)
	f.w_b = Vector3(0.0, 0.3, 0.0)  # pulling about 2 g and more
	for i in 240:
		f.step(1.0 / 120.0)
		for k in f.gear.compression:
			if float(f.gear.compression[k]) != 0.0:
				return "%s compressed %.3f m in the air at tick %d" % [k, f.gear.compression[k], i]
	return ""
