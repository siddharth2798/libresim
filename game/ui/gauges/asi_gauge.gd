extends Gauge
## Airspeed indicator (KIAS). Markings from the aircraft's aircraft.json "limits": white arc
## vs0 .. max flap-extended speed (last vfe_kias entry), green vs1 .. vno, yellow vno .. vne,
## red line vne; the scale runs asi_min_kias .. asi_max_kias. A short red line marks each flap setting's VFE, named
## by the flap angles it covers (instruments/flap_speeds.gd, config.json controls.flaps detents).

var _lim := {}
var _max := 200.0
var _flap_marks := []  # [[kt, label], ...]


func _limits() -> Dictionary:
	if _lim.is_empty():
		_lim = AircraftDef.current().section_or("limits", Damage.LIMIT_DEFAULTS)
		_max = float(_lim.get("asi_max_kias", 200.0))
		var degs := []
		var flaps: Variant = AircraftDef.current().config().get("controls", {}).get("flaps", [])
		for d in (flaps.get("detents", []) if flaps is Dictionary else flaps):  # C172: the list; A320: {"detents": [...]}
			degs.append(float(d.get("deg", d.get("flap_deg", 0.0))) if d is Dictionary else float(d))
		var by_flap := _lim.has("vfe_kias") and str(_lim.get("vfe_by", "flap")) == "flap"  # slats too: the PFD tape marks them
		_flap_marks = FlapSpeeds.marks(_lim, degs) if by_flap else []
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
	for m in _flap_marks:  # each flap setting's VFE: a red line inside the arcs, and its flap angles
		var a := ang(float(m[0]))
		draw_line(c + dir(a) * r * 0.83, c + dir(a) * r * 0.7, Color(0.9, 0.1, 0.1), 3.0)
		label(c + dir(a) * r * 0.5, str(m[1]), 9)
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
