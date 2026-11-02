class_name SdPages
extends RefCounted
## The pages of the system display, drawn onto the SD (static helpers, design 520 x 420 px). Props read
## only: instruments/engines/<n>/*, fuel/{tank_kg, tank_cap_kg, total_kg}, engines/<n>/ff, fdm/{gear_pos,
## aileron_deg, elevator_deg, rudder_deg, stabilizer_deg, spoiler_deg}, controls/{autobrake, parking_brake,
## aileron, elevator, rudder}. Missing props draw as zero.

const A320_TANKS_KG := [691.0, 5712.0, 6633.0, 5712.0, 691.0]  # L outer, L inner, centre, R inner, R outer
const TANK_NAMES := ["L OUTER", "L INNER", "CENTER", "R INNER", "R OUTER"]


static func _bar(d: Display, r: Rect2, frac: float, col: Color) -> void:
	d.fill(r, Color(0.15, 0.15, 0.17))
	d.fill(Rect2(r.position.x, r.end.y - r.size.y * clampf(frac, 0.0, 1.0), r.size.x, r.size.y * clampf(frac, 0.0, 1.0)), col)
	d.frame(r, Display.GREY, 1.0)


static func eng(d: Display) -> void:
	d.txt(Vector2(260, 44), "ENGINE", 20, Display.WHITE, 0)
	var n := clampi(int(Props.get_f("instruments/engines/count", 2.0)), 1, 4)
	for i in n:
		var x := 520.0 * (i + 0.5) / n
		var b := "instruments/engines/%d/" % (i + 1)
		d.txt(Vector2(x, 90), "ENG %d" % (i + 1), 16, Display.WHITE, 0)
		var psi := Props.get_f(b + "oil_psi")
		d.txt(Vector2(x, 128), "OIL PSI", 13, Display.CYAN, 0)
		_bar(d, Rect2(x - 12, 150, 24, 130), psi / 100.0, Display.GREEN if psi >= 20.0 or not Props.get_b(b + "running") else Display.AMBER)
		d.txt(Vector2(x, 298), "%d" % roundi(psi), 22, Display.GREEN, 0)
		d.txt(Vector2(x, 336), "N1 %.0f  N2 %.0f" % [Props.get_f(b + "n1_pct"), Props.get_f(b + "n2_pct")], 14, Display.WHITE, 0)


static func fuel(d: Display) -> void:
	d.txt(Vector2(260, 44), "FUEL", 20, Display.WHITE, 0)
	var tanks: Array = Props.get_v("fuel/tank_kg", [])
	var caps: Array = Props.get_v("fuel/tank_cap_kg", A320_TANKS_KG)
	var xs := [60.0, 150.0, 260.0, 370.0, 460.0]
	var wing_y := 110.0
	for i in 5:
		var kg: float = tanks[i] if i < tanks.size() else 0.0
		var cap: float = caps[i] if i < caps.size() else A320_TANKS_KG[i]
		var w := 56.0 if i != 2 else 90.0
		var r := Rect2(xs[i] - w * 0.5, wing_y, w, 70.0)
		_bar(d, Rect2(r.position + Vector2(0, 0), Vector2(r.size.x, r.size.y)), kg / maxf(cap, 1.0), Display.GREEN if kg > 0.02 * cap else Display.AMBER)
		d.txt(Vector2(xs[i], wing_y + 92), "%d" % roundi(kg), 17, Display.GREEN, 0)
		d.txt(Vector2(xs[i], wing_y - 12), TANK_NAMES[i], 11, Display.CYAN, 0)
	for e in 2:
		var x := 150.0 + e * 220.0
		d.frame(Rect2(x - 34, 270, 68, 38), Display.WHITE, 1.5)
		d.txt(Vector2(x, 281), "ENG %d" % (e + 1), 12, Display.WHITE, 0)
		d.txt(Vector2(x, 298), "%d KG/H" % roundi(Props.get_f("instruments/engines/%d/ff_kgh" % (e + 1))), 12, Display.GREEN, 0)
		d.line(Vector2(x, 270), Vector2(x, 218), Display.GREEN, 2.0)
	d.txt(Vector2(260, 340), "FOB  %d KG" % roundi(Props.get_f("fuel/total_kg")), 20, Display.GREEN, 0)


