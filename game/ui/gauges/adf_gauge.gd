extends Gauge
## ADF indicator (KI-227 style) with a rotatable compass card: needle shows the NDB's
## relative bearing; HDG knob (click halves / wheel) turns the card so the needle can
## read magnetic bearing directly.

var _card := 0.0


func _draw_face(c: Vector2, r: float) -> void:
	var cd := deg_to_rad(_card)
	for i in 72:
		var a := TAU * i / 72.0 - cd
		var big := i % 2 == 0
		draw_line(c + dir(a) * r, c + dir(a) * r * (0.86 if big else 0.92), INK, 1.5 if big else 1.0, true)
	var names := {0: "N", 9: "E", 18: "S", 27: "W"}
	for d in range(0, 36, 3):
		label(c + dir(deg_to_rad(d * 10.0) - cd) * r * 0.72, names.get(d, str(d)), 12)
	draw_line(c + Vector2(0, -r), c + Vector2(0, -r * 0.84), Color(1, 0.6, 0.1), 3.0)
	label(c + Vector2(0, r * 0.35), "ADF", 11)


func _draw_needles(c: Vector2, r: float) -> void:
	var a := deg_to_rad(Props.get_f("avionics/adf/bearing_deg", 90.0))
	needle(c, a, r * 0.8, 5.0, Color(1, 0.85, 0.3), 0.6)
	var ident: String = str(Props.get_v("avionics/adf/ident", ""))
	if ident != "":
		label(c + Vector2(0, r * 0.52), ident, 10, Color(0.7, 0.9, 1))


func _knob(d: float) -> void:
	_card = fposmod(_card + d * (10.0 if Input.is_key_pressed(KEY_SHIFT) else 5.0), 360.0)
