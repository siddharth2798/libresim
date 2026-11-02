extends Node
## The A320 cockpit controls that move (aircraft/common/cockpit_levers.gd, aircraft.json cockpit.levers, the
## pivot_<name> nodes of models/interior.glb): map interpolation, drive expressions, smoothing, the pivots exist
## in the glb, the C172 has no levers.

func _levers() -> Dictionary:
	return AircraftDef.load_def("a320").section("cockpit").get("levers", {})


func _interior() -> Node:
	return (load("res://aircraft/a320/models/interior.glb") as PackedScene).instantiate()


func _item(spec: Dictionary, node: Node3D = null) -> Dictionary:
	var c := CockpitLevers.new()
	var holder := Node3D.new()
	var pv := node if node != null else Node3D.new()
	pv.name = "pivot_t"
	holder.add_child(pv)
	c.build(holder, {"t": spec})
	var it: Dictionary = c._items[0]
	holder.remove_child(pv)  # the pivot outlives the helper: the caller frees it.node
	c.free()
	holder.free()
	return it


func _target(spec: Dictionary) -> float:
	var it := _item(spec)
	var a := CockpitLevers.target(it)
	(it.node as Node).free()
	return a


func test_levers_map_interpolates_and_clamps() -> String:
	var rows := [[-1.0, -23.0], [0.0, 0.0], [0.5, 22.5], [1.0, 45.0]]
	for p in [[-2.0, -23.0], [-0.5, -11.5], [0.0, 0.0], [0.25, 11.25], [0.5, 22.5], [0.75, 33.75], [1.0, 45.0], [3.0, 45.0]]:
		if absf(ModelDrives.table(rows, p[0]) - p[1]) > 1e-4:
			return "map(%s) = %s, want %s" % [p[0], ModelDrives.table(rows, p[0]), p[1]]
	return ""


func test_levers_drive_expression_and_bools() -> String:
	var t := CockpitLevers.parse_drive("controls/throttle_1 - controls/reverse_1")
	if t != [[1.0, "controls/throttle_1"], [-1.0, "controls/reverse_1"]] or CockpitLevers.parse_drive("a + b").size() != 2:
		return "parse_drive: %s" % [t]
	Props.set_v("controls/throttle_1", 0.8)
	Props.set_v("controls/reverse_1", 0.0)
	var fwd := CockpitLevers.read_drive(t)
	Props.set_v("controls/throttle_1", 0.0)
	Props.set_v("controls/reverse_1", 0.6)
	var rev := CockpitLevers.read_drive(t)
	Props.set_v("controls/engine_master_1", true)
	var b := CockpitLevers.read_drive(CockpitLevers.parse_drive("controls/engine_master_1"))
	Props.set_v("controls/reverse_1", 0.0)
	return "" if absf(fwd - 0.8) < 1e-6 and absf(rev + 0.6) < 1e-6 and b == 1.0 else "fwd %s rev %s bool %s" % [fwd, rev, b]


func test_levers_thrust_lever_detent_angles() -> String:
	var spec: Dictionary = _levers().get("thr_l", {})
	if spec.is_empty():
		return "no thr_l"
	var want := {0.0: 0.0, 0.556: 25.0, 0.778: 35.0, 1.0: 45.0}  # TLA: CL 25, FLX/MCT 35, TOGA 45
	for pos in want:
		Props.set_v("controls/throttle_1", pos)
		Props.set_v("controls/reverse_1", 0.0)
		var a := _target(spec)
		if absf(a - want[pos]) > 0.3:
			return "throttle %s -> %.2f deg, want %s" % [pos, a, want[pos]]
	Props.set_v("controls/throttle_1", 0.0)
	Props.set_v("controls/reverse_1", 1.0)  # reverse max: lever position -1
	var r := _target(spec)
	Props.set_v("controls/reverse_1", 0.0)
	return "" if r < -20.0 and r > -30.0 else "reverse max %.1f deg" % r


func test_levers_pivots_exist_in_interior_glb() -> String:
	var lv := _levers()
	if lv.size() < 30:
		return "only %d levers in aircraft.json" % lv.size()
	var glb := _interior()
	var err := _check_pivots(glb, lv)
	glb.free()
	return err


