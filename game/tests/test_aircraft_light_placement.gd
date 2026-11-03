extends Node
## Exterior-light data of every aircraft (AircraftDef.list_ids(), aircraft.json "lights", aircraft_lights.gd): each
## light lies on its exterior model (within a few cm of the glb's bounds), position lights follow the red-left /
## green-right / white-tail rule, switches and pivots exist, and a light on a moving part follows that part and goes
## out with the gear up.

const KINDS := ["nav", "beacon", "strobe", "lamps"]
const TOL_M := 0.05


## Structural position of the glb origin (AircraftModel._origin): model.origin_m, else config metrics.vrp_m.
func _origin(def: AircraftDef) -> Vector3:
	var v: Array = def.section("model").get("origin_m", def.config().get("metrics", {}).get("vrp_m", [0, 0, 0]))
	return Vector3(v[0], v[1], v[2])


## Bounds of the exterior glb in its own frame (glTF Y-up: X = x aft, Y = z up, Z = -y right).
func _glb_bounds(path: String) -> AABB:
	var root: Node3D = (load(path) as PackedScene).instantiate()
	var box := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var t := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != root:
			t = (n as Node3D).transform * t
			n = n.get_parent()
		var b: AABB = t * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	root.free()
	return box


func _lights(def: AircraftDef) -> Array:
	var out := []
	var sec := def.section("lights")
	for k in KINDS:
		for d in sec.get(k, []):
			out.append([k, d])
	return out


func test_lights_lie_on_every_exterior_model() -> String:
	var checked := 0
	for id in AircraftDef.list_ids():
		var def := AircraftDef.load_def(id)
		if not ResourceLoader.exists(def.path("exterior")):
			continue
		var box := _glb_bounds(def.path("exterior")).grow(TOL_M)
		var o := _origin(def)
		for e in _lights(def):
			var p: Array = e[1].pos
			var q := Vector3(p[0], p[1], p[2]) - o
			if not box.has_point(Vector3(q.x, q.z, -q.y)):
				return "%s %s light at %s is off the model (bounds %s, glb frame)" % [id, e[0], p, box]
			checked += 1
	return "" if checked >= 10 else "only %d lights checked" % checked


func test_nav_lights_red_left_green_right_white_tail() -> String:
	for id in AircraftDef.list_ids():
		var def := AircraftDef.load_def(id)
		var sides := {"left": 0, "right": 0, "tail": 0}
		var max_tip_x := -INF
		var tail_x := INF
		for d in def.section("lights").get("nav", []):
			var side := str(d.get("side", "tail"))
			var c := str(d.get("color", "white"))
			var y := float(d.pos[1])
			if side == "left" and (c != "red" or y >= 0.0):
				return "%s: the left nav light must be red on the left (y < 0): %s" % [id, d]
			if side == "right" and (c != "green" or y <= 0.0):
				return "%s: the right nav light must be green on the right (y > 0): %s" % [id, d]
			if side == "tail" and (c != "white" or absf(y) > 0.5):
				return "%s: the tail nav light must be white on the centreline: %s" % [id, d]
			sides[side] = sides.get(side, 0) + 1
			if side == "tail":
				tail_x = minf(tail_x, float(d.pos[0]))
			else:
				max_tip_x = maxf(max_tip_x, float(d.pos[0]))
		if sides.left != 1 or sides.right != 1 or sides.tail < 1:
			return "%s: needs one red, one green and a white tail nav light, got %s" % [id, sides]
		if tail_x <= max_tip_x + 2.0:
			return "%s: the white nav light must be well aft of the wingtips" % id
		for d in def.section("lights").get("strobe", []):
			if not str(d.get("color", "strobe")) in ["strobe", "white"]:
				return "%s: strobes are white: %s" % [id, d]
		var bcn: Array = def.section("lights").get("beacon", [])
		if bcn.is_empty():
			return "%s: no anti-collision beacon" % id
		for d in bcn:
			if str(d.get("color", "red")) != "red" or absf(float(d.pos[1])) > 0.2:
				return "%s: beacons are red on the centreline: %s" % [id, d]
	return ""


func test_light_switches_and_parents_exist() -> String:
	for id in AircraftDef.list_ids():
		var def := AircraftDef.load_def(id)
		var glb: Node = null
		if ResourceLoader.exists(def.path("exterior")):
			glb = (load(def.path("exterior")) as PackedScene).instantiate()
		var err := ""
		for e in _lights(def):
			var sw = e[1].get("switch", "landing" if e[0] == "lamps" else e[0])
			for s in (sw if sw is Array else [sw]):
				if not str(s) in AirlinerLights.NAMES:
					err = "%s: unknown light switch '%s'" % [id, s]
			var par := str(e[1].get("parent", ""))
			if par != "" and (glb == null or glb.find_child("pivot_" + par, true, false) == null):
				err = "%s: light parent pivot_%s is not in the model" % [id, par]
		if glb != null:
			glb.free()
		if err != "":
			return err
	return ""


## A lamp on a gear leg: follows the leg's pivot, and is dark while the gear is up.
func test_gear_lamp_follows_its_pivot_and_goes_out_gear_up() -> String:
	var model := Node3D.new()
	add_child(model)
	var glb := Node3D.new()
	model.add_child(glb)
	var pv := Node3D.new()
	pv.name = "pivot_gear_nose"
	pv.position = Vector3(0.0, -1.0, -5.0)
	glb.add_child(pv)
	var lights := AircraftLights.new()
	model.add_child(lights)
	var s := func(p: Vector3) -> Vector3: return Vector3(p.y, p.z, p.x)
	lights.build(s, {"lamps": [{"switch": "taxi", "parent": "gear_nose", "gear": true, "pos": [-5.2, 0.0, -2.0], "beam": 0}]}, glb)
	var keep := {}
	for k in ["controls/lights/taxi", "fdm/gear_pos", "systems/electrical/powered"]:
		keep[k] = Props.get_v(k, null)
	Props.set_v("controls/lights/taxi", true)
	Props.set_v("systems/electrical/powered", true)
	Props.set_v("fdm/gear_pos", 1.0)
	var err := ""
	lights._process(0.01)
	var spot: SpotLight3D = lights.find_children("*", "SpotLight3D", true, false)[0]
	var p0 := spot.global_position
	if not spot.visible:
		err = "taxi lamp should be lit with the gear down"
	pv.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2), pv.position)  # retract: leg swings up
	Props.set_v("fdm/gear_pos", 0.0)
	lights._process(0.01)
	var p1 := spot.global_position
	var want := pv.transform * Vector3(0.0, -1.0, -0.2)  # the lamp's offset from the pivot, rotated with it
	if err == "" and not p1.is_equal_approx(want):
		err = "lamp did not follow the pivot: %s -> %s, want %s" % [p0, p1, want]
	if err == "" and spot.visible:
		err = "taxi lamp should be out with the gear up"
	for k in keep:
		if keep[k] == null:
			Props._p.erase(k)
		else:
			Props.set_v(k, keep[k])
	remove_child(model)
	model.free()
	return err
