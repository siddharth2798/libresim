extends Gauge
## Tachometer 0-3500 RPM, green 2100-2700, red line 2700, hour meter omitted.


static func ang(rpm: float) -> float:
	return deg_to_rad(-135.0 + clampf(rpm, 0.0, 3500.0) / 3500.0 * 270.0)


func _draw_face(c: Vector2, r: float) -> void:
	arc(c, r * 0.94, ang(2100), ang(2700), Color(0.1, 0.75, 0.2), 7.0)
	draw_line(c + dir(ang(2700)) * r, c + dir(ang(2700)) * r * 0.78, Color(0.9, 0.1, 0.1), 4.0)
	for i in 36:
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


func _process(_dt: float) -> void:
	queue_redraw()
