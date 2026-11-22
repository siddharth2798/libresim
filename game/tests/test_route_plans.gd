extends RefCounted
## Saved route plans (core/plan_store.gd, in a test folder) and MSFS / Little Navmap .PLN files (core/plan_file.gd,
## core/plan_import.gd): save / list / load round trip, a different departure, .PLN export -> import round trip, a
## real-looking MSFS file and a Little Navmap one, waypoints outside the world, lat/lon accuracy (core/geo.gd).
## Nav world: tests/route_fixture.gd, except where a test says it reads the real data.

const Fx := preload("res://tests/route_fixture.gd")
const DIR := "user://test_plans/"
const NM := 1852.0

const MSFS := """<?xml version="1.0" encoding="UTF-8"?>

<SimBase.Document Type="AceXML" version="1,0">
    <Descr>AceXML Document</Descr>
    <FlightPlan.FlightPlan>
        <Title>VABB to VAPO</Title>
        <FPType>IFR</FPType>
        <RouteType>LowAlt</RouteType>
        <CruisingAlt>6500</CruisingAlt>
        <DepartureID>VABB</DepartureID>
        <DepartureLLA>N19° 5' 19.32",E72° 52' 4.43",+000039.00</DepartureLLA>
        <DestinationID>VAPO</DestinationID>
        <DestinationLLA>N18° 34' 55.56",E73° 55' 10.92",+001942.00</DestinationLLA>
        <Descr>VABB, VAPO</Descr>
        <DeparturePosition>27</DeparturePosition>
        <AppVersion>
            <AppVersionMajor>11</AppVersionMajor>
            <AppVersionBuild>282174</AppVersionBuild>
        </AppVersion>
        <ATCWaypoint id="VABB">
            <ATCWaypointType>Airport</ATCWaypointType>
            <WorldPosition>N19° 5' 19.32",E72° 52' 4.43",+000039.00</WorldPosition>
            <ICAO>
                <ICAOIdent>VABB</ICAOIdent>
            </ICAO>
        </ATCWaypoint>
        <ATCWaypoint id="CUST1">
            <ATCWaypointType>User</ATCWaypointType>
            <WorldPosition>N18° 50' 0.00",E73° 10' 0.00",+005500.00</WorldPosition>
        </ATCWaypoint>
        <ATCWaypoint id="VAPO">
            <ATCWaypointType>Airport</ATCWaypointType>
            <WorldPosition>N18° 34' 55.56",E73° 55' 10.92",+001942.00</WorldPosition>
            <ICAO>
                <ICAOIdent>VAPO</ICAOIdent>
            </ICAO>
        </ATCWaypoint>
    </FlightPlan.FlightPlan>
</SimBase.Document>
"""

# Little Navmap (MSFS export): a comment first, extra elements, ICAORegion, and an outside-the-world waypoint (Delhi).
const LNM := """<?xml version="1.0" encoding="UTF-8"?>
<!-- Built by Little Navmap version 2.8.12 -->
<SimBase.Document Type="AceXML" version="1,0">
  <Descr>AceXML Document</Descr>
  <FlightPlan.FlightPlan>
    <Title>AAAA to BBBB</Title>
    <FPType>VFR</FPType>
    <RouteType>Direct</RouteType>
    <CruisingAlt>4500</CruisingAlt>
    <DepartureID>AAAA</DepartureID>
    <DepartureLLA>N18° 45' 0.00",E73° 24' 0.00",+000033.00</DepartureLLA>
    <DestinationID>BBBB</DestinationID>
    <Descr>AAAA, BBBB</Descr>
    <DepartureName>Alpha Airport</DepartureName>
    <ATCWaypoint id="AAAA">
      <ATCWaypointType>Airport</ATCWaypointType>
      <WorldPosition>N18° 45' 0.00",E73° 24' 0.00",+000033.00</WorldPosition>
      <SpeedMaxFP>-1</SpeedMaxFP>
      <ICAO>
        <ICAOIdent>AAAA</ICAOIdent>
      </ICAO>
    </ATCWaypoint>
    <ATCWaypoint id="FA">
      <ATCWaypointType>Intersection</ATCWaypointType>
      <WorldPosition>%s</WorldPosition>
      <ATCAirway>W1</ATCAirway>
      <ICAO>
        <ICAORegion>VA</ICAORegion>
        <ICAOIdent>FA</ICAOIdent>
      </ICAO>
    </ATCWaypoint>
    <ATCWaypoint id="DELHI">
      <ATCWaypointType>User</ATCWaypointType>
      <WorldPosition>N28° 34' 0.00",E77° 6' 0.00",+004500.00</WorldPosition>
    </ATCWaypoint>
    <ATCWaypoint id="BBBB">
      <ATCWaypointType>Airport</ATCWaypointType>
      <WorldPosition>%s</WorldPosition>
      <ICAO>
        <ICAOIdent>BBBB</ICAOIdent>
      </ICAO>
    </ATCWaypoint>
  </FlightPlan.FlightPlan>
</SimBase.Document>
"""

