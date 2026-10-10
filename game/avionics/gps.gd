class_name Gps
extends Node
## Simple GPS (Garmin 196 class): direct-to an airport or navaid by ident.
## In: Props "controls/gps/target" (ident). Out: "avionics/gps/{ident, brg_mag, dist_nm,
## ete, xtk_nm, valid}". Magnetic = true + local variation (~ -0.3 deg near Mumbai/Pune).

const VAR_DEG := -0.3
const NM := 1852.0

var db: NavDatabase
var _from := Vector2.ZERO
var _last_target := ""


func target_position(ident: String) -> Variant:
	for a in db.airports:
		if a.ident == ident or a.icao == ident:
			return Vector2(a.x, a.y)
	for v in db.vors:
		if v.ident == ident:
			return Vector2(v.x, v.y)
	for n in db.ndbs:
		if n.ident == ident:
			return Vector2(n.x, n.y)
	return null


func _physics_process(_dt: float) -> void:
	if db == null:
		return
	var ident: String = str(Props.get_v("controls/gps/target", ""))
	var p3: Vector3 = Props.get_v("fdm/position_enu", Vector3.ZERO)
	var p := Vector2(p3.x, p3.y)
	if ident != _last_target:
		_last_target = ident
		_from = p  # direct-to leg starts here
	var tp = target_position(ident) if ident != "" else null
	if tp == null:
		Props.set_v("avionics/gps/ident", "")
		return
	var d: Vector2 = tp - p
	var dist := d.length()
	var gs := maxf(Props.get_f("fdm/groundspeed_mps"), 1.0)
	var leg: Vector2 = (tp - _from).normalized() if _from.distance_to(tp) > 1.0 else d.normalized()
	Props.set_v("avionics/gps/ident", ident)
	Props.set_v("avionics/gps/brg_mag", fposmod(rad_to_deg(atan2(d.x, d.y)) - VAR_DEG, 360.0))
	Props.set_v("avionics/gps/dist_nm", dist / NM)
	var secs := int(dist / gs)
	Props.set_v("avionics/gps/ete", "%d:%02d" % [secs / 60, secs % 60] if gs > 5.0 else "--")
	Props.set_v("avionics/gps/xtk_nm", ((p - _from).cross(leg)) / NM)  # + = right of the leg
	Props.set_v("avionics/gps/valid", true)
