class_name AirportOps
extends Node3D
## Airport ground infrastructure from data/processed/airport_ops.json (tools/13):
## stands (gates with jetbridges / remote / GA), the taxiway graph with A* routing,
## and 3D dressing near the aircraft: jetbridges, stand lead-in lines + numbers,
## windsocks that point downwind. Everything is built lazily per airport.

const BUILD_RADIUS := 6000.0

var data: Dictionary = {}
var terrain: TerrainQuadtree
var _built := {}  # icao -> Node3D
var _socks: Array = []  # [MeshInstance3D cone pivot]
var _yellow := StandardMaterial3D.new()
var _bridge_mat := StandardMaterial3D.new()
var _timer := 0.0
const VEH := "res://world/models/vehicles/%s.glb"
const FG_YAW := -PI / 2  # FlightGear vehicle models face -X; ours face -Z
var _scenes := {}
var _solids := {}  # icao -> OpsSolids (collision of the dressing, see ops_solids.gd)
var _cur: OpsSolids  # the airport being built
var _corridors := {}  # icao -> true: OpsCorridors registered


func setup(t: TerrainQuadtree) -> void:
	terrain = t
	var d = Paths.load_json("airport_ops.json")
	data = d if d else {}
	_register_corridors()
	_yellow.albedo_color = Color(0.95, 0.78, 0.15)
	_yellow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bridge_mat.albedo_color = Color(0.72, 0.74, 0.76)
	_bridge_mat.roughness = 0.5
	_bridge_mat.metallic = 0.3
	FloatingOrigin.shifted.connect(func(d2: Vector3):
		for k in _built:
			_built[k].position += d2)


## Stand lookup: by ref ("Bay 40", "GA3"), or "" -> the aircraft's default stand (GroundChoice.default_stand:
## for stand_class "any" the first gate with a jetbridge, else the first stand; airliners: a gate; GA: a tie-down).
func find_stand(icao: String, ref: String, stand_class := "") -> Dictionary:
	var a: Dictionary = data.get(icao, {})
	var stands: Array = a.get("stands", [])
	if stands.is_empty():
		return {}
	if ref != "":
		for s in stands:
			if str(s.ref).to_lower().replace(" ", "") == ref.to_lower().replace(" ", ""):
				return s
	return GroundChoice.default_stand(stands, stand_class if stand_class != "" else str(GroundParams.ground().stand_class))


func _h(x: float, y: float) -> float:
	return terrain.height_at(x, y) if terrain else 0.0


func _process(dt: float) -> void:
	GroundVehicles.tick(dt)
	_timer -= dt
	if _timer <= 0.0:
		_timer = 1.0
		var cam := get_viewport().get_camera_3d()
		if cam:
			var w := FloatingOrigin.to_world(cam.global_position)
			for icao in data:
				var a: Dictionary = data[icao]
				if a.stands.is_empty() and a.taxi.nodes.is_empty():
					continue
				var s0: Dictionary = a.stands[0] if not a.stands.is_empty() else {"x": a.taxi.nodes.values()[0][0], "y": a.taxi.nodes.values()[0][1]}
				var near := Vector2(w.x, w.y).distance_to(Vector2(s0.x, s0.y)) < BUILD_RADIUS
				if near and not _built.has(icao):
					_build(icao)
				elif not near and _built.has(icao):
					_built[icao].queue_free()
					_built.erase(icao)
					_solids[icao].clear()
					_solids.erase(icao)
	# windsocks point downwind and stiffen with wind speed
	var wind: Vector3 = Props.get_v("environment/wind_ned", Vector3.ZERO)
	var wh := Vector2(wind.y, -wind.x)  # render frame: x east, z south (air moving toward)
	for s in _socks:
		if is_instance_valid(s) and wh.length() > 0.3:
			s.rotation.y = atan2(-wh.x, -wh.y)
			s.rotation.z = 0.0
			s.rotation.x = -clampf(wh.length() / 8.0, 0.1, 1.0) * PI * 0.45


func _build(icao: String) -> void:
	var a: Dictionary = data[icao]
	var root := Node3D.new()
	root.name = "ops_" + icao
	add_child(root)
	_built[icao] = root
	_cur = OpsSolids.new("ops:" + icao)
	_solids[icao] = _cur
	root.position = FloatingOrigin.to_render(Vector3.ZERO)
	var i := 0
	for s in a.stands:
		_stand_marking(root, s)
		_service_vehicles(root, s, i)
		i += 1
	for jb in a.jetbridges:
		_jetbridge(root, jb.pts, a.stands)
	for ws in a.windsocks:
		_windsock(root, ws.x, ws.y)
	for tw in a.towers.slice(0, 1):
		_place(root, "fire_truck", Vector2(tw.x + 40.0, tw.y + 25.0), 0.0, FG_YAW)


