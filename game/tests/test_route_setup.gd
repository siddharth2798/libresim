extends RefCounted
## core/route_setup.gd and core/route_air_start.gd: the planned route (Session.setup.route) going into the flight. GPS
## target and route, user waypoints resolvable by every NavDatabase, MCDU INIT prefilled for airliners, ATC naming the
## route's destination, the session repairing a damaged route, and the air start on a route leg (pure maths).
## Made-up nav world: tests/route_fixture.gd. The Props this touches are put back after each test.

const Fx := preload("res://tests/route_fixture.gd")
const KEYS := ["controls/gps/target", "controls/gps/route_next", "route/dest", "mcdu/init/from_to", "mcdu/init/dep_rwy",
	"mcdu/init/arr_rwy", "mcdu/init/cruise_fl", "controls/fms/origin", "controls/fcu/alt_ft", "controls/fcu/vs_managed",
	"fdm/position_enu", "fdm/wow", "mcdu/scratch", "controls/fcu/hdg_managed", "controls/throttle", "controls/fcu/athr",
	"controls/fcu/spd_managed"]
const FILE := "user://test_route_session.json"

var _saved := {}
var _setup := {}
var _path := ""


func _keep() -> void:
	if not _saved.is_empty():
		return
	for k in KEYS:
		_saved[k] = Props.get_v(k, null) if Props.has(k) else "<none>"
	_setup = Session.setup.duplicate(true)
	_path = Session.save_path


func teardown() -> void:
	NavDatabase.route_fixes.clear()
	if _saved.is_empty():
		return
	for k in _saved:
		if str(_saved[k]) == "<none>":
			Props._p.erase(k)
		else:
			Props.set_v(k, _saved[k])
	Session.setup = _setup
	Session.save_path = _path
	Session.training = ""
	_saved = {}
	if FileAccess.file_exists(FILE):
		DirAccess.remove_absolute(FILE)


func _setup_with(route: Dictionary, start := "runway", runway := "18") -> Dictionary:
	var s: Dictionary = Session.DEFAULT.duplicate(true)
	s.airport = "AAAA"
	s.start = start
	s.runway = runway
	s.route = route
	return s


func _route() -> Dictionary:
	return {"dest": "BBBB", "arr_rwy": "36", "cruise_ft": 4500.0, "kind": "manual", "air_at": -1,
		"wps": [{"id": "FA", "kind": "fix", "x": Fx.p(0, 10).x, "y": Fx.p(0, 10).y, "alt_ft": 6500.0},
			{"id": "WPT01", "kind": "user", "x": 1000.0, "y": 50000.0, "alt_ft": 5500.0}]}


func test_route_setup_apply_sets_the_gps_route() -> String:
	_keep()
	var db := Fx.db()
	RouteSetup.clear()
	RouteSetup.apply(_setup_with(_route()), db, false)
	var tgt := str(Props.get_v("controls/gps/target", ""))
	var nxt: Array = Props.get_v("controls/gps/route_next", [])
	if tgt != "AAAA18D" or nxt != ["FA", "WPT01", "BBBB36F", "BBBB"]:
		return "runway fix, waypoints, final fix, destination: %s %s" % [tgt, nxt]
	if str(Props.get_v("route/dest", "")) != "BBBB":
		return "route/dest %s" % Props.get_v("route/dest")
	var air := _setup_with(_route(), "stand", "")
	RouteSetup.apply(air, db, false)
	if str(Props.get_v("controls/gps/target", "")) != "FA":
		return "a stand start has no departure fix: %s" % Props.get_v("controls/gps/target")
	return ""


func test_route_setup_user_waypoint_resolves_in_the_flight() -> String:
	_keep()
	RouteSetup.clear()
	if Fx.db().position_of("WPT01") != null:
		return "WPT01 resolves before the route is applied"
	RouteSetup.apply(_setup_with(_route()), Fx.db(), false)
	var other := NavDatabase.new()  # the flight's own database, built elsewhere
	var p: Variant = other.position_of("WPT01")
	if p == null or not (p as Vector2).is_equal_approx(Vector2(1000.0, 50000.0)):
		return "user waypoint in any NavDatabase: %s" % [p]
	var plan := RoutePlan.from_idents(str(Props.get_v("controls/gps/target")), Props.get_v("controls/gps/route_next"), Fx.db().position_of)
	if plan.wps.size() != 5:
		return "the GPS drops a route waypoint: %s" % [plan.wps]
	RouteSetup.clear()
	if other.position_of("WPT01") != null:
		return "the next flight still knows WPT01"
	return ""


