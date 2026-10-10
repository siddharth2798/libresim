extends Gauge
## Vertical speed indicator, +/-2000 fpm, zero at 9 o'clock.


static func ang(fpm: float) -> float:
	return -PI / 2 + clampf(fpm, -2000.0, 2000.0) / 2000.0 * deg_to_rad(170.0)


func _draw_face(c: Vector2, r: float) -> void:
	for f in range(-2000, 2001, 100):
		var big := f % 500 == 0
		var a := ang(f)
		draw_line(c + dir(a) * r, c + dir(a) * r * (0.82 if big else 0.9), INK, 2.0 if big else 1.0, true)
	for f in [0, 5, 10, 15, 20]:
		label(c + dir(ang(f * 100)) * r * 0.66, str(f), 14)
		if f > 0:
			label(c + dir(ang(-f * 100)) * r * 0.66, str(f), 14)
	label(c + Vector2(r * 0.15, -r * 0.3), "UP", 10)
	label(c + Vector2(r * 0.15, r * 0.3), "DOWN", 10)
	label(c + Vector2(r * 0.3, 0), "VERTICAL SPEED", 8)
	label(c + Vector2(r * 0.3, r * 0.14), "100 FT PER MIN", 7)


func _draw_needles(c: Vector2, r: float) -> void:
	needle(c, ang(Props.get_f("instruments/vsi_fpm")), r * 0.85)
