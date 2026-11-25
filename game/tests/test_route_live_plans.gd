extends "res://tests/route_live_base.gd"
## Saved plans and .PLN files on the pause screen's Edit route (ui/route_live_page.gd, core/route_live_plan.gd): Save and
## Export write the whole route (flown waypoints too); Load and Import replace only the route ahead, from the present
## position (waypoints behind the aircraft left out), never change the departure, and reach the flight only on Apply. The
## Save / Load dialog sits over the pause screen, which leaves Esc to it (modal_open).

const Pause := preload("res://ui/pause_menu.gd")
const DIR := "user://test_live_plans/"

var _dir := ""


class StubFdm extends Node:
	var paused := false
	var replaying := false


class StubFlight extends Node:
	var fdm_node := StubFdm.new()
	var _apt := "VABB"


func _plans_dir() -> void:
	if _dir == "":
		_dir = PlanStore.dir
		PlanStore.dir = DIR


func teardown() -> void:
	if _dir != "":
		for f in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute(DIR.path_join(f))
		PlanStore.dir = _dir
		_dir = ""
	AudioSettings.hold_game(false)
	super.teardown()


# ---- the rules (made-up world) ----

func test_waypoints_behind_the_aircraft_are_left_out() -> String:
	var d := Fx.db()
	var r := {"dest": "BBBB", "wps": [{"id": "FA", "x": Fx.p(0, 10).x, "y": Fx.p(0, 10).y},
		{"id": "WPT01", "x": Fx.p(10, 40).x, "y": Fx.p(10, 40).y}, {"id": "FB", "x": Fx.p(30, 100).x, "y": Fx.p(30, 100).y}]}
	var dep: Vector2 = d.position_of("AAAA")
	var dest: Vector2 = d.position_of("BBBB")
	var cases := [[Fx.p(0, -5), 0], [Fx.p(1, 5), 0], [Fx.p(2, 20), 1], [Fx.p(25, 90), 2], [Fx.p(10, 190), 3]]
	for c in cases:
		var n := RouteLivePlan.behind(r, dep, dest, c[0])
		if n != c[1]:
			return "at %s nm: %d behind, want %d" % [c[0] / Fx.NM, n, c[1]]
	if RouteLivePlan.behind(r, null, dest, Fx.p(0, 5)) != 0:
		return "without a known departure, short of the first waypoint nothing is behind"
	return ""


func test_a_plan_from_another_airport_keeps_the_flights_departure() -> String:
	var d := Fx.db()
	var flight := {"airport": "AAAA", "aircraft": "c172"}
	var plan := {"name": "From Charlie", "departure": "CCCC", "aircraft": "c172", "route": {"dest": "BBBB", "cruise_ft": 4500.0,
		"wps": [{"id": "FA", "kind": "fix", "x": Fx.p(0, 10).x, "y": Fx.p(0, 10).y}, {"id": "FB", "kind": "fix", "x": Fx.p(30, 100).x,
		"y": Fx.p(30, 100).y}]}}
	var res := RouteLivePlan.take(plan, flight, Fx.p(2, 20), d)
	if not res.ok or Fx.ids(res.route.wps) != ["FB"] or res.route.dest != "BBBB" or res.dropped != 1:
		return "the route ahead is FB then BBBB (FA behind): %s" % [res]
	if flight.airport != "AAAA" or not "CCCC" in str(res.text) or not "stays AAAA" in str(res.text) or not res.warn:
		return "the note tells the player the departure stays: %s" % res.text
	var gone := RouteLivePlan.take({"name": "x", "departure": "AAAA", "route": {"wps": plan.route.wps}}, flight, Fx.p(30, 120), d)
	if gone.ok:
		return "a plan wholly behind the aircraft is refused"
	return ""


# ---- the pause page (real nav data) ----

func _page() -> Control:
	var d := RouteEdit.db()
	if d.position_of("VAPO") == null or d.position_of("MUBKU") == null:
		return null
	_keep()
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
	return page


func test_save_and_export_write_the_whole_route_with_the_edit() -> String:
	_plans_dir()
	var page := _page()
	if page == null:
		return ""
	var rp: Control = page.page
	if not rp.plans.visible or rp.start.visible:
		return "in flight the plan buttons show (not the air-start leg)"
	rp.add_point(Vector2(40000.0, -15000.0), "")
	rp.plans.save_as("In the air")
	var p := PlanStore.read("in_the_air")
	if p.is_empty() or p.departure != "VABB" or Fx.ids(p.route.wps) != ["WPT01", "MUBKU", "WPT02"] or p.route.dest != "VAPO":
		return "saved: the flown WPT01, then the edited route ahead: %s" % [p]
	var pln: String = rp.plans.export_text()
	if not "<DepartureID>VABB</DepartureID>" in pln or not 'id="WPT01"' in pln or not 'id="WPT02"' in pln:
		return "export writes the whole route from VABB"
	if _gps() != ["MUBKU", "VAPO"]:
		return "saving changes nothing in the flight: %s" % [_gps()]
	return ""


