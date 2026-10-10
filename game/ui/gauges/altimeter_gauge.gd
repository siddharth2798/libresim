extends Gauge
## Three-pointer altimeter with Kollsman window (inHg).
## Knob: click left/right half or mouse wheel = -/+ 0.01 inHg (shift: 0.10).


func _draw_face(c: Vector2, r: float) -> void:
	for i in 50:
		var a := TAU * i / 50.0
		draw_line(c + dir(a) * r, c + dir(a) * r * (0.85 if i % 5 == 0 else 0.92), INK, 2.0 if i % 5 == 0 else 1.0, true)
	for d in 10:
		label(c + dir(TAU * d / 10.0) * r * 0.7, str(d), 15)
	var k := Props.get_f("instruments/altimeter/kollsman_inhg", 29.92)
	var box := Rect2(c + Vector2(r * 0.22, -10), Vector2(r * 0.55, 20))
	draw_rect(box, Color(0.15, 0.15, 0.15))
	label(box.get_center(), "%.2f" % k, 12)
	label(c + Vector2(0, r * 0.35), "ALT", 11)


func _draw_needles(c: Vector2, r: float) -> void:
	var ft := Props.get_f("instruments/altimeter_ft")
	needle(c, TAU * ft / 100000.0, r * 0.9, 1.5, Color(0.9, 0.9, 0.9), 0.0)  # 10,000s
	needle(c, TAU * ft / 10000.0, r * 0.5, 7.0)  # 1,000s
	needle(c, TAU * ft / 1000.0, r * 0.85, 4.0)  # 100s


func _knob(d: float) -> void:
	var step := 0.1 if Input.is_key_pressed(KEY_SHIFT) else 0.01
	var k := Props.get_f("instruments/altimeter/kollsman_inhg", 29.92) + d * step
	Props.set_v("instruments/altimeter/kollsman_inhg", clampf(snappedf(k, 0.01), 28.1, 31.0))
