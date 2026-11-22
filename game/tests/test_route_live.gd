extends "res://tests/route_live_base.gd"
## Editing the route during the flight (core/route_live.gd, RouteSetup.update_live, ui/map/map_route_edit.gd, the N map's
## Edit route mode and the pause screen's Edit route page): the route ahead starts at the active GPS waypoint, edits keep
## or advance the active waypoint, route waypoints / route/dest / MCDU follow, the GPS re-reads a moved free waypoint,
## the A320 MCDU (F-PLN, FROM/TO, CRZ FL; DEP RWY and the FCU kept), and a save keeps the edited route. The editors' UI:
## tests/test_route_live_ui.gd. Made-up nav world: tests/route_fixture.gd. Props and Session.setup are put back after
## each test.


func test_live_split_starts_at_the_active_waypoint() -> String:
	var d := _flying()
	var sp := RouteLive.split(Session.setup, d)
	if Fx.ids(sp.passed) != ["FA"] or Fx.ids(sp.route.wps) != ["WPT01", "FB"] or sp.route.dest != "BBBB" or sp.first != "WPT01":
		return "split: passed %s ahead %s dest %s first %s" % [Fx.ids(sp.passed), Fx.ids(sp.route.wps), sp.route.dest, sp.first]
	if Vector2(sp.route.wps[0].x, sp.route.wps[0].y) != Fx.p(10, 40) or float(sp.route.wps[0].alt_ft) != 5500.0:
		return "the free waypoint keeps its place and altitude: %s" % [sp.route.wps[0]]
	var r := RouteEdit.route_of(Session.setup)
	var lead := RouteLive.split_ids(r, ["AAAA18D", "FA", "WPT01", "FB", "BBBB36F", "BBBB"], d)
	if lead.lead != ["AAAA18D"] or Fx.ids(lead.route.wps) != ["FA", "WPT01", "FB"] or not lead.passed.is_empty():
		return "runway fixes: lead %s ahead %s" % [lead.lead, Fx.ids(lead.route.wps)]
	var off := RouteLive.split_ids(r, ["V2", "CCCC"], d)
	if Fx.ids(off.route.wps) != ["V2"] or off.route.dest != "CCCC" or not off.passed.is_empty():
		return "a GPS route off the plan is the route ahead: %s -> %s" % [Fx.ids(off.route.wps), off.route.dest]
	var s := RouteLive.edit_setup(Session.setup, sp.route, RouteLive.here(), false)
	var legs := RouteEdit.legs(s, d, 100.0)
	if legs.size() != 3 or legs[0].a != Fx.p(2, 20) or legs[0].from != RouteLive.PPOS or int(legs[0].wp) != 0:
		return "the editors' legs start at the present position: %s" % [legs.map(func(l): return [l.from, l.ident])]
	return ""


