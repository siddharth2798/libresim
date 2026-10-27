class_name MapFeatures
extends RefCounted
## Map symbols of the moving map: runways, airports, VOR / NDB, ILS feathers, the aircraft, its
## track, the north arrow and the scale bar. Less is drawn as the view zooms out so a 300 nm
## picture stays readable. Also picks the airport or navaid under a click (same visibility rules).

const SHOW_HELI_NM := 15.0  # heliports appear below this width
const SHOW_NAVAID_NM := 140.0  # VOR / NDB labels
const SHOW_ILS_NM := 50.0


static func airport_ident(a: Dictionary) -> String:
	return a.icao if a.icao != "" else a.ident


static func _airport_visible(a: Dictionary, across_nm: float) -> bool:
	return a.type != "heliport" or across_nm <= SHOW_HELI_NM


static func draw_airports(ci: CanvasItem, view: MapView, db: NavDatabase, runways: Array, font: Font, taken: Array) -> void:
	var rect := Rect2(Vector2.ZERO, view.size).grow(40.0)
	var across := view.across_nm()
	for r in runways:
		var e0 := view.to_px(Vector2(r.ends[0].x, r.ends[0].y))
		var e1 := view.to_px(Vector2(r.ends[1].x, r.ends[1].y))
		if rect.has_point(e0) or rect.has_point(e1):
			var w := maxf(3.0, r.width / view.m_per_px)
			ci.draw_line(e0, e1, MapStyle.OUTLINE, w + 2.5, true)
			ci.draw_line(e0, e1, Color.WHITE, w, true)
	for a in db.airports:
		var p := view.to_px(Vector2(a.x, a.y))
		if not rect.has_point(p) or not _airport_visible(a, across):
			continue
		var heli: bool = a.type == "heliport"
		ci.draw_arc(p, 6.0 if heli else 10.0, 0.0, TAU, 20, MapStyle.OUTLINE, 5.0, true)
		ci.draw_arc(p, 6.0 if heli else 10.0, 0.0, TAU, 20, MapStyle.AIRPORT, 2.5, true)
		MapStyle.text_free(ci, font, airport_ident(a), p + Vector2(14.0, 5.0), 14, Color(0.7, 0.93, 1.0), taken)


static func draw_navaids(ci: CanvasItem, view: MapView, db: NavDatabase, font: Font, taken: Array) -> void:
	var rect := Rect2(Vector2.ZERO, view.size).grow(40.0)
	var named := view.across_nm() <= SHOW_NAVAID_NM
	for v in db.vors:
		var p := view.to_px(Vector2(v.x, v.y))
		if rect.has_point(p):
			MapStyle.poly(ci, PackedVector2Array([p + Vector2(-8, 0), p + Vector2(-4, -7), p + Vector2(4, -7), p + Vector2(8, 0), p + Vector2(4, 7), p + Vector2(-4, 7)]), Color(0.25, 0.55, 1.0), 1.5)
			if named:
				MapStyle.text_free(ci, font, "%s %.2f" % [v.ident, v.mhz], p + Vector2(12, -6), 13, Color(0.7, 0.82, 1.0), taken)
	for n in db.ndbs:
		var p2 := view.to_px(Vector2(n.x, n.y))
		if rect.has_point(p2):
			ci.draw_circle(p2, 7.0, MapStyle.OUTLINE)
			ci.draw_circle(p2, 5.0, Color(0.85, 0.35, 0.85))
			if named:
				MapStyle.text_free(ci, font, "%s %.0f" % [n.ident, n.khz], p2 + Vector2(10, -6), 13, Color(0.95, 0.7, 0.95), taken)


static func draw_ils(ci: CanvasItem, view: MapView, db: NavDatabase, font: Font, taken: Array) -> void:
	if view.across_nm() > SHOW_ILS_NM:
		return
	for s in db.ils:
		var th := Vector2(s.threshold.x, s.threshold.y)
		var back := -Vector2(sin(deg_to_rad(s.course_true)), cos(deg_to_rad(s.course_true))) * 10.0 * MapView.NM
		for k in [-1.0, 1.0]:
			ci.draw_line(view.to_px(th), view.to_px(th + back.rotated(deg_to_rad(2.5 * k))), Color(0.4, 1.0, 0.4, 0.75), 1.5, true)
		MapStyle.text_free(ci, font, "%s %.2f*" % [s.ident, s.mhz], view.to_px(th + back * 0.6) + Vector2(4, 0), 12, Color(0.6, 1, 0.6), taken)


