class_name Gps
extends Node
## Simple GPS (Garmin 196 class): direct-to an airport or navaid by ident, plus a modest
## multi-leg route (RoutePlan): the first leg is flown, and the GPS sequences to the next one
## when the aircraft passes within 1 nm of the active waypoint.
## In: Props "controls/gps/target" (active ident), "controls/gps/route_next" (idents after it).
## Out: "avionics/gps/{ident, brg_mag, dist_nm, ete, xtk_nm, valid}".
## Magnetic = true + local variation (~ -0.3 deg near Mumbai/Pune).

const VAR_DEG := -0.3
const NM := 1852.0

var db: NavDatabase
var plan := RoutePlan.new()
var _last_target := ""
var _last_next: Array = []
var _tod_key := ""  # cruise|destination once a descent has been commanded


func target_position(ident: String) -> Variant:
	return db.position_of(ident)


## Follow Props (set by the map, the session or tests) and sequence the route.
func _sync(p: Vector2) -> void:
	var ident: String = str(Props.get_v("controls/gps/target", ""))
	var next: Array = Props.get_v("controls/gps/route_next", [])
	if ident != _last_target or next != _last_next:
		var leg_from := plan.from_pos if ident == _last_target else p  # direct-to: the leg starts here
		plan = RoutePlan.from_idents(ident, next, target_position)
		plan.from_pos = leg_from
		_last_target = ident
		_last_next = next.duplicate()
	if plan.update(p):
		_last_target = plan.active().ident
		_last_next = plan.next_idents()
		Props.set_v("controls/gps/target", _last_target)
		Props.set_v("controls/gps/route_next", _last_next.duplicate())


func _physics_process(_dt: float) -> void:
	if db == null:
		return
	var p3: Vector3 = Props.get_v("fdm/position_enu", Vector3.ZERO)
	var p := Vector2(p3.x, p3.y)
	_sync(p)
	var ok := Props.get_b("systems/electrical/avionics_powered", true) and not Props.get_b("failures/gps")
	Props.set_v("avionics/gps/valid", ok)
	if plan.is_empty() or not ok:
		Props.set_v("avionics/gps/ident", "")
		Props.set_v("avionics/fms/legs", [])
		_profile(p, p3.z, false)
		return
	var tp: Vector2 = plan.active().pos
	var d: Vector2 = tp - p
	var dist := d.length()
	var gs := maxf(Props.get_f("fdm/groundspeed_mps"), 1.0)
	var from := plan.from_pos
	var leg: Vector2 = (tp - from).normalized() if from.distance_to(tp) > 1.0 else d.normalized()
	Props.set_v("avionics/gps/ident", plan.active().ident)
	Props.set_v("avionics/gps/brg_mag", fposmod(rad_to_deg(atan2(d.x, d.y)) - VAR_DEG, 360.0))
	Props.set_v("avionics/gps/dist_nm", dist / NM)
	var secs := int(dist / gs)
	Props.set_v("avionics/gps/ete", "%d:%02d" % [secs / 60, secs % 60] if gs > 5.0 else "--")
	Props.set_v("avionics/gps/xtk_nm", ((p - from).cross(leg)) / NM)  # + = right of the leg
	Props.set_v("avionics/gps/valid", true)
	_legs(p)
	_profile(p, p3.z, true)


## Course and distance of each leg, from the aircraft to the active waypoint and then waypoint to waypoint.
## avionics/fms/legs [{ident, course (deg magnetic), dist_nm}], for the MCDU F-PLN page.
func _legs(p: Vector2) -> void:
	var legs := []
	var a := p
	for w in plan.wps:
		var b: Vector2 = w.pos
		legs.append({"ident": w.ident, "course": fposmod(RoutePlan.bearing_deg(a, b) - VAR_DEG, 360.0), "dist_nm": a.distance_to(b) / NM})
		a = b
	Props.set_v("avionics/fms/legs", legs)


## Managed vertical: publish the phase, and at top of descent set the FCU altitude once.
func _profile(p: Vector2, alt_m: float, route_ok: bool) -> void:
	if not route_ok or not Props.get_b("controls/fcu/vs_managed") or Props.get_b("fdm/wow"):
		_tod_key = ""
		Props.set_v("avionics/fms/phase", "")
		Props.set_v("avionics/fms/tod_nm", -1.0)
		return
	var cruise := float(Props.get_v("mcdu/init/cruise_fl", 0.0)) * 100.0
	var dest: Dictionary = plan.wps.back()
	var ident := str(dest.get("ident", ""))
	var ap := db.airport(ident)
	if ap.is_empty():
		var parsed := RunwayWaypoints.parse(ident)
		if not parsed.is_empty():
			ap = db.airport(str(parsed.icao))
	if cruise <= 0.0 or ap.is_empty():
		Props.set_v("avionics/fms/phase", "")
		Props.set_v("avionics/fms/tod_nm", -1.0)
		return
	var dist_nm := plan.remaining_m(p) / NM
	var d := VerticalProfile.decide(cruise, Units.m_to_ft(alt_m), dist_nm, Units.m_to_ft(float(ap.get("elev_m", 0.0))))
	Props.set_v("avionics/fms/phase", d.phase)
	Props.set_v("avionics/fms/tod_nm", d.tod_nm)
	var key := "%d|%s" % [int(cruise), ident]
	if d.descend and _tod_key != key:
		_tod_key = key
		if Props.get_f("controls/fcu/alt_ft") > float(d.approach_ft) + 100.0:
			Props.set_v("controls/fcu/alt_ft", d.approach_ft)
			Props.set_v("controls/fcu/vert_select", "MANAGED")
	elif not d.descend:
		_tod_key = ""
