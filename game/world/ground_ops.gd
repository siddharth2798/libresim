class_name GroundOps
extends Node3D
## Ground operations: progressive taxi guidance (T) and pushback (P).
## T: A* route from the aircraft to the into-wind runway's threshold over the OSM
##    taxi graph; drawn as a green line with chevrons, instruction shown on screen.
##    T again clears it. Reaching the end shows "Hold short runway NN".
## P: pushback tug: straight back 30 m, then a 90 deg swing (tail toward the taxiway);
##    the aircraft is moved kinematically (as a real tug does), brakes must be off.
##    P again stops the push.

const PUSH_SPEED := 1.4
const PUSH_STRAIGHT := 30.0
const PUSH_RADIUS := 18.0

var ops: AirportOps
var airports: AirportBuilder
var fdm_node: FdmNode
var terrain: TerrainQuadtree
var _route: Array = []  # [Vector2]
var _route_txt := ""
var _line: MeshInstance3D
var _label: Label
var _push := {}  # active pushback state
var _tug: Node3D
var _mat := StandardMaterial3D.new()


func setup(o: AirportOps, ab: AirportBuilder, fn: FdmNode, t: TerrainQuadtree, ui: CanvasLayer) -> void:
	ops = o
	airports = ab
	fdm_node = fn
	terrain = t
	_mat.albedo_color = Color(0.2, 1.0, 0.35)
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.emission_enabled = true
	_mat.emission = Color(0.2, 1.0, 0.35)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 5)
	_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_label.position = Vector2(-300, -300)
	_label.custom_minimum_size = Vector2(600, 0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.add_child(_label)
	FloatingOrigin.shifted.connect(func(d: Vector3):
		if _line:
			_line.position += d)


func _airport_here() -> String:
	var p := fdm_node.position_enu()
	var best := ""
	var bd := INF
	for icao in ops.data:
		var a: Dictionary = ops.data[icao]
		if a.taxi.nodes.is_empty():
			continue
		var n0: Array = a.taxi.nodes.values()[0]
		var d := Vector2(p.x, p.y).distance_to(Vector2(n0[0], n0[1]))
		if d < bd:
			bd = d
			best = icao
	return best if bd < 8000.0 else ""


func _best_runway_end(icao: String) -> Dictionary:
	var wind: Vector3 = Props.get_v("environment/wind_ned", Vector3.ZERO)
	var best := {}
	var bs := -INF
	for r in airports.data.runways:
		if r.airport != icao:
			continue
		for e in r.ends:
			var hd := deg_to_rad(float(e.heading_true))
			var head := -(wind.x * cos(hd) + wind.y * sin(hd))  # headwind component
			var score: float = head + float(r.length) / 1000.0
			if score > bs:
				bs = score
				best = e
	return best


func _unhandled_key_input(e: InputEvent) -> void:
	if not e.pressed or e.echo:
		return
	if e.keycode == KEY_T and not e.ctrl_pressed:
		if _route.is_empty():
			request_taxi()
		else:
			clear_route()
	elif e.keycode == KEY_P and not e.ctrl_pressed:
		if _push.is_empty():
			start_pushback()
		else:
			_end_push("Pushback stopped")


func request_taxi() -> void:
	var icao := _airport_here()
	if icao == "":
		_say("No taxiway data here")
		return
	var rwy := _best_runway_end(icao)
	if rwy.is_empty():
		return
	var p := fdm_node.position_enu()
	var r := ops.route(icao, Vector2(p.x, p.y), Vector2(rwy.x, rwy.y))
	if r.is_empty():
		_say("No taxi route found")
		return
	_route = r.path
	_route_txt = "Taxi to runway %s%s — hold short" % [rwy.ident, (" via " + ", ".join(r.via)) if not r.via.is_empty() else ""]
	Props.set_v("ops/taxi_route", _route_txt)
	_draw_route()


func clear_route() -> void:
	_route.clear()
	if _line:
		_line.queue_free()
		_line = null
	_label.text = ""


func _draw_route() -> void:
	if _line:
		_line.queue_free()
	var verts := PackedVector3Array()
	for i in range(_route.size() - 1):
		var a: Vector2 = _route[i]
		var b: Vector2 = _route[i + 1]
		var d := (b - a).normalized()
		var sd := Vector2(d.y, -d.x) * 0.35
		var n := maxi(int(a.distance_to(b) / 8.0), 1)
		for k in n:
			var p0 := a.lerp(b, float(k) / n)
			var p1 := a.lerp(b, float(k + 1) / n)
			var h0 := terrain.height_at(p0.x, p0.y) + 0.25
			var h1 := terrain.height_at(p1.x, p1.y) + 0.25
			for v in [p0 - sd, p0 + sd, p1 + sd, p0 - sd, p1 + sd, p1 - sd]:
				var h: float = h0 if v.distance_to(p0) < v.distance_to(p1) else h1
				verts.append(Vector3(v.x, h, -v.y))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_line = MeshInstance3D.new()
	_line.mesh = m
	_line.material_override = _mat
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_line.position = FloatingOrigin.to_render(Vector3.ZERO)
	add_child(_line)


func _say(t: String) -> void:
	_label.text = t


func _process(_dt: float) -> void:
	if not _route.is_empty():
		var p := fdm_node.position_enu()
		var here := Vector2(p.x, p.y)
		var rem := 0.0
		var nearest := 0
		var bd := INF
		for i in _route.size():
			var d := here.distance_to(_route[i])
			if d < bd:
				bd = d
				nearest = i
		for i in range(nearest, _route.size() - 1):
			rem += (_route[i] as Vector2).distance_to(_route[i + 1])
		_say("%s   (%.0f m)%s" % [_route_txt, rem, "\nHOLD SHORT — contact tower for takeoff" if rem < 40.0 else ""])
	elif _push.is_empty():
		if _label.text.begins_with("Pushback") or _label.text.begins_with("No "):
			pass


func start_pushback() -> void:
	var f := fdm_node.fdm
	if not f.gear.wow or Vector2(f.velocity_ned().x, f.velocity_ned().y).length() > 0.5:
		_say("Pushback is only possible when stopped on the ground")
		return
	if Props.get_b("controls/parking_brake"):
		_say("Release the parking brake (Shift+B) for pushback")
		return
	var e := f.euler()
	var p := fdm_node.position_enu()
	# swing the tail toward the nearest taxi node
	var icao := _airport_here()
	var side := 1.0
	if icao != "":
		var r := ops.route(icao, Vector2(p.x, p.y), Vector2(p.x, p.y))
		if not r.is_empty():
			var node: Vector2 = r.path[0]
			var right := Vector2(cos(e.z), -sin(e.z))  # body right in (east, north)
			side = 1.0 if (node - Vector2(p.x, p.y)).dot(right) > 0.0 else -1.0
	_push = {"s": 0.0, "hdg0": e.z, "p0": Vector2(p.x, p.y), "side": side}
	_spawn_tug()
	_say("Pushback in progress — P to stop")


func _end_push(msg: String) -> void:
	_push = {}
	if _tug:
		_tug.queue_free()
		_tug = null
	_say(msg)


func _spawn_tug() -> void:
	_tug = Node3D.new()
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.8, 1.0, 3.0)
	body.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.95, 0.75, 0.1)
	body.material_override = m
	body.position = Vector3(0, 0.5, -1.5)
	_tug.add_child(body)
	var bar := MeshInstance3D.new()
	var b2 := BoxMesh.new()
	b2.size = Vector3(0.12, 0.12, 2.2)
	bar.mesh = b2
	bar.position = Vector3(0, 0.35, 0.9)
	_tug.add_child(bar)
	add_child(_tug)


