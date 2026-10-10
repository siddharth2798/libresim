extends Gauge
## Turn coordinator: tilting aircraft symbol (standard rate at the L/R marks)
## and the inclinometer ball. Electric: shows OFF flag without power.

const MARK := deg_to_rad(20.0)


func _draw_face(c: Vector2, r: float) -> void:
	for s in [-1.0, 1.0]:
		var a: float = PI / 2 * s + MARK * s
		draw_line(c + dir(a) * r * 0.95, c + dir(a) * r * 0.78, INK, 3.0, true)
		var a0: float = PI / 2 * s
		draw_line(c + dir(a0) * r * 0.95, c + dir(a0) * r * 0.82, INK, 3.0, true)
	label(c + dir(-PI / 2 - MARK) * r * 0.66, "L", 13)
	label(c + dir(PI / 2 + MARK) * r * 0.66, "R", 13)
	label(c + Vector2(0, -r * 0.55), "TURN COORDINATOR", 9)
	label(c + Vector2(0, r * 0.75), "2 MIN", 10)
	# ball tube
	var tube := Rect2(c + Vector2(-r * 0.5, r * 0.38), Vector2(r, r * 0.18))
	draw_rect(tube, Color(0.75, 0.75, 0.7))
	draw_line(c + Vector2(-r * 0.09, r * 0.38), c + Vector2(-r * 0.09, r * 0.56), Color.BLACK, 2.0)
	draw_line(c + Vector2(r * 0.09, r * 0.38), c + Vector2(r * 0.09, r * 0.56), Color.BLACK, 2.0)


func _draw_needles(c: Vector2, r: float) -> void:
	var a := clampf(Props.get_f("instruments/tc_rate"), -1.6, 1.6) * MARK
	var right := Vector2(cos(a), sin(a))
	var up := Vector2(sin(a), -cos(a))
	var wing := r * 0.62
	draw_line(c - right * wing, c + right * wing, INK, 5.0, true)
	draw_line(c, c + up * r * 0.18, INK, 4.0, true)
	draw_line(c - up * r * 0.12 - right * r * 0.14, c - up * r * 0.12 + right * r * 0.14, INK, 3.0, true)
	draw_circle(c, r * 0.1, INK)
	var ball := Props.get_f("instruments/tc_ball")
	draw_circle(c + Vector2(ball * r * 0.4, r * 0.47), r * 0.08, Color.BLACK)
	if Props.get_b("instruments/tc_flag"):
		label(c + Vector2(r * 0.4, -r * 0.2), "OFF", 12, Color(1, 0.3, 0.2))


func _process(_dt: float) -> void:
	queue_redraw()
