extends Node
## The Route step's data and map, without the page: RouteEdit (legs with magnetic course, distance, time; edits; rail and
## chip texts; SetupChecks warnings), RouteLog rows, and RouteMap turning mouse input into its signals (click on empty
## map, click a waypoint, drag a leg, drag a waypoint, right-click). A made-up NavDatabase keeps the numbers exact.

var _keep := {}
var _nodes: Array[Node] = []


func teardown() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	if not _keep.is_empty():
		Session.setup = _keep
		_keep = {}


## Two airports 10 nm apart, AAAA at the origin and BBBB due east; a fix FIXN 10 nm north of AAAA.
func _db() -> NavDatabase:
	var d := NavDatabase.new()
	d.airports = [{"ident": "AAAA", "icao": "AAAA", "x": 0.0, "y": 0.0, "type": "small_airport"},
		{"ident": "BBBB", "icao": "BBBB", "x": 18520.0, "y": 0.0, "type": "small_airport"}]
	d.vors = []
	d.ndbs = []
	d.airways = {}
	d.fixes = {"FIXN": Vector2(0.0, 18520.0)}
	return d


func _setup(route: Dictionary) -> Dictionary:
	var s := Session.DEFAULT.duplicate(true)
	s.airport = "AAAA"
	s.route = route
	return s


func test_route_legs_course_distance_time_and_altitude() -> String:
	var s := _setup({"dest": "BBBB", "wps": [{"id": "FIXN", "kind": "fix", "x": 0.0, "y": 18520.0, "alt_ft": 3500.0}], "cruise_ft": 4500.0})
	var ls := RouteEdit.legs(s, _db(), 120.0)
	if ls.size() != 2:
		return "expected 2 legs, got %d" % ls.size()
	# AAAA -> FIXN due north: true 000, magnetic 000.3 with the GPS variation of -0.3; 10 nm at 120 kt = 5:00
	if roundi(ls[0].course_mag) != 0 or absf(ls[0].dist_m / 1852.0 - 10.0) > 0.01 or absf(ls[0].ete_s - 300.0) > 0.5 or ls[0].alt_ft != 3500.0:
		return "leg 1: %s" % [ls[0]]
	# FIXN -> BBBB south-east: true 135, magnetic 135.3; 14.14 nm; the leg into the destination inherits 3500 ft
	if absf(ls[1].course_mag - 135.3) > 0.05 or absf(ls[1].cum_m / 1852.0 - 24.142) > 0.01 or ls[1].wp != -2 or ls[1].alt_ft != 3500.0 or ls[1].insert_at != 1:
		return "leg 2: %s" % [ls[1]]
	var nl := RouteLog.new()
	_nodes.append(nl)
	nl.show_legs(ls, 0, 1, 120.0)
	if nl.rows.size() != 2 or nl.rows[0].crs.text != "000°" or nl.rows[0].dist.text != "10.0" or nl.rows[0].ete.text != "5:00" or nl.rows[1].cum.text != "24.1":
		return "log row: %s %s %s / %s" % [nl.rows[0].crs.text, nl.rows[0].dist.text, nl.rows[0].ete.text, nl.rows[1].cum.text]
	if not (nl.rows[0].alt is SpinBox) or nl.rows[0].alt.value != 3500.0 or nl.rows[1].alt is SpinBox or nl.rows[1].del.visible:
		return "waypoint rows edit the altitude, the destination row does not"
	if not nl.total.text.contains("24.1 nm") or not nl.total.text.contains("12:04"):
		return "total: " + nl.total.text
	return ""


func test_route_edits_add_insert_move_remove_and_cruise() -> String:
	var r := RouteEdit.normalized({"dest": "BBBB", "cruise_ft": 4500.0})
	var a := {"id": "A1", "kind": "fix", "x": 1.0, "y": 1.0, "alt_ft": 4500.0}
	var b := {"id": "B1", "kind": "fix", "x": 2.0, "y": 2.0, "alt_ft": 2000.0}
	if not RouteEdit.add(r, a) or RouteEdit.add(r, a.duplicate()):
		return "add appends, a repeat of the last point is refused"
	RouteEdit.insert(r, 0, b)
	if r.wps.map(func(w): return w.id) != ["B1", "A1"]:
		return "insert: %s" % [r.wps]
	if RouteEdit.move(r, 0, 1) != 1 or r.wps[1].id != "B1":
		return "move down"
	RouteEdit.set_cruise(r, 6500.0)
	if r.wps[0].alt_ft != 6500.0 or r.wps[1].alt_ft != 2000.0:
		return "only waypoints at the old cruise follow it: %s" % [r.wps]
	RouteEdit.remove(r, 0)
	if r.wps.size() != 1 or r.wps[0].id != "B1" or r.kind != "manual":
		return "remove: %s" % [r.wps]
	return ""