func _physics_process(dt: float) -> void:
	if _push.is_empty():
		return
	var f := fdm_node.fdm
	if f.gear.brake_left > 0.5 or f.gear.brake_right > 0.5:
		return  # brakes on: tug stalls
	_push.s += PUSH_SPEED * dt
	var s: float = _push.s
	var h0: float = _push.hdg0
	var back := -Vector2(sin(h0), cos(h0))  # tail direction (east, north)
	var pos: Vector2
	var hdg: float
	if s <= PUSH_STRAIGHT:
		pos = _push.p0 + back * s
		hdg = h0
	else:
		var a := minf((s - PUSH_STRAIGHT) / PUSH_RADIUS, PI / 2)
		var side: float = _push.side
		var right := Vector2(cos(h0), -sin(h0))
		var centre: Vector2 = _push.p0 + back * PUSH_STRAIGHT + right * side * PUSH_RADIUS
		var rel := -right * side * PUSH_RADIUS
		pos = centre + rel.rotated(side * a)  # keeps moving tail-first around the arc
		hdg = h0 - side * a  # tail swings toward `side`
		if a >= PI / 2 - 1e-3:
			_end_push("Pushback complete — set parking brake, start engine, then T for taxi")
	f.pos_e = pos.x
	f.pos_n = pos.y
	var e := f.euler()
	f.q = FDM.euler_to_quat(e.x, e.y, hdg)
	f.v_b = Vector3.ZERO
	f.w_b = Vector3.ZERO
	if _tug:
		var nose := Vector2(sin(hdg), cos(hdg))
		var tp := pos + nose * 3.2
		_tug.position = FloatingOrigin.to_render(Vector3(tp.x, tp.y, terrain.height_at(tp.x, tp.y)))
		_tug.rotation.y = -hdg
