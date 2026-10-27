class_name AtcLayout
extends RefCounted
## Where the radio goes so that it never covers the rest of the in-flight UI. The bar lives top-left,
## level with the flight-data bar (home(), bar_width(): the room left of that bar; free flight has
## nothing else there). The open radio uses place(): the first of a few screen spots (home, right,
## bottom) that does not overlap anything busy, else the one that overlaps least. "Busy" = the
## fixed regions of the flight-data bar and the notification cards (the taxi instruction is one of them),
## plus whatever panels are open right now (the 2D instrument-panel pieces, the training card,
## the checklist, the moving map).

const MARGIN := 8.0
const TOP := 64.0  # below the flight-data bar
const BOTTOM_GAP := 64.0  # keeps clear of the hint line at the bottom
const BAR_TOP := 10.0     # the radio bar is level with the flight-data bar
const MIN_BAR := 300.0
const MAX_BAR := 440.0


## Fixed regions of always-present UI, for a viewport of size vp.
static func reserved(vp: Vector2) -> Array:
	return [
		Rect2(vp.x * 0.5 - 270.0, 4.0, 540.0, 58.0),     # flight-data bar
		Rect2(vp.x * 0.5 - 225.0, 60.0, 450.0, 250.0),   # notification cards
	]


## Room between the left edge and the flight-data bar.
static func _room(vp: Vector2) -> float:
	return vp.x * 0.5 - 270.0 - MARGIN - 12.0


## Width of the radio bar: the room left of the flight-data bar, 300 to 440 px.
static func bar_width(vp: Vector2) -> float:
	return clampf(_room(vp), MIN_BAR, MAX_BAR)


## Top-left corner of the radio bar; below the flight-data bar when the window is too narrow to sit beside it.
static func home(vp: Vector2) -> Vector2:
	return Vector2(MARGIN, BAR_TOP if _room(vp) >= MIN_BAR else TOP)


## Top-left corner for a panel of `size` on a viewport `vp`, given the busy Rect2s. `first` is tried first.
static func place(size: Vector2, vp: Vector2, busy: Array, first := Vector2(MARGIN, TOP)) -> Vector2:
	var low := maxf(vp.y - size.y - BOTTOM_GAP, TOP)
	var spots := [first, Vector2(vp.x - size.x - MARGIN, TOP),
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
