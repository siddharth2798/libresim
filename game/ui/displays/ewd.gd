class_name EWD
extends Display
## Engine / warning display: per engine an N1 dial (needle, digits, optional target ring), EGT, N2 and
## fuel flow, the thrust-limit mode, fuel on board, flaps / slats position and the memo / warning lines.
## Reads Props only: instruments/engines/{count, <n>/{n1_pct, n2_pct, egt_c, ff_kgh, running}}
## (instruments/airliner_engines.gd), ap/thrust_limit (string, e.g. "CLB", "FLX 50", "TOGA"),
## ap/n1_target (fraction, optional), fuel/total_kg, fdm/{flap_lever, flap_deg, slat_deg, gear_pos,
## speedbrake}, controls/parking_brake, ewd/warnings and ewd/memo (arrays of [text, colour name]).

const N1_MAX := 110.0
const EGT_RED := 950.0
const COLS := {"green": GREEN, "white": WHITE, "amber": AMBER, "red": RED, "cyan": CYAN, "magenta": MAGENTA}
const A0 := deg_to_rad(-135.0)
const A1 := deg_to_rad(105.0)


func _init() -> void:
	design = Vector2(520, 420)


static func n1_angle(pct: float) -> float:
	return lerpf(A0, A1, clampf(pct / N1_MAX, 0.0, 1.0))


func _paint() -> void:
	var count := clampi(int(Props.get_f("instruments/engines/count", 2.0)), 1, 4)
	var left_w := 270.0
	txt(Vector2(8, 14), "FOB", 14, WHITE)
	txt(Vector2(46, 14), "%d" % roundi(Props.get_f("fuel/total_kg")), 18, GREEN)
	txt(Vector2(100, 14), "KG", 13, CYAN)
	var lim := str(Props.get_v("ap/thrust_limit", ""))
	if lim != "":
		txt(Vector2(left_w - 8, 14), lim, 17, CYAN, 1)
	for i in count:
		_engine(i + 1, Vector2(left_w * (i + 0.5) / count, 0), count)
	line(Vector2(left_w + 4, 28), Vector2(left_w + 4, 410), GREY, 1.5)
	_flaps()
	_lines()


func _engine(n: int, at: Vector2, count: int) -> void:
	var b := "instruments/engines/%d/" % n
	var r := 56.0 if count <= 2 else 40.0
	var c := Vector2(at.x, 100.0)
	var n1 := Props.get_f(b + "n1_pct")
	var run := Props.get_b(b + "running") or n1 > 5.0
	arc(c, r, A0, A1, WHITE, 2.0)
	arc(c, r, n1_angle(100.0), A1, RED, 4.0)
	for v in [0, 20, 40, 60, 80, 100]:
		line(DispMath.polar(c, r, n1_angle(v)), DispMath.polar(c, r - 8, n1_angle(v)), WHITE, 2.0)
	var tgt := Props.get_f("ap/n1_target", -1.0)
	if tgt > 0.0:
		ring(DispMath.polar(c, r - 2, n1_angle(tgt * 100.0)), 5.0, CYAN)
	var a := n1_angle(n1)
	arc(c, r - 3, A0, a, GREEN if run else GREY, 3.0)
	line(c, DispMath.polar(c, r - 4, a), GREEN if run else GREY, 3.0)
	fill(Rect2(c.x - 34, c.y + 6, 68, 24), Color.BLACK)
	txt(Vector2(c.x + 30, c.y + 18), "%.1f" % n1 if run else "0.0", 22, GREEN if run else AMBER, 1)
	txt(Vector2(c.x - r - 6, c.y - r + 4), "N1", 13, CYAN)
	var egt := Props.get_f(b + "egt_c")
	var ey := 182.0
	txt(Vector2(at.x - 22, ey), "EGT", 13, CYAN, 1)
	txt(Vector2(at.x + 54, ey), "%d" % roundi(egt), 22, RED if egt >= EGT_RED else GREEN, 1)
	var bar := Rect2(at.x - 44, ey + 14, 88, 6)
	fill(bar, Color(0.15, 0.15, 0.17))
	fill(Rect2(bar.position, Vector2(bar.size.x * clampf(egt / 1000.0, 0.0, 1.0), 6)), RED if egt >= EGT_RED else GREEN)
	txt(Vector2(at.x - 22, 232), "N2", 13, CYAN, 1)
	txt(Vector2(at.x + 54, 232), "%.1f" % Props.get_f(b + "n2_pct"), 22, GREEN, 1)
	txt(Vector2(at.x - 22, 280), "FF", 13, CYAN, 1)
	txt(Vector2(at.x + 54, 280), "%d" % roundi(Props.get_f(b + "ff_kgh")), 22, GREEN, 1)
	if n == 1:
		txt(Vector2(8, 296), "KG/H", 11, CYAN)


func _flaps() -> void:
	var y := 340.0
	var lever := roundi(Props.get_f("fdm/flap_lever"))
	var conf := DispMath.conf_text(lever, Props.get_f("fdm/flap_deg"))
	var slat := Props.get_f("fdm/slat_deg") / 27.0
	var flap := Props.get_f("fdm/flap_deg") / 35.0
	txt(Vector2(8, y), "S", 15, WHITE)
	fill(Rect2(26, y - 6, 120, 12), Color(0.15, 0.15, 0.17))
	fill(Rect2(26, y - 6, 120 * clampf(slat, 0.0, 1.0), 12), GREEN)
	txt(Vector2(8, y + 24), "F", 15, WHITE)
	fill(Rect2(26, y + 18, 120, 12), Color(0.15, 0.15, 0.17))
	fill(Rect2(26, y + 18, 120 * clampf(flap, 0.0, 1.0), 12), GREEN)
	txt(Vector2(160, y + 10), "CONF " + conf, 18, GREEN)
	txt(Vector2(8, 396), "FLAPS", 12, CYAN)


func _lines() -> void:
	var out := []
	for w in Array(Props.get_v("ewd/warnings", [])):
		out.append(w)
	var memo: Variant = Props.get_v("ewd/memo", null)
	if memo is Array:
		out.append_array(memo)
	else:
		out.append_array(_default_memo())
	for i in mini(out.size(), 13):
		txt(Vector2(284, 40 + i * 26), str(out[i][0]), 17, COLS.get(str(out[i][1]), GREEN))


func _default_memo() -> Array:
	var m := []
	var gear: Variant = Props.get_v("fdm/gear_pos", 0.0)
	if (gear.min() if gear is Array and not gear.is_empty() else float(gear)) > 0.95:
		m.append(["LDG GEAR DN", "green"])
	if Props.get_f("fdm/speedbrake") > 0.05:
		m.append(["SPEED BRK", "green"])
	if Props.get_b("controls/parking_brake"):
		m.append(["PARK BRK", "green"])
	return m
