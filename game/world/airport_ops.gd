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


func setup(t: TerrainQuadtree) -> void:
	terrain = t
	var d = Paths.load_json("airport_ops.json")
	data = d if d else {}
	_yellow.albedo_color = Color(0.95, 0.78, 0.15)
	_yellow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bridge_mat.albedo_color = Color(0.72, 0.74, 0.76)
	_bridge_mat.roughness = 0.5
	_bridge_mat.metallic = 0.3
	FloatingOrigin.shifted.connect(func(d2: Vector3):
		for k in _built:
			_built[k].position += d2)


## Stand lookup: by ref ("Bay 40", "GA3"), or "" -> first gate with a jetbridge, else first stand.
func find_stand(icao: String, ref: String) -> Dictionary:
	var a: Dictionary = data.get(icao, {})
	var stands: Array = a.get("stands", [])
	if stands.is_empty():
		return {}
	if ref != "":
		for s in stands:
			if str(s.ref).to_lower().replace(" ", "") == ref.to_lower().replace(" ", ""):
				return s
	for s in stands:
		if s.jetbridge:
			return s
	return stands[0]


func _h(x: float, y: float) -> float:
	return terrain.height_at(x, y) if terrain else 0.0


func _process(dt: float) -> void:
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
	root.position = FloatingOrigin.to_render(Vector3.ZERO)
	for s in a.stands:
		_stand_marking(root, s)
	for jb in a.jetbridges:
		_jetbridge(root, jb.pts)
	for ws in a.windsocks:
		_windsock(root, ws.x, ws.y)


func _local(x: float, y: float, up: float) -> Vector3:
	return Vector3(x, _h(x, y) + up, -y)


func _stand_marking(root: Node3D, s: Dictionary) -> void:
	var hd := deg_to_rad(float(s.heading_deg))
	var fwd := Vector2(sin(hd), cos(hd))
	var lead := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(0.25, 0.02, 28.0)
	lead.mesh = m
	lead.material_override = _yellow
	var c := Vector2(s.x, s.y) - fwd * 14.0
	lead.position = _local(c.x, c.y, 0.18)
	lead.rotation.y = -hd + PI
	root.add_child(lead)
	var stop := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(3.0, 0.02, 0.3)
	stop.mesh = sm
	stop.material_override = _yellow
	stop.position = _local(s.x, s.y, 0.18)
	stop.rotation.y = -hd
	root.add_child(stop)
	var lbl := Label3D.new()
	lbl.text = str(s.ref)
	lbl.font_size = 64
	lbl.pixel_size = 0.02
	lbl.modulate = Color(0.95, 0.78, 0.15)
	lbl.rotation = Vector3(-PI / 2, -hd, 0)
	var p := Vector2(s.x, s.y) - fwd * 6.0
	lbl.position = _local(p.x, p.y, 0.2)
	root.add_child(lbl)


func _jetbridge(root: Node3D, pts: Array) -> void:
	for i in range(pts.size() - 1):
		var a := Vector2(pts[i][0], pts[i][1])
		var b := Vector2(pts[i + 1][0], pts[i + 1][1])
		var len := a.distance_to(b)
		if len < 0.5:
			continue
		var mi := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(3.2, 3.0, len)
		mi.mesh = m
		mi.material_override = _bridge_mat
		var mid := (a + b) * 0.5
		mi.position = _local(mid.x, mid.y, 4.6)
		mi.rotation.y = atan2(-(b.x - a.x), -(b.y - a.y))  # local -Z along the segment (render z = -north)
		root.add_child(mi)
		# support leg
		var leg := MeshInstance3D.new()
		var lm := CylinderMesh.new()
		lm.top_radius = 0.25
		lm.bottom_radius = 0.25
		lm.height = 3.2
		leg.mesh = lm
		leg.material_override = _bridge_mat
		leg.position = _local(b.x, b.y, 1.6)
		root.add_child(leg)


func _windsock(root: Node3D, x: float, y: float) -> void:
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