func test_route_setup_empty_route_leaves_gps_empty() -> String:
	_keep()
	Props.set_v("controls/gps/target", "OLD")
	Props.set_v("controls/gps/route_next", ["X"])
	RouteSetup.clear()
	for r in [{}, {"dest": "", "wps": []}, "junk"]:
		var s := _setup_with({})
		s.route = r
		RouteSetup.apply(s, Fx.db(), true)
		if str(Props.get_v("controls/gps/target", "")) != "" or not (Props.get_v("controls/gps/route_next", []) as Array).is_empty():
			return "no route: GPS %s %s" % [Props.get_v("controls/gps/target"), Props.get_v("controls/gps/route_next")]
	if RouteSetup.active({}) or RouteSetup.active("junk") or not RouteSetup.active({"dest": "BBBB"}):
		return "active()"
	return ""


func test_route_setup_prefills_the_mcdu_init() -> String:
	_keep()
	RouteSetup.clear()
	Props.set_v("controls/fcu/vs_managed", false)
	Props.set_v("controls/fcu/hdg_managed", false)
	Props.set_v("controls/fcu/spd_managed", false)
	RouteSetup.apply(_setup_with(_route()), Fx.db(), true)
	if not Props.get_b("controls/fcu/hdg_managed"):
		return "the route selects NAV (managed heading), as filing INIT does, so the autopilot flies it"
	if not Props.get_b("controls/fcu/spd_managed"):
		return "the route selects managed speed, so the climb, cruise and approach speeds are the FMS ones (not a selected 250 kt)"
	var got := [Props.get_v("mcdu/init/from_to"), Props.get_v("mcdu/init/dep_rwy"), Props.get_v("mcdu/init/arr_rwy"),
		Props.get_v("mcdu/init/cruise_fl"), Props.get_v("controls/fms/origin"), Props.get_f("controls/fcu/alt_ft")]
	if got != ["AAAA/FA/WPT01/BBBB", "18", "36", 65.0, "AAAA", 6500.0] or not Props.get_b("controls/fcu/vs_managed"):
		return "INIT %s managed %s" % [got, Props.get_b("controls/fcu/vs_managed")]
	# filing that INIT page by hand gives the same GPS route
	var want := [Props.get_v("controls/gps/target"), Props.get_v("controls/gps/route_next")]
	var m := MCDU.new()
	Props.set_v("fdm/wow", true)  # filed at the gate
	Props.set_v("controls/fcu/spd_managed", false)
	m._file_route(str(Props.get_v("mcdu/init/from_to")))
	var filed := [Props.get_v("controls/gps/target"), Props.get_v("controls/gps/route_next")]
	var spd := Props.get_b("controls/fcu/spd_managed")
	m.free()
	if filed != want:
		return "INIT filing %s, route setup %s" % [filed, want]
	if not spd:
		return "filing FROM/TO on the ground selects managed speed, as a Route-step route does"
	return ""


func test_route_setup_atc_uses_the_route_destination() -> String:
	_keep()
	var airports := [{"icao": "AAAA", "ident": "AAAA", "name": "Alpha Airport", "type": "medium_airport", "x": 0.0, "y": 0.0},
		{"icao": "BBBB", "ident": "BBBB", "name": "Bravo Field Airport", "type": "medium_airport", "x": 0.0, "y": 50000.0},
		{"icao": "LLLL", "ident": "LLLL", "name": "Lima International Airport", "type": "large_airport", "x": 150000.0, "y": 0.0}]
	var env := AtcWorld.make_env(airports, {}, [], {})
	env.has_rwy["AAAA"] = true
	Props.set_v("fdm/position_enu", Vector3.ZERO)
	Props.set_v("fdm/wow", true)
	Props.set_v("route/dest", "")
	var auto_dest := str(AtcWorld.snapshot(env, 0.0).dest)
	Props.set_v("route/dest", "BBBB")
	var planned := str(AtcWorld.snapshot(env, 0.0).dest)
	if auto_dest != "Lima" or planned != "Bravo Field":
		return "automatic %s, planned %s" % [auto_dest, planned]
	if AtcProfile.dest_text({"dest": planned}) != "Bravo Field":
		return "clearance wording"
	return ""


