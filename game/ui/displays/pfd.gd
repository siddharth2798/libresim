class_name PFD
extends Display
## Primary flight display: attitude sphere with pitch ladder, roll scale, slip, flight-director bars,
## ILS deviation and radio altitude; the FMA row on top; the scales around it are in pfd_tapes.gd.
## Reads Props only: instruments/adirs/* (attitude, heading), instruments/pfd/* (air data),
## controls/fcu/{spd_kt, alt_ft, hdg_deg, spd_managed, hdg_managed}, ap/{ap1, ap2, athr, fd,
## fd_pitch_rad, fd_roll_rad (commanded attitude)}, ap/fma/{thrust, vertical, lateral, approach, misc}
## (strings, "\n" separates lines), avionics/nav{2,1}/* for the ILS.

const Z := Rect2(104, 62, 352, 318)
const PX_DEG := 7.0  # pitch ladder px per degree
var _c := Z.get_center()


func _init() -> void:
	design = Vector2(600, 480)


func _paint() -> void:
	var ok := Props.get_b("instruments/adirs/valid", true)
	var pitch := rad_to_deg(Props.get_f("instruments/adirs/pitch_rad"))
	var roll := Props.get_f("instruments/adirs/roll_rad")
	_sphere(pitch, roll)
	if ok:
		_ladder(pitch, roll)
		_flight_director(pitch, roll)
	_roll_scale(roll, ok)
	_ils()
	_symbol()
	PfdTapes.speed(self)
	PfdTapes.altitude(self)
	PfdTapes.vertical_speed(self)
	PfdTapes.heading(self)
	_fma()
	var ra := Props.get_f("instruments/pfd/ra_ft", -1.0)
	if ra >= 0.0 and Props.get_b("instruments/pfd/valid", true):
		txt(_c + Vector2(0, 118), "%d" % (roundi(ra) if ra < 50.0 else roundi(ra / 10.0) * 10), 24, AMBER if ra < 400.0 else GREEN, 0)
	if not ok:
		txt(_c + Vector2(0, -20), "ATT", 30, RED, 0)


func _sphere(pitch: float, roll: float) -> void:
	fill(Z, SKY if Props.get_b("instruments/adirs/valid", true) else Color(0.1, 0.1, 0.1))
	var hy := _c.y + pitch * PX_DEG
	var g := PackedVector2Array()
	for p: Vector2 in [Vector2(-900, 0), Vector2(900, 0), Vector2(900, 900), Vector2(-900, 900)]:
		g.append(DispMath.sphere_point(Vector2(_c.x + p.x, hy + p.y), _c, roll))
	poly(DispMath.clip_poly(g, Z), GROUND)
	_seg(Vector2(_c.x - 900, hy), Vector2(_c.x + 900, hy), roll, WHITE, 2.5)


## Line given in the unrolled sphere frame, rolled and clipped to the sphere window.
func _seg(a: Vector2, b: Vector2, roll: float, col: Color, w: float) -> void:
	var cl := DispMath.clip_line(DispMath.sphere_point(a, _c, roll), DispMath.sphere_point(b, _c, roll), Z)
	if cl.size() == 2:
		line(cl[0], cl[1], col, w)


func _ladder(pitch: float, roll: float) -> void:
	for i in range(-12, 13):
		var deg := i * 2.5
		if i == 0 or absf(deg - pitch) > 24.0:
			continue
		var y := _c.y + (pitch - deg) * PX_DEG
		var big := i % 4 == 0
		var half := 46.0 if big else (24.0 if i % 2 == 0 else 11.0)
		_seg(Vector2(_c.x - half, y), Vector2(_c.x + half, y), roll, WHITE, 2.0)
		if big:
			for s: float in [-1.0, 1.0]:
				var p := DispMath.sphere_point(Vector2(_c.x + s * (half + 16), y), _c, roll)
				if Z.grow(-14).has_point(p):
					txt(p, "%d" % absi(int(deg)), 15, WHITE, 0)


func _roll_scale(roll: float, ok: bool) -> void:
	var r := 140.0
	for b in [-45, -30, -20, -10, 0, 10, 20, 30, 45]:
		var a := deg_to_rad(b)
		var len := 14.0 if b in [-45, -30, 0, 30, 45] else 8.0
		line(DispMath.polar(_c, r, a), DispMath.polar(_c, r - len, a), WHITE, 2.0)
	arc(_c, r, deg_to_rad(-60), deg_to_rad(60), WHITE, 1.5)
	var a := clampf(-roll, -deg_to_rad(60), deg_to_rad(60))
	var tip := DispMath.polar(_c, r - 1, a)
	arrow(tip, a + PI, 14, 8, AMBER if ok else RED)
	var slip := Props.get_f("instruments/adirs/slip") * 18.0
	var base := DispMath.polar(_c, r - 18, a)
	var along := Vector2(cos(a), sin(a))
	var q := PackedVector2Array([base + along * (slip - 10), base + along * (slip + 10), base + along * (slip + 8) + Vector2(0, 7).rotated(a), base + along * (slip - 8) + Vector2(0, 7).rotated(a)])
	poly(q, AMBER)


