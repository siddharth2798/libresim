extends RefCounted
## avionics/route_builder.gd (+ route_airways.gd): the Route step's automatic routes (direct, VOR/NDB hops, airways),
## the text entry, one waypoint by ident and free user waypoints. Made-up nav world: tests/route_fixture.gd.

const Fx := preload("res://tests/route_fixture.gd")


func teardown() -> void:
	NavDatabase.route_fixes.clear()


func test_route_builder_direct_has_no_waypoints() -> String:
	var r := RouteBuilder.auto("direct", "AAAA", "BBBB", Fx.db(), 4500.0)
	if not r.ok or not (r.wps as Array).is_empty() or r.error != "":
		return "direct: %s" % [r]
	return ""


func test_route_builder_vor_hops_via_the_station_on_the_way() -> String:
	var db := Fx.db()
	var r := RouteBuilder.auto("vor", "AAAA", "BBBB", db, 5500.0)
	if not r.ok or Fx.ids(r.wps) != ["V1"]:
		return "200 nm trip should hop via V1 (not V2 off the line, not N1 beside the airport): %s" % [r]
	var w: Dictionary = r.wps[0]
	if w.kind != "vor" or not is_equal_approx(w.alt_ft, 5500.0) or not Vector2(w.x, w.y).is_equal_approx(Fx.p(5, 100)):
		return "waypoint dict: %s" % [w]
	var short := RouteBuilder.auto("vor", "AAAA", "CCCC", db, 4500.0)
	if not short.ok or not (short.wps as Array).is_empty():
		return "a 60 nm trip with no station near the line stays direct: %s" % [short]
	var far := RouteBuilder.auto("vor", "AAAA", "ZZZZ", db, 4500.0)
	if far.ok or not str(far.error).contains("VOR"):
		return "no station chain to ZZZZ must be an error: %s" % [far]
	return ""


func test_route_builder_airway_shortest_path_honours_direction() -> String:
	var db := Fx.db()
	var south_north := RouteBuilder.auto("airway", "AAAA", "BBBB", db, 9000.0)
	if not south_north.ok or Fx.ids(south_north.wps) != ["FA", "FB", "FC"]:
		return "J9 is one way north to south, so AAAA-BBBB flies W1: %s" % [south_north]
	var north_south := RouteBuilder.auto("airway", "BBBB", "AAAA", db, 9000.0)
	if not north_south.ok or Fx.ids(north_south.wps) != ["FC", "FX", "FA"]:
		return "BBBB-AAAA takes the shorter one-way J9: %s" % [north_south]
	if north_south.wps[0].kind != "fix" or not is_equal_approx(north_south.wps[0].alt_ft, 9000.0):
		return "fix waypoint: %s" % [north_south.wps[0]]
	return ""


func test_route_builder_airway_leaves_out_fixes_at_the_airports() -> String:
	var db := Fx.db()
	db.fixes["FN"] = Fx.p(0, 0.5)  # the airport's own VOR, 0.5 nm from AAAA, first fix of W1
	db.airways["W1"].fixes = ["FN", "FA", "FB", "FC"]
	var r := RouteBuilder.auto("airway", "AAAA", "BBBB", db, 9000.0)
	if not r.ok or Fx.ids(r.wps) != ["FA", "FB", "FC"]:
		return "a fix within 3 nm of the departure is no waypoint (0.5 nm first leg): %s" % [r]
	return ""


func test_route_builder_airway_errors() -> String:
	var db := Fx.db()
	var island := RouteBuilder.auto("airway", "ZZZZ", "AAAA", db, 9000.0)
	if island.ok or not str(island.error).contains("No airway route"):
		return "Q2 near ZZZZ joins nothing: %s" % [island]
	db.airways.erase("Q2")
	var none := RouteBuilder.auto("airway", "ZZZZ", "AAAA", db, 9000.0)
	if none.ok or not str(none.error).contains("within 60 nm of ZZZZ"):
		return "no airway near ZZZZ: %s" % [none]
	return ""


