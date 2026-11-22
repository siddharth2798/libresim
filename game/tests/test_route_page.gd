extends Node
## The Route step of Free flight (ui/menu/route_page.gd): seven steps with Route after Airport, and the page's edits as
## Session.setup.route: a named point by a map click, a free waypoint by an empty-map click, remove, insert on a leg,
## drag, auto-route Direct, typed routes, a refused auto-route without a destination, and the "start on a leg" choice
## shown only for "In the air" starts. Real nav data (VABB, VAPO, PUN, MUBKU), headless.

const PageFrame := preload("res://ui/menu/page_frame.gd")
const StartFlow := preload("res://ui/menu/start_flow.gd")

var _keep := {}
var _page: Control


func _open(extra := {}) -> Control:
	_keep = Session.setup.duplicate(true)
	var s := Session.DEFAULT.duplicate(true)
	s.airport = "VABB"
	s.runway = "27"
	s.route = {}
	s.merge(extra, true)
	Session.setup = s
	_page = PageFrame.make_page("res://ui/menu/route_page.gd")
	add_child(_page)
	return _page


func teardown() -> void:
	if _page != null and is_instance_valid(_page):
		_page.free()
	_page = null
	if not _keep.is_empty():
		Session.setup = _keep
		_keep = {}


func _route() -> Dictionary:
	return RouteEdit.route_of(Session.setup)


func _ids() -> Array:
	return _route().wps.map(func(w): return w.id)


func test_route_flow_has_seven_steps_with_route_after_the_airport() -> String:
	var st: Array = StartFlow.STEPS
	if st.size() != 7 or st[2][1] != "res://ui/menu/airport_page.gd" or st[3][1] != "res://ui/menu/route_page.gd" or not str(st[3][0]).contains("optional"):
		return "steps: %s" % [st.map(func(x): return x[0])]
	if FlowValues.KEYS.size() != 7 or FlowValues.KEYS[3] != "route" or not FlowValues.OPTIONAL.has("route") or FlowValues.TITLES.route != "Route":
		return "flow keys: %s" % [FlowValues.KEYS]
	return ""


func test_route_page_click_adds_named_point_and_empty_map_adds_free_waypoint() -> String:
	var p := _open({"route": {"dest": "VAPO"}})
	var changed := [0]
	p.changed.connect(func(): changed[0] += 1)
	var d := RouteEdit.db()
	p._on_map_click(d.position_of("MUBKU"), "MUBKU", false)
	if _ids() != ["MUBKU"] or _route().wps[0].kind != "fix" or _route().dest != "VAPO" or changed[0] != 1:
		return "named click: %s dest %s (changed %d)" % [_ids(), _route().dest, changed[0]]
	var spot := Vector2(10000.0, 5000.0)
	p._on_map_click(spot, "", false)
	var w: Dictionary = _route().wps.back()
	if _ids() != ["MUBKU", "WPT01"] or w.kind != "user" or Vector2(w.x, w.y) != spot or w.alt_ft != _route().cruise_ft:
		return "empty click: %s %s" % [_ids(), w]
	p._on_map_click(d.position_of("VAPO"), "VAPO", false)
	p._on_map_click(d.position_of("VABB"), "VABB", false)
	if _ids().size() != 2 or not p.note.text.contains("departure"):
		return "the destination and departure are not added again: %s / %s" % [_ids(), p.note.text]
	if p.selected != 1 or p.nav_log.rows.size() != 3:
		return "the new waypoint is selected (%d) and the log has 3 legs (%d)" % [p.selected, p.nav_log.rows.size()]
	return ""


