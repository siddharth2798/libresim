extends Node
## Lite flight-management route (avionics/flight_plan.gd). No scene and no nav database:
## the tests pass their own ident check.


func _known(id: String) -> bool:
	return id in ["VABB", "BBB", "VAPO", "VOCL", "VAGO"]


func test_flight_plan_files_origin_then_route() -> String:
	var known := Callable(self, "_known")
	var f := FlightPlan.file(FlightPlan.split_from_to(" VABB / BBB / VAPO "), known)
	if not f.ok or f.origin != "VABB" or f.target != "BBB" or f.next != ["VAPO"]:
		return "file %s" % f
	var one := FlightPlan.file(["VAPO"], known)
	if one.target != "VAPO" or not one.next.is_empty() or one.origin != "":
		return "one ident is a direct-to, got %s" % one
	var bad := FlightPlan.file(["VABB", "XXXX"], known)
	if bad.ok or bad.error != FlightPlan.NOT_IN_DB:
		return "an unknown ident must reject the whole route"
	if FlightPlan.file([], known).ok:
		return "an empty route must not file"
	return ""


func test_flight_plan_direct_inserts_or_skips() -> String:
	var known := Callable(self, "_known")
	var ins := FlightPlan.direct("VAGO", "VABB", ["VAPO", "VOCL"], known)
	if ins.target != "VAGO" or ins.next != ["VABB", "VAPO", "VOCL"] or ins.scratch != "" or ins.error != "":
		return "insert %s" % ins
	var skip := FlightPlan.direct("VOCL", "VABB", ["VAPO", "VOCL"], known)
	if skip.target != "VOCL" or not skip.next.is_empty():
		return "skip %s" % skip
	var copy := FlightPlan.direct("", "VABB", ["VAPO"], known)
	if copy.scratch != "VABB" or copy.target != "VABB" or copy.next != ["VAPO"]:
		return "copy %s" % copy
	var unk := FlightPlan.direct("XXXX", "VABB", ["VAPO"], known)
	if unk.error != FlightPlan.NOT_IN_DB or unk.target != "VABB" or unk.next != ["VAPO"]:
		return "reject %s" % unk
	return ""


func test_flight_plan_edit_replaces_and_appends() -> String:
	var known := Callable(self, "_known")
	var rep := FlightPlan.edit(["VABB", "VAPO"], 1, "BBB", known)
	if rep.wps != ["VABB", "BBB"] or rep.scratch != "" or rep.error != "":
		return "replace %s" % rep
	var add := FlightPlan.edit(["VABB"], 5, "VAPO", known)
	if add.wps != ["VABB", "VAPO"]:
		return "append %s" % add
	var cp := FlightPlan.edit(["VABB", "VAPO"], 0, "", known)
	if cp.scratch != "VABB" or cp.wps != ["VABB", "VAPO"]:
		return "copy line %s" % cp
	var bad := FlightPlan.edit(["VABB"], 0, "XXXX", known)
	if bad.error != FlightPlan.NOT_IN_DB or bad.wps != ["VABB"]:
		return "unknown edit %s" % bad
	return ""


func test_airway_expands_between_fixes() -> String:
	var aw := {"W1": {"fixes": ["BBB", "MID", "BIA"], "direction": "both"},
		"W2": {"fixes": ["BIA", "OPABA", "CLC"], "direction": "forward"}}
	var go = Airway.expand(["VABB", "BBB", "W1", "BIA", "VAPO"], aw)
	if not go.ok or go.parts != ["VABB", "BBB", "MID", "BIA", "VAPO"]:
		return "expand %s" % go
	var back = Airway.expand(["BIA", "W1", "BBB"], aw)
	if back.parts != ["BIA", "MID", "BBB"]:
		return "reverse %s" % back
	var off = Airway.expand(["VABB", "W1", "VAPO"], aw)
	if off.ok or off.error != Airway.NOT_ON:
		return "not on airway %s" % off
	var way = Airway.expand(["CLC", "W2", "BIA"], aw)
	if way.ok or way.error != Airway.WRONG_WAY:
		return "one way %s" % way
	var plain = Airway.expand(["VABB", "BBB", "VAPO"], {})
	if plain.parts != ["VABB", "BBB", "VAPO"]:
		return "no database %s" % plain
	var filed := FlightPlan.file(go.parts, Callable(self, "_known_airway"))
	if filed.origin != "VABB" or filed.target != "BBB" or filed.next != ["MID", "BIA", "VAPO"]:
		return "filed %s" % filed
	return ""


func _known_airway(id: String) -> bool:
	return id in ["VABB", "BBB", "MID", "BIA", "VAPO", "OPABA", "CLC"]


func test_published_w56_when_the_database_is_present() -> String:
	if not FileAccess.file_exists(Paths.data("airways.json")):
		return ""
	var db := NavDatabase.new()
	var exp: Dictionary = Airway.expand(["BBB", "W56", "BIA"], db.airways)
	if not exp.ok or exp.parts.size() < 4 or str(exp.parts[0]) != "BBB" or str(exp.parts.back()) != "BIA":
		return "W56 %s" % exp
	for id in exp.parts:
		if db.position_of(str(id)) == null:
			return "no position for %s" % id
	return ""


func test_flight_plan_inserts_runway_fixes() -> String:
	var known := Callable(self, "_known")
	var filed := FlightPlan.file(FlightPlan.split_from_to("VABB/BBB/VAPO"), known)
	var both := FlightPlan.with_procedures(filed, "27", "10")
	if both.target != "VABB27D" or both.next != ["BBB", "VAPO10F", "VAPO"] or both.origin != "VABB":
		return "both %s" % both
	var dep := FlightPlan.with_procedures(filed, "9L", "")
	if dep.target != "VABB09LD" or dep.next != ["BBB", "VAPO"]:
		return "dep %s" % dep
	var direct := FlightPlan.with_procedures(FlightPlan.file(["VAPO"], known), "27", "10")
	if direct.target != "VAPO" or not direct.next.is_empty():
		return "direct-to stays %s" % direct
	return ""


