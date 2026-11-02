class_name GroundOps
extends Node3D
## Ground operations: progressive taxi guidance (T) and pushback (P).
## T: A* route from the aircraft to the into-wind runway's threshold over the OSM
##    taxi graph; drawn as a green line with chevrons, instruction shown on screen.
##    T again clears it. Reaching the end shows "Hold short runway NN".
## P: pushback tug: straight back, then a 90 deg swing (tail toward the taxiway), path and speed from
##    aircraft.json "pushback" (GroundParams); the aircraft is moved kinematically (as a real tug does),
##    brakes must be off. P again stops the push.

var ops: AirportOps
var airports: AirportBuilder
var fdm_node: FdmNode
var terrain: TerrainQuadtree
var _route: Array = []  # [Vector2]
var _route_txt := ""
var _hold_at_end := true  # runway route: "hold short" at the end; stand route: just ends
var _line: MeshInstance3D
var _banner: TaxiBanner  # the instruction on screen (a fading card, ui/taxi_banner.gd)
var _push := {}  # active pushback state
var _tug: Node3D
var _follow: FollowMeCar  # follow-me car leading along the taxi route
var _follow_s := 0.0  # its distance along the route (m)
var _gap := 35.0  # follow-me car's target gap ahead of the CG (it starts gap + 5 m ahead)
var _pb := GroundParams.PUSHBACK  # pushback path and speed
var _tow_ahead := 3.2  # tug origin ahead of the CG
var _route_len: PackedFloat32Array = []  # cumulative distance at each route point
var _mat := StandardMaterial3D.new()


func setup(o: AirportOps, ab: AirportBuilder, fn: FdmNode, t: TerrainQuadtree, ui: CanvasLayer) -> void:
	ops = o
	airports = ab
	fdm_node = fn
	terrain = t
	_gap = GroundParams.follow_gap_m()
	_pb = GroundParams.pushback()
	_tow_ahead = float(GroundParams.ground().tow_ahead_m)
	_mat.albedo_color = Color(0.2, 1.0, 0.35)
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.emission_enabled = true
	_mat.emission = Color(0.2, 1.0, 0.35)
	_banner = TaxiBanner.new()
	add_child(_banner)
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
			var score: float = GroundChoice.runway_score(head, float(r.length))  # headwind + length, short runways last
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


## ATC "taxi to the apron" after landing: route to the nearest stand (ramp stands before jetbridge gates;
## the other way round for stand_class "gate"). Returns the instruction text, "" if there is none.
func request_taxi_to_stand() -> String:
	var icao := _airport_here()
	var p := fdm_node.position_enu()
	var here := Vector2(p.x, p.y)
	var best := {}
	var bd := INF
	var cls := str(GroundParams.ground().stand_class)
	for s in ops.data.get(icao, {}).get("stands", []):
		var d := here.distance_to(Vector2(s.x, s.y)) + GroundChoice.taxi_penalty(s, cls)
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
	_banner.announce(txt)
	_draw_route()


func clear_route() -> void:
	_route.clear()
	if _follow:
		_follow.queue_free()
		_follow = null
	if _line:
		_line.queue_free()
		_line = null
	_banner.route_cleared()


func _draw_route() -> void:
	if _line:
		_line.queue_free()
	_line = RouteLine.build(_route, terrain.height_at, _mat)
	add_child(_line)


func _say(t: String) -> void:
	_banner.say(t)


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
		_banner.route_progress(_route_txt, rem, _hold_at_end)
		if not _hold_at_end and rem < 12.0:
			clear_route()


func _spawn_follow_me() -> void:
	if _follow:
		_follow.queue_free()
	_follow = FollowMeCar.new()
	add_child(_follow)
	_follow_s = _gap + 5.0


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
	var v := clampf((gap - _gap) * -0.3 + 7.0, 0.0, 9.0) if gap < _gap + 25.0 else 0.0  # wait if too far ahead
	_follow_s = minf(_follow_s + v * dt, total + _gap - 5.0)
	if _follow_s > total + _gap - 10.0:  # peel off after the hold point
		_follow.queue_free()
		_follow = null
		return
	var r := _route_at(minf(_follow_s, total))
	_follow.place(r[0].x, r[0].y, r[1], dt, terrain.height_at)


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
	var icao := _airport_here()
	var side := 1.0  # swing the tail toward the nearest taxi node
	if icao != "":
		var r := ops.route(icao, Vector2(p.x, p.y), Vector2(p.x, p.y))
		if not r.is_empty():
			var node: Vector2 = r.path[0]
			var right := Vector2(cos(e.z), -sin(e.z))  # body right in (east, north)
			side = 1.0 if (node - Vector2(p.x, p.y)).dot(right) > 0.0 else -1.0
	_push = {"s": 0.0, "hdg0": e.z, "p0": Vector2(p.x, p.y), "side": side}
	_spawn_tug()
	_banner.say("Pushback in progress — P to stop", "Pushback in progress  ·  P to stop")


func _end_push(msg: String) -> void:
	_push = {}
	if _tug:
		_tug.queue_free()
		_tug = null
	_say(msg)


func _exit_tree() -> void:
	FollowMeCar.release()


func _spawn_tug() -> void:  # world/veh_tug.gd, sized by ground.tug_scale
	_tug = Node3D.new()
	_tug.add_child(GroundVehicles.make("pushback_tug", float(GroundParams.ground().tug_scale)))
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
	_push.s += float(_pb.speed_mps) * dt
	var s: float = _push.s
	var h0: float = _push.hdg0
	var pose := PushbackPath.pose(_push.p0, h0, _push.side, s, _pb.straight_m, _pb.radius_m)
	var pos: Vector2 = pose[0]
	var hdg: float = pose[1]
	if s >= PushbackPath.length(_pb.straight_m, _pb.radius_m) - 1e-3 * float(_pb.radius_m):
		_end_push("Pushback complete — set parking brake, start engine, then T for taxi")
	f.pos_e = pos.x
	f.pos_n = pos.y
	var e := f.euler()
	f.q = FDM.euler_to_quat(e.x, e.y, hdg)
	f.v_b = Vector3.ZERO
	f.w_b = Vector3.ZERO
	if _tug:
		var nose := Vector2(sin(hdg), cos(hdg))
		var tp := pos + nose * _tow_ahead  # tug position ahead of the CG
		_tug.position = FloatingOrigin.to_render(Vector3(tp.x, tp.y, terrain.height_at(tp.x, tp.y)))
		_tug.rotation.y = -hdg