static func _gear_state(i: int) -> float:
	var g: Variant = Props.get_v("fdm/gear_pos", 1.0)
	return float(g[i]) if g is Array and i < g.size() else (float(g) if not g is Array else 1.0)


static func wheel(d: Display) -> void:
	d.txt(Vector2(260, 44), "WHEEL", 20, Display.WHITE, 0)
	var pos := [Vector2(260, 130), Vector2(110, 230), Vector2(410, 230)]
	for i in 3:
		var g := _gear_state(i)
		var col := Display.GREEN if g > 0.99 else (Display.AMBER if g > 0.01 else Display.GREY)
		var c: Vector2 = pos[i]
		d.poly(PackedVector2Array([c + Vector2(0, -22), c + Vector2(22, 16), c + Vector2(-22, 16)]), col if g > 0.01 else Color(0.2, 0.2, 0.22))
		d.txt(c + Vector2(0, 36), ["NOSE", "L", "R"][i] if g > 0.01 else "UP", 14, col, 0)
		d.txt(c + Vector2(0, 54), "DOWN" if g > 0.99 else ("UNLK" if g > 0.01 else ""), 13, col, 0)
	var ab: int = int(Props.get_f("controls/autobrake"))
	d.txt(Vector2(20, 340), "A/BRK", 14, Display.CYAN)
	d.txt(Vector2(90, 340), ["OFF", "LO", "MED", "MAX"][clampi(ab, 0, 3)], 18, Display.GREEN if ab > 0 else Display.WHITE)
	if Props.get_b("controls/parking_brake"):
		d.txt(Vector2(260, 340), "PARK BRK ON", 18, Display.AMBER)


static func flt_ctl(d: Display) -> void:
	d.txt(Vector2(260, 44), "F/CTL", 20, Display.WHITE, 0)
	var ail := Props.get_f("fdm/aileron_deg", Props.get_f("controls/aileron") * 25.0)
	var elv := Props.get_f("fdm/elevator_deg", Props.get_f("controls/elevator") * -30.0)
	var rud := Props.get_f("fdm/rudder_deg", Props.get_f("controls/rudder") * 30.0)
	var ths := Props.get_f("fdm/stabilizer_deg")
	var spl := Props.get_f("fdm/spoiler_deg")
	for s: float in [-1.0, 1.0]:
		var x := 260.0 + s * 150.0
		d.frame(Rect2(x - 40, 100, 80, 14), Display.GREY, 1.0)  # wing
		var a := ail * s  # right aileron up when the left is down
		d.fill(Rect2(x - 40 + (0 if s < 0 else 50), 118, 30, 4 + absf(a) * 2.0), Display.GREEN)
		d.txt(Vector2(x + s * 20, 150), "AIL %d" % roundi(a), 12, Display.GREEN, 0)
		for k in 5:
			var h := spl * 0.4
			d.fill(Rect2(x - 36 + k * 16, 100 - h, 12, h), Display.GREEN if spl > 1.0 else Color(0.2, 0.2, 0.22))
		d.fill(Rect2(x - 25, 230, 50, 6 + absf(elv)), Display.GREEN)
		d.txt(Vector2(x, 262), "ELEV %d" % roundi(elv), 12, Display.GREEN, 0)
	d.txt(Vector2(260, 180), "SPLR %d" % roundi(spl), 13, Display.GREEN, 0)
	d.txt(Vector2(260, 300), "RUD %d" % roundi(rud), 14, Display.GREEN, 0)
	d.fill(Rect2(260 + rud * 2.0 - 3, 312, 6, 24), Display.GREEN)
	d.line(Vector2(200, 324), Vector2(320, 324), Display.GREY, 1.0)
	d.txt(Vector2(260, 360), "PITCH TRIM %+.1f" % ths, 14, Display.CYAN, 0)