func test_load_replaces_only_the_route_ahead_on_apply() -> String:
	_plans_dir()
	var page := _page()
	if page == null:
		return ""
	var rp: Control = page.page
	var mub: Vector2 = RouteEdit.db().position_of("MUBKU")
	var plan := {"dest": "VAPO", "cruise_ft": 6500.0, "wps": [{"id": "WPT01", "kind": "user", "x": 10000.0, "y": -2000.0},
		{"id": "WPT05", "kind": "user", "x": 40000.0, "y": -15000.0}, {"id": "MUBKU", "kind": "fix", "x": mub.x, "y": mub.y}]}
	PlanStore.save("Other way", {"airport": "VABB", "aircraft": str(Session.setup.aircraft), "route": plan})
	rp.plans.load_plan("other_way")
	if Fx.ids(RouteEdit.route_of(rp.live).wps) != ["WPT05", "MUBKU"] or not "1 waypoint behind" in rp.note.text:
		return "the route ahead is the plan after the aircraft: %s (%s)" % [Fx.ids(RouteEdit.route_of(rp.live).wps), rp.note.text]
	if _gps() != ["MUBKU", "VAPO"] or not page.status.text.begins_with("Not applied"):
		return "nothing reaches the flight before Apply: %s / %s" % [_gps(), page.status.text]
	page.apply()
	if _gps() != ["WPT05", "MUBKU", "VAPO"] or Session.setup.airport != "VABB":
		return "Apply flies it from the present position: %s" % [_gps()]
	if Fx.ids(Session.setup.route.wps) != ["WPT01", "WPT05", "MUBKU"]:
		return "the flown waypoints stay in front: %s" % [Fx.ids(Session.setup.route.wps)]
	return ""


func test_import_from_another_departure_never_moves_the_flight() -> String:
	var page := _page()
	if page == null:
		return ""
	var rp: Control = page.page
	var mub: Vector2 = RouteEdit.db().position_of("MUBKU")
	var other := {"airport": "VAPO", "aircraft": "c172", "route": {"dest": "VABB", "cruise_ft": 5500.0,
		"wps": [{"id": "MUBKU", "kind": "fix", "x": mub.x, "y": mub.y, "alt_ft": 5500.0}]}}
	var text := PlanFile.write(PlanImport.from_setup(other, RouteEdit.db()))
	var res: Dictionary = rp.plans.import_text(text, "back.pln")
	if not res.ok:
		return "import: %s" % res
	rp.plans.loaded.emit(str(res.text), bool(res.warn))
	if RouteEdit.route_of(rp.live).dest != "VABB" or Session.setup.airport != "VABB" or not "stays VABB" in rp.note.text:
		return "a plan from VAPO brings its destination, not its departure: %s / %s" % [RouteEdit.route_of(rp.live).dest, rp.note.text]
	page.cancel()
	if _gps() != ["MUBKU", "VAPO"] or str(Session.setup.route.dest) != "VAPO":
		return "Cancel drops the import: %s" % [_gps()]
	return ""


func test_plan_dialog_sits_over_the_pause_screen_and_takes_esc() -> String:
	_plans_dir()
	var f := StubFlight.new()
	f.add_child(f.fdm_node)
	add_child(f)
	_nodes.append(f)
	var p := Control.new()
	p.set_script(Pause)
	p.set("flight", f)
	f.add_child(p)
	if _page() == null:
		return ""
	p.open()
	p.show_page("route")
	var rp: Control = p._pages["route"].page
	rp.plans.open_load()
	var dlg: Node = rp.plans.dialog
	if dlg == null or dlg.get_parent() != p or not p.modal_open():
		return "the plan dialog goes over the whole pause screen: parent %s" % [dlg.get_parent() if dlg else null]
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	p._input(esc)  # the dialog takes Esc first in the real tree; the pause screen must not also go back
	if p.cur != "route" or not p.visible or not f.fdm_node.paused:
		return "Esc with the dialog open keeps the pause screen on Edit route (%s)" % p.cur
	dlg.close()
	if not p.visible or not Props.get_b("ui/pause_open"):
		return "closing the dialog leaves the flight paused"
	p.close()
	return ""

