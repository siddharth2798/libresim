class_name GlideProfile
extends Control
## Side view of an air start: height over distance on final with the runway at the right, the dashed 3 degree path
## to the threshold and the aircraft marker with its height, distance and indicated speed. Reads Session.setup air_ft /
## air_nm / air_kt; call refresh() after any of them changed. Maths in glide_math.gd. `caption` is the one-line verdict.

const PATH := Color("6fe3a0")
const MARK := Color("ff5a4f")

var ft := 1500.0
var nm := 5.0
var kias := 90.0
var caption := ""
var max_nm := 25.0  # the aircraft's distance and height limits: the scale of the picture
var max_ft := 12000.0


func _ready() -> void:
	custom_minimum_size = Vector2(260, 96)
	refresh()


func refresh() -> void:
	var s: Dictionary = Session.setup
	ft = float(s.get("air_ft", ft))
	nm = float(s.get("air_nm", nm))
	kias = float(s.get("air_kt", kias))
	var lim: Dictionary = AirStart.of(AircraftDef.load_def(str(s.get("aircraft", AircraftDef.DEFAULT_ID)))).limits
	max_nm = float(lim.dist_nm[1])
	max_ft = float(lim.alt_ft[1])
	caption = GlideMath.caption(ft, nm)
	tooltip_text = "Where you start: %s ft up, %s nm from the threshold, %d kt. The dashed line is the 3° path to the runway." % [
		AirportData.thousands(roundi(ft)), Session.nm_text(nm), roundi(kias)]
	queue_redraw()


func _draw() -> void:
	draw_style_box(MenuTheme.box(Color(0.02, 0.04, 0.06, 0.55), 8, MenuTheme.LINE), Rect2(Vector2.ZERO, size))
	var l := GlideMath.layout(size, ft, nm, max_nm, max_ft)
	var plot: Rect2 = l.plot
	var thr: Vector2 = l.threshold
	draw_line(Vector2(plot.position.x, thr.y), Vector2(thr.x + 14.0, thr.y), Color(1, 1, 1, 0.3), 1.0)
	_dashed(thr, l.path_end, PATH, 2.0)
	draw_rect(Rect2(thr.x - 2.0, thr.y - 3.0, 18.0, 6.0), Color(0.81, 0.84, 0.86))
	var m: Vector2 = l.marker
	draw_line(Vector2(m.x, thr.y), m, Color(MARK, 0.5), 1.0)
	draw_circle(m, 6.0, MARK)
	draw_arc(m, 6.5, 0.0, TAU, 20, Color.WHITE, 1.5)
	var head := "%s ft · %d kt" % [AirportData.thousands(roundi(ft)), roundi(kias)]
	var f := MenuTheme.font("semibold")
	var reg := MenuTheme.font("regular")
	var cap := "%.1f° · %s" % [GlideMath.angle_deg(ft, nm), GlideMath.verdict(ft, nm)]
	var cap_w := reg.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var w := f.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var hx := clampf(m.x - w * 0.5, 4.0, size.x - w - 4.0)
	var hy := maxf(m.y - 11.0, 14.0)
	if hy < 20.0 and hx < cap_w + 14.0:  # it would sit on the verdict line: go below the marker
		hy = m.y + 22.0
	draw_string(f, Vector2(hx, hy), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	draw_string(reg, Vector2(8.0, 14.0), cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MenuTheme.DIM)
	var d := "%s nm" % Session.nm_text(nm)
	draw_string(reg, Vector2(clampf(m.x - reg.get_string_size(d, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x * 0.5, 4.0, size.x - 50.0), size.y - 6.0), d, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MenuTheme.DIM)
	draw_string(reg, Vector2(thr.x - 4.0, size.y - 6.0), "Rwy", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MenuTheme.DIM)


func _dashed(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	var n := maxi(int(a.distance_to(b) / 9.0), 1)
	for i in n:
		if i % 2 == 0:
			draw_line(a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n), col, width)
