extends Node
## Shared state for the in-flight route suites (tests/test_route_live.gd, tests/test_route_live_ui.gd): a flight on a
## made-up route (tests/route_fixture.gd), and the Props, Session.setup and nodes put back after each test.

const Fx := preload("res://tests/route_fixture.gd")
const KEYS := ["controls/gps/target", "controls/gps/route_next", "route/dest", "route/rev", "mcdu/init/from_to",
	"mcdu/init/arr_rwy", "controls/fcu/alt_ft", "controls/fcu/hdg_managed", "fdm/position_enu", "fuel/total_kg",
	"mcdu/init/dep_rwy", "mcdu/init/cruise_fl", "controls/fms/origin", "controls/fcu/vs_managed"]

var _saved := {}
var _setup := {}
var _nodes: Array = []


func _keep() -> void:
	if _saved.is_empty():
		for k in KEYS:
			_saved[k] = Props.get_v(k, null) if Props.has(k) else "<none>"
		_setup = Session.setup.duplicate(true)


func teardown() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	NavDatabase.route_fixes.clear()
	if _saved.is_empty():
		return
	for k in _saved:
		if str(_saved[k]) == "<none>":
			Props._p.erase(k)
		else:
			Props.set_v(k, _saved[k])
	Session.setup = _setup
	_saved = {}


## AAAA -> FA -> WPT01 (free, at 10 E 40 N nm) -> FB -> BBBB; the GPS flies WPT01 (FA is behind). `runway`: a runway
## start on it (its departure fix VABB18D-style is then known).
func _flying(target := "WPT01", next: Array = ["FB", "BBBB"], runway := "") -> NavDatabase:
	_keep()
	var s := Session.DEFAULT.duplicate(true)
	s.airport = "AAAA"
	if runway != "":
		s.start = "runway"
		s.runway = runway
	s.route = {"dest": "BBBB", "arr_rwy": "", "cruise_ft": 4500.0, "kind": "airway", "air_at": -1, "wps": [
		{"id": "FA", "kind": "fix", "x": Fx.p(0, 10).x, "y": Fx.p(0, 10).y, "alt_ft": 4500.0},
		{"id": "WPT01", "kind": "user", "x": Fx.p(10, 40).x, "y": Fx.p(10, 40).y, "alt_ft": 5500.0},
		{"id": "FB", "kind": "fix", "x": Fx.p(30, 100).x, "y": Fx.p(30, 100).y, "alt_ft": 4500.0}]}
	Session.setup = s
	NavDatabase.route_fixes.clear()
	RouteSetup.register(RouteSetup.repair(s.route))
	Props.set_v("controls/gps/target", target)
	Props.set_v("controls/gps/route_next", next)
	var here := Fx.p(2, 20)
	Props.set_v("fdm/position_enu", Vector3(here.x, here.y, 900.0))
	return Fx.db()


func _gps() -> Array:
	return [str(Props.get_v("controls/gps/target", ""))] + Array(Props.get_v("controls/gps/route_next", []))