func test_route_page_remove_insert_on_leg_and_drag() -> String:
	var p := _open({"route": {"dest": "VAPO"}})
	var d := RouteEdit.db()
	p.add_point(d.position_of("PUN"), "PUN")
	p.add_point(Vector2(0.0, 0.0), "")
	p.insert_on_leg(1, Vector2(20000.0, 0.0), "")  # on the PUN -> WPT01 leg
	if _ids() != ["PUN", "WPT02", "WPT01"]:
		return "insert on leg: %s" % [_ids()]
	p.drag_waypoint(2, Vector2(1000.0, 2000.0), "")
	var w: Dictionary = _route().wps[2]
	if w.id != "WPT01" or Vector2(w.x, w.y) != Vector2(1000.0, 2000.0):
		return "a dragged free waypoint keeps its name and moves: %s" % [w]
	p.drag_waypoint(0, Vector2(-3000.0, 4000.0), "")
	if _route().wps[0].kind != "user" or _ids()[0] == "PUN":
		return "a named point dragged to empty map becomes a free waypoint: %s" % [_route().wps[0]]
	p.drag_waypoint(0, Vector2.ZERO, "MUBKU")
	if _ids()[0] != "MUBKU" or _route().wps[0].kind != "fix":
		return "dropped on a fix it becomes that fix: %s" % [_route().wps[0]]
	p.map.wp_removed.emit(1)  # right-click on the map
	if _ids() != ["MUBKU", "WPT01"]:
		return "remove: %s" % [_ids()]
	p.nav_log.rows[1].del.pressed.emit()
	p.nav_log.rows[0].down.pressed.emit()
	if _ids() != ["MUBKU"] or p.nav_log.rows.size() != 2:
		return "the log's remove button: %s" % [_ids()]
	return ""


func test_route_page_auto_direct_sets_destination_without_waypoints() -> String:
	var p := _open()
	p.auto_route("direct")
	if RouteEdit.planned(_route()) or not p.note.text.contains("destination"):
		return "no destination: nothing is built and the note says why (%s)" % p.note.text
	p.set_destination("VAPO")
	p.add_point(Vector2(0.0, 0.0), "")
	p.auto_route("direct")
	var r := _route()
	if r.dest != "VAPO" or not r.wps.is_empty() or r.kind != "direct" or p.auto_seg.get_value() != "direct":
		return "direct: %s" % [r]
	if FlowValues.rail_value("route", Session.setup).find("VABB → VAPO · direct") != 0:
		return "rail: " + FlowValues.rail_value("route", Session.setup)
	p.clear_route()
	if RouteEdit.planned(_route()) or FlowValues.rail_value("route", Session.setup) != "Not planned":
		return "clear: %s" % [_route()]
	return ""


func test_route_page_typed_route_and_altitude() -> String:
	var p := _open()
	p.text_box.text = "VABB DCT MUBKU PUN VAPO"
	p.enter_text(p.text_box.text)
	if _route().dest != "VAPO" or _ids() != ["MUBKU", "PUN"]:
		return "typed: %s -> %s" % [_route().dest, _ids()]
	p.nav_log.rows[1].alt.value = 6000.0  # typing an altitude in the log
	if _route().wps[1].alt_ft != 6000.0:
		return "log altitude: %s" % [_route().wps[1]]
	p.enter_text("VABB NOTAFIX VAPO")
	if _ids() != ["MUBKU", "PUN"] or p.note.get_theme_color("font_color") != MenuTheme.WARN:
		return "a bad route keeps the old one and warns: %s / %s" % [_ids(), p.note.text]
	return ""


func test_route_page_start_on_leg_only_for_air_starts() -> String:
	var p := _open({"start": "runway", "route": {"dest": "VAPO", "wps": [{"id": "PUN", "kind": "vor", "x": 54276.0, "y": -18773.0, "alt_ft": 4500.0}]}})
	if p.start_opt.visible or not p.start_note.text.contains("In the air"):
		return "runway start: the leg choice is hidden with a note (%s)" % p.start_note.text
	Session.setup.start = "air"
	p._refresh(false)
	if not p.start_opt.visible or p.start_opt.item_count != 3 or p.start_opt.selected != 0:
		return "air start: final + 2 legs, final chosen (%s, %d items)" % [p.start_opt.visible, p.start_opt.item_count]
	p.start_opt.select(2)
	p.start_opt.item_selected.emit(2)
	if _route().air_at != 1:
		return "on leg 2: air_at %d" % _route().air_at
	p.remove_waypoint(0)  # one leg left: leg 2 is gone, the start goes back to final
	if _route().air_at != -1 or p.start_opt.item_count != 2:
		return "a start leg that went away resets: %d" % _route().air_at
	return ""


