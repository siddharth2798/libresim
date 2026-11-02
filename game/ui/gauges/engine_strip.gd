extends Control
## Engine/fuel gauge cluster as compact horizontal bar gauges plus the wet magnetic compass
## strip. Ranges and colours come from the aircraft's aircraft.json "limits.gauges"
## ({min, max, green: [lo, hi], red (optional)} per gauge key); a gauge it does not list is not shown.

const SPEC := [
	# [label, prop, gauge key (limits.gauges), fmt]
	["FUEL L", "instruments/fuel_left_gal", "fuel_gal", "%.0f gal"],
	["FUEL R", "instruments/fuel_right_gal", "fuel_gal", "%.0f gal"],
	["OIL °F", "instruments/oil_temp_f", "oil_temp_f", "%.0f"],
	["OIL PSI", "instruments/oil_press_psi", "oil_press_psi", "%.0f"],
	["EGT °F", "instruments/egt_f", "egt_f", "%.0f"],
	["FF GPH", "instruments/fuel_flow_gph", "fuel_flow_gph", "%.1f"],
	["VAC inHg", "instruments/suction_inhg", "suction_inhg", "%.1f"],
	["AMPS", "instruments/ammeter_a", "ammeter_a", "%+.0f"],
]

var font: Font
var _gauges := []  # [label, prop, min, max, green_lo, green_hi, red_hi (-1: none), fmt]


func _ready() -> void:
	font = ThemeDB.fallback_font
	custom_minimum_size = Vector2(240, 300)


func _load_gauges() -> void:
	var g: Dictionary = AircraftDef.current().section("limits").get("gauges", {})
	for sp in SPEC:
		if g.has(sp[2]):
			var l: Dictionary = g[sp[2]]
			_gauges.append([sp[0], sp[1], float(l.min), float(l.max), float(l.green[0]), float(l.green[1]), float(l.get("red", -1.0)), sp[3]])


func _draw() -> void:
	if _gauges.is_empty():
		_load_gauges()
	var w := size.x
	var row_h := size.y / (_gauges.size() + 1.5)
	# magnetic compass window
	var hdg := Props.get_f("instruments/compass_deg")
	var box := Rect2(Vector2(w * 0.15, 4), Vector2(w * 0.7, row_h * 1.1))
	draw_rect(box, Color(0.02, 0.02, 0.02))
	for d in range(-30, 31, 5):
		var deg := int(roundi(hdg / 5.0) * 5 + d)
		var x := box.get_center().x + (deg - hdg) * box.size.x / 60.0
		if x < box.position.x + 4 or x > box.end.x - 4:
			continue
		var big := posmod(deg, 30) == 0
		draw_line(Vector2(x, box.position.y + 2), Vector2(x, box.position.y + (12 if big else 7)), Color.WHITE, 1.5)
		if big:
			var names := {0: "N", 90: "E", 180: "S", 270: "W"}
			var t: String = names.get(posmod(deg, 360), str(posmod(deg, 360) / 10))
			draw_string(font, Vector2(x - 6, box.end.y - 4), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	draw_line(Vector2(box.get_center().x, box.position.y), Vector2(box.get_center().x, box.end.y), Color(1, 0.5, 0.1), 2.0)
	for i in _gauges.size():
		var r: Array = _gauges[i]
		var y := row_h * (i + 1.5)
		var v := Props.get_f(r[1])
		draw_string(font, Vector2(4, y + 5), r[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.85, 0.8))
		var bar := Rect2(Vector2(w * 0.36, y - 6), Vector2(w * 0.4, 12))
		draw_rect(bar, Color(0.12, 0.12, 0.13))
		var span: float = r[3] - r[2]
		var gx0: float = bar.position.x + (r[4] - r[2]) / span * bar.size.x
		var gx1: float = bar.position.x + (r[5] - r[2]) / span * bar.size.x
		draw_rect(Rect2(Vector2(gx0, y + 3), Vector2(gx1 - gx0, 3)), Color(0.1, 0.7, 0.2))
		if r[6] > 0.0:
			var rx: float = bar.position.x + (r[6] - r[2]) / span * bar.size.x
			draw_line(Vector2(rx, y - 7), Vector2(rx, y + 7), Color(0.9, 0.1, 0.1), 2.0)
		var px: float = bar.position.x + clampf((v - r[2]) / span, 0.0, 1.0) * bar.size.x
		draw_colored_polygon(PackedVector2Array([Vector2(px, y - 2), Vector2(px - 5, y - 9), Vector2(px + 5, y - 9)]), Color.WHITE)
		draw_string(font, Vector2(w * 0.79, y + 5), r[7] % v, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
