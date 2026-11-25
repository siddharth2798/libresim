extends "res://tests/route_live_base.gd"
## The in-flight route editors on screen: the N map's Edit route mode turns the mouse into edits, the pause screen's Edit
## route page applies from the present position (no departure ring there), route labels never overlap (MapRouteLayer,
## shared by the N map, mini-map and Route step map; nor over airport / navaid symbols), and the N map stays clear of
## the radio and flight-data bars and of the attribution line (MapStrip.top_clear / bottom_clear). Logic:
## tests/test_route_live.gd.


# ---- labels ----

func _legs_through(pts: Array) -> Array:
	var out := []
	var cum := 0.0
	for k in range(1, pts.size()):
		var d: float = (pts[k - 1] as Vector2).distance_to(pts[k])
		cum += d
		out.append({"a": pts[k - 1], "b": pts[k], "ident": "WPT%02d" % k if k < pts.size() - 1 else "VAPO", "active": k == 1,
			"dist_m": d, "cum_m": cum})
	return out


func test_route_labels_never_overlap_for_close_waypoints() -> String:
	var v := MapView.new()
	v.size = Vector2(900, 600)
	v.centre = Vector2.ZERO
	v.set_across_nm(60.0)
	var px := func(x: float, y: float) -> Vector2: return v.to_world(Vector2(x, y))
	# a tight cluster of three, then WPT04 45 px left of VAPO on one line (as in the pause screenshot)
	var pts: Array = [px.call(60, 80), px.call(300, 100), px.call(320, 130), px.call(340, 105), px.call(600, 420), px.call(645, 420)]
	var legs := _legs_through(pts)
	var font := ThemeDB.fallback_font
	var taken: Array = []
	# an airport symbol (not on the route) just right of WPT04, where its label would go first, and one above WPT02
	var symbols: Array = [Rect2(Vector2(612, 395), Vector2(26, 26)), Rect2(Vector2(307, 72), Vector2(26, 26))]
	MapRouteLayer.reserve(v, legs, font, taken, symbols)
	var boxes: Array = []
	for i in legs.size():
		var l: Dictionary = legs[i]
		if not l.has("lbl_pos"):
			return "reserve() must place (or drop) every label: leg %d" % i
		if l.lbl_pos != null:
			boxes.append([i, MapStyle.text_rect(font, str(l.lbl_text), l.lbl_pos, MapRouteLayer.LABEL_PX)])
	if legs[0].lbl_pos == null or legs[3].lbl_pos == null or legs[4].lbl_pos == null:
		return "the active label and both WPT04 / VAPO labels must find room (moved or shortened): %s" % [legs.map(func(l): return l.get("lbl_text"))]
	for m in boxes:
		for n in boxes:
			if m[0] < n[0] and (m[1] as Rect2).intersects(n[1]):
				return "labels of legs %d and %d overlap" % [m[0], n[0]]
		for sym in symbols:
			if (m[1] as Rect2).intersects(sym):
				return "the label of leg %d covers an airport symbol %s" % [m[0], sym]
		for j in legs.size():
			var r := 11.0 if legs[j].active else 8.0
			var mark := Rect2(v.to_px(legs[j].b) - Vector2(r, r), Vector2(r, r) * 2.0)
			if (m[1] as Rect2).intersects(mark):
				return "the label of leg %d covers the marker of leg %d" % [m[0], j]
	for l in legs:
		var pill := MapRouteLayer.leg_label(v, l, 60.0, font, taken)
		if pill.is_empty():
			continue
		var pr := MapStyle.pill_rect(font, pill.text, pill.at, 13)
		for m in boxes:
			if pr.intersects(m[1]):
				return "the leg pill %s covers a waypoint label" % pill.text
	return ""


func test_route_map_draws_the_latest_route_not_the_one_of_the_last_click() -> String:
	var m := RouteMap.new()
	add_child(m)
	_nodes.append(m)
	m.size = Vector2(800, 600)
	var two := _legs_through([Vector2.ZERO, Vector2(5000, 0), Vector2(9000, 3000)])
	for l in two:
		l.merge({"wp": 0, "insert_at": 0})
	m.show_route(two, {}, {}, -1, true)
	var e := InputEventMouseButton.new()  # a click hands the gestures these legs
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = Vector2(5, 5)
	m._gui_input(e)
	e = e.duplicate()
	e.pressed = false
	m._gui_input(e)
	var three := two + [{"a": Vector2(9000, 3000), "b": Vector2(12000, 0), "ident": "VAPO", "active": false, "dist_m": 1.0,
		"cum_m": 2.0, "wp": -2, "insert_at": 2}]
	m.show_route(three, {}, {}, -1)  # an edit made by the page (nav log, text, the click's own add)
	if m.drawn_legs().size() != 3:
		return "the map draws %d legs, not the 3 it was just handed" % m.drawn_legs().size()
	return ""