static func draw_track(ci: CanvasItem, view: MapView, track: Array) -> void:
	for i in range(1, track.size()):
		ci.draw_line(view.to_px(track[i - 1]), view.to_px(track[i]), Color(1, 0.95, 0.3, 0.7), 2.0, true)


static func draw_aircraft(ci: CanvasItem, p: Vector2, heading_rad: float, view_rot: float) -> void:
	var shape := [Vector2(0, -16), Vector2(2.5, -8), Vector2(2.5, -3), Vector2(16, 2), Vector2(16, 5), Vector2(2.5, 3), Vector2(2, 11),
		Vector2(7, 14), Vector2(7, 16), Vector2(0, 14.5), Vector2(-7, 16), Vector2(-7, 14), Vector2(-2, 11), Vector2(-2.5, 3),
		Vector2(-16, 5), Vector2(-16, 2), Vector2(-2.5, -3), Vector2(-2.5, -8)]
	var pts := PackedVector2Array()
	for v in shape:
		pts.append(p + (v * 1.15).rotated(heading_rad + view_rot))
	MapStyle.poly(ci, pts, MapStyle.AIRCRAFT)


## North arrow in a disc at `c`: red tip points to true north whatever the map rotation.
static func draw_north(ci: CanvasItem, c: Vector2, view_rot: float, font: Font) -> void:
	ci.draw_circle(c, 26.0, MapStyle.PANEL)
	ci.draw_arc(c, 26.0, 0.0, TAU, 32, Color(1, 1, 1, 0.35), 1.5, true)
	var up := Vector2(0, -1).rotated(view_rot)
	var side := Vector2(-up.y, up.x)
	ci.draw_colored_polygon(PackedVector2Array([c + up * 20.0, c + side * 6.0, c - side * 6.0]), Color(0.95, 0.25, 0.2))
	ci.draw_colored_polygon(PackedVector2Array([c - up * 20.0, c + side * 6.0, c - side * 6.0]), Color(0.9, 0.9, 0.9))
	var ts := font.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	MapStyle.text(ci, font, "N", c + up * 36.0 + Vector2(-ts.x * 0.5, ts.y * 0.35), 13, Color.WHITE)


static func draw_scale_bar(ci: CanvasItem, view: MapView, origin: Vector2, font: Font) -> void:
	var sc := MapView.nice_scale(view.m_per_px, 170.0)
	var a := origin
	var b := origin + Vector2(sc.px, 0.0)
	for pass_ in 2:
		var col := MapStyle.OUTLINE if pass_ == 0 else Color.WHITE
		var w := 6.0 if pass_ == 0 else 2.5
		ci.draw_line(a, b, col, w)
		ci.draw_line(a + Vector2(0, -6), a + Vector2(0, 6), col, w)
		ci.draw_line(b + Vector2(0, -6), b + Vector2(0, 6), col, w)
	MapStyle.text(ci, font, sc.label, a + Vector2(0, -12), 14, Color.WHITE)


## Ident of the airport or navaid within `radius_px` of a click, "" if none (nearest wins).
static func pick(view: MapView, db: NavDatabase, px: Vector2, radius_px := 26.0) -> String:
	var best := ""
	var bd := radius_px
	var across := view.across_nm()
	for a in db.airports:
		var d := view.to_px(Vector2(a.x, a.y)).distance_to(px)
		if d < bd and _airport_visible(a, across):
			bd = d
			best = airport_ident(a)
	for v in db.vors + db.ndbs:
		var d2 := view.to_px(Vector2(v.x, v.y)).distance_to(px)
		if d2 < bd:
			bd = d2
			best = v.ident
	return best