func test_runway_fix_geometry() -> String:
	var airports: Array = [{"ident": "VAPO", "icao": "VAPO", "elev_m": 500.0, "runways": [
		{"le": {"ident": "10", "x": 0.0, "y": 0.0, "heading_true": 90.0},
			"he": {"ident": "28", "x": 3000.0, "y": 0.0, "heading_true": 270.0}}]}]
	var dep = RunwayWaypoints.position("VAPO10D", airports)
	var expect_dep := Vector2(RunwayWaypoints.DEP_M, 0.0)
	if dep == null or Vector2(dep).distance_to(expect_dep) > 1.0:
		return "departure %s" % dep
	var arr = RunwayWaypoints.position("VAPO28F", airports)
	var expect_arr := Vector2(3000.0 + RunwayWaypoints.ARR_M, 0.0)
	if arr == null or Vector2(arr).distance_to(expect_arr) > 1.0:
		return "arrival %s" % arr
	if RunwayWaypoints.position("VAPO99D", airports) != null or not RunwayWaypoints.parse("BBB").is_empty():
		return "unknown runway or a navaid must not parse as a fix"
	return ""


func test_vertical_profile_tod() -> String:
	var far: Dictionary = VerticalProfile.decide(35000.0, 35000.0, 200.0, 0.0)
	if far.descend or far.phase != "CRZ" or far.approach_ft != 3000.0:
		return "far %s" % far
	var near: Dictionary = VerticalProfile.decide(35000.0, 35000.0, 100.0, 0.0)
	if not near.descend or near.phase != "DES" or absf(float(near.tod_nm) - (32000.0 / 300.0 + 8.0)) > 0.1:
		return "near %s" % near
	var climb: Dictionary = VerticalProfile.decide(35000.0, 10000.0, 200.0, 0.0)
	if climb.descend or climb.phase != "CLB":
		return "climb %s" % climb
	var low: Dictionary = VerticalProfile.decide(4000.0, 4000.0, 10.0, 500.0)
	if low.approach_ft != 1500.0 or not low.descend:
		return "low cruise %s" % low
	return ""


func test_fms_profile_commands_descent() -> String:
	var saved := Props.dump("")
	var db := NavDatabase.new()
	var ap: Dictionary = db.airport("VAPO")
	if ap.is_empty():
		Props._p.clear()
		Props.restore(saved)
		return "VAPO missing from airports.json"
	var err := ""
	var pos = db.position_of("VAPO28D")
	var end := RunwayWaypoints.runway_end(db.airports, "VAPO", "28")
	if pos == null or end.is_empty():
		err = "VAPO28D not in the nav database"
	else:
		var hdg := deg_to_rad(float(end.heading_true))
		var expect: Vector2 = Vector2(end.x, end.y) + Vector2(sin(hdg), cos(hdg)) * RunwayWaypoints.DEP_M
		if Vector2(pos).distance_to(expect) > 1.0:
			err = "VAPO28D geometry"
	if err == "" and db.position_of("VAPO99D") != null:
		err = "missing runway resolved"
	var g := Gps.new()
	_made.append(g)
	g.db = db
	if err == "":
		err = _descent_from(g, ap)
	Props._p.clear()
	Props.restore(saved)
	return err


var _made: Array = []


func teardown() -> void:
	for n in _made:
		if is_instance_valid(n):
			n.free()
	_made.clear()


func _descent_from(g: Gps, ap: Dictionary) -> String:
	Props.set_v("controls/gps/target", "VAPO")
	Props.set_v("controls/gps/route_next", [])
	Props.set_v("mcdu/init/cruise_fl", 350.0)
	Props.set_v("controls/fcu/vs_managed", true)
	Props.set_v("controls/fcu/alt_ft", 35000.0)
	Props.set_v("controls/fcu/vert_select", "")
	Props.set_v("fdm/wow", false)
	Props.set_v("systems/electrical/avionics_powered", true)
	Props.set_v("failures/gps", false)
	var alt_m := Units.ft_to_m(35000.0)
	Props.set_v("fdm/position_enu", Vector3(ap.x, float(ap.y) + 10.0 * 1852.0, alt_m))
	g._physics_process(0.05)
	var got := Props.get_f("controls/fcu/alt_ft")
	if got > 8000.0 or str(Props.get_v("avionics/fms/phase")) != "DES":
		return "TOD alt %s phase %s" % [got, Props.get_v("avionics/fms/phase")]
	Props.set_v("controls/fcu/alt_ft", 35000.0)
	Props.set_v("fdm/position_enu", Vector3(ap.x, float(ap.y) + 200.0 * 1852.0, alt_m))
	g._physics_process(0.05)
	if absf(Props.get_f("controls/fcu/alt_ft") - 35000.0) > 1.0 or str(Props.get_v("avionics/fms/phase")) != "CRZ":
		return "cruise hold %s %s" % [Props.get_f("controls/fcu/alt_ft"), Props.get_v("avionics/fms/phase")]
	Props.set_v("fdm/position_enu", Vector3(ap.x, float(ap.y) + 200.0 * 1852.0, Units.ft_to_m(10000.0)))
	g._physics_process(0.05)
	if str(Props.get_v("avionics/fms/phase")) != "CLB" or absf(Props.get_f("controls/fcu/alt_ft") - 35000.0) > 1.0:
		return "climb %s %s" % [Props.get_v("avionics/fms/phase"), Props.get_f("controls/fcu/alt_ft")]
	return ""
