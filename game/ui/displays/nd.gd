class_name ND
extends Display
## Navigation display: ARC or ROSE view, heading up, with the compass scale, heading / track /
## selected-heading marks, range rings, track line, route (magenta) and nearby airports and VORs, ground
## speed / TAS, wind and the active waypoint. Reads Props only: instruments/adirs/{heading_deg,
## track_deg}, instruments/pfd/tas_kt, fdm/{groundspeed_mps, position_enu}, controls/fcu/hdg_deg,
## avionics/gps/{valid, ident, dist_nm, ete}, instruments/nd/{route, near, wind_dir_deg, wind_kt}
## (instruments/nd_feed.gd). Writes controls/nd/mode (0 ARC, 1 ROSE) and controls/nd/range_nm
## when the mode / range labels (top left / right under the header) are clicked.

const RANGES := [10, 20, 40, 80, 160, 320]
const NM := 1852.0
var _c := Vector2.ZERO
var _r := 0.0
var _rose := false
var _range_m := 40.0 * NM
var _hdg := 0.0


func _init() -> void:
	design = Vector2(600, 560)


func _press(id: String, _b: int, _p: Vector2) -> void:
	if id == "mode":
		Props.set_v("controls/nd/mode", 1 - int(Props.get_f("controls/nd/mode")))
	elif id == "range":
		var i := RANGES.find(int(Props.get_f("controls/nd/range_nm", 40.0)))
		Props.set_v("controls/nd/range_nm", float(RANGES[(i + 1) % RANGES.size()]))


func _wheel(id: String, dir: float) -> void:
	if id == "range":
		var i := maxi(RANGES.find(int(Props.get_f("controls/nd/range_nm", 40.0))), 0)
		Props.set_v("controls/nd/range_nm", float(RANGES[clampi(i + int(dir), 0, RANGES.size() - 1)]))


func _paint() -> void:
	_rose = Props.get_f("controls/nd/mode") >= 1.0
	_range_m = Props.get_f("controls/nd/range_nm", 40.0) * NM
	_hdg = Props.get_f("instruments/adirs/heading_deg")
	_c = Vector2(300, 318) if _rose else Vector2(300, 490)
	_r = 200.0 if _rose else 380.0
	_rings()
	_map()
	_compass()
	_ownship()
	_header()


func _ang(deg: float) -> float:
	return deg_to_rad(DispMath.wrap180(deg - _hdg))


func _vis(p: Vector2) -> bool:
	return p.distance_to(_c) <= _r and (_rose or p.y <= _c.y + 4.0)


func _rings() -> void:
	var span := Vector2(-PI, PI) if _rose else Vector2(-deg_to_rad(52), deg_to_rad(52))
	for k in [0.25, 0.5, 0.75]:
		var n := 36
		for i in n:
			if i % 2 == 0:
				var a0: float = lerpf(span.x, span.y, float(i) / n)
				var a1: float = lerpf(span.x, span.y, float(i + 1) / n)
				arc(_c, _r * k, a0, a1, Color(0.45, 0.47, 0.5), 1.5)
	txt(_c + Vector2(6, -_r * 0.5 - 2) if not _rose else _c + Vector2(6, -_r * 0.5), "%d" % (_range_m / NM / 2.0), 14, WHITE)
	txt(_c + Vector2(6, -_r * 0.25), "%d" % (_range_m / NM / 4.0), 12, Color(0.7, 0.7, 0.72))


func _compass() -> void:
	var lo := -PI if _rose else -deg_to_rad(52)
	var hi := PI if _rose else deg_to_rad(52)
	arc(_c, _r, lo, hi, WHITE, 2.0)
	var h0 := int(floorf((_hdg - 55.0) / 5.0)) * 5 if not _rose else 0
	var h1 := int(_hdg + 55.0) if not _rose else 355
	for h in range(h0, h1 + 1, 5):
		var a := _ang(h)
		if not _rose and absf(a) > deg_to_rad(52):
			continue
		var big := posmod(h, 10) == 0
		line(DispMath.polar(_c, _r, a), DispMath.polar(_c, _r - (14.0 if big else 7.0), a), WHITE, 2.0)
		if big:
			var hh := posmod(h, 360) / 10
			var lab := "%d" % hh
			if hh % 9 == 0:
				lab = {0: "N", 9: "E", 18: "S", 27: "W"}.get(hh, lab) if _rose else lab
			txt(DispMath.polar(_c, _r - 28.0, a), lab, 15, WHITE if hh % 3 == 0 else Color(0.75, 0.75, 0.78), 0)
	# heading index
	var top := DispMath.polar(_c, _r + 2.0, 0.0)
	poly(PackedVector2Array([top, top + Vector2(-8, -14), top + Vector2(8, -14)]), AMBER)
	# selected heading, track
	var sel := Props.get_f("controls/fcu/hdg_deg", -1.0)
	if sel >= 0.0:
		var a := _ang(sel)
		if _rose or absf(a) < deg_to_rad(52):
			arrow(DispMath.polar(_c, _r + 1.0, a), a + PI, 14, 8, CYAN)
	var ta := _ang(Props.get_f("instruments/adirs/track_deg"))
	var tp := DispMath.polar(_c, _r - 5.0, ta)
	poly(PackedVector2Array([tp + Vector2(0, -8), tp + Vector2(7, 0), tp + Vector2(0, 8), tp + Vector2(-7, 0)]), GREEN)
	line(_c, DispMath.polar(_c, _r - 10.0, ta), GREEN, 2.0)


