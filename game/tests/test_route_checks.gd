extends RefCounted
## Route step checks: the vertical profile against the terrain (core/route_terrain.gd, over a made-up height function),
## the route fuel (core/route_fuel.gd, both aircraft) and the route problems SetupChecks gets from core/route_checks.gd
## (ids and levels, the rail level, the "Fly anyway?" reasons). Nav world: tests/route_fixture.gd (AAAA (0, 0), BBBB
## (0, 200 nm)); one test reads the real runway data.

const Fx := preload("res://tests/route_fixture.gd")
const NM := 1852.0
const FT := 0.3048


func teardown() -> void:
	RouteChecks._db = null
	RouteChecks.height_override = Callable()
	RouteTerrain._memo_sig = ""


func _flat(m: float) -> Callable:
	return func(_x: float, _y: float) -> float: return m


func _ridge(m: float, from_nm: float, to_nm: float) -> Callable:  # a wall across the north axis
	return func(_x: float, y: float) -> float: return m if y >= from_nm * NM and y <= to_nm * NM else 0.0


func _setup(route: Dictionary, extra := {}) -> Dictionary:
	var s: Dictionary = Session.DEFAULT.duplicate(true)
	s.airport = "AAAA"
	s.runway = "18"
	s.route = route
	s.wind_kt = 0.0
	s.merge(extra, true)
	return s


func _direct(alt := 4500.0) -> Dictionary:
	return {"dest": "BBBB", "arr_rwy": "", "wps": [], "cruise_ft": alt, "kind": "direct", "air_at": -1}


func _route_ids(s: Dictionary) -> Dictionary:  # id -> level of the route step's checks
	var out := {}
	for c in SetupChecks.checks(s, {"ident": "18", "length_m": 3000.0, "heading_deg": 180.0}):
		if c.step == "route":
			out[c.id] = c.level
	return out


func test_profile_samples_every_half_mile_with_the_leg_ends() -> String:
	var pts := [Vector2.ZERO, Fx.p(0, 10), Fx.p(10, 10)]
	var s := RouteTerrain.sample(pts, [3000.0, 4000.0], _flat(100.0))
	if s.is_empty() or float(s[0].d_m) != 0.0 or absf(float(s.back().d_m) - 20.0 * NM) > 0.01:
		return "samples should run from 0 to 20 nm: %s .. %s" % [s.front(), s.back()]
	for i in range(1, s.size()):
		if float(s[i].d_m) - float(s[i - 1].d_m) > RouteTerrain.STEP_M + 0.01:
			return "gap over half a mile at sample %d" % i
	var at_turn := s.filter(func(x): return absf(float(x.d_m) - 10.0 * NM) < 0.01)
	if at_turn.size() != 1:
		return "the waypoint itself should be sampled once, got %d" % at_turn.size()
	if s[3].alt_ft != 3000.0 or s.back().alt_ft != 4000.0 or s.back().leg != 1:
		return "leg altitudes: leg k flies alts[k]"
	if absf(float(s[5].terrain_ft) - 100.0 / FT) > 0.01:
		return "terrain in feet"
	return ""


func test_profile_finds_a_leg_below_and_near_the_terrain() -> String:
	var pts := [Vector2.ZERO, Fx.p(0, 20), Fx.p(0, 40)]
	var ridge := _ridge(1500.0, 24.0, 26.0)  # 4921 ft, on the second leg
	var v := RouteTerrain.verdict(RouteTerrain.sample(pts, [6000.0, 4500.0], ridge))
	if v.below_leg != 1 or v.low_leg != 1 or v.leg != 1:
		return "4500 ft over a 4921 ft ridge on leg 2 is below the terrain: %s" % v
	v = RouteTerrain.verdict(RouteTerrain.sample(pts, [4500.0, 5500.0], ridge))
	if v.below_leg != -1 or v.low_leg != 1 or absf(float(v.clear_ft) - (5500.0 - 1500.0 / FT)) > 1.0:
		return "5500 ft over the ridge clears it by under 1000 ft only: %s" % v
	v = RouteTerrain.verdict(RouteTerrain.sample(pts, [4500.0, 6000.0], ridge))
	if v.low_leg != -1 or v.below_leg != -1:
		return "6000 ft clears the ridge by over 1000 ft: %s" % v
	var low := RouteTerrain.sample(pts, [4500.0, 5500.0], ridge).filter(RouteTerrain.is_low)
	if low.is_empty() or low.any(func(x): return float(x.d_m) < 24.0 * NM - 1.0 or float(x.d_m) > 26.0 * NM + 1.0):
		return "only the samples over the ridge are drawn red"
	return ""


