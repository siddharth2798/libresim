extends Gauge
## Tachometer, hour meter omitted. Scale and markings from the aircraft's aircraft.json
## "limits.tach": {"max_rpm", "green": [lo, hi], "red": rpm}.

var _t := {}


func _tach() -> Dictionary:
	if _t.is_empty():
		_t = AircraftDef.current().section("limits").get("tach", {"max_rpm": 3500.0})
	return _t


func ang(rpm: float) -> float:
	var mx: float = _tach().get("max_rpm", 3500.0)
	return deg_to_rad(-135.0 + clampf(rpm, 0.0, mx) / mx * 270.0)


func _draw_face(c: Vector2, r: float) -> void:
	var t := _tach()
	if t.has("green"):
		arc(c, r * 0.94, ang(t.green[0]), ang(t.green[1]), Color(0.1, 0.75, 0.2), 7.0)
	if t.has("red"):
		draw_line(c + dir(ang(t.red)) * r, c + dir(ang(t.red)) * r * 0.78, Color(0.9, 0.1, 0.1), 4.0)
	for i in int(t.get("max_rpm", 3500.0) / 100.0) + 1:
		var rpm := i * 100.0
		var a := ang(rpm)
		var big := i % 5 == 0
		draw_line(c + dir(a) * r * 0.9, c + dir(a) * r * (0.78 if big else 0.85), INK, 2.0 if big else 1.0, true)
		if big:
			label(c + dir(a) * r * 0.62, str(i), 13)
	label(c + Vector2(0, r * 0.35), "RPM", 11)
	label(c + Vector2(0, r * 0.52), "x100", 9)


func _draw_needles(c: Vector2, r: float) -> void:
	needle(c, ang(Props.get_f("instruments/tach_rpm")), r * 0.85)