func test_route_rail_and_chip_texts() -> String:
	var s := Session.DEFAULT.duplicate(true)
	s.airport = "VABB"
	if FlowValues.rail_value("route", s) != "Not planned" or FlowValues.chip_text("route", s) != "No route":
		return "no route: %s / %s" % [FlowValues.rail_value("route", s), FlowValues.chip_text("route", s)]
	var d := RouteEdit.db()
	var bb: Vector2 = d.position_of("VABB")
	var po: Vector2 = d.position_of("VAPO")
	s.route = {"dest": "VAPO"}
	var nm := roundi(bb.distance_to(po) / 1852.0)
	if FlowValues.rail_value("route", s) != "VABB → VAPO · direct · %d nm" % nm or FlowValues.chip_text("route", s) != "→ VAPO · %d nm" % nm:
		return "direct: %s / %s" % [FlowValues.rail_value("route", s), FlowValues.chip_text("route", s)]
	var mid := (bb + po) * 0.5 + Vector2(0, 9260.0)
	s.route = {"dest": "VAPO", "wps": [{"id": "WPT01", "kind": "user", "x": mid.x, "y": mid.y, "alt_ft": 4500.0},
		{"id": "PUN", "kind": "vor", "x": po.x, "y": po.y, "alt_ft": 4500.0}]}
	var total := roundi((bb.distance_to(mid) + mid.distance_to(po)) / 1852.0)
	if FlowValues.rail_value("route", s) != "VABB → VAPO · 2 wpts · %d nm" % total:
		return "with waypoints: " + FlowValues.rail_value("route", s)
	if FlowValues.level("route", s, SetupChecks.checks(s)) != "ok" or FlowValues.level("route", Session.DEFAULT, []) != "none":
		return "level: a planned route is ok, none is none"
	return ""


func test_route_warnings_in_the_setup_checks() -> String:
	var s := Session.DEFAULT.duplicate(true)
	s.airport = "VABB"
	s.route = {"dest": "QQQQ"}
	var ids := SetupChecks.checks(s).filter(func(c): return c.step == "route").map(func(c): return c.id)
	if ids != ["route_dest"]:
		return "unknown destination: %s" % [ids]
	s.route = {"dest": "VAPO", "wps": [{"id": "WPT01", "kind": "user", "x": 0.0, "y": -1500000.0, "alt_ft": 4500.0}]}
	ids = SetupChecks.checks(s).filter(func(c): return c.step == "route").map(func(c): return c.id)
	if ids != ["route_far"] or FlowValues.level("route", s, SetupChecks.checks(s)) != "warn":
		return "far waypoint: %s" % [ids]
	s.route = {"dest": "VAPO", "air_at": 3}
	s.start = "air"
	ids = SetupChecks.checks(s).filter(func(c): return c.step == "route").map(func(c): return c.id)
	if ids != ["route_leg"] or SetupChecks.worst(SetupChecks.checks(s).filter(func(c): return c.step == "route")) != "warn":
		return "start leg past the route: %s" % [ids]
	return ""


# ---- the map ----

func _map(route: Dictionary) -> Array:
	var s := _setup(route)
	var d := _db()
	var m := RouteMap.new()
	add_child(m)
	_nodes.append(m)
	m.db = d
	m.size = Vector2(800, 600)
	m.show_route(RouteEdit.legs(s, d, 120.0), {"id": "AAAA", "pos": Vector2.ZERO}, {"id": "BBBB", "pos": Vector2(18520.0, 0.0)}, -1, true)
	var got := []
	m.clicked.connect(func(w, id, shift): got.append(["click", w, id, shift]))
	m.wp_selected.connect(func(i): got.append(["select", i]))
	m.wp_dragged.connect(func(i, w, id): got.append(["drag", i, w, id]))
	m.leg_dragged.connect(func(i, w, id): got.append(["leg", i, w, id]))
	m.wp_removed.connect(func(i): got.append(["remove", i]))
	return [m, got]


func _mouse(m: RouteMap, px: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = px
	m._gui_input(e)


func _move(m: RouteMap, px: Vector2, rel := Vector2.ZERO) -> void:
	var e := InputEventMouseMotion.new()
	e.position = px
	e.relative = rel
	m._gui_input(e)


func test_route_map_mouse_becomes_click_select_drag_insert_and_remove() -> String:
	var pair := _map({"dest": "BBBB", "wps": [{"id": "FIXN", "kind": "fix", "x": 0.0, "y": 18520.0, "alt_ft": 4500.0}]})
	var m: RouteMap = pair[0]
	var got: Array = pair[1]
	var fix_px := m.view.to_px(Vector2(0.0, 18520.0))
	var empty := m.view.to_px(Vector2(15000.0, 15000.0))
	_mouse(m, empty, true)
	_mouse(m, empty, false)
	if got.size() != 1 or got[0][0] != "click" or got[0][2] != "" or (got[0][1] as Vector2).distance_to(Vector2(15000.0, 15000.0)) > 200.0:
		return "click on empty map: %s" % [got]
	got.clear()
	_mouse(m, fix_px, true)
	_mouse(m, fix_px, false)
	if got != [["select", 0]]:
		return "click on a waypoint selects it: %s" % [got]
	got.clear()
	var mid := m.view.to_px(Vector2(9260.0, 9260.0))  # the middle of the FIXN -> BBBB leg
	_mouse(m, mid, true)
	_move(m, mid + Vector2(40, 40))
	_mouse(m, mid + Vector2(40, 40), false)
	if got.size() != 1 or got[0][0] != "leg" or got[0][1] != 1:
		return "dragging a leg inserts on it (at 1): %s" % [got]
	got.clear()
	_mouse(m, fix_px, true)
	_move(m, empty)
	_mouse(m, empty, false)
	if got.size() != 1 or got[0][0] != "drag" or got[0][1] != 0 or got[0][3] != "":
		return "dragging a waypoint moves it: %s" % [got]
	got.clear()
	_mouse(m, fix_px, true, MOUSE_BUTTON_RIGHT)
	if got != [["remove", 0]]:
		return "right-click removes: %s" % [got]
	got.clear()
	var c0 := m.view.centre
	_mouse(m, empty, true)
	_move(m, empty + Vector2(50, 0), Vector2(50, 0))
	_mouse(m, empty + Vector2(50, 0), false)
	if not got.is_empty() or m.view.centre.distance_to(c0) < 1.0:
		return "dragging the empty map pans and adds nothing: %s" % [got]
	return ""