func test_profile_does_not_judge_take_off_and_landing() -> String:
	var pts := [Vector2.ZERO, Fx.p(0, 20)]
	var hill := _ridge(800.0, 0.0, 1.5)  # 2625 ft within 2 nm of the departure
	var v := RouteTerrain.verdict(RouteTerrain.sample(pts, [2000.0], hill))
	if v.below_leg != -1 or v.low_leg != -1:
		return "terrain within 2 nm of the departure is the take-off: not judged (%s)" % v
	v = RouteTerrain.verdict(RouteTerrain.sample(pts, [2000.0], hill, false))
	if v.below_leg != 0:
		return "without a departure airport the first point is an ordinary waypoint: judged"
	if absf(float(v.top_ft) - 800.0 / FT) > 0.1:
		return "top_ft counts terminal samples too"
	return ""


func test_profile_path_follows_route_setup_leg_alts() -> String:
	var r := {"dest": "BBBB", "arr_rwy": "", "cruise_ft": 4500.0, "kind": "manual", "air_at": -1,
		"wps": [{"id": "FA", "kind": "fix", "x": Fx.p(0, 10).x, "y": Fx.p(0, 10).y, "alt_ft": 6500.0},
			{"id": "WPT01", "kind": "user", "x": 1000.0, "y": 50000.0, "alt_ft": 5500.0}]}
	var p := RouteTerrain.path(_setup(r), Fx.db())
	if p.pts.size() != 4 or p.alts != RouteSetup.leg_alts(RouteSetup.repair(r)) or not p.dep or not p.dest:
		return "dep, 2 wps, dest; alts = RouteSetup.leg_alts: %s" % p
	var s := _setup(r)
	s.airport = "NOPE"
	p = RouteTerrain.path(s, Fx.db())
	if p.pts.size() != 3 or p.alts != [5500.0, 5500.0] or p.dep:
		return "unknown departure: the route starts at the first waypoint: %s" % p
	return ""


func test_fuel_c172_trip_reserve_and_levels() -> String:
	var ac := AircraftDef.load_def("c172").data
	var f := RouteFuel.estimate(ac, 124.0 * NM, 124.0, 34.0)  # one hour
	if f.unit != "gal" or absf(f.trip - 9.0) > 0.001 or f.reserve != 3.0 or f.level != "ok":
		return "C172: an hour at 9 gph + 3 gal reserve: %s" % f
	if RouteFuel.text(f) != "Trip 9 gal + reserve 3 gal · on board 34 gal":
		return "text: " + RouteFuel.text(f)
	if RouteFuel.estimate(ac, 124.0 * NM, 124.0, 11.9).level != "bad":
		return "under trip + reserve (12 gal) is bad"
	if RouteFuel.estimate(ac, 124.0 * NM, 124.0, 14.0).level != "warn":
		return "landing with 5 gal (under twice the reserve) is thin"
	if RouteFuel.estimate(ac, 124.0 * NM, 124.0, 15.0).level != "ok":
		return "landing with twice the reserve is fine"
	return ""


func test_fuel_a320_in_kg_and_default_reserve() -> String:
	var ac := AircraftDef.load_def("a320").data
	var f := RouteFuel.estimate(ac, 450.0 * NM, 450.0, 8500.0)
	if f.unit != "kg" or absf(f.trip - 2500.0) > 0.01 or f.reserve != 1800.0 or f.level != "ok":
		return "A320: an hour at 2500 kg/h + 1800 kg reserve: %s" % f
	if RouteFuel.text(f) != "Trip 2,500 kg + reserve 1,800 kg · on board 8,500 kg":
		return "text: " + RouteFuel.text(f)
	if RouteFuel.estimate(ac, 450.0 * NM, 450.0, 4000.0).level != "bad":
		return "4000 kg < 4300 kg needed"
	var bare := ac.duplicate(true)
	bare.payload.erase("reserve_kg")
	if RouteFuel.estimate(bare, 450.0 * NM, 450.0, 8500.0).reserve != 1250.0:
		return "no reserve given: 30 min at cruise burn"
	if RouteFuel.cruise_kt("a320") != 450.0 or RouteFuel.cruise_kt("c172") != 124.0:
		return "cruise speeds from the specs"
	return ""


