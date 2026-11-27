class_name NdFeed
extends Node
## Publishes what the navigation display draws, from the nav database and the GPS route, so the ND
## itself only reads Props. Out (twice a second): instruments/nd/route [{id, x, y, cstr?, state?}] (active waypoint
## first, ENU metres; a SID / STAR fix adds its constraint text and "met" / "missed"), instruments/nd/near
## [{id, x, y, kind: "apt" | "vor" | "ndb" | "wpt"}] (within
## `RANGE_M` of the aircraft), instruments/nd/wind_dir_deg / wind_kt (from environment/wind_ned,
## where the wind blows FROM). Which kinds go in follows the EFIS option buttons (controls/efis/nd_filter, kinds()):
## none selected = airports and VORs as before; CSTR = no near points, the route's constraint values instead (nd.gd).

const RANGE_M := 200000.0
const PERIOD := 0.5
const MAX_POINTS := 60

var db: NavDatabase
var _t := PERIOD


func _physics_process(dt: float) -> void:
	_t += dt
	if _t < PERIOD:
		return
	_t = 0.0
	publish()


## The near kinds an EFIS option shows: 0 none selected (airports and VORs), 1 CSTR, 2 WPT, 3 VOR.D, 4 NDB, 5 ARPT.
static func kinds(filter: int) -> Array:
	return [["apt", "vor"], [], ["wpt"], ["vor"], ["ndb"], ["apt"]][clampi(filter, 0, 5)]


## Wind blowing from (deg true) and speed (kt) for a NED wind vector (m/s, the way the air moves).
static func wind_from(wind_ned: Vector3) -> Vector2:
	var spd := Vector2(wind_ned.x, wind_ned.y).length()
	return Vector2(fposmod(rad_to_deg(atan2(-wind_ned.y, -wind_ned.x)), 360.0), Units.mps_to_kt(spd))


func publish() -> void:
	var w := wind_from(Props.get_v("environment/wind_ned", Vector3.ZERO))
	Props.set_v("instruments/nd/wind_dir_deg", w.x)
	Props.set_v("instruments/nd/wind_kt", w.y)
	if db == null:
		return
	var p3: Vector3 = Props.get_v("fdm/position_enu", Vector3.ZERO)
	var p := Vector2(p3.x, p3.y)
	var route := []
	var cstr: Dictionary = Props.get_v(RouteSetup.CSTR_PROP, {})
	var state: Dictionary = Props.get_v("avionics/fms/cstr_state", {})
	for id in [str(Props.get_v("controls/gps/target", ""))] + Array(Props.get_v("controls/gps/route_next", [])):
		var pos = db.position_of(str(id)) if id != "" else null
		if pos != null:
			var wp := {"id": id, "x": pos.x, "y": pos.y}
			if cstr.has(id):  # a SID / STAR constraint: its text, and "met" / "missed" (FmsConstraints)
				wp["cstr"] = Procedures.text(cstr[id])
				wp["state"] = str(state.get(id, "met"))
			route.append(wp)
	var near := []
	var want := kinds(int(Props.get_f("controls/efis/nd_filter")))
	if "apt" in want:
		for a in db.airports:
			if Vector2(a.x, a.y).distance_to(p) < RANGE_M and str(a.get("type", "")) != "closed":
				near.append({"id": a.icao if a.icao != "" else a.ident, "x": a.x, "y": a.y, "kind": "apt"})
	for pair in [["vor", db.vors], ["ndb", db.ndbs]]:
		if pair[0] in want:
			for v in pair[1]:
				if Vector2(v.x, v.y).distance_to(p) < RANGE_M:
					near.append({"id": v.ident, "x": v.x, "y": v.y, "kind": pair[0]})
	if "wpt" in want:
		for id in db.fixes:
			var f: Vector2 = db.fixes[id]
			if f.distance_to(p) < RANGE_M:
				near.append({"id": id, "x": f.x, "y": f.y, "kind": "wpt"})
	near.sort_custom(func(a, b): return Vector2(a.x, a.y).distance_squared_to(p) < Vector2(b.x, b.y).distance_squared_to(p))
	Props.set_v("instruments/nd/route", route)
	Props.set_v("instruments/nd/near", near.slice(0, MAX_POINTS))