func _check_pivots(glb: Node, lv: Dictionary) -> String:
	for k in lv:
		if glb.find_child("pivot_" + k, true, false) == null:
			return "pivot_%s is not in interior.glb" % k
		var s: Dictionary = lv[k]
		if not s.get("map") is Array or s.map.size() < 2 or str(s.get("drive", "")) == "":
			return "%s: drive / map" % k
		for i in range(1, s.map.size()):
			if s.map[i][0] <= s.map[i - 1][0]:
				return "%s: map not ascending" % k
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://aircraft/a320/models/interior_pivots.json"))
	for k in info.pivots:  # the record of the converter agrees with the glb
		if glb.find_child("pivot_" + k, true, false) == null:
			return "interior_pivots.json lists %s, glb has no such pivot" % k
	return ""


func test_levers_build_counts_and_applies() -> String:
	var glb := _interior()
	var c := CockpitLevers.new()
	var n := c.build(glb, _levers())
	var it: Dictionary = c._items[0]
	var node: Node3D = it.node
	var before := node.transform.basis
	CockpitLevers.apply(it, 30.0)
	var turned := (before.inverse() * node.transform.basis).get_euler()
	CockpitLevers.apply(it, 0.0)
	var back := node.transform.basis.is_equal_approx(before)
	c.free()
	glb.free()
	return "" if n == _levers().size() and absf(absf(turned.x) - deg_to_rad(30.0)) < 1e-4 and back else "built %d, turned %s, back %s" % [n, turned, back]


func test_levers_translate_moves_along_axis() -> String:
	var pv := Node3D.new()
	pv.transform = Transform3D(Basis(Vector3.UP, 0.5), Vector3(1, 2, 3))
	var it := _item({"drive": "x", "map": [[0, 0], [1, 0.1]], "move": "translate"}, pv)
	CockpitLevers.apply(it, 0.1)
	var moved: Vector3 = pv.position - Vector3(1, 2, 3)
	var ok := absf(moved.length() - 0.1) < 1e-5 and moved.normalized().is_equal_approx(Basis(Vector3.UP, 0.5).x)
	pv.free()
	return "" if ok else "moved %s" % [moved]


func test_levers_smoothing_lag_and_rate() -> String:
	if not is_nan(CockpitLevers.step(NAN, 5.0, 0.1, 10.0, 0.01)) and CockpitLevers.step(NAN, 5.0, 0.1, 10.0, 0.01) != 5.0:
		return "no snap"
	var lag := CockpitLevers.step(0.0, 10.0, 0.1, 0.0, 0.1)
	var rate := CockpitLevers.step(0.0, 100.0, 0.0, 50.0, 0.1)
	var down := CockpitLevers.step(0.0, -100.0, 0.0, 50.0, 0.1)
	var inst := CockpitLevers.step(2.0, 7.0, 0.0, 0.0, 0.1)
	return "" if absf(lag - 6.321) < 0.01 and absf(rate - 5.0) < 1e-6 and absf(down + 5.0) < 1e-6 and inst == 7.0 else "%s %s %s %s" % [lag, rate, down, inst]


func test_levers_only_move_in_the_cockpit_view() -> String:
	var pv := Node3D.new()
	var c := CockpitLevers.new()
	var holder := Node3D.new()
	pv.name = "pivot_t"
	holder.add_child(pv)
	c.build(holder, {"t": {"drive": "t/x", "map": [[0, 0], [1, 90]]}})
	Props.set_v("t/x", 1.0)
	var was = Props.get_v("view/mode")
	Props.set_v("view/mode", "Chase")
	c._process(0.1)
	var outside := pv.transform.basis.is_equal_approx(Basis())
	Props.set_v("view/mode", "Cockpit")
	c._process(0.1)  # first frame in the cockpit: snaps to the pose
	var inside := absf(pv.transform.basis.get_euler().x - deg_to_rad(90.0)) < 1e-4
	Props.set_v("view/mode", was if was != null else "Chase")
	c.free()
	holder.free()
	return "" if outside and inside else "outside %s inside %s" % [outside, inside]


func test_levers_c172_has_none() -> String:
	var d := AircraftDef.load_def("c172")
	if d.section("cockpit").has("levers"):
		return "c172 gained levers"
	var c := CockpitLevers.new()
	var empty := Node3D.new()
	var n := c.build(empty, d.section("cockpit").get("levers", {}))
	c.free()
	empty.free()
	return "" if n == 0 else "built %d" % n
