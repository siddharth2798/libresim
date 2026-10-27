class_name MapRouteLayer
extends RefCounted
## The magenta route line of the moving map (MSFS style): aircraft -> active waypoint in bold,
## later legs thinner, a dark outline for contrast on imagery, direction arrows, a bearing /
## distance / ETE label per leg and a marker with ident and distance at every waypoint.
## Input: RoutePlan.legs() (world metres); drawn through the MapView.

const ARROW_EVERY := 280.0  # px between direction arrows on a long visible leg
const LABEL_MIN_LEN := 120.0  # px of visible leg needed to carry a label


## Rects of the waypoint labels, to be added to the map's `taken` list before other labels are
## placed (the route's own labels win over airport and navaid names).
static func reserve(view: MapView, legs: Array, font: Font, taken: Array) -> void:
	for leg in legs:
		var p := view.to_px(leg.b)
		if Rect2(Vector2.ZERO, view.size).grow(20.0).has_point(p):
			taken.append(MapStyle.text_rect(font, _marker_text(leg), _marker_pos(p, leg), 14))


static func _marker_text(leg: Dictionary) -> String:
	return "%s  %.1f nm" % [leg.ident, leg.cum_m / MapView.NM]


static func _marker_pos(p: Vector2, leg: Dictionary) -> Vector2:
	var r := 11.0 if leg.active else 8.0
	return p + Vector2(r + 10.0, -r - 1.0)


static func draw(ci: CanvasItem, view: MapView, legs: Array, gs_mps: float, font: Font, taken: Array) -> void:
	if legs.is_empty():
		return
	var rect := Rect2(Vector2.ZERO, view.size)
	# later legs first, so the active one lies on top
	for i in range(legs.size() - 1, -1, -1):
		var leg: Dictionary = legs[i]
		var a := view.to_px(leg.a)
		var b := view.to_px(leg.b)
		var seg := MapView.clip_segment(a, b, rect.grow(-4.0))
		if seg.size() < 2 or seg[0].distance_to(seg[1]) < 1.0:
			continue
		var w := 5.0 if leg.active else 3.0
		var col: Color = MapStyle.ROUTE if leg.active else MapStyle.ROUTE_DIM
		var wide := MapView.clip_segment(a, b, rect.grow(30.0))  # lines far off screen are not sent
		ci.draw_line(wide[0], wide[1], MapStyle.OUTLINE, w + 4.0, true)
		ci.draw_line(wide[0], wide[1], col, w, true)
		_arrows(ci, seg, col, 1.3 if leg.active else 1.0)
	for i in range(legs.size() - 1, -1, -1):
		var leg2: Dictionary = legs[i]
		_label(ci, view, leg2, gs_mps, font, taken)
	for i in legs.size():
		_marker(ci, view, legs[i], font)


## Direction arrowheads: one at the middle of the visible part, more on a long leg.
static func _arrows(ci: CanvasItem, seg: PackedVector2Array, col: Color, k: float) -> void:
	var seg_len := seg[0].distance_to(seg[1])
	var dir := (seg[1] - seg[0]) / seg_len
	var n := clampi(int(seg_len / ARROW_EVERY), 0, 6)
	for j in n + 1:
		var t := (float(j) + 0.5) / float(n + 1)
		var c := seg[0].lerp(seg[1], t)
		var side := Vector2(-dir.y, dir.x)
		MapStyle.poly(ci, PackedVector2Array([c + dir * 9.0 * k, c - dir * 7.0 * k + side * 7.0 * k, c - dir * 3.0 * k, c - dir * 7.0 * k - side * 7.0 * k]), col.lightened(0.25), 1.5)


## "087°  23.4 nm  ETE 14:20" beside the visible leg: at the middle, or the nearest free spot
## along it if a waypoint label or another leg label is in the way.
static func _label(ci: CanvasItem, view: MapView, leg: Dictionary, gs_mps: float, font: Font, taken: Array) -> void:
	var a := view.to_px(leg.a)
	var b := view.to_px(leg.b)
	var seg := MapView.clip_segment(a, b, Rect2(Vector2.ZERO, view.size).grow(-30.0))
	if seg.size() < 2 or seg[0].distance_to(seg[1]) < LABEL_MIN_LEN:
		return
	var dir := (seg[1] - seg[0]).normalized()
	var normal := Vector2(-dir.y, dir.x)
	if normal.y > 0.0:
		normal = -normal  # the label sits above the line
	var brg := fposmod(RoutePlan.bearing_deg(leg.a, leg.b) - Gps.VAR_DEG, 360.0)
	var s := "%03d°  %.1f nm  ETE %s" % [int(round(brg)) % 360, leg.dist_m / MapView.NM, RoutePlan.format_ete(RoutePlan.ete_s(leg.dist_m, gs_mps))]
	var col: Color = MapStyle.ROUTE if leg.active else MapStyle.ROUTE_DIM
	var at := (seg[0] + seg[1]) * 0.5 + normal * 26.0
	for side in [1.0, -1.0]:  # above the line first, then below it
		for t in [0.5, 0.35, 0.65, 0.22, 0.78]:
			var c: Vector2 = seg[0].lerp(seg[1], t) + normal * 26.0 * side
			if MapStyle.is_free(MapStyle.pill_rect(font, s, c, 13), taken):
				at = c
				side = 0.0
				break
		if side == 0.0:
			break
	taken.append(MapStyle.pill_rect(font, s, at, 13))
	MapStyle.pill(ci, font, s, at, 13, Color.WHITE, col)


## Diamond at the end of a leg with its ident and the distance to it along the route.
static func _marker(ci: CanvasItem, view: MapView, leg: Dictionary, font: Font) -> void:
	var p := view.to_px(leg.b)
	if not Rect2(Vector2.ZERO, view.size).grow(20.0).has_point(p):
		return
	var r := 11.0 if leg.active else 8.0
	var col: Color = MapStyle.ROUTE if leg.active else MapStyle.ROUTE_DIM
	MapStyle.poly(ci, PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)]), col.lightened(0.2))
	if leg.active:
		ci.draw_arc(p, r + 7.0, 0.0, TAU, 28, MapStyle.OUTLINE, 5.0, true)
		ci.draw_arc(p, r + 7.0, 0.0, TAU, 28, col, 2.5, true)
	MapStyle.text(ci, font, _marker_text(leg), _marker_pos(p, leg), 14, Color.WHITE)
