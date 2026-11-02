extends Gauge
## Airspeed indicator (KIAS). Markings from the aircraft's aircraft.json "limits": white arc
## vs0 .. max flap-extended speed (last vfe_kias entry), green vs1 .. vno, yellow vno .. vne,
## red line vne; the scale runs asi_min_kias .. asi_max_kias.

var _lim := {}
var _max := 200.0


func _limits() -> Dictionary:
	if _lim.is_empty():
		_lim = AircraftDef.current().section_or("limits", Damage.LIMIT_DEFAULTS)
		_max = float(_lim.get("asi_max_kias", 200.0))
	return _lim


func ang(kt: float) -> float:
	return deg_to_rad(15.0 + clampf(kt, 0.0, _max) / _max * 330.0)


func _draw_face(c: Vector2, r: float) -> void:
	var l := _limits()
	var vfe: float = l.vfe_kias[-1][1]
	var vno: float = l.get("vno_kias", l.vne_kias)
	if l.has("vs0_kias"):
		arc(c, r * 0.86, ang(l.vs0_kias), ang(vfe), Color(0.95, 0.95, 0.95), 6.0)
	if l.has("vs1_kias"):
		arc(c, r * 0.94, ang(l.vs1_kias), ang(vno), Color(0.1, 0.75, 0.2), 7.0)
	arc(c, r * 0.94, ang(vno), ang(l.vne_kias), Color(0.95, 0.85, 0.1), 7.0)
	draw_line(c + dir(ang(l.vne_kias)) * r, c + dir(ang(l.vne_kias)) * r * 0.8, Color(0.9, 0.1, 0.1), 4.0)
	for kt in range(int(l.get("asi_min_kias", 40.0)), int(_max) + 1, 10):
		var a := ang(kt)
		var big := kt % 20 == 0
		draw_line(c + dir(a) * r * 0.9, c + dir(a) * r * (0.78 if big else 0.84), INK, 2.0, true)
		if big:
			label(c + dir(a) * r * 0.63, str(kt), 13)
	label(c + Vector2(0, r * 0.3), "KNOTS", 11)
	label(c + Vector2(0, -r * 0.25), "AIRSPEED", 10)


func _draw_needles(c: Vector2, r: float) -> void:
	needle(c, ang(Props.get_f("instruments/asi_kt")), r * 0.85)