# ---- the N map's title row ----

func test_map_title_row_clears_the_top_bars_and_the_bottom_credits() -> String:
	_keep()
	var screen := SubViewport.new()  # a 1280x720 screen (the headless window is tiny)
	screen.size = Vector2i(1280, 720)
	add_child(screen)
	_nodes.append(screen)
	var m: Control = load("res://ui/moving_map.gd").new()
	screen.add_child(m)
	var bar := Panel.new()
	bar.position = Vector2(10, 8)
	bar.size = Vector2(420, 70)
	bar.add_to_group(MapStrip.CLEAR_GROUP)
	screen.add_child(bar)
	m.clear_top(true)
	if m.offset_top < 78.0 + 6.0 - 0.01:
		return "the map top must sit under the bar: %.1f" % m.offset_top
	bar.size.y = 40.0
	m.clear_top()
	if m.offset_top < 84.0 - 0.01:
		return "while open the top only moves down (no jumping): %.1f" % m.offset_top
	var vh: float = m.get_viewport_rect().size.y
	var credit := Label.new()  # the data attribution line, as ui/credits_screen.gd puts it at the bottom
	credit.position = Vector2(24, vh - 50.0)
	credit.size = Vector2(600, 46)
	credit.add_to_group(MapStrip.BOTTOM_GROUP)
	screen.add_child(credit)
	m.clear_top()
	if m.offset_bottom > -(50.0 + 4.0) + 0.01:
		return "the map bottom must end above the attribution line: %.1f" % m.offset_bottom
	bar.visible = false
	credit.visible = false
	m.clear_top(true)
	if m.offset_top != m.MARGIN or m.offset_bottom != -m.MARGIN:
		return "with no bar showing the usual margins: %.1f / %.1f" % [m.offset_top, m.offset_bottom]
	var box := AtcBox.new()
	_nodes.append(box)
	box._open = true
	if box.map_clear_rect().size.y > 0.0:
		return "the open radio call list does not push the map down"
	return ""


# ---- the N map's edit mode ----

func _map(d: NavDatabase) -> Control:
	var m: Control = load("res://ui/moving_map.gd").new()
	m.db = d
	add_child(m)
	_nodes.append(m)
	m.view.size = Vector2(1200, 800)
	m.view.centre = Fx.p(15, 90)
	m.view.set_across_nm(220.0)
	m.follow = false
	return m


