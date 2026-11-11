extends RefCounted
## The C172 ailerons in the glb move with the roll command and in opposite directions (aircraft.json model.surfaces,
## ModelDrives, AircraftModel._animate_glb).

func _rig(id: String) -> Array:
	var def := AircraftDef.load_def(id)
	var f := FDM.new(def)
	f.set_airborne(0.0, 0.0, 1000.0, 0.0, 50.0)
	var surf: Dictionary = def.section("model").surfaces
	var inst: Node3D = (load(def.path("exterior")) as PackedScene).instantiate()
	return [f, surf, inst]


func test_ailerons_follow_roll() -> String:
	for id in ["c172", "a320"]:
		var e := _check(id)
		if e != "":
			return "%s: %s" % [id, e]
	return ""


func _check(id: String) -> String:
	var r := _rig(id)
	var f: FDM = r[0]
	var surf: Dictionary = r[1]
	var inst: Node3D = r[2]
	f.fcs.roll = 1.0
	f.fcs.act_roll = 1.0
	for i in 120:  # a second: the A320's law and actuators need time and the FDM's sensed state
		f.step(1.0 / 120.0)
	var out := ""
	if absf(f.fcs.aileron) < 0.1:
		out = "fcs.aileron = %s after full right roll" % f.fcs.aileron
	var ang := {}
	for n in ["aileron_L", "aileron_R"]:
		if not surf.has(n) or inst.find_child("pivot_" + n, true, false) == null:
			out = "no %s surface or pivot" % n
		else:
			ang[n] = ModelDrives.angle(n, surf[n], f, {}) * float(surf[n].get("sign", 1.0))
	if out == "" and (absf(ang.aileron_L) < 0.1 or ang.aileron_L * ang.aileron_R > 0.0):
		out = "aileron angles %s should be opposite" % [ang]
	inst.free()
	return out


## The glb pivot of each aileron exists and turning it by the drive angle really moves the surface's mesh.
func test_aileron_meshes_move() -> String:
	for id in ["c172", "a320"]:
		var r := _rig(id)
		var inst: Node3D = r[2]
		for n in ["aileron_L", "aileron_R"]:
			var pv := inst.find_child("pivot_" + n, true, false) as Node3D
			if pv == null:
				inst.free()
				return "%s: no pivot_%s in the exterior glb" % [id, n]
			var mi := pv.find_children("*", "MeshInstance3D", true, false)
			if mi.is_empty():
				inst.free()
				return "%s: pivot_%s has no mesh under it" % [id, n]
			var m: MeshInstance3D = mi[0]
			var before := m.transform * m.get_aabb().get_center()
			var base := pv.transform.basis
			pv.transform.basis = base * Basis(Vector3.RIGHT, deg_to_rad(15.0))
			var after := pv.transform * (m.transform * m.get_aabb().get_center())
			var was := pv.transform.origin + base * (m.transform * m.get_aabb().get_center())
			if after.distance_to(was) < 0.005:
				inst.free()
				return "%s: %s mesh does not move when the pivot turns (hinge through its centre?)" % [id, n]
		inst.free()
	return ""