func test_route_setup_session_repairs_a_damaged_route() -> String:
	_keep()
	Session.save_path = FILE
	var cases := [["junk", {}], [{"dest": "BBBB", "wps": "x"}, ["BBBB", 0]],
		[{"dest": "BBBB", "air_at": 1.0, "wps": [{"id": "FA", "x": 1.0, "y": 2.0}, {"id": "NOY", "x": 1.0}, "bad",
			{"id": "", "x": 1.0, "y": 2.0}, {"id": "wpt02", "x": 3, "y": 4, "alt_ft": 7000.0}]}, ["BBBB", 2]]]
	for c in cases:
		var f := FileAccess.open(FILE, FileAccess.WRITE)
		f.store_string(JSON.stringify({"route": c[0]}))
		f.close()
		Session.setup = Session.DEFAULT.duplicate(true)
		Session._load()
		var r = Session.setup.get("route")
		if not r is Dictionary:
			return "route not a dictionary after load: %s" % [r]
		if c[1] is Dictionary:
			if not r.is_empty():
				return "junk route: %s" % [r]
			continue
		if r.get("dest") != c[1][0] or not r.get("wps") is Array or r.wps.size() != c[1][1]:
			return "repaired %s from %s" % [r, c[0]]
	var r: Dictionary = Session.setup.route
	if r.wps[1].id != "WPT02" or r.wps[1].kind != "user" or r.wps[0].alt_ft != 4500.0 or r.air_at != 1 or typeof(r.air_at) != TYPE_INT:
		return "repaired waypoints %s" % [r]
	return ""


func test_route_setup_lesson_and_saved_flight() -> String:
	_keep()
	Session.setup.route = _route()
	Session.begin_lesson("x", {"airport": "VAJJ"}, "full")
	var in_lesson: Dictionary = Session.setup.route
	Session.end_lesson()
	if not in_lesson.is_empty():
		return "a lesson must not fly the planned route: %s" % [in_lesson]
	Situation.apply_setup({"airport": "AAAA", "route": {"dest": "BBBB", "wps": [{"id": "WPT01", "x": 7.0, "y": 8.0}, "bad"]}})
	if Session.setup.route.wps.size() != 1:
		return "saved flight route not repaired: %s" % [Session.setup.route]
	NavDatabase.route_fixes.clear()
	RouteSetup.restore(Session.setup, Fx.db(), true)
	if Fx.db().position_of("WPT01") != Vector2(7.0, 8.0) or str(Props.get_v("route/dest")) != "BBBB":
		return "restored flight: WPT01 %s dest %s" % [Fx.db().position_of("WPT01"), Props.get_v("route/dest")]
	if str(Props.get_v("mcdu/init/from_to")) != "AAAA/WPT01/BBBB":
		return "restored INIT %s" % Props.get_v("mcdu/init/from_to")
	return ""


func test_route_setup_air_start_gps_and_leg() -> String:
	var s := _setup_with(_route(), "air", "18")
	s.route.air_at = 1
	if RouteSetup.air_leg(s) != 1:
		return "air_leg %d" % RouteSetup.air_leg(s)
	var plan := RouteSetup.gps_plan(s, func(_id): return true)
	if plan.target != "WPT01" or plan.next != ["BBBB36F", "BBBB"] or plan.dep_rwy != "":
		return "leg 1 flies point 2 (WPT01) first, no departure fix: %s" % [plan]
	s.route.air_at = 9
	if RouteSetup.air_leg(s) != 2:
		return "air_at past the last leg is the last leg: %d" % RouteSetup.air_leg(s)
	s.start = "runway"
	if RouteSetup.air_leg(s) != -1:
		return "air_at only counts for an air start"
	if RouteSetup.leg_alts(RouteSetup.repair(_route())) != [6500.0, 5500.0, 5500.0]:
		return "leg altitudes %s" % [RouteSetup.leg_alts(RouteSetup.repair(_route()))]
	return ""