func _map() -> void:
	if not Props.has("fdm/position_enu"):
		return
	var p3: Vector3 = Props.get_v("fdm/position_enu", Vector3.ZERO)
	var me := Vector2(p3.x, p3.y)
	var h := deg_to_rad(_hdg)
	var on_route := []
	for w in Array(Props.get_v("instruments/nd/route", [])):
		on_route.append(w.id)
	for n in Array(Props.get_v("instruments/nd/near", [])):
		if n.id in on_route:
			continue
		var s := DispMath.nd_project(Vector2(n.x, n.y) - me, h, _range_m, _c, _r)
		if not _vis(s):
			continue
		match str(n.kind):
			"apt":
				dot(s, 5.0, MAGENTA)
				dot(s, 3.0, BG)
				txt(s + Vector2(8, 0), str(n.id), 14, WHITE)
			"vor":
				poly(PackedVector2Array([s + Vector2(0, -7), s + Vector2(6, 0), s + Vector2(0, 7), s + Vector2(-6, 0)]), CYAN)
				txt(s + Vector2(8, 0), str(n.id), 14, CYAN)
	var prev := _c
	var first := true
	for w in Array(Props.get_v("instruments/nd/route", [])):
		var s := DispMath.nd_project(Vector2(w.x, w.y) - me, h, _range_m, _c, _r)
		var a := _clip_to_disc(prev, s)
		if a.size() == 2:
			line(a[0], a[1], MAGENTA, 3.0 if first else 2.0)
		if _vis(s):
			fill(Rect2(s - Vector2(5, 5), Vector2(10, 10)), MAGENTA if not first else WHITE)
			txt(s + Vector2(9, -8), str(w.id), 15, MAGENTA if not first else WHITE)
		prev = s
		first = false


## Segment a-b limited to the display area (the disc, in ARC mode also above the aircraft).
func _clip_to_disc(a: Vector2, b: Vector2) -> PackedVector2Array:
	var box := Rect2(_c - Vector2(_r, _r), Vector2(_r * 2, _r * 2 if _rose else _r + 4.0))
	var cl := DispMath.clip_line(a, b, box)
	return cl


func _ownship() -> void:
	var c := _c
	line(c + Vector2(0, -16), c + Vector2(0, 18), AMBER, 3.0)
	line(c + Vector2(-16, 2), c + Vector2(16, 2), AMBER, 3.0)
	line(c + Vector2(-6, 16), c + Vector2(6, 16), AMBER, 3.0)


func _header() -> void:
	var gs := Units.mps_to_kt(Props.get_f("fdm/groundspeed_mps"))
	txt(Vector2(8, 14), "GS", 14, WHITE)
	txt(Vector2(34, 14), "%d" % gs, 20, GREEN)
	txt(Vector2(92, 14), "TAS", 14, WHITE)
	txt(Vector2(124, 14), "%d" % Props.get_f("instruments/pfd/tas_kt"), 20, GREEN)
	var wk := Props.get_f("instruments/nd/wind_kt")
	if wk >= 1.0:
		var wd := Props.get_f("instruments/nd/wind_dir_deg")
		txt(Vector2(592, 14), "%03d/%d" % [roundi(wd), roundi(wk)], 20, GREEN, 1)
		arrow(Vector2(540, 40), _ang(wd) + PI, 14, 6, GREEN)
	else:
		txt(Vector2(592, 14), "---/--", 20, WHITE, 1)
	fill(Rect2(262, 2, 76, 28), Color.BLACK)
	frame(Rect2(262, 2, 76, 28), GREY, 1.5)
	txt(Vector2(300, 16), "%03d" % posmod(roundi(_hdg), 360), 22, GREEN, 0)
	txt(Vector2(8, 50), "ROSE NAV" if _rose else "ARC", 15, CYAN)
	hot(Rect2(4, 38, 120, 24), "mode")
	txt(Vector2(592, 50), "%d NM" % (_range_m / NM), 15, CYAN, 1)
	hot(Rect2(480, 38, 116, 24), "range")
	if Props.get_b("avionics/gps/valid") and str(Props.get_v("avionics/gps/ident", "")) != "":
		var y := 540.0
		txt(Vector2(8, y), str(Props.get_v("avionics/gps/ident", "")), 18, MAGENTA)
		txt(Vector2(140, y), "%d NM" % roundi(Props.get_f("avionics/gps/dist_nm")), 18, MAGENTA)
		txt(Vector2(260, y), str(Props.get_v("avionics/gps/ete", "--")), 18, MAGENTA)
