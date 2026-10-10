extends Gauge
## Directional gyro (heading indicator): rotating compass card.
## Knob: click left/right or wheel = turn the card -/+ 1 deg (shift: 10);
## middle click = sync to the magnetic compass.


func _draw_face(c: Vector2, r: float) -> void:
	var hdg := deg_to_rad(Props.get_f("instruments/hi_deg"))
	for i in 72:
		var a := TAU * i / 72.0 - hdg
		var big := i % 2 == 0
		draw_line(c + dir(a) * r, c + dir(a) * r * (0.84 if big else 0.9), INK, 2.0 if big else 1.0, true)
	var names := {0: "N", 9: "E", 18: "S", 27: "W"}
	for d in range(0, 36, 3):
		var a := deg_to_rad(d * 10.0) - hdg
		label(c + dir(a) * r * 0.68, names.get(d, str(d)), 15 if names.has(d) else 13,
			Color(1, 0.8, 0.3) if names.has(d) else INK)


func _draw_needles(c: Vector2, r: float) -> void:
	var o := Color(1.0, 0.55, 0.05)
	draw_line(c + Vector2(0, -r), c + Vector2(0, -r * 0.82), o, 3.0)  # lubber line
	# aircraft symbol
	draw_line(c + Vector2(0, -r * 0.35), c + Vector2(0, r * 0.3), o, 4.0, true)
	draw_line(c + Vector2(-r * 0.3, -r * 0.05), c + Vector2(r * 0.3, -r * 0.05), o, 4.0, true)
	draw_line(c + Vector2(-r * 0.12, r * 0.25), c + Vector2(r * 0.12, r * 0.25), o, 3.0, true)


func _knob(d: float) -> void:
	Props.set_v("instruments/hi/adjust_deg", Props.get_f("instruments/hi/adjust_deg") + d * (10.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0))


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_MIDDLE:
		Props.set_v("instruments/hi/sync", true)
		return
	super._gui_input(e)
