extends Gauge
## VOR / ILS course deviation indicator (KI-208 / KI-209 style). The prop prefix and
## glideslope option are set by the owner via set_meta("nav", 1|2) / ("gs", bool).
## OBS knob: click left/right half or wheel = -/+ 1 deg (Shift: 10 deg).

var nav := 1
var has_gs := false


func _ready() -> void:
	super._ready()
	nav = get_meta("nav", 1)
	has_gs = get_meta("gs", false)


func _p(k: String) -> Variant:
	return Props.get_v("avionics/nav%d/%s" % [nav, k], null)


func _draw_face(c: Vector2, r: float) -> void:
	var obs := deg_to_rad(Props.get_f("controls/nav%d/obs_deg" % nav))
	for i in 72:  # rotating OBS card
		var a := TAU * i / 72.0 - obs
		var big := i % 2 == 0
		draw_line(c + dir(a) * r, c + dir(a) * r * (0.88 if big else 0.93), INK, 1.5 if big else 1.0, true)
	for d in range(0, 36, 3):
		label(c + dir(deg_to_rad(d * 10.0) - obs) * r * 0.76, str(d), 11)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r * 0.99), c + Vector2(-6, -r * 0.88), c + Vector2(6, -r * 0.88)]), Color(1, 0.6, 0.1))
	for k in range(-5, 6):  # deviation dots (2 deg each for VOR)
		if k != 0:
			draw_circle(c + Vector2(k * r * 0.1, 0), 2.5, INK)
	draw_arc(c, r * 0.06, 0, TAU, 16, INK, 1.5)
	if has_gs:
		for k in range(-4, 5):
			if k != 0:
				draw_circle(c + Vector2(r * 0.5, k * r * 0.1), 2.0, INK)


func _draw_needles(c: Vector2, r: float) -> void:
	var valid: bool = _p("valid") == true
	var cdi: float = _p("cdi") if valid else 0.0
	var x := c.x + cdi * r * 0.5
	draw_line(Vector2(x, c.y - r * 0.55), Vector2(x, c.y + r * 0.55), NEEDLE, 3.0, true)
	if has_gs:
		var gv: bool = _p("gs_valid") == true
		var gs: float = _p("gs") if gv else 0.0
		var y := c.y - gs * r * 0.4
		draw_line(Vector2(c.x - r * 0.5, y), Vector2(c.x + r * 0.5, y), NEEDLE, 3.0, true)
		if not gv:
			draw_rect(Rect2(c + Vector2(r * 0.35, -r * 0.25), Vector2(r * 0.3, r * 0.14)), Color(0.85, 0.1, 0.1))
			label(c + Vector2(r * 0.5, -r * 0.18), "GS", 10)
	var tf: int = _p("to_from") if valid else 0
	if not valid:
		draw_rect(Rect2(c + Vector2(-r * 0.6, -r * 0.42), Vector2(r * 0.34, r * 0.16)), Color(0.85, 0.1, 0.1))
		label(c + Vector2(-r * 0.43, -r * 0.34), "NAV", 10)
	else:
		label(c + Vector2(-r * 0.4, r * 0.32), "TO" if tf > 0 else "FR", 12, Color(1, 1, 1))
	var ident: String = str(_p("ident")) if valid else ""
	label(c + Vector2(0, r * 0.5), "NAV%d %s" % [nav, ident], 10, Color(0.7, 0.9, 1))


func _knob(d: float) -> void:
	var k := "controls/nav%d/obs_deg" % nav
	Props.set_v(k, fposmod(Props.get_f(k) + d * (10.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0), 360.0))