func test_route_builder_unknown_idents() -> String:
	var db := Fx.db()
	var r := RouteBuilder.auto("direct", "AAAA", "NOPE", db, 4500.0)
	if r.ok or not str(r.error).contains("NOPE"):
		return "unknown destination: %s" % [r]
	r = RouteBuilder.auto("vor", "XXXX", "AAAA", db, 4500.0)
	if r.ok or not str(r.error).contains("XXXX"):
		return "unknown departure: %s" % [r]
	if not RouteBuilder.waypoint("NOPE", db, 4500.0).is_empty():
		return "waypoint() of an unknown ident must be {}"
	var p := RouteBuilder.parse("AAAA XYZZY BBBB", "AAAA", db, 4500.0)
	if p.ok or not str(p.error).contains("XYZZY"):
		return "parse with an unknown ident: %s" % [p]
	return ""


func test_route_builder_parse_text() -> String:
	var db := Fx.db()
	var r := RouteBuilder.parse("aaaa dct FA W1 FC BBBB", "AAAA", db, 6000.0)
	if not r.ok or r.dest != "BBBB" or Fx.ids(r.wps) != ["FA", "FB", "FC"]:
		return "DCT dropped, W1 expanded, departure ignored, last airport = destination: %s" % [r]
	r = RouteBuilder.parse("AAAA/V1/BBBB", "AAAA", db, 6000.0)
	if not r.ok or r.dest != "BBBB" or Fx.ids(r.wps) != ["V1"] or r.wps[0].kind != "vor":
		return "slash form: %s" % [r]
	r = RouteBuilder.parse("V1 FB", "AAAA", db, 6000.0)
	if not r.ok or r.dest != "" or Fx.ids(r.wps) != ["V1", "FB"]:
		return "no departure given, last ident not an airport: %s" % [r]
	r = RouteBuilder.parse("  ", "AAAA", db, 6000.0)
	if not r.ok or r.dest != "" or not (r.wps as Array).is_empty():
		return "empty text = no route: %s" % [r]
	return ""


func test_route_builder_parse_wrong_airway_direction() -> String:
	var r := RouteBuilder.parse("AAAA FA J9 FC BBBB", "AAAA", Fx.db(), 6000.0)
	if r.ok or not str(r.error).contains("J9") or not str(r.error).contains("one way"):
		return "J9 flown against its direction must be refused: %s" % [r]
	r = RouteBuilder.parse("AAAA FA W1 FQ1 BBBB", "AAAA", Fx.db(), 6000.0)
	if r.ok or not str(r.error).contains("not both on airway W1"):
		return "exit not on the airway: %s" % [r]
	return ""


func test_route_builder_waypoint_kinds() -> String:
	var db := Fx.db()
	var want := {"aaaa": "airport", "V1": "vor", "N1": "ndb", "FB": "fix", "AAAA18D": "fix"}
	for id in want:
		var w := RouteBuilder.waypoint(id, db, 3000.0)
		if w.is_empty() or w.kind != want[id] or w.id != id.to_upper() or not is_equal_approx(w.alt_ft, 3000.0):
			return "%s: %s" % [id, w]
	return ""


func test_route_builder_user_waypoint_takes_the_next_free_id() -> String:
	var w := RouteBuilder.user_waypoint(Vector2(100.0, -200.0), [], 3500.0)
	if w.id != "WPT01" or w.kind != "user" or not is_equal_approx(w.x, 100.0) or not is_equal_approx(w.y, -200.0) or not is_equal_approx(w.alt_ft, 3500.0):
		return "first: %s" % [w]
	var used := [{"id": "WPT01"}, {"id": "FA"}, {"id": "WPT03"}]
	if RouteBuilder.user_waypoint(Vector2.ZERO, used, 3500.0).id != "WPT02":
		return "a gap is reused: %s" % [RouteBuilder.user_waypoint(Vector2.ZERO, used, 3500.0)]
	used.append({"id": "WPT02"})
	if RouteBuilder.user_waypoint(Vector2.ZERO, used, 3500.0).id != "WPT04":
		return "after WPT01-03: %s" % [RouteBuilder.user_waypoint(Vector2.ZERO, used, 3500.0)]
	return ""
