extends HBoxContainer
## Start screen step 4 (optional): Route. Plan the waypoints to fly from the Airport step's airport. Top (RouteControls):
## the departure (read only), the destination (search box), its arrival runway, the cruise altitude; auto-route (Direct /
## VOR to VOR / Airways, avionics/route_builder.gd), Clear and the route as text (type one, Enter). Below, the map
## (RouteMap: click to add, drag to move or to add on a leg, right-click to remove) beside the nav log (RouteLog) and,
## for an "In the air" start, where on the route the flight starts (RouteStart, route.air_at). Every edit reads
## Session.setup.route, changes it (RouteEdit), writes it back and emits `changed`; an empty route skips the step.

signal changed

var controls: RouteControls
var map: RouteMap
var nav_log: RouteLog
var start: RouteStart
var selected := -1  # wps index of the selected waypoint, -2 = destination, -1 = none
# the controls, where tests look for them
var auto_seg: Segmented
var text_box: LineEdit
var note: Label
var start_opt: OptionButton
var start_note: Label
var _airports: Array = []


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	_airports = RoutePageData.airports()
	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	controls = RouteControls.new()
	controls.dest_picked.connect(set_destination)
	controls.rwy_picked.connect(func(v): _edit(func(r): r.arr_rwy = v))
	controls.cruise_changed.connect(func(v): _edit(func(r): RouteEdit.set_cruise(r, v)))
	controls.auto_pressed.connect(auto_route)
	controls.clear_pressed.connect(clear_route)
	controls.text_entered.connect(enter_text)
	col.add_child(controls)
	auto_seg = controls.auto_seg
	text_box = controls.text_box
	note = controls.note
	var body := HBoxContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	col.add_child(body)
	map = RouteMap.new()
	map.size_flags_horizontal = SIZE_EXPAND_FILL
	map.size_flags_vertical = SIZE_EXPAND_FILL
	map.db = RouteEdit.db()
	map.runways = RoutePageData.runways(_airports)
	map.clicked.connect(_on_map_click)
	map.wp_selected.connect(select)
	map.wp_dragged.connect(drag_waypoint)
	map.leg_dragged.connect(insert_on_leg)
	map.wp_removed.connect(remove_waypoint)
	body.add_child(map)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(440, 0)
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)
	right.add_child(MenuTheme.heading("Nav log", 13))
	nav_log = RouteLog.new()
	nav_log.size_flags_vertical = SIZE_EXPAND_FILL
	nav_log.row_selected.connect(select)
	nav_log.alt_changed.connect(set_altitude)
	nav_log.move_requested.connect(move_waypoint)
	nav_log.remove_requested.connect(remove_waypoint)
	right.add_child(nav_log)
	start = RouteStart.new()
	start.leg_picked.connect(func(k): _edit(func(r): r.air_at = k))
	right.add_child(start)
	start_opt = start.opt
	start_note = start.note
	visibility_changed.connect(func():
		if visible:
			_refresh(true))
	_refresh(true)


# ---- edits: each reads the route, changes it and writes it back (_commit) ----

func _route() -> Dictionary:
	return RouteEdit.route_of(Session.setup)


func _edit(f: Callable, refit := false) -> void:
	var r := _route()
	f.call(r)
	_commit(r, refit)


func _commit(r: Dictionary, refit := false, msg := "", warn := false) -> void:
	var s: Dictionary = Session.setup
	s["route"] = r
	if r.air_at >= RouteEdit.leg_count(s):
		r.air_at = -1
	if msg != "":
		say(msg, warn)
	_refresh(refit)
	changed.emit()


func set_destination(icao: String) -> void:
	var r := _route()
	r.dest = icao
	r.arr_rwy = ""
	selected = -1
	if r.kind in ["direct", "vor", "airway"]:
		var res := RouteBuilder.auto(r.kind, str(Session.setup.airport), icao, RouteEdit.db(), r.cruise_ft)
		if res.ok:
			r.wps = res.wps
		else:
			r.kind = "manual"
			say(str(res.error), true)
	_commit(r, true)


func auto_route(kind: String) -> void:
	var r := _route()
	if r.dest == "":
		say("Pick a destination first (the box beside From).", true)
		controls.auto_seg.select(r.kind)
		return
	var res := RouteBuilder.auto(kind, str(Session.setup.airport), r.dest, RouteEdit.db(), r.cruise_ft)
	if not res.ok:
		say(str(res.error), true)
		controls.auto_seg.select(r.kind)
		return
	r.wps = res.wps
	r.kind = kind
	selected = -1
	_commit(r, true, "%s route: %d waypoint%s." % [controls.auto_seg.button_of(kind).text, r.wps.size(), "" if r.wps.size() == 1 else "s"])


