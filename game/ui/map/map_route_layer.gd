class_name MapRouteLayer
extends RefCounted
## The magenta route line of the moving map (MSFS style): aircraft -> active waypoint in bold,
## later legs thinner, a dark outline for contrast on imagery, direction arrows, a bearing /
## distance / ETE label per leg and a marker with ident and distance at every waypoint. Labels never overlap: reserve()
## places the waypoint labels (moved round the marker, shortened or left out), leg_label() the leg pills in what is free.
## Input: RoutePlan.legs() or RouteEdit.legs() (world metres); drawn through the MapView. Used by the N map, the
## mini-map and the Route step's map.

const ARROW_EVERY := 280.0  # px between direction arrows on a long visible leg
const LABEL_MIN_LEN := 120.0  # px of visible leg needed to carry a label
const LABEL_PX := 14  # waypoint label font size


## Places the waypoint labels before any other label (the route's own names win over airports and navaids): beside the
## marker on the right, else left, above or below; with no room for "IDENT  12.3 nm" the ident alone is tried in those
## places, and with none for that either the label is left out. A label never covers another route label or marker.
## `symbols`: rects of the other map symbols (MapFeatures.marker_rects: airports, VOR / NDB; buttons on the map) the
## labels keep off too, and a label stays inside the view;
## the airport and navaid names give way to the route's (they are placed later, around `taken`).
## The place is stored in the leg (lbl_pos baseline, lbl_text; lbl_pos null = no label) for draw(); the label and
## marker rects go into `taken`, so the leg labels and other names keep off them. The active leg's label goes first.
static func reserve(view: MapView, legs: Array, font: Font, taken: Array, symbols: Array = []) -> void:
	var marks: Array = []
	for leg in legs:
		var r := _radius(leg)
		marks.append(Rect2(view.to_px(leg.b) - Vector2(r, r), Vector2(r, r) * 2.0))
	var order: Array = range(legs.size()).filter(func(i): return legs[i].active)
	order.append_array(range(legs.size()).filter(func(i): return not legs[i].active))
	var area := Rect2(Vector2.ZERO, view.size).grow(20.0)
	var view_rect := Rect2(Vector2.ZERO, view.size)  # a label is never cut by the map's edge
	for i in order:
		var leg: Dictionary = legs[i]
		var p := view.to_px(leg.b)
		leg.lbl_pos = null
		if not area.has_point(p):
			continue
		for s in [_marker_text(leg), str(leg.ident)]:
			for at in label_spots(font, s, p, _radius(leg)):
				var box := MapStyle.text_rect(font, s, at, LABEL_PX)
				if view_rect.encloses(box) and MapStyle.is_free(box, taken) and MapStyle.is_free(box, marks) \
						and MapStyle.is_free(box, symbols):
					taken.append(box)
					leg.lbl_pos = at
					leg.lbl_text = s
					break
			if leg.lbl_pos != null:
				break
	taken.append_array(marks)


## Baselines to try for a label `s` by a marker of radius r at p: right, left, above, below, then the four corners
## (below right, below left, above right, above left).
static func label_spots(font: Font, s: String, p: Vector2, r: float) -> Array:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_PX).x
	var asc := font.get_ascent(LABEL_PX)
	var desc := font.get_height(LABEL_PX) - asc
	var up := p.y - r - 5.0 - desc
	var down := p.y + r + 5.0 + asc
	return [p + Vector2(r + 10.0, -r - 1.0), p + Vector2(-r - 10.0 - w, -r - 1.0), Vector2(p.x - w * 0.5, up),
		Vector2(p.x - w * 0.5, down), Vector2(p.x + r + 6.0, down), Vector2(p.x - r - 6.0 - w, down),
		Vector2(p.x + r + 6.0, up), Vector2(p.x - r - 6.0 - w, up)]


static func _marker_text(leg: Dictionary) -> String:
	return "%s  %.1f nm" % [leg.ident, leg.cum_m / MapView.NM]


static func _radius(leg: Dictionary) -> float:
	return 11.0 if leg.active else 8.0


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


## "087°  23.4 nm  ETE 14:20" beside the visible leg (leg_label).
static func _label(ci: CanvasItem, view: MapView, leg: Dictionary, gs_mps: float, font: Font, taken: Array) -> void:
	var l := leg_label(view, leg, gs_mps, font, taken)
	if not l.is_empty():
		MapStyle.pill(ci, font, l.text, l.at, 13, Color.WHITE, MapStyle.ROUTE if leg.active else MapStyle.ROUTE_DIM)


