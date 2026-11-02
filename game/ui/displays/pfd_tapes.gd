class_name PfdTapes
extends RefCounted
## The scales around the PFD attitude sphere: speed tape (left), altitude tape and vertical speed
## (right), heading arc (bottom). Static drawing helpers taking the Display `d` they draw on; all values
## come from Props instruments/pfd/*, instruments/adirs/* and controls/fcu/*. Geometry in PFD design px.

const CY := 221.0  # centre line of the tapes (the aircraft symbol)
const TAPE := Color(0.17, 0.18, 0.21)
const SPD_R := Rect2(6, 84, 88, 274)
const ALT_R := Rect2(466, 84, 80, 274)
const VS_R := Rect2(552, 84, 44, 274)
const PX_KT := 3.0
const PX_FT := 0.27
const ARC_C := Vector2(280, 590)
const ARC_R := 190.0


## Vertical band x..x+w between y0 and y1 (any order, clipped to the speed tape): solid, or red and
## black stripes.
static func _band(d: Display, x: float, w: float, y0: float, y1: float, col: Color, striped: bool) -> void:
	var top := clampf(minf(y0, y1), SPD_R.position.y, SPD_R.end.y)
	var bot := clampf(maxf(y0, y1), SPD_R.position.y, SPD_R.end.y)
	var y := top
	var k := 0
	while y < bot:
		var h := minf(8.0 if striped else bot - y, bot - y)
		d.fill(Rect2(x, y, w, h), col if k % 2 == 0 else Color.BLACK)
		y += h
		k += 1


static func speed(d: Display) -> void:
	var ias := Props.get_f("instruments/pfd/ias_kt")
	var ok := Props.get_b("instruments/pfd/valid", true)
	d.fill(SPD_R, TAPE)
	for v in DispMath.tape_marks(ias, PX_KT, SPD_R.size.y * 0.5, 10.0):
		var y := DispMath.tape_y(v, ias, PX_KT, CY)
		if v < 30.0 or y < SPD_R.position.y or y > SPD_R.end.y:
			continue
		d.line(Vector2(SPD_R.end.x, y), Vector2(SPD_R.end.x - (14 if int(v) % 20 == 0 else 8), y), Display.WHITE, 2.0)
		if int(v) % 20 == 0:
			d.txt(Vector2(SPD_R.end.x - 20, y), "%d" % v, 18, Display.WHITE, 1)
	var vls := Props.get_f("instruments/pfd/vls_kt")
	var vsw := Props.get_f("instruments/pfd/vsw_kt")
	var vmax := Props.get_f("instruments/pfd/vmax_kt")
	if vls > 0.0:
		var yl := DispMath.tape_y(vls, ias, PX_KT, CY)
		var ys := DispMath.tape_y(vsw, ias, PX_KT, CY)
		_band(d, SPD_R.end.x - 5, 5, yl, ys, Display.AMBER, false)
		_band(d, SPD_R.end.x - 9, 9, ys, SPD_R.end.y, Display.RED, true)
		_band(d, SPD_R.end.x - 9, 9, SPD_R.position.y, DispMath.tape_y(vmax, ias, PX_KT, CY), Display.RED, true)
	var sel := Props.get_f("controls/fcu/spd_kt", 0.0)
	if sel > 0.0:
		var col := Display.MAGENTA if Props.get_b("controls/fcu/spd_managed") else Display.CYAN
		var y := clampf(DispMath.tape_y(sel, ias, PX_KT, CY), SPD_R.position.y + 6, SPD_R.end.y - 6)
		d.poly(PackedVector2Array([Vector2(94, y), Vector2(106, y - 7), Vector2(106, y + 7)]), col)
		d.txt(Vector2(50, 71), "%d" % sel, 20, col, 0)
	var trend := Props.get_f("instruments/pfd/trend_kt")
	if absf(trend) > 2.0:
		var ty := DispMath.tape_y(ias + trend, ias, PX_KT, CY)
		d.line(Vector2(86, CY), Vector2(86, ty), Display.GREEN, 3.0)
		d.arrow(Vector2(86, ty), 0.0 if trend > 0 else PI, 9, 6, Display.GREEN)
	d.fill(Rect2(26, CY - 17, 68, 34), Color.BLACK)
	d.frame(Rect2(26, CY - 17, 68, 34), Display.AMBER if not ok else Display.GREY, 2.0)
	d.poly(PackedVector2Array([Vector2(94, CY), Vector2(106, CY - 7), Vector2(106, CY + 7)]), Display.AMBER)
	if ok:
		d.txt(Vector2(88, CY), "%d" % int(ias), 26, Display.GREEN, 1)
	else:
		d.txt(Vector2(60, CY), "SPD", 22, Display.RED, 0)
	var mach := Props.get_f("instruments/pfd/mach")
	if mach >= 0.5 and ok:
		d.txt(Vector2(50, 372), ("%.3f" % mach).substr(1), 22, Display.GREEN, 0)