func test_route_page_shows_the_profile_and_the_fuel_line() -> String:
	var p := _open()
	if p.profile == null or not p.profile.samples.is_empty() or p.nav_log.fuel.visible:
		return "no route: an empty profile and no fuel line"
	if not p.plans.save_btn.disabled or not p.plans.export_btn.disabled or p.plans.load_btn.disabled:
		return "no route: Save and Export greyed, Load open"
	p.set_destination("VAPO")
	p.auto_route("direct")
	if p.profile.samples.size() < 100 or not p.profile.caption.begins_with("Highest ground"):
		return "VABB-VAPO (62 nm) sampled every half mile: %d samples, '%s'" % [p.profile.samples.size(), p.profile.caption]
	if not p.nav_log.fuel.visible or not p.nav_log.fuel.text.begins_with("Fuel  Trip ") or not p.nav_log.fuel.text.contains("on board 34 gal"):
		return "fuel line: " + p.nav_log.fuel.text
	if p.plans.save_btn.disabled or p.plans.export_btn.disabled:
		return "a route: Save and Export open"
	Session.setup.fuel_gal = 3.0
	p._refresh(false)
	if p.nav_log.fuel.get_theme_color("font_color") != MenuTheme.BAD:
		return "6 gal for trip + reserve: the fuel line is red"
	return ""


func test_route_page_plans_save_load_and_a_new_departure() -> String:
	var keep_dir := PlanStore.dir
	PlanStore.dir = "user://test_page_plans/"
	var p := _open()
	p.set_destination("VAPO")
	p.auto_route("direct")
	p.plans.open_save()
	var d: RoutePlanDialog = p.plans.dialog
	var err := ""
	if d == null or d.name_box.text != "VABB to VAPO":
		err = "the save dialog suggests the route's name"
	else:
		p.plans.save_as(d.name_box.text)
		if p.plans.dialog != null or not PlanStore.exists("VABB to VAPO"):
			err = "saved and closed"
	if err == "":
		Session.setup.airport = "VAPO"
		p.clear_route()
		var msgs := []
		p.plans.loaded.connect(func(t, _w): msgs.append(t))
		p.plans.load_plan("vabb_to_vapo")
		if Session.setup.airport != "VABB" or Session.setup.runway != "" or _route().dest != "VAPO":
			err = "loading puts back the departure and the route: %s %s" % [Session.setup.airport, _route()]
		elif msgs.is_empty() or not str(msgs[0]).contains("departure is now VABB") or p.controls.from_label.text.begins_with("VAPO"):
			err = "tells the player and repaints: %s / %s" % [msgs, p.controls.from_label.text]
	for f in DirAccess.get_files_at(PlanStore.dir):
		DirAccess.remove_absolute(PlanStore.dir.path_join(f))
	PlanStore.dir = keep_dir
	return err


func test_route_page_pln_export_then_import() -> String:
	var p := _open()
	p.set_destination("VAPO")
	p.auto_route("vor")
	var want := _ids()
	var text: String = p.plans.export_text()
	if not text.contains("<DepartureID>VABB</DepartureID>") or not text.contains("<DestinationID>VAPO</DestinationID>"):
		return "export: " + text.left(300)
	p.clear_route()
	var r: Dictionary = p.plans.import_text(text, "x.pln")
	if not r.ok or _ids() != want or _route().dest != "VAPO":
		return "import gives the same route: %s vs %s (%s)" % [_ids(), want, r]
	if p.plans.import_text("<nope/>", "bad.pln").ok:
		return "a file that is not a plan is refused"
	return ""


func test_airport_page_follows_a_departure_set_by_a_plan() -> String:
	_open()
	var ap: Control = PageFrame.make_page("res://ui/menu/airport_page.gd")
	add_child(ap)
	ap.visible = false
	Session.setup.airport = "VAPO"  # what PlanStore.apply does when a plan starts elsewhere
	Session.setup.runway = ""
	ap.visible = true
	var got := str(ap._cur.get("icao", ""))
	ap.free()
	if got != "VAPO" or Session.setup.airport != "VAPO":
		return "shown again, the Airport step shows the plan's departure: %s" % got
	return ""
