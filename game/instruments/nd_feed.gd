class_name NdFeed
extends Node
## Publishes what the navigation display draws, from the nav database and the GPS route, so the ND
## itself only reads Props. Out (twice a second): instruments/nd/route [{id, x, y}] (active waypoint
## first, ENU metres), instruments/nd/near [{id, x, y, kind: "apt" | "vor" | "ndb"}] (within
## `RANGE_M` of the aircraft), instruments/nd/wind_dir_deg / wind_kt (from environment/wind_ned,
## where the wind blows FROM).

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
	for id in [str(Props.get_v("controls/gps/target", ""))] + Array(Props.get_v("controls/gps/route_next", [])):
		var pos = db.position_of(str(id)) if id != "" else null
		if pos != null:
			route.append({"id": id, "x": pos.x, "y": pos.y})
	var near := []
	for a in db.airports:
		if Vector2(a.x, a.y).distance_to(p) < RANGE_M and str(a.get("type", "")) != "closed":
			near.append({"id": a.icao if a.icao != "" else a.ident, "x": a.x, "y": a.y, "kind": "apt"})
	for v in db.vors:
		if Vector2(v.x, v.y).distance_to(p) < RANGE_M:
			near.append({"id": v.ident, "x": v.x, "y": v.y, "kind": "vor"})
	near.sort_custom(func(a, b): return Vector2(a.x, a.y).distance_squared_to(p) < Vector2(b.x, b.y).distance_squared_to(p))
	Props.set_v("instruments/nd/route", route)
	Props.set_v("instruments/nd/near", near.slice(0, MAX_POINTS))