func _btn(m: Control, px: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT, shift := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = px
	e.shift_pressed = shift
	m._gui_input(e)


func _drag(m: Control, from: Vector2, to: Vector2) -> void:
	_btn(m, from, true)
	for k in range(1, 5):
		var mv := InputEventMouseMotion.new()
		mv.position = from.lerp(to, k / 4.0)
		mv.relative = (to - from) / 4.0
		m._gui_input(mv)
	_btn(m, to, false)


func test_map_edit_mode_turns_the_mouse_into_route_edits() -> String:
	var d := _flying()
	var m := _map(d)
	m._on_button("edit")
	if not m.editing():
		return "the Edit route toggle turns edit mode on"
	var v: MapView = m.view
	var empty := v.to_px(Fx.p(45, 60))
	_btn(m, empty, true)
	_btn(m, empty, false)
	if _gps() != ["WPT01", "FB", "WPT02", "BBBB"] or Fx.ids(Session.setup.route.wps) != ["FA", "WPT01", "FB", "WPT02"]:
		return "click on empty map adds a free waypoint before the destination: GPS %s" % [_gps()]
	_drag(m, v.to_px(Fx.p(30, 100)), v.to_px(Fx.p(40, 110)))
	if _gps().size() != 4 or _gps()[1] != "WPT03" or d.position_of("WPT03").distance_to(Fx.p(40, 110)) > 400.0:
		return "dragging FB makes it a free waypoint there: GPS %s" % [_gps()]
	_drag(m, v.to_px((Fx.p(10, 40) + Fx.p(40, 110)) * 0.5), v.to_px(Fx.p(-20, 80)))
	if _gps().size() != 5 or _gps()[0] != "WPT01" or _gps()[2] != "WPT03":
		return "dragging a leg inserts a point on it: GPS %s" % [_gps()]
	var inserted := str(_gps()[1])
	_btn(m, v.to_px(d.position_of(inserted)), true, MOUSE_BUTTON_RIGHT)
	if _gps().has(inserted) or _gps().size() != 4:
		return "right-click removes the waypoint: GPS %s" % [_gps()]
	var c0: Vector2 = v.centre
	_drag(m, v.to_px(Fx.p(-40, 150)), v.to_px(Fx.p(-40, 150)) + Vector2(80, 0))
	if v.centre.x >= c0.x or _gps().size() != 4:
		return "dragging the empty map pans (and edits nothing): centre %s -> %s, GPS %s" % [c0, v.centre, _gps()]
	var mpp: float = v.target_m_per_px
	_btn(m, v.size * 0.5, true, MOUSE_BUTTON_WHEEL_UP)
	if v.target_m_per_px >= mpp:
		return "the wheel still zooms in edit mode"
	m._on_button("edit")
	_btn(m, v.to_px(Fx.p(45, 60)), true)
	_btn(m, v.to_px(Fx.p(45, 60)), false)
	if _gps().size() != 4:
		return "with edit mode off a click on empty map edits nothing: %s" % [_gps()]
	return ""


# ---- the pause screen's Edit route page (real nav data) ----

func test_pause_edit_route_page_applies_from_the_present_position() -> String:
	_keep()
	var d := RouteEdit.db()
	if d.position_of("VAPO") == null or d.position_of("MUBKU") == null:
		return ""
	var s := Session.DEFAULT.duplicate(true)
	s.airport = "VABB"
	var mub: Vector2 = d.position_of("MUBKU")
	s.route = {"dest": "VAPO", "wps": [{"id": "WPT01", "kind": "user", "x": 10000.0, "y": -2000.0, "alt_ft": 4500.0},
		{"id": "MUBKU", "kind": "fix", "x": mub.x, "y": mub.y, "alt_ft": 4500.0}]}
	Session.setup = s
	RouteSetup.register(RouteSetup.repair(s.route))
	Props.set_v("controls/gps/target", "MUBKU")
	Props.set_v("controls/gps/route_next", ["VAPO"])
	Props.set_v("fdm/position_enu", Vector3(15000.0, -3000.0, 1000.0))
	var page: Control = VBoxContainer.new()
	page.set_script(load("res://ui/route_live_page.gd"))
	add_child(page)
	_nodes.append(page)
	var rp: Control = page.page
	if not rp.map.ring_dep().is_empty() or rp.map.aircraft.is_empty():
		return "in flight the start is the aircraft symbol, not a departure ring at PPOS"
	if rp.map.legs.size() != 2 or rp.map.legs[0].from != RouteLive.PPOS or not rp.plans.visible or rp.start.visible:
		return "page: legs %s, plans %s, start %s" % [rp.map.legs.map(func(l): return l.from), rp.plans.visible, rp.start.visible]
	var closed := [0]
	page.closed.connect(func(): closed[0] += 1)
	rp.add_point(Vector2(40000.0, -15000.0), "")
	if _gps() != ["MUBKU", "VAPO"]:
		return "nothing reaches the flight before Apply: %s" % [_gps()]
	if Fx.ids(RouteEdit.route_of(rp.live).wps) != ["MUBKU", "WPT02"] or not page.status.text.begins_with("Not applied"):
		return "the page names the new point apart from the flown WPT01: %s (%s)" % [Fx.ids(RouteEdit.route_of(rp.live).wps), page.status.text]
	page.apply()
	if _gps() != ["MUBKU", "WPT02", "VAPO"] or closed[0] != 1:
		return "Apply: GPS %s closed %d" % [_gps(), closed[0]]
	if Fx.ids(Session.setup.route.wps) != ["WPT01", "MUBKU", "WPT02"] or NavDatabase.route_fixes.has(RouteLive.PPOS):
		return "plan after Apply: %s, PPOS left %s" % [Fx.ids(Session.setup.route.wps), NavDatabase.route_fixes.has(RouteLive.PPOS)]
	return ""