## Where a leg's course / distance / time pill goes: by the middle of the visible leg, or the nearest free spot along
## it, above the line first; {} when the leg is short on screen or every spot is taken (it never covers another label).
## {text, at (pill centre)}; its rect is added to `taken`.
static func leg_label(view: MapView, leg: Dictionary, gs_mps: float, font: Font, taken: Array) -> Dictionary:
	var a := view.to_px(leg.a)
	var b := view.to_px(leg.b)
	var seg := MapView.clip_segment(a, b, Rect2(Vector2.ZERO, view.size).grow(-30.0))
	if seg.size() < 2 or seg[0].distance_to(seg[1]) < LABEL_MIN_LEN:
		return {}
	var dir := (seg[1] - seg[0]).normalized()
	var normal := Vector2(-dir.y, dir.x)
	if normal.y > 0.0:
		normal = -normal  # the label sits above the line
	var brg := fposmod(RoutePlan.bearing_deg(leg.a, leg.b) - Gps.VAR_DEG, 360.0)
	var s := "%03d°  %.1f nm  ETE %s" % [int(round(brg)) % 360, leg.dist_m / MapView.NM, RoutePlan.format_ete(RoutePlan.ete_s(leg.dist_m, gs_mps))]
	for side in [1.0, -1.0]:  # above the line first, then below it
		for t in [0.5, 0.35, 0.65, 0.22, 0.78]:
			var c: Vector2 = seg[0].lerp(seg[1], t) + normal * 26.0 * side
			if MapStyle.is_free(MapStyle.pill_rect(font, s, c, 13), taken):
				taken.append(MapStyle.pill_rect(font, s, c, 13))
				return {"text": s, "at": c}
	return {}


## Diamond at the end of a leg with its ident and the distance to it along the route.
static func _marker(ci: CanvasItem, view: MapView, leg: Dictionary, font: Font) -> void:
	var p := view.to_px(leg.b)
	if not Rect2(Vector2.ZERO, view.size).grow(20.0).has_point(p):
		return
	var r := _radius(leg)
	var col: Color = MapStyle.ROUTE if leg.active else MapStyle.ROUTE_DIM
	MapStyle.poly(ci, PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, 0), p + Vector2(0, r), p + Vector2(-r, 0)]), col.lightened(0.2))
	if leg.active:
		ci.draw_arc(p, r + 7.0, 0.0, TAU, 28, MapStyle.OUTLINE, 5.0, true)
		ci.draw_arc(p, r + 7.0, 0.0, TAU, 28, col, 2.5, true)
	if not leg.has("lbl_pos"):  # not placed by reserve(): the usual spot
		MapStyle.text(ci, font, _marker_text(leg), label_spots(font, _marker_text(leg), p, r)[0], LABEL_PX, Color.WHITE)
	elif leg.lbl_pos != null:
		MapStyle.text(ci, font, str(leg.lbl_text), leg.lbl_pos, LABEL_PX, Color.WHITE)


## What the N map draws over its route (strip, route pill and hint band, north disc, scale bar): reserve() keeps the
## waypoint labels off it.
static func chrome_rects(size: Vector2, strip: Rect2) -> Array:
	return [strip, Rect2(0.0, size.y - 58.0, size.x, 58.0), Rect2(size.x - 80.0, 50.0, 80.0, 80.0),
		Rect2(16.0, size.y - 84.0, 200.0, 40.0)]


## Along the bottom of the N map: the route pill ("ROUTE  A > B   12.3 nm   ETE 0:12"), the hint line in `hint_col`,
## and the simulated-ILS note when `ils_note`.
static func draw_footer(ci: CanvasItem, size: Vector2, legs: Array, gs_mps: float, font: Font, hint: String, hint_col: Color, ils_note: bool) -> void:
	if not legs.is_empty():
		var ids := PackedStringArray()
		for l in legs:
			ids.append(l.ident)
		var rem: float = legs.back().cum_m
		var s := "ROUTE  %s   %.1f nm   ETE %s" % [" > ".join(ids), rem / MapView.NM, RoutePlan.format_ete(RoutePlan.ete_s(rem, gs_mps))]
		MapStyle.pill(ci, font, s, Vector2(size.x * 0.5, size.y - 46.0), 15, Color.WHITE, MapStyle.ROUTE)
	var px := 13
	var ts := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
	while ts.x > size.x - 24.0 and px > 9:  # a narrow map: smaller, not cut off
		px -= 1
		ts = font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, px)
	MapStyle.text(ci, font, hint, Vector2((size.x - ts.x) * 0.5, size.y - 14.0), px, hint_col)
	if ils_note:
		MapStyle.text(ci, font, "* ILS frequencies are simulated", Vector2(size.x - 210.0, size.y - 14.0), 12, Color(0.8, 0.8, 0.8))