static func altitude(d: Display) -> void:
	var alt := Props.get_f("instruments/pfd/alt_ft")
	var ok := Props.get_b("instruments/pfd/valid", true)
	d.fill(ALT_R, TAPE)
	for v in DispMath.tape_marks(alt, PX_FT, ALT_R.size.y * 0.5, 100.0):
		var y := DispMath.tape_y(v, alt, PX_FT, CY)
		if y < ALT_R.position.y or y > ALT_R.end.y:
			continue
		var lab := int(roundf(v / 100.0)) % 2 == 0
		d.line(Vector2(ALT_R.position.x, y), Vector2(ALT_R.position.x + (14 if lab else 8), y), Display.WHITE, 2.0)
		if lab:
			d.txt(Vector2(ALT_R.position.x + 20, y), "%d" % absi(int(v / 100.0)), 18, Display.WHITE)
	var sel := Props.get_f("controls/fcu/alt_ft", -1.0)
	if sel >= 0.0:
		var y := clampf(DispMath.tape_y(sel, alt, PX_FT, CY), ALT_R.position.y + 8, ALT_R.end.y - 8)
		d.frame(Rect2(ALT_R.position.x - 2, y - 8, 22, 16), Display.CYAN, 3.0)
		d.txt(Vector2(ALT_R.get_center().x, 71), "%d" % sel, 20, Display.CYAN, 0)
	d.fill(Rect2(ALT_R.position.x - 4, CY - 17, 82, 34), Color.BLACK)
	d.frame(Rect2(ALT_R.position.x - 4, CY - 17, 82, 34), Display.AMBER if not ok else Display.GREY, 2.0)
	d.poly(PackedVector2Array([Vector2(ALT_R.position.x - 4, CY), Vector2(ALT_R.position.x - 14, CY - 7), Vector2(ALT_R.position.x - 14, CY + 7)]), Display.AMBER)
	if ok:
		var v := DispMath.round_alt(alt)
		d.txt(Vector2(ALT_R.position.x + 48, CY), "%d" % (v / 100), 26, Display.GREEN, 1)
		d.txt(Vector2(ALT_R.position.x + 50, CY + 2), "%02d" % absi(v % 100), 18, Display.GREEN)
	else:
		d.txt(Vector2(ALT_R.get_center().x, CY), "ALT", 22, Display.RED, 0)
	var std := Props.get_b("instruments/pfd/baro_std")
	d.txt(Vector2(ALT_R.get_center().x, 372), "STD" if std else "%d" % roundi(Props.get_f("instruments/pfd/baro_hpa", 1013.25)), 20, Display.CYAN, 0)


static func vertical_speed(d: Display) -> void:
	var vs := Props.get_f("instruments/pfd/vs_fpm")
	var half := VS_R.size.y * 0.5
	d.fill(VS_R, Color(0.12, 0.13, 0.15))
	for k in [-6000, -4000, -2000, -1000, -500, 0, 500, 1000, 2000, 4000, 6000]:
		var y := CY - DispMath.vs_frac(k) * half
		d.line(Vector2(VS_R.position.x, y), Vector2(VS_R.position.x + (10 if k % 1000 == 0 else 5), y), Display.WHITE, 1.5)
		if k != 0 and k % 1000 == 0 and absi(k) <= 6000 and absi(k) != 3000:
			d.txt(Vector2(VS_R.position.x + 14, y), "%d" % (absi(k) / 1000), 13, Display.WHITE)
	var yv := CY - DispMath.vs_frac(vs) * half
	d.line(Vector2(VS_R.end.x, CY), Vector2(VS_R.position.x + 24, yv), Display.GREEN, 3.0)
	if absf(vs) >= 200.0:
		var ty := clampf(yv + (-16.0 if vs > 0 else 16.0), VS_R.position.y + 8, VS_R.end.y - 8)
		d.txt(Vector2(VS_R.end.x - 2, ty), "%d" % (roundi(absf(vs) / 100.0) * 100), 14, Display.GREEN, 1)
	if not Props.get_b("instruments/pfd/valid", true):
		d.txt(Vector2(VS_R.get_center().x, CY), "VS", 16, Display.RED, 0)


static func heading(d: Display) -> void:
	var hdg := Props.get_f("instruments/adirs/heading_deg")
	var trk := Props.get_f("instruments/adirs/track_deg")
	d.fill(Rect2(0, 396, 600, 84), Color.BLACK)
	for h in range(int(floorf((hdg - 42.0) / 5.0)) * 5, int(hdg + 42.0) + 5, 5):
		var a := deg_to_rad(DispMath.wrap180(h - hdg))
		if absf(a) > deg_to_rad(40.0):
			continue
		var big := posmod(h, 10) == 0
		d.line(DispMath.polar(ARC_C, ARC_R, a), DispMath.polar(ARC_C, ARC_R - (14 if big else 7), a), Display.WHITE, 2.0)
		if posmod(h, 10) == 0:
			var hh := posmod(h, 360) / 10
			d.txt(DispMath.polar(ARC_C, ARC_R - 28, a), "%02d" % hh, 17, Display.WHITE, 0)
	d.arc(ARC_C, ARC_R, deg_to_rad(-40), deg_to_rad(40), Display.WHITE, 2.0)
	d.poly(PackedVector2Array([Vector2(280, ARC_C.y - ARC_R - 2), Vector2(271, ARC_C.y - ARC_R - 14), Vector2(289, ARC_C.y - ARC_R - 14)]), Display.AMBER)
	var sel := Props.get_f("controls/fcu/hdg_deg", -1.0)
	if sel >= 0.0:
		var a := clampf(deg_to_rad(DispMath.wrap180(sel - hdg)), deg_to_rad(-39), deg_to_rad(39))
		d.arrow(DispMath.polar(ARC_C, ARC_R + 1, a), a + PI, 12, 7, Display.MAGENTA if Props.get_b("controls/fcu/hdg_managed") else Display.CYAN)
	var ta := clampf(deg_to_rad(DispMath.wrap180(trk - hdg)), deg_to_rad(-39), deg_to_rad(39))
	var tp := DispMath.polar(ARC_C, ARC_R - 4, ta)
	d.poly(PackedVector2Array([tp + Vector2(0, -8), tp + Vector2(7, 0), tp + Vector2(0, 8), tp + Vector2(-7, 0)]), Display.GREEN)
	if not Props.get_b("instruments/adirs/valid", true):
		d.txt(Vector2(280, 440), "HDG", 22, Display.RED, 0)