func test_live_update_keeps_or_advances_the_active_waypoint() -> String:
	var d := _flying()
	var sp := RouteLive.split(Session.setup, d)
	var r: Dictionary = sp.route.duplicate(true)
	RouteOps.add(r, Fx.p(40, 150), "", d)  # a point near the end: the active waypoint stays
	RouteLive.commit(sp, r, d, false)
	if _gps() != ["WPT01", "FB", "WPT02", "BBBB"]:
		return "added at the end: GPS %s" % [_gps()]
	if Fx.ids(Session.setup.route.wps) != ["FA", "WPT01", "FB", "WPT02"]:
		return "the plan keeps the flown waypoints: %s" % [Fx.ids(Session.setup.route.wps)]
	sp = RouteLive.split(Session.setup, d)
	r = sp.route.duplicate(true)
	RouteOps.remove(r, 0)  # the active waypoint goes: the next one ahead takes over
	RouteLive.commit(sp, r, d, false)
	if _gps() != ["FB", "WPT02", "BBBB"]:
		return "active waypoint removed: GPS %s" % [_gps()]
	sp = RouteLive.split(Session.setup, d)
	r = sp.route.duplicate(true)
	RouteOps.insert(r, 0, Fx.p(5, 50), "", d)  # a point on the leg from the aircraft is flown first
	RouteLive.commit(sp, r, d, false)
	if _gps().size() != 4 or _gps()[1] != "FB" or not str(_gps()[0]).begins_with("WPT") or _gps()[0] == "WPT02":
		return "inserted on the active leg: GPS %s" % [_gps()]
	_flying("FB", ["BBBB"])  # WPT01 is behind: a free point added ahead must not take its name
	sp = RouteLive.split(Session.setup, d)
	r = sp.route.duplicate(true)
	RouteOps.add(r, Fx.p(40, 150), "", d)
	RouteLive.commit(sp, r, d, false)
	if Fx.ids(Session.setup.route.wps) != ["FA", "WPT01", "FB", "WPT02"] or _gps() != ["FB", "WPT02", "BBBB"] \
			or NavDatabase.route_fixes.get("WPT01") != Fx.p(10, 40):
		return "a new free waypoint is named apart from the flown ones: %s GPS %s" % [Fx.ids(Session.setup.route.wps), _gps()]
	_flying("AAAA18D", ["FA", "WPT01", "FB", "BBBB"])
	sp = RouteLive.split(Session.setup, d)
	r = sp.route.duplicate(true)
	RouteOps.remove(r, 2)
	RouteLive.commit(sp, r, d, false)
	if _gps() != ["AAAA18D", "FA", "WPT01", "BBBB"]:
		return "the departure fix stays while the first point ahead does: %s" % [_gps()]
	return ""


func test_live_update_moves_route_fixes_atc_destination_and_the_gps() -> String:
	var d := _flying()
	Props.set_v("controls/fcu/alt_ft", 7000.0)
	var gps := Gps.new()
	gps.db = d
	_nodes.append(gps)
	gps._sync(Fx.p(2, 20))
	var sp := RouteLive.split(Session.setup, d)
	var r: Dictionary = sp.route.duplicate(true)
	RouteOps.drag(r, 0, Fx.p(-10, 45), "", d)  # WPT01 moved: it keeps its name
	r.dest = "CCCC"
	RouteLive.commit(sp, r, d, false)
	if NavDatabase.route_fixes.get("WPT01") != Fx.p(-10, 45) or str(Props.get_v("route/dest")) != "CCCC":
		return "route fixes / ATC: WPT01 %s dest %s" % [NavDatabase.route_fixes.get("WPT01"), Props.get_v("route/dest")]
	if _gps() != ["WPT01", "FB", "CCCC"] or float(Props.get_v("controls/fcu/alt_ft")) != 7000.0:
		return "GPS %s, FCU altitude %s (must stay)" % [_gps(), Props.get_v("controls/fcu/alt_ft")]
	gps._sync(Fx.p(2, 21))
	if gps.plan.active().get("pos") != Fx.p(-10, 45):
		return "the GPS still flies the old WPT01 position: %s" % [gps.plan.active()]
	return ""


