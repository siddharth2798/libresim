class_name AtcLayout
extends RefCounted
## Where the radio panel goes so that it never covers the rest of the in-flight UI: the first of
## a few screen spots (left, right, bottom) that does not overlap anything busy, else the one
## that overlaps least. "Busy" = the fixed regions of the flight-data bar, the notification
## cards and the taxi/pushback instruction, plus whatever panels are open right now (the 2D
## instrument-panel pieces, the training card, the checklist, the moving map).

const MARGIN := 8.0
const TOP := 64.0  # below the flight-data bar
const BOTTOM_GAP := 64.0  # keeps clear of the hint line at the bottom


## Fixed regions of always-present UI, for a viewport of size vp.
static func reserved(vp: Vector2) -> Array:
	return [
		Rect2(vp.x * 0.5 - 270.0, 4.0, 540.0, 58.0),     # flight-data bar
		Rect2(vp.x * 0.5 - 225.0, 60.0, 450.0, 250.0),   # notification cards
		Rect2(vp.x * 0.5 - 262.0, 296.0, 524.0, 90.0),   # taxi / pushback instruction
	]


## Top-left corner for a panel of `size` on a viewport `vp`, given the busy Rect2s.
static func place(size: Vector2, vp: Vector2, busy: Array) -> Vector2:
	var low := maxf(vp.y - size.y - BOTTOM_GAP, TOP)
	var spots := [Vector2(MARGIN, TOP), Vector2(vp.x - size.x - MARGIN, TOP),
		Vector2(MARGIN, low), Vector2(vp.x - size.x - MARGIN, low), Vector2((vp.x - size.x) * 0.5, low)]
	var best: Vector2 = spots[0]
	var best_area := INF
	for p in spots:
		var r := Rect2(p, size)
		var area := 0.0
		for b in busy:
			area += r.intersection(b).get_area()
		if area <= 0.0:
			return p
		if area < best_area:
			best_area = area
			best = p
	return best
