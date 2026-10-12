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

var ops: AirportOps
var airports: AirportBuilder
var fdm_node: FdmNode
var terrain: TerrainQuadtree
var _route: Array = []  # [Vector2]
var _route_txt := ""
var _hold_at_end := true  # runway route: "hold short" at the end; stand route: just ends
var _line: MeshInstance3D
var _label: Label
var _push := {}  # active pushback state
var _tug: Node3D
var _follow: Node3D  # follow-me car leading along the taxi route
var _follow_s := 0.0  # its distance along the route (m)
var _route_len: PackedFloat32Array = []  # cumulative distance at each route point
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
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	_label.add_theme_stylebox_override("normal", Notifications.card_style(Color(0.3, 0.9, 0.45)))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(520, 0)
	_label.visible = false
	ui.add_child(Notifications.centered(_label, Control.PRESET_TOP_WIDE, 300))  # taxi / pushback instructions under the notices
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
	_set_route(r, "Taxi to runway %s%s — hold short" % [rwy.ident, (" via " + ", ".join(r.via)) if not r.via.is_empty() else ""], true)
	Props.set_v("ops/taxi_route", _route_txt)


## ATC "taxi to the apron" after landing: route to the nearest stand (a ramp stand is preferred
## over a gate with a jetbridge). Returns the instruction text, "" if there is none.
func request_taxi_to_stand() -> String:
	var icao := _airport_here()
	var p := fdm_node.position_enu()
	var here := Vector2(p.x, p.y)
	var best := {}
	var bd := INF
	for s in ops.data.get(icao, {}).get("stands", []):
		var d := here.distance_to(Vector2(s.x, s.y)) + (400.0 if s.jetbridge else 0.0)
		if d < bd:
			bd = d
			best = s
	var r := ops.route(icao, here, Vector2(best.x, best.y)) if not best.is_empty() else {}
	if r.is_empty():
		_say("No taxi route to a stand found")
		return ""
	var ref := str(best.get("ref", ""))
	_set_route(r, "Taxi to the apron%s%s" % [(" (stand " + ref + ")") if ref != "" else "", (" via " + ", ".join(r.via)) if not r.via.is_empty() else ""], false)
	return _route_txt


func _set_route(r: Dictionary, txt: String, hold_at_end: bool) -> void:
	_route = r.path
	_route_len.clear()
	var acc := 0.0
	for i in _route.size():
		if i > 0:
			acc += (_route[i - 1] as Vector2).distance_to(_route[i])
		_route_len.append(acc)
	_spawn_follow_me()
	_route_txt = txt
	_hold_at_end = hold_at_end
	_draw_route()


func clear_route() -> void:
	_route.clear()
	if _follow:
		_follow.queue_free()
		_follow = null
	if _line:
		_line.queue_free()
		_line = null
	_label.text = ""
	_label.visible = _label.text != ""


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
	_label.visible = _label.text != ""


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
		_update_follow_me(_dt, _route_len[nearest])
		_say("%s   (%.0f m)%s" % [_route_txt, rem, "\nHOLD SHORT — contact tower for takeoff" if rem < 40.0 and _hold_at_end else ""])
		if not _hold_at_end and rem < 12.0:
			clear_route()
	elif _push.is_empty():
		if _label.text.begins_with("Pushback") or _label.text.begins_with("No "):
			pass


func _spawn_follow_me() -> void:
	if _follow:
		_follow.queue_free()
	_follow = (load("res://world/models/vehicles/follow_me.glb") as PackedScene).instantiate()
	add_child(_follow)
	_follow_s = 40.0


## Point and heading (compass rad) at distance s along the route.
func _route_at(s: float) -> Array:
	for i in range(1, _route.size()):
		if _route_len[i] >= s:
			var a: Vector2 = _route[i - 1]
			var b: Vector2 = _route[i]
			var t := (s - _route_len[i - 1]) / maxf(_route_len[i] - _route_len[i - 1], 0.01)
			var d := b - a
			return [a.lerp(b, t), atan2(d.x, d.y)]
	var e: Vector2 = _route[-1]
	return [e, 0.0]


func _update_follow_me(dt: float, here_s: float) -> void:
	if _follow == null or _route.size() < 2:
		return
	var total: float = _route_len[-1]
	var gap := _follow_s - here_s
	var v := clampf((gap - 35.0) * -0.3 + 7.0, 0.0, 9.0) if gap < 60.0 else 0.0  # wait if too far ahead
	_follow_s = minf(_follow_s + v * dt, total + 30.0)
	if _follow_s > total + 25.0:  # peel off after the hold point
		_follow.queue_free()
		_follow = null
		return
	var r := _route_at(minf(_follow_s, total))
	var p: Vector2 = r[0]
	_follow.position = FloatingOrigin.to_render(Vector3(p.x, p.y, terrain.height_at(p.x, p.y)))
	_follow.rotation.y = -r[1]


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
	# FlightGear Goldhofer towbarless tug (GPL, fgdata); its model faces -X
	var holder := Node3D.new()
	var tug: Node3D = (load("res://world/models/vehicles/pushback_tug.glb") as PackedScene).instantiate()
	tug.rotation.y = -PI / 2
	holder.add_child(tug)
	_tug = holder
	add_child(_tug)


func _physics_process(dt: float) -> void:
	if _push.is_empty():
		return
	var f := fdm_node.fdm
	if f.damage.crashed:
		_end_push("Pushback stopped: collision")
		return
	if f.gear.brake_left > 0.5 or f.gear.brake_right > 0.5:
		return  # brakes on: tug stalls
	_push.s += PUSH_SPEED * dt
	var s: float = _push.s
	var h0: float = _push.hdg0
	var pose := PushbackPath.pose(_push.p0, h0, _push.side, s)
	var pos: Vector2 = pose[0]
	var hdg: float = pose[1]
	if s >= PushbackPath.length() - 1e-3 * PushbackPath.RADIUS:
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