func test_live_update_refiles_the_a320_mcdu() -> String:
	var d := _flying("WPT01", ["FB", "BBBB"], "18")
	RouteSetup.apply(Session.setup, d, true)  # the flight start files INIT: DEP RWY 18, CRZ FL 55
	if str(Props.get_v("mcdu/init/dep_rwy")) != "18" or float(Props.get_v("mcdu/init/cruise_fl")) != 55.0:
		return "INIT at the start: DEP RWY %s CRZ FL %s" % [Props.get_v("mcdu/init/dep_rwy"), Props.get_v("mcdu/init/cruise_fl")]
	Props.set_v("controls/gps/target", "WPT01")  # flown past the departure fix and FA
	Props.set_v("controls/gps/route_next", ["FB", "BBBB"])
	Props.set_v("controls/fcu/alt_ft", 7000.0)  # the pilot's
	var sp := RouteLive.split(Session.setup, d)
	var r: Dictionary = sp.route.duplicate(true)
	RouteEdit.set_cruise(r, 9500.0)
	RouteOps.click(r, d.position_of("V1"), "V1", false, "", d)
	RouteLive.commit(sp, r, d, true)
	if MCDU.route() != ["WPT01", "FB", "V1", "BBBB"]:
		return "MCDU F-PLN: %s" % [MCDU.route()]
	if str(Props.get_v("mcdu/init/from_to")) != "AAAA/FA/WPT01/FB/V1/BBBB" or not Props.get_b("controls/fcu/hdg_managed"):
		return "MCDU INIT %s, NAV %s" % [Props.get_v("mcdu/init/from_to"), Props.get_v("controls/fcu/hdg_managed")]
	if float(Props.get_v("mcdu/init/cruise_fl")) != 95.0 or str(Props.get_v("mcdu/init/dep_rwy")) != "18":
		return "after the edit: CRZ FL %s (want 95), DEP RWY %s (want 18)" % [Props.get_v("mcdu/init/cruise_fl"), Props.get_v("mcdu/init/dep_rwy")]
	if float(Props.get_v("controls/fcu/alt_ft")) != 7000.0 or not Props.get_b("controls/fcu/vs_managed"):
		return "the FCU is the pilot's: altitude %s, managed vertical %s" % [Props.get_v("controls/fcu/alt_ft"), Props.get_v("controls/fcu/vs_managed")]
	return ""


func test_live_edit_survives_save_and_load() -> String:
	var d := _flying("WPT01", ["FB", "BBBB"], "18")
	Props.set_v("mcdu/init/dep_rwy", "18")
	var sp := RouteLive.split(Session.setup, d)
	var r: Dictionary = sp.route.duplicate(true)
	RouteOps.drag(r, 0, Fx.p(-10, 45), "", d)
	RouteOps.add(r, Fx.p(20, 160), "", d)
	RouteEdit.set_cruise(r, 8000.0)
	RouteLive.commit(sp, r, d, true)
	var want := _gps()
	var fl := float(Props.get_v("mcdu/init/cruise_fl"))
	var props := {}
	for k in Props.dump("controls/"):
		props[k] = Situation._enc(Props.get_v(k))
	var saved: Dictionary = JSON.parse_string(JSON.stringify({"setup": Session.setup.duplicate(true), "props": props}))
	Session.setup = Session.DEFAULT.duplicate(true)
	NavDatabase.route_fixes.clear()
	Props.set_v("controls/gps/target", "")
	Props.set_v("controls/gps/route_next", [])
	Situation.apply_setup(saved.setup)
	var back := {}
	for k in saved.props:
		back[k] = Situation._dec(saved.props[k])
	Props.restore(back)
	RouteSetup.restore(Session.setup, d, true)
	if Fx.ids(Session.setup.route.wps) != ["FA", "WPT01", "FB", "WPT02"] or _gps() != want:
		return "loaded: plan %s GPS %s (want %s)" % [Fx.ids(Session.setup.route.wps), _gps(), want]
	if d.position_of("WPT01") != Fx.p(-10, 45) or d.position_of("WPT02") != Fx.p(20, 160) or str(Props.get_v("route/dest")) != "BBBB":
		return "loaded waypoints: WPT01 %s WPT02 %s" % [d.position_of("WPT01"), d.position_of("WPT02")]
	if str(Props.get_v("mcdu/init/dep_rwy")) != "18" or float(Props.get_v("mcdu/init/cruise_fl")) != fl or fl != 80.0:
		return "loaded MCDU: DEP RWY %s CRZ FL %s (saved %s)" % [Props.get_v("mcdu/init/dep_rwy"), Props.get_v("mcdu/init/cruise_fl"), fl]
	return ""