func _symbol() -> void:
	for s: float in [-1.0, 1.0]:
		var p0 := _c + Vector2(s * 98, 0)
		var p1 := _c + Vector2(s * 48, 0)
		line(p0, p1, Color.BLACK, 9.0)
		line(p1, p1 + Vector2(0, 11), Color.BLACK, 9.0)
		line(p0, p1, AMBER, 5.0)
		line(p1, p1 + Vector2(0, 11), AMBER, 5.0)
	fill(Rect2(_c - Vector2(5, 5), Vector2(10, 10)), AMBER)


func _flight_director(pitch: float, roll: float) -> void:
	if not Props.get_b("ap/fd"):
		return
	var py := _c.y - (rad_to_deg(Props.get_f("ap/fd_pitch_rad")) - pitch) * PX_DEG
	var rx := _c.x + (rad_to_deg(Props.get_f("ap/fd_roll_rad")) - rad_to_deg(roll)) * 4.0
	py = clampf(py, Z.position.y + 20, Z.end.y - 20)
	rx = clampf(rx, Z.position.x + 20, Z.end.x - 20)
	line(Vector2(_c.x - 62, py), Vector2(_c.x + 62, py), GREEN, 5.0)
	line(Vector2(rx, _c.y - 62), Vector2(rx, _c.y + 62), GREEN, 5.0)


func _ils() -> void:
	for n in [2, 1]:
		var b := "avionics/nav%d/" % n
		if str(Props.get_v(b + "kind", "")) != "ILS" or not Props.get_b(b + "valid"):
			continue
		var y := Z.end.y - 12.0
		for k in [-72, -36, 36, 72]:
			dot(Vector2(_c.x + k, y), 3.5, WHITE)
		line(Vector2(_c.x, y - 7), Vector2(_c.x, y + 7), AMBER, 2.0)
		var dx := _c.x + clampf(Props.get_f(b + "cdi"), -1.0, 1.0) * 72.0
		poly(PackedVector2Array([Vector2(dx, y - 9), Vector2(dx + 9, y), Vector2(dx, y + 9), Vector2(dx - 9, y)]), MAGENTA)
		if Props.get_b(b + "gs_valid"):
			var x := Z.end.x - 12.0
			for k in [-72, -36, 36, 72]:
				dot(Vector2(x, _c.y + k), 3.5, WHITE)
			line(Vector2(x - 7, _c.y), Vector2(x + 7, _c.y), AMBER, 2.0)
			var gy := _c.y - clampf(Props.get_f(b + "gs"), -1.0, 1.0) * 72.0
			poly(PackedVector2Array([Vector2(x, gy - 9), Vector2(x + 9, gy), Vector2(x, gy + 9), Vector2(x - 9, gy)]), MAGENTA)
		txt(Vector2(Z.position.x + 6, Z.end.y - 38), str(Props.get_v(b + "ident", "ILS")), 16, MAGENTA)
		var dme := Props.get_f(b + "dme_nm", -1.0)
		if dme >= 0.0:
			txt(Vector2(Z.position.x + 6, Z.end.y - 20), "%.1f NM" % dme, 16, MAGENTA)
		return


func _fma() -> void:
	fill(Rect2(0, 0, 600, 58), Color.BLACK)
	var cols := ["thrust", "vertical", "lateral", "approach", "misc"]
	for i in 5:
		var s := str(Props.get_v("ap/fma/" + cols[i], ""))
		if i == 4 and s == "":
			s = _status_lines()
		var x := i * 120.0
		if i > 0:
			line(Vector2(x, 2), Vector2(x, 56), GREY, 1.0)
		var n := 0
		for ln in s.split("\n"):
			if n >= 3:
				break
			var col := GREEN if i < 3 and n == 0 else (WHITE if i >= 3 else CYAN)
			if i == 4 and ln == "A/THR":
				col = CYAN
			txt(Vector2(x + 60, 12 + n * 18), ln, 16, col, 0)
			n += 1


func _status_lines() -> String:
	var ap1 := Props.get_b("ap/ap1")
	var ap2 := Props.get_b("ap/ap2")
	var lines := []
	lines.append("AP1+2" if ap1 and ap2 else ("AP1" if ap1 else ("AP2" if ap2 else "")))
	lines.append("1FD2" if Props.get_b("ap/fd") else "")
	lines.append("A/THR" if Props.get_b("ap/athr") else "")
	return "\n".join(lines)