var _dir := ""


func _keep() -> void:
	if _dir == "":
		_dir = PlanStore.dir
		PlanStore.dir = DIR


func teardown() -> void:
	if _dir != "":
		for f in DirAccess.get_files_at(DIR):
			DirAccess.remove_absolute(DIR.path_join(f))
		PlanStore.dir = _dir
		_dir = ""


func _inside(p: Vector2) -> bool:  # the made-up world: 300 nm around the origin
	return p.length() < 300.0 * NM


func _setup(route: Dictionary, airport := "AAAA") -> Dictionary:
	var s: Dictionary = Session.DEFAULT.duplicate(true)
	s.airport = airport
	s.runway = "18"
	s.route = route
	return s


func _route() -> Dictionary:
	return {"dest": "BBBB", "arr_rwy": "36", "cruise_ft": 4500.0, "kind": "manual", "air_at": -1,
		"wps": [{"id": "FA", "kind": "fix", "x": Fx.p(0, 10).x, "y": Fx.p(0, 10).y, "alt_ft": 6500.0},
			{"id": "V1", "kind": "vor", "x": Fx.p(5, 100).x, "y": Fx.p(5, 100).y, "alt_ft": 5500.0},
			{"id": "WPT01", "kind": "user", "x": 1000.0, "y": 50000.0, "alt_ft": 5500.0}]}


func _lla(p: Vector2, ft: float) -> String:
	var ll := Geo.to_latlon(p.x, p.y)
	return PlanFile.format_lla(ll.x, ll.y, ft)


func test_geo_matches_the_data_pipeline_positions() -> String:
	# airports.json x / y come from tools/common.py WORLD_PROJ (pyproj); lat / lon are the source.
	for a in [[19.088699, 72.867897, -55997.08, 37576.01], [18.5821, 73.919701, 54856.12, -18505.25],
			[10.151047, 76.400838, 328998.93, -949914.12]]:
		var e := Geo.to_enu(a[0], a[1])
		if e.distance_to(Vector2(a[2], a[3])) > 1.0:
			return "to_enu off by %.2f m at %s" % [e.distance_to(Vector2(a[2], a[3])), a]
		var ll := Geo.to_latlon(a[2], a[3])
		if absf(ll.x - a[0]) > 1e-5 or absf(ll.y - a[1]) > 1e-5:
			return "to_latlon off at %s: %s" % [a, ll]
	return ""


func test_lla_text_round_trip() -> String:
	var t := PlanFile.format_lla(18.758367, 73.4, 500.0)
	if t != "N18° 45' 30.12\",E73° 24' 0.00\",+000500.00":
		return "format: " + t
	var p := PlanFile.parse_lla(t)
	if absf(p.lat - 18.758367) > 1e-6 or absf(p.lon - 73.4) > 1e-9 or p.alt_ft != 500.0:
		return "parse: %s" % p
	var s := PlanFile.parse_lla("S12° 30.5',W45° 0' 36.00\",-000010.00")  # decimal minutes, south / west
	if absf(s.lat + 12.508333) > 1e-5 or absf(s.lon + 45.01) > 1e-6 or s.alt_ft != -10.0:
		return "south / west / decimal minutes: %s" % s
	var latin := PlanFile.parse_lla("N19° 5' 19.32\",E72* 52' 4.43\",+000039.00")
	if latin.is_empty() or absf(latin.lon - (72.0 + 52.0 / 60.0 + 4.43 / 3600.0)) > 1e-6:
		return "any degree sign: %s" % latin
	return ""


func test_plan_store_save_list_load_round_trip() -> String:
	_keep()
	var s := _setup(_route())
	if PlanStore.default_name(s) != "AAAA to BBBB":
		return "default name: " + PlanStore.default_name(s)
	var res := PlanStore.save("Coast run #1", s)
	if not res.ok or not FileAccess.file_exists(DIR.path_join("coast_run_1.json")):
		return "saved as coast_run_1.json: %s" % res
	if PlanStore.save("   ", s).ok or PlanStore.save("x", _setup({})).ok:
		return "no name / no route: not saved"
	var l := PlanStore.list()
	if l.size() != 1 or l[0].name != "Coast run #1" or l[0].departure != "AAAA" or l[0].dest != "BBBB" or l[0].wps != 3:
		return "list: %s" % [l]
	var p := PlanStore.read(l[0].key)
	if p.route != RouteSetup.repair(_route()):
		return "route back as saved: %s" % p.route
	var into := _setup({})
	var a := PlanStore.apply(p, into, Fx.db())
	if not a.ok or a.airport_changed or into.route != p.route:
		return "apply on the same departure: %s" % a
	if not PlanStore.remove(l[0].key) or not PlanStore.list().is_empty():
		return "remove"
	return ""


