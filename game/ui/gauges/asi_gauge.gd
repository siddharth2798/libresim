extends Gauge
## Airspeed indicator, C172S markings (KIAS): white arc 40-85, green 48-129,
## yellow 129-163, red line 163.

const MAX := 200.0


static func ang(kt: float) -> float:
	return deg_to_rad(15.0 + clampf(kt, 0.0, MAX) / MAX * 330.0)


func _draw_face(c: Vector2, r: float) -> void:
	arc(c, r * 0.86, ang(40), ang(85), Color(0.95, 0.95, 0.95), 6.0)
	arc(c, r * 0.94, ang(48), ang(129), Color(0.1, 0.75, 0.2), 7.0)
	arc(c, r * 0.94, ang(129), ang(163), Color(0.95, 0.85, 0.1), 7.0)
	draw_line(c + dir(ang(163)) * r, c + dir(ang(163)) * r * 0.8, Color(0.9, 0.1, 0.1), 4.0)
	for kt in range(40, 201, 10):
		var a := ang(kt)
		var big := kt % 20 == 0
		draw_line(c + dir(a) * r * 0.9, c + dir(a) * r * (0.78 if big else 0.84), INK, 2.0, true)
		if big:
			label(c + dir(a) * r * 0.63, str(kt), 13)
	label(c + Vector2(0, r * 0.3), "KNOTS", 11)
	label(c + Vector2(0, -r * 0.25), "AIRSPEED", 10)


func _draw_needles(c: Vector2, r: float) -> void:
	needle(c, ang(Props.get_f("instruments/asi_kt")), r * 0.85)