func test_fuel_for_setup_counts_the_route_from_the_air_start_leg() -> String:
	RouteChecks._db = Fx.db()
	var r := {"dest": "BBBB", "arr_rwy": "", "cruise_ft": 4500.0, "kind": "manual", "air_at": 1,
		"wps": [{"id": "CCCC", "kind": "airport", "x": Fx.p(0, 60).x, "y": Fx.p(0, 60).y, "alt_ft": 4500.0}]}
	var full := RouteFuel.for_setup(_setup(r), Fx.db())
	var air := RouteFuel.for_setup(_setup(r, {"start": "air"}), Fx.db())
	if absf(full.trip - 200.0 / 124.0 * 9.0) > 0.01 or absf(air.trip - 140.0 / 124.0 * 9.0) > 0.01:
		return "200 nm on the ground, 140 nm from leg 2 in the air: %s / %s" % [full.trip, air.trip]
	if absf(full.on_board - 34.0) > 0.001:
		return "on board = both tanks"
	return ""


func test_checks_route_terrain_bad_and_low_warn() -> String:
	RouteChecks._db = Fx.db()
	RouteChecks.height_override = _flat(0.0)
	var ids := _route_ids(_setup(_direct()))
	if not ids.is_empty():
		return "a flat world and fuel enough: no route problems, got %s" % ids
	RouteChecks.height_override = _ridge(1500.0, 90.0, 110.0)
	var s := _setup(_direct())
	ids = _route_ids(s)
	if ids.get("route_terrain") != "bad":
		return "4500 ft into 4921 ft terrain is bad: %s" % ids
	var list := SetupChecks.checks(s, {"ident": "18", "length_m": 3000.0, "heading_deg": 180.0})
	if not SetupChecks.reasons(list).any(func(t): return t.contains("below the terrain") and t.contains("BBBB")):
		return "Fly anyway lists it: %s" % SetupChecks.reasons(list)
	if FlowValues.level("route", s, list) != "bad":
		return "the rail shows the route step bad"
	ids = _route_ids(_setup(_direct(5500.0)))
	if ids.get("route_low") != "warn" or ids.has("route_terrain"):
		return "5500 ft over it is a warning only: %s" % ids
	return ""


func test_checks_route_fuel_bad_and_thin() -> String:
	RouteChecks._db = Fx.db()
	RouteChecks.height_override = _flat(0.0)  # 200 nm: trip 14.5 gal + 3 reserve
	var ids := _route_ids(_setup(_direct(), {"fuel_gal": 8.0}))
	if ids.get("route_fuel") != "bad":
		return "16 gal for 17.5 needed is bad: %s" % ids
	ids = _route_ids(_setup(_direct(), {"fuel_gal": 10.0}))
	if ids.get("route_fuel_low") != "warn" or ids.has("route_fuel"):
		return "20 gal lands with 5.5 (under twice the reserve): a warning: %s" % ids
	var list := SetupChecks.checks(_setup(_direct(), {"fuel_gal": 8.0}), {"ident": "18", "length_m": 3000.0, "heading_deg": 180.0})
	if not SetupChecks.reasons(list).any(func(t): return t.begins_with("Not enough fuel")):
		return "Fly anyway lists the fuel"
	return ""


func test_checks_destination_runway_too_short_for_the_aircraft() -> String:
	RouteChecks.height_override = _flat(0.0)
	var r := {"dest": "VAAV", "arr_rwy": "", "wps": [], "cruise_ft": 24000.0, "kind": "direct", "air_at": -1}
	var s := _setup(r, {"airport": "VABB", "aircraft": "a320", "fuel_gal": 12000.0})
	if RouteChecks.db().position_of("VAAV") == null or SetupChecks.runway_of({"airport": "VAAV"}).is_empty():
		return ""  # no local nav / runway data
	var ids := _route_ids(s)
	if ids.get("route_dest_rwy") != "warn":
		return "Aamby Valley (1196 m) is too short for the A320 (1800 m): %s" % ids
	s.aircraft = "c172"
	s.fuel_gal = 17.0
	s.route.cruise_ft = 4500.0
	if _route_ids(s).has("route_dest_rwy"):
		return "fine for the C172"
	return ""