func test_plan_store_load_sets_a_different_departure() -> String:
	_keep()
	PlanStore.save("from bravo", _setup({"dest": "AAAA", "wps": [], "cruise_ft": 4500.0}, "BBBB"))
	var into := _setup({}, "AAAA")
	into.stand = "12"
	var a := PlanStore.apply(PlanStore.read("from_bravo"), into, Fx.db())
	if not a.ok or not a.airport_changed or into.airport != "BBBB" or into.runway != "" or into.stand != "":
		return "departure BBBB, runway and stand cleared: %s %s" % [a, into]
	if not str(a.text).contains("BBBB"):
		return "tells the player: " + str(a.text)
	var bad := PlanStore.apply({"name": "x", "departure": "QQQQ", "route": _route()}, _setup({}), Fx.db())
	if bad.ok or not str(bad.error).contains("QQQQ"):
		return "unknown departure: a clear error"
	return ""


func test_pln_export_import_round_trip() -> String:
	var d := Fx.db()
	var plan := PlanImport.from_setup(_setup(_route()), d)
	var text := PlanFile.write(plan)
	for want in ["<DepartureID>AAAA</DepartureID>", "<DestinationID>BBBB</DestinationID>", "<CruisingAlt>4500</CruisingAlt>",
			"<ATCWaypointType>VOR</ATCWaypointType>", "<ATCWaypointType>Intersection</ATCWaypointType>", '<ATCWaypoint id="WPT01">']:
		if not text.contains(want):
			return "export lacks " + want
	var parsed := PlanFile.parse(text)
	if not parsed.ok or parsed.plan.wps.size() != 5:
		return "parse back: %s" % parsed
	var res := PlanImport.to_route(parsed.plan, d, 3000.0, _inside)
	if not res.ok or res.airport != "AAAA" or res.route.dest != "BBBB" or res.route.cruise_ft != 4500.0:
		return "import: %s" % res
	var got: Array = res.route.wps
	var want: Array = _route().wps
	if got.size() != 3 or Fx.ids(got) != ["FA", "V1", "WPT01"]:
		return "waypoints: %s" % [Fx.ids(got)]
	for i in 3:
		if Vector2(got[i].x, got[i].y).distance_to(Vector2(want[i].x, want[i].y)) > 1.0 or got[i].alt_ft != want[i].alt_ft:
			return "waypoint %d moved or changed altitude: %s vs %s" % [i, got[i], want[i]]
	return ""


func test_pln_reads_an_msfs_plan_from_the_real_data() -> String:
	var parsed := PlanFile.parse(MSFS)
	if not parsed.ok or parsed.plan.fp_type != "IFR" or parsed.plan.cruise_ft != 6500.0 or parsed.plan.dep_id != "VABB":
		return "header: %s" % parsed
	if parsed.plan.wps.size() != 3 or parsed.plan.wps[1].type != "User" or parsed.plan.wps[1].lla.alt_ft != 5500.0:
		return "waypoints: %s" % [parsed.plan.wps]
	var d := RouteChecks.db()
	if d.airport("VABB").is_empty() or d.airport("VAPO").is_empty():
		return ""  # no local nav data
	var res := PlanImport.to_route(parsed.plan, d, 4500.0, _inside)
	if not res.ok or res.airport != "VABB" or res.route.dest != "VAPO" or res.route.wps.size() != 1:
		return "import: %s" % res
	var w: Dictionary = res.route.wps[0]
	var at := Geo.to_enu(18.0 + 50.0 / 60.0, 73.0 + 10.0 / 60.0)
	if w.kind != "user" or Vector2(w.x, w.y).distance_to(at) > 1.0 or w.alt_ft != 5500.0:
		return "the custom point is a free waypoint where the file says, at its altitude: %s" % w
	return ""


func test_pln_reads_a_little_navmap_plan_and_drops_points_outside() -> String:
	var text := LNM % [_lla(Fx.p(0, 10), 0.0), _lla(Fx.p(0, 200), 33.0)]
	var parsed := PlanFile.parse(text)
	if not parsed.ok or parsed.plan.wps.size() != 4 or parsed.plan.wps[1].airway != "W1":
		return "parse: %s" % parsed
	var res := PlanImport.to_route(parsed.plan, Fx.db(), 3000.0, _inside)
	if not res.ok or Fx.ids(res.route.wps) != ["FA"] or res.route.wps[0].kind != "fix" or res.route.wps[0].alt_ft != 4500.0:
		return "FA from the nav data at the cruise altitude (its file altitude is 0): %s" % res
	if res.notes.size() != 1 or not str(res.notes[0]).contains("DELHI") or not str(res.notes[0]).contains("outside"):
		return "a note names the point outside the world: %s" % [res.notes]
	return ""


func test_pln_import_errors_are_clear() -> String:
	if PlanFile.parse("<html></html>").ok or not str(PlanFile.parse("hello").error).contains("Not a flight plan"):
		return "not a plan"
	var plan: Dictionary = PlanFile.parse(MSFS).plan
	plan.dep_id = "KSFO"
	plan.wps[0].id = "KSFO"
	var res := PlanImport.to_route(plan, Fx.db(), 4500.0, _inside)
	if res.ok or not str(res.error).contains("KSFO"):
		return "unknown departure: %s" % res
	return ""
