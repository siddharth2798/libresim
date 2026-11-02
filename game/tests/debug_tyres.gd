extends Node
## Debug: where do the tyres of the parked aircraft stand? Prints each wheel (glb nodes, structural metres)
## against the FDM gear contacts, the compression and the terrain under each wheel, then saves side / front /
## rear / gear close-up PNGs to --shots=<dir>.
##   godot --path game res://tests/debug_tyres.tscn --audio-driver Dummy -- --aircraft=a320 --airport=VABB --stand --shots=<dir>
var t := 0.0
var f: Node
var _shots := ""
var _phase := 0
var _at := 5.0  # --at=<s>: when to report and shoot
var _nolegs := false  # --nolegs: skip the compression raise of the leg pivots (the "before" state)
var _views := [
	["side", Vector3(-3, 26, 1.0), Vector3(-1.5, 0, -3.0)],
	["front", Vector3(-30, 0, 0.0), Vector3(-13.65, 0, -3.0)],
	["rear", Vector3(25, 0, 0.0), Vector3(-1.5, 0, -3.0)],
	["gear_front34", Vector3(-19, -9, -1.0), Vector3(-1.1, -4.3, -3.6)],
	["door_left", Vector3(-24, -16, 1.0), Vector3(-12, -2.5, 0.5)],
	["nose_close", Vector3(-17.5, -4.0, -2.5), Vector3(-13.65, 0, -3.8)],
]


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots = a.substr(8)
		elif a.begins_with("--at="):
			_at = float(a.substr(5))
		elif a == "--nolegs":
			_nolegs = true
	DirAccess.make_dir_recursive_absolute(_shots)
	f = load("res://world/flight.tscn").instantiate()
	add_child(f)


func _report() -> void:
	var fn: FdmNode = f.get_node("Fdm")
	var m: AircraftModel = f.get_node("Aircraft")
	var fdm: FDM = fn.fdm
	var cg: Vector3 = fdm.mb.cg
	var terrain: TerrainQuadtree = f.get_node("Terrain")
	print("CG struct ", cg, " model.origin ", m._origin(), " pos_enu ", fn.position_enu(), " agl ", fdm.agl, " pitch deg ", rad_to_deg(Basis(fdm.q).get_euler().x))
	print("gear_pos ", fdm.gear.gear_pos, " wow ", fdm.gear.wow, " v_b ", fdm.v_b)
	print("SPEED ned ", fdm.velocity_ned(), " wheels ", m._wheels, " parking brake ", Props.get_v("controls/parking_brake"), " brakes ", fdm.gear.brake_left, fdm.gear.brake_right, " pos ", fn.position_enu())
	var basis_ned := Basis(fdm.q)
	for c in fdm.gear.contacts:
		var rb: Vector3 = fdm.mb.body_of(c.pos)
		var p: Vector3 = Vector3(fdm.pos_n, fdm.pos_e, fdm.pos_d) + basis_ned * rb
		var gh: float = terrain.height_at(p.y, p.x)
		print("CONTACT %-9s pos %s compression %.3f  contact up %.3f  fdm ground %.3f terrain %.3f" % [c.name, c.pos, fdm.gear.compression.get(c.name, 0.0), -p.z, fdm.ground_height.call(p.x, p.y), gh])
	var inst: Node3D = m.get_child(0)
	for w in ["MLGWheelsL", "MLGWheelsR", "NLGWheels"]:
		var mi := inst.find_child(w, true, false) as MeshInstance3D
		var low := INF
		var cen := Vector3.ZERO
		var cnt := 0.0
		for si in mi.mesh.get_surface_count():  # real vertices: a spinning wheel's AABB corners overshoot the tyre
			for v in mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]:
				var wp := FloatingOrigin.to_world(mi.global_transform * v)
				low = minf(low, wp.z)
				cen += wp
				cnt += 1.0
		cen /= cnt
		print("TYRE %-10s bottom up %.3f  terrain under %.3f  gap %+.3f m (negative = sunk in the ground)" % [w, low, terrain.height_at(cen.x, cen.y), low - terrain.height_at(cen.x, cen.y)])
	for n in inst.find_children("*", "Node3D", true, false):
		var nm := String(n.name).to_lower()
		if nm.contains("wheel") or nm.contains("gear") or nm.contains("bogie") or nm.contains("tyre") or nm.contains("tire"):
			var s := _struct(m, cg, n.global_position)
			var line := "NODE %-24s struct %.3f %.3f %.3f" % [n.name, s.x, s.y, s.z]
			if n is MeshInstance3D:
				var bb: AABB = (n as MeshInstance3D).get_aabb()
				var lo := INF
				var hi := -INF
				for i in 8:
					var gp: Vector3 = n.global_transform * bb.get_endpoint(i)
					var sp := _struct(m, cg, gp)
					lo = minf(lo, sp.z)
					hi = maxf(hi, sp.z)
				var mn := Vector3(INF, INF, INF)
				var mx := -mn
				for i in 8:
					var sp := _struct(m, cg, n.global_transform * bb.get_endpoint(i))
					mn = mn.min(sp)
					mx = mx.max(sp)
				line += "  mesh x %.2f..%.2f y %.2f..%.2f z %.3f..%.3f" % [mn.x, mx.x, mn.y, mx.y, mn.z, mx.z]
			print(line)
	for n in inst.find_children("pivot_*", "Node3D", true, false):
		if String(n.name).contains("gear") or String(n.name).contains("wheel") or String(n.name).contains("steer"):
			print("PIVOT %-22s parent %-22s local %s" % [n.name, n.get_parent().name, n.position])
	print("LEGS ", m._legs.map(func(l): return [l[0].name, l[2], l[3], l[0].position]))


