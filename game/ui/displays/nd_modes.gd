class_name NdModes
extends RefCounted
## The ND modes of the A320 EFIS selector (controls/nd/mode) and what the radio modes add to the rose.
##   0 ARC, 1 ROSE NAV, 2 ROSE VOR, 3 ROSE LS, 4 PLAN. The numbers keep 0 / 1 as before (saved flights); the knob
##   turns through them in its dial order KNOB_ORDER (LS, VOR, NAV, ARC, PLAN).
## ROSE VOR: VOR1 (avionics/nav1) course pointer and deviation bar, cyan, with a TO / FROM arrow.
## ROSE LS: the ILS (avionics/nav2, else nav1, kind "ILS"), magenta, plus the glide slope scale on the right.
## Course = controls/nav<n>/obs_deg; deviation = avionics/nav<n>/cdi_raw (1 = 2 dots, + = fly right), clamped to the
## scale. No signal: the pointer stays, the bar and the scale go. Receiver lines (bottom right): name, frequency,
## CRS, ident, DME. In these two modes the flight plan and the map points are not drawn (as on the A320).

const ARC := 0
const NAV := 1
const VOR := 2
const LS := 3
const PLAN := 4
const NAMES := ["ARC", "ROSE NAV", "ROSE VOR", "ROSE LS", "PLAN"]
const KNOB_ORDER := [LS, VOR, NAV, ARC, PLAN]
const DOT_FRAC := 0.2  # one deviation dot, of the rose radius


static func mode_of(v: float) -> int:
	return clampi(roundi(v), ARC, PLAN)


static func is_rose(m: int) -> bool:
	return m == NAV or m == VOR or m == LS


## The mode `n` detents round the knob from `m` (a label click steps one, wrapping like the knob's click).
static func step(m: int, n: int) -> int:
	var i := maxi(KNOB_ORDER.find(m), 0)
	return KNOB_ORDER[posmod(i + n, KNOB_ORDER.size())]


## The NAV receiver a radio mode shows: VOR -> 1; LS -> the one with an ILS (2 first), else 2. 0 for other modes.
static func receiver(m: int) -> int:
	if m == VOR:
		return 1
	if m == LS:
		for n in [2, 1]:
			if str(Props.get_v("avionics/nav%d/kind" % n, "")) == "ILS":
				return n
		return 2
	return 0


## Screen offset of the deviation bar from the centre for deviation `dev` (1 = 2 dots), course `crs_rel` (rad,
## compass from the top of the display), rose radius `r`. + deviation = the bar right of the course line. Pure.
static func bar_offset(dev: float, crs_rel: float, r: float) -> Vector2:
	var right := Vector2(cos(crs_rel), sin(crs_rel))  # 90 deg clockwise of the course direction (sin, -cos)
	return right * clampf(dev, -1.0, 1.0) * 2.0 * DOT_FRAC * r


## Course pointer, deviation scale and bar, TO / FROM, glide slope (LS) and the receiver lines.
static func draw_radio(d: Display, m: int, c: Vector2, r: float, hdg: float) -> void:
	var n := receiver(m)
	if n == 0:
		return
	var b := "avionics/nav%d/" % n
	var col := Display.MAGENTA if m == LS else Display.CYAN
	var crs := Props.get_f("controls/nav%d/obs_deg" % n)
	var a := deg_to_rad(DispMath.wrap180(crs - hdg))
	var fwd := Vector2(sin(a), -cos(a))
	var right := Vector2(cos(a), sin(a))
	var valid := Props.get_b(b + "valid")
	# pointer: arrow head ahead, tail behind, the middle third left for the bar
	d.line(c + fwd * r * 0.42, c + fwd * r * 0.92, col, 3.0)
	d.arrow(c + fwd * r * 0.98, a, 16, 8, col)
	d.line(c - fwd * r * 0.42, c - fwd * r * 0.92, col, 3.0)
	for k in [-2, -1, 1, 2]:
		d.ring(c + right * k * DOT_FRAC * r, 4.0, Display.WHITE)
	if valid:
		var off := bar_offset(PfdIls.dev(n, "cdi"), a, r)
		d.line(c + off - fwd * r * 0.38, c + off + fwd * r * 0.38, col, 3.0)
		var tf := int(Props.get_f(b + "to_from"))
		if m == VOR and tf != 0:  # small arrow on the bar: up the course for TO, down it for FROM
			d.arrow(c + off + fwd * r * 0.3 * tf, a if tf > 0 else a + PI, 14, 7, Display.WHITE)
		if m == LS and Props.get_b(b + "gs_valid"):
			var x := c.x + r + 40.0
			for k in [-2, -1, 1, 2]:
				d.dot(Vector2(x, c.y + k * 36.0), 3.5, Display.WHITE)
			d.line(Vector2(x - 7, c.y), Vector2(x + 7, c.y), Display.AMBER, 2.0)
			d.poly(PfdIls.diamond_points(Vector2(x, c.y), Vector2.UP, PfdIls.dev(n, "gs")), Display.MAGENTA)
	var lines := receiver_lines(m, n)
	for i in lines.size():
		d.txt(Vector2(592, 470 + i * 20), str(lines[i]), 16, col if i > 0 else Display.WHITE, 1)


## The bottom-right lines: "VOR1" / "ILS2", frequency, "CRS 270", ident and DME when received.
static func receiver_lines(m: int, n: int) -> Array:
	var b := "avionics/nav%d/" % n
	var out := [("ILS%d" if m == LS else "VOR%d") % n, "%.2f" % Props.get_f("controls/nav%d/freq_mhz" % n),
		"CRS %03d" % posmod(roundi(Props.get_f("controls/nav%d/obs_deg" % n)), 360)]
	if Props.get_b(b + "valid"):
		out.append(str(Props.get_v(b + "ident", "")))
		var dme := Props.get_f(b + "dme_nm", -1.0)
		if dme >= 0.0:
			out.append("%.1f NM" % dme if dme < 20.0 else "%d NM" % roundi(dme))
	return out


## PLAN: the aircraft symbol at `p`, nose along heading `hdg` (deg; the map is north up).
static func draw_plan_aircraft(d: Display, p: Vector2, hdg: float) -> void:
	var a := deg_to_rad(hdg)
	var f := Vector2(sin(a), -cos(a))
	var s := Vector2(cos(a), sin(a))
	d.line(p - f * 14.0, p + f * 16.0, Display.AMBER, 3.0)
	d.line(p - s * 14.0 + f * 2.0, p + s * 14.0 + f * 2.0, Display.AMBER, 3.0)
	d.line(p - f * 12.0 - s * 5.0, p - f * 12.0 + s * 5.0, Display.AMBER, 3.0)


## PLAN: the cardinal marks on the rings, north up.
static func draw_plan_rose(d: Display, c: Vector2, r: float) -> void:
	d.ring(c, r, Display.WHITE)
	for k in 4:
		var a := k * PI * 0.5
		var dir := Vector2(sin(a), -cos(a))
		d.line(c + dir * (r - 10.0), c + dir * (r + 10.0), Display.WHITE, 2.0)
		d.txt(c + dir * (r - 24.0), ["N", "E", "S", "W"][k], 16, Display.WHITE, 0)