func clear_route() -> void:
	var r := _route()
	r.merge({"dest": "", "arr_rwy": "", "wps": [], "kind": "manual", "air_at": -1}, true)
	selected = -1
	_commit(r, false, "Route cleared: the step is skipped.")


func enter_text(t: String) -> void:
	var s: Dictionary = Session.setup
	if t.strip_edges() == RouteEdit.as_text(s):
		return
	if t.strip_edges() == "":
		clear_route()
		return
	var r := _route()
	var res := RouteBuilder.parse(t, str(s.airport), RouteEdit.db(), r.cruise_ft)
	if not res.ok:
		say(str(res.error), true)
		return
	r.dest = str(res.dest)
	r.wps = res.wps
	r.kind = "manual"
	selected = -1
	_commit(r, true)


func _on_map_click(world: Vector2, ident: String, shift: bool) -> void:
	var s: Dictionary = Session.setup
	if shift and ident != "" and not RouteEdit.db().airport(ident).is_empty():
		set_destination(ident)
		return
	var r := _route()
	if ident == r.dest and ident != "":
		say("%s is already the destination." % ident)
		return
	if ident == str(s.airport) and ident != "":
		say("%s is the departure." % ident)
		return
	add_point(world, ident)


## Add the named point `ident` (or, "" / unknown, a free waypoint at `world`) at the end, before the destination.
func add_point(world: Vector2, ident: String) -> void:
	var r := _route()
	var wp := _make(world, ident, r.cruise_ft, r.wps)
	if RouteEdit.add(r, wp):
		selected = r.wps.size() - 1
		_commit(r, false, "%s added." % wp.id)


func drag_waypoint(i: int, world: Vector2, ident: String) -> void:
	var r := _route()
	if i < 0 or i >= r.wps.size():
		return
	var old: Dictionary = r.wps[i]
	var others: Array = r.wps.filter(func(w): return w != old)
	var wp := _make(world, ident, float(old.alt_ft), others)
	if wp.kind == "user" and str(old.kind) == "user":
		wp.id = old.id  # a free waypoint keeps its name when moved
	RouteEdit.replace(r, i, wp)
	selected = i
	_commit(r)


func insert_on_leg(at: int, world: Vector2, ident: String) -> void:
	var r := _route()
	var wp := _make(world, ident, RouteEdit.leg_alt(r, at if at < r.wps.size() else -2), r.wps)
	RouteEdit.insert(r, at, wp)
	selected = clampi(at, 0, r.wps.size() - 1)
	_commit(r, false, "%s added on the leg." % wp.id)


func remove_waypoint(i: int) -> void:
	var r := _route()
	if i < 0 or i >= r.wps.size():
		return
	var id := str(r.wps[i].id)
	RouteEdit.remove(r, i)
	selected = -1
	_commit(r, false, "%s removed." % id)


func move_waypoint(i: int, delta: int) -> void:
	var r := _route()
	selected = RouteEdit.move(r, i, delta)
	_commit(r)


func set_altitude(i: int, ft: float) -> void:
	_edit(func(r):
		if i >= 0 and i < r.wps.size():
			r.wps[i].alt_ft = ft)


func select(i: int) -> void:
	selected = i
	_refresh(false)


## A waypoint for a named point (RouteBuilder.waypoint), else a free one at `world`.
func _make(world: Vector2, ident: String, alt: float, wps: Array) -> Dictionary:
	var wp := RouteBuilder.waypoint(ident, RouteEdit.db(), alt) if ident != "" else {}
	return wp if not wp.is_empty() else RouteBuilder.user_waypoint(world, wps, alt)


func say(msg: String, warn := false) -> void:
	controls.say(msg, warn)


## Repaint everything from Session.setup; `refit` frames the route on the map.
func _refresh(refit: bool) -> void:
	var s: Dictionary = Session.setup
	var r := _route()
	var tas := RouteEdit.cruise_kt(str(s.get("aircraft", "")))
	var d := RouteEdit.db()
	if selected >= r.wps.size() or (selected == -2 and r.dest == ""):
		selected = -1
	controls.refresh(s, r, _airports)
	var legs := RouteEdit.legs(s, d, tas)
	map.tas_mps = tas * RouteEdit.NM / 3600.0
	map.show_route(legs, RoutePageData.dep_point(s, d), RoutePageData.dest_point(r, d), selected, refit)
	nav_log.show_legs(legs, selected, r.wps.size(), tas)
	start.fill(s, r, legs)