func _struct(m: Node3D, cg: Vector3, gp: Vector3) -> Vector3:
	var l := m.to_local(gp)
	return Vector3(l.z + cg.x, l.x + cg.y, l.y + cg.z)


func _process(dt: float) -> void:
	t += dt
	var cam: CameraRig = f.get_node("Camera")
	if _nolegs and t > 0.1:
		var am: AircraftModel = f.get_node("Aircraft")
		for l in am._legs:
			l[0].position = l[1]
		am._legs.clear()
	if t > _at and _phase == 0:
		_phase = 1
		_report()
		cam.set_mode(CameraRig.Mode.FREE)
		t = _at - 5.0
	if _phase >= 1 and _phase <= _views.size() and t > 6.0 + _phase * 1.5:
		# place free cam: structural offset from the aircraft, rotated by heading
		var v = _views[_phase - 1]
		_place(cam, v[1], v[2])
		_phase = -_phase
	elif _phase < 0 and t > 6.0 + (-_phase) * 1.5 + 0.8:
		var i := -_phase
		get_viewport().get_texture().get_image().save_png(_shots.path_join(_views[i - 1][0] + ".png"))
		print("SHOT ", _views[i - 1][0])
		_phase = i + 1
		if _phase > _views.size():
			get_tree().quit()


func _place(cam: CameraRig, eye: Vector3, target: Vector3) -> void:
	var m: AircraftModel = f.get_node("Aircraft")
	var cg: Vector3 = f.get_node("Fdm").fdm.mb.cg
	var ge: Vector3 = m.global_transform * m._s(eye + Vector3.ZERO)
	var gt: Vector3 = m.global_transform * m._s(target)
	# eye is given as structural (x aft, y right, z up) but relative to the model origin
	var enu_e := FloatingOrigin.to_world(ge)
	var enu_t := FloatingOrigin.to_world(gt)
	cam._free_enu = enu_e
	var d := enu_t - enu_e
	cam._look = Vector2(-atan2(d.x, d.y), atan2(d.z, Vector2(d.x, d.y).length()))