func _exit_tree() -> void:
	GroundVehicles.release()
	for icao in _solids:
		_solids[icao].clear()
	for icao in _corridors:
		OpsCorridors.unregister(icao)


## Stands, taxiways and runways of every airport are corridors from the start (not only once built).
func _register_corridors() -> void:
	var ab := get_node_or_null("../Airports") as AirportBuilder
	var rws := {}
	if ab and ab.data:
		for r in ab.data.runways:
			if not rws.has(r.airport):
				rws[r.airport] = []
			rws[r.airport].append(r)
	for icao in data.keys() + rws.keys():
		if not _corridors.has(icao):
			OpsCorridors.register(icao, data.get(icao, {}), rws.get(icao, []))
			_corridors[icao] = true


func _scene(name: String) -> PackedScene:
	if not _scenes.has(name):
		_scenes[name] = load(VEH % name)
	return _scenes[name]


## Place a vehicle model at world (east, north) facing heading (rad, compass), with a model yaw offset.
func _place(root: Node3D, name: String, p: Vector2, heading: float, yaw_off := 0.0) -> Node3D:
	var ours := GroundVehicles.has(name)  # built in code (world/ground_vehicles.gd), faces -Z
	var n: Node3D = GroundVehicles.make(name) if ours else _scene(name).instantiate()
	n.position = _local(p.x, p.y, 0.0)
	n.rotation.y = -heading + (0.0 if ours else yaw_off)
	root.add_child(n)
	if not _cur.add_model(name, n, _h(p.x, p.y)):  # it would sit in a C172 stand's way: leave it out
		n.queue_free()
		return null
	return n


## Legacy service-vehicle offsets [forward, right] from the stand point (made for the C172's stands).
const SERVICE := {"gpu": [1.0, -5.0], "baggage": [-12.0, 9.0], "fuel_gate": [-3.0, -14.0], "fuel_ramp": [-2.0, -12.0], "bus": [0.0, 16.0]}


## Ground-service vehicles around a stand (stand heading = aircraft nose direction). An aircraft with a
## ground.service block (keys gpu, baggage, fuel, bus; [forward, right] from the L1 door) gets them there
## (GroundParams.door_point), so they sit clear of its larger footprint; otherwise the legacy offsets
## from the stand point.
func _service_vehicles(root: Node3D, s: Dictionary, i: int) -> void:
	var hd := deg_to_rad(float(s.heading_deg))
	var fwd := Vector2(sin(hd), cos(hd))
	var right := Vector2(fwd.y, -fwd.x)
	var own: Dictionary = GroundParams.ground().get("service", {})
	var c := GroundParams.door_point(s) if not own.is_empty() else Vector2(s.x, s.y)
	var at := func(key: String, legacy: String) -> Vector2:
		var o: Array = own.get(key, SERVICE[legacy])
		return c + fwd * float(o[0]) + right * float(o[1])
	if s.jetbridge:
		_place(root, "gpu", at.call("gpu", "gpu"), hd)
		var bag: Vector2 = at.call("baggage", "baggage")
		_place(root, "baggage_tug", bag, hd + PI / 2)
		_place(root, "baggage_cart", bag + right * 4.0, hd + PI / 2)
		_place(root, "baggage_cart", bag + right * 8.0, hd + PI / 2)
		if i % 3 == 0:
			_place(root, "fuel_truck", at.call("fuel", "fuel_gate"), hd)
	elif i % 6 == 0:
		_place(root, "fuel_truck", at.call("fuel", "fuel_ramp"), hd)
	elif i % 9 == 4 and str(s.ref).begins_with("GA") == false:
		_place(root, "apron_bus", at.call("bus", "bus"), hd, FG_YAW)


func _local(x: float, y: float, up: float) -> Vector3:
	return Vector3(x, _h(x, y) + up, -y)


## Lead-in line, stop bar and number of a stand, sized by the aircraft: the line is at least 28 m, else 1.5
## x its length; the bar is at the nose wheel (ground.nose_gear_m ahead of the CG, 0 for the C172).
func _stand_marking(root: Node3D, s: Dictionary) -> void:
	var hd := deg_to_rad(float(s.heading_deg))
	var fwd := Vector2(sin(hd), cos(hd))
	var g := GroundParams.ground()
	var lead_len := maxf(28.0, 1.5 * (float(g.ahead_m) + float(g.behind_m)))
	var bar := GroundParams.cg_at_stand(s) + fwd * float(g.nose_gear_m)
	var lead := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(0.25, 0.02, lead_len)
	lead.mesh = m
	lead.material_override = _yellow
	var c := bar - fwd * lead_len * 0.5
	lead.position = _local(c.x, c.y, 0.18)
	lead.rotation.y = -hd + PI
	root.add_child(lead)
	var stop := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(maxf(3.0, 0.3 * float(g.across_m)), 0.02, 0.3)
	stop.mesh = sm
	stop.material_override = _yellow
	stop.position = _local(bar.x, bar.y, 0.18)
	stop.rotation.y = -hd
	root.add_child(stop)
	var lbl := Label3D.new()
	lbl.text = str(s.ref)
	lbl.font_size = 64
	lbl.pixel_size = 0.02
	lbl.modulate = Color(0.95, 0.78, 0.15)
	lbl.rotation = Vector3(-PI / 2, -hd, 0)
	var p := bar - fwd * maxf(6.0, 0.2 * lead_len)
	lbl.position = _local(p.x, p.y, 0.2)
	root.add_child(lbl)