func test_route_air_start_placement_maths() -> String:
	var flat := func(_x, _y): return 0.0
	var pts := [Vector2.ZERO, Fx.p(0, 10), Fx.p(10, 10)]
	var pl := RouteAirStart.placement(pts, [3000.0, 5000.0], 1, flat)
	if not (pl.pos as Vector2).is_equal_approx(Fx.p(2, 10)) or absf(pl.hdg_deg - 90.0) > 0.01 or absf(pl.alt_m - 1524.0) > 0.1 or pl.target != 2:
		return "2 nm past point 1, heading east, 5000 ft: %s" % [pl]
	var short := RouteAirStart.placement([Vector2.ZERO, Vector2(0.0, 2000.0)], [2000.0], 0, flat)
	if not (short.pos as Vector2).is_equal_approx(Vector2(0.0, 1000.0)) or absf(short.hdg_deg) > 0.01:
		return "mid-leg on a short leg: %s" % [short]
	var ridge := func(_x, y): return 1500.0 if y > Fx.p(0, 3).y else 100.0  # high ground 1 nm ahead of the start point
	var hill := RouteAirStart.placement(pts, [3000.0, 5000.0], 0, ridge)
	if absf(hill.alt_m - (1500.0 + 304.8)) > 0.1:
		return "at least 1000 ft above the ground ahead: %.1f m" % hill.alt_m
	return ""


func test_route_air_start_cruise_speed_and_spawn() -> String:
	var c172 := AircraftDef.load_def("c172")
	var a320 := AircraftDef.load_def("a320")
	if RouteAirStart.cruise_kias(c172, 4500.0) != 110.0:
		return "C172 cruise %.0f" % RouteAirStart.cruise_kias(c172, 4500.0)
	if RouteAirStart.cruise_kias(a320, 8000.0) != 250.0:
		return "A320 below 10,000 ft %.0f" % RouteAirStart.cruise_kias(a320, 8000.0)
	if RouteAirStart.cruise_kias(a320, 24000.0) != 280.0:
		return "A320 at FL240 flies the managed cruise speed (280 kt), not 0.85 x Vmo: %.0f" % RouteAirStart.cruise_kias(a320, 24000.0)
	_keep()
	Props.set_v("controls/throttle", 0.9)
	Props.set_v("controls/fcu/athr", false)
	RouteAirStart.cruise_state()
	if not is_equal_approx(Props.get_f("controls/throttle"), AfThrust.CL) or not Props.get_b("controls/fcu/athr") or not Props.get_b("controls/fcu/spd_managed"):
		return "airliner cruise state: levers CL, A/THR armed, managed speed"
	var high := RouteAirStart.cruise_kias(a320, 35000.0)
	if high < 220.0 or high > 260.0:
		return "A320 at FL350 (Mach limit) %.0f" % high
	var own := AircraftDef.make("x", {"start": {"air": {"cruise_kias": 135}}, "limits": {"vs1_kias": 50.0, "vne_kias": 200.0}}, "res://aircraft/c172")
	if RouteAirStart.cruise_kias(own, 3000.0) != 135.0 or RouteAirStart.cruise_kias(AircraftDef.make("y", {}, "res://aircraft/c172"), 3000.0) != 100.0:
		return "own %.0f, none %.0f" % [RouteAirStart.cruise_kias(own, 3000.0), RouteAirStart.cruise_kias(AircraftDef.make("y", {}, "res://aircraft/c172"), 3000.0)]
	var s := _setup_with(_route(), "air", "")
	var base := {"kias": 70.0, "asked": -1.0, "gear_up": false, "flaps": 3}
	if RouteAirStart.spawn(c172, s, base) != base:
		return "air_at -1 keeps the final-approach start"
	s.route.air_at = 0
	var sp := RouteAirStart.spawn(a320, s, base)
	if sp.kias != 250.0 or not sp.gear_up or sp.flaps != 0:
		return "on the route: cruise speed, clean: %s" % [sp]
	return ""