## FlightGear generic jetway (rotunda at the origin, tunnel along +X to the cab) laid
## along the OSM jet_bridge way, rotunda at the end farther from the nearest stand.
func _jetbridge(root: Node3D, pts: Array, stands: Array) -> void:
	var a := Vector2(pts[0][0], pts[0][1])
	var b := Vector2(pts[-1][0], pts[-1][1])
	var near_a := INF
	var near_b := INF
	for st in stands:
		near_a = minf(near_a, a.distance_to(Vector2(st.x, st.y)))
		near_b = minf(near_b, b.distance_to(Vector2(st.x, st.y)))
	var terminal := a if near_a > near_b else b
	var cab := b if terminal == a else a
	var d := cab - terminal
	var n: Node3D = _scene("jetway").instantiate()
	n.position = _local(terminal.x, terminal.y, 0.0)
	n.rotation.y = atan2(d.y, d.x)  # model +X along terminal -> cab (render: x east, -z north)
	var len := d.length()
	n.scale = Vector3(clampf(len / 22.0, 0.6, 1.8), 1.0, 1.0)
	root.add_child(n)
	_cur.add_jetway(n, _h(terminal.x, terminal.y))


func _windsock(root: Node3D, x: float, y: float) -> void:
	OpsSolids.add_pole(_cur.group, Vector2(x, y), 0.5, 6.0, _h(x, y), "a windsock")
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.06
	pm.bottom_radius = 0.08
	pm.height = 6.0
	pole.mesh = pm
	pole.material_override = _bridge_mat
	pole.position = _local(x, y, 3.0)
	root.add_child(pole)
	var pivot := Node3D.new()
	pivot.position = _local(x, y, 6.0)
	root.add_child(pivot)
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.45
	cm.bottom_radius = 0.15
	cm.height = 3.6
	cone.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.45, 0.1)
	cone.material_override = mat
	cone.position = Vector3(0, -1.8, 0)  # hangs from the pivot; pivot tilts it out
	pivot.add_child(cone)
	_socks.append(pivot)


## A* over the airport taxi graph. Returns [[x, y], ...] from the node nearest `from`
## to the node nearest `to`, plus the taxiway refs used, or {} if no route.
func route(icao: String, from: Vector2, to: Vector2) -> Dictionary:
	var g: Dictionary = data.get(icao, {}).get("taxi", {})
	if g.is_empty():
		return {}
	var adj := {}
	for e in g.edges:
		if e[4] == "runway":
			continue  # don't taxi along runways unless unavoidable
		for pair in [[e[0], e[1]], [e[1], e[0]]]:
			if not adj.has(pair[0]):
				adj[pair[0]] = []
			adj[pair[0]].append([pair[1], str(e[2])])
	var nearest := func(p: Vector2) -> String:
		var best := ""
		var bd := INF
		for id in adj:
			var q: Array = g.nodes[id]
			var d := p.distance_squared_to(Vector2(q[0], q[1]))
			if d < bd:
				bd = d
				best = id
		return best
	var s: String = nearest.call(from)
	var t: String = nearest.call(to)
	if s == "" or t == "":
		return {}
	var pos := func(id: String) -> Vector2: return Vector2(g.nodes[id][0], g.nodes[id][1])
	var open := {s: true}
	var came := {}
	var gs := {s: 0.0}
	var tp: Vector2 = pos.call(t)
	while not open.is_empty():
		var cur := ""
		var bf := INF
		for id in open:
			var f: float = gs[id] + (pos.call(id) as Vector2).distance_to(tp)
			if f < bf:
				bf = f
				cur = id
		if cur == t:
			break
		open.erase(cur)
		for nb in adj.get(cur, []):
			var ng: float = gs[cur] + (pos.call(cur) as Vector2).distance_to(pos.call(nb[0]))
			if ng < gs.get(nb[0], INF):
				gs[nb[0]] = ng
				came[nb[0]] = [cur, nb[1]]
				open[nb[0]] = true
	if not came.has(t) and s != t:
		return {}
	var path: Array = [pos.call(t)]
	var refs: Array[String] = []
	var c := t
	while came.has(c):
		var r: String = came[c][1]
		if r != "" and (refs.is_empty() or refs[-1] != r):
			refs.append(r)
		c = came[c][0]
		path.push_front(pos.call(c))
	refs.reverse()
	return {"path": path, "via": refs}
