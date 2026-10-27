class_name ChecklistGeom
extends RefCounted
## Pure geometry of the floating checklist window (ui/checklist_window.gd), in UI units (the
## viewport rect: about 1280x720 at UI scale 1, more on a wider window). Nothing here touches
## nodes, so tests/test_checklist_window.gd runs it headless.
## A window position is stored as fractions of the free space (viewport minus window size):
## (1, 0.5) = docked at the right edge, vertically centred, whatever the window shape.

const MARGIN := 8.0  # gap kept to the screen edge by snapping and by the default dock
const SNAP := 22.0  # snapping distance to an edge
const EDGE := 6.0  # resize band along the window edges
const CORNER := 16.0  # resize square in the corners
const MIN_SIZE := Vector2(250.0, 130.0)
const OPACITY_MIN := 0.3
const OPACITY_MAX := 1.0


static func max_size(vp: Vector2) -> Vector2:
	return Vector2(maxf(MIN_SIZE.x, minf(vp.x * 0.6, 700.0)), maxf(MIN_SIZE.y, vp.y - 2.0 * MARGIN))


## Window size a fresh install starts with.
static func default_size(vp: Vector2) -> Vector2:
	return fit_size(Vector2(340.0, clampf(vp.y * 0.55, 260.0, 440.0)), vp)


## Size limited to [MIN_SIZE, max_size(vp)] (and never bigger than the viewport).
static func fit_size(s: Vector2, vp: Vector2) -> Vector2:
	var hi := max_size(vp).min(vp)
	return Vector2(clampf(s.x, minf(MIN_SIZE.x, hi.x), hi.x), clampf(s.y, minf(MIN_SIZE.y, hi.y), hi.y))


## Rect moved so that it lies fully inside the viewport (size limited first).
static func clamp_rect(r: Rect2, vp: Vector2) -> Rect2:
	var s := fit_size(r.size, vp)
	return Rect2(Vector2(clampf(r.position.x, 0.0, maxf(vp.x - s.x, 0.0)), clampf(r.position.y, 0.0, maxf(vp.y - s.y, 0.0))), s)


## Snap an edge that is within SNAP of the screen edge to MARGIN from it (per axis).
static func snap(r: Rect2, vp: Vector2) -> Rect2:
	var p := r.position
	if absf(p.x - MARGIN) < SNAP:
		p.x = MARGIN
	elif absf(vp.x - MARGIN - (p.x + r.size.x)) < SNAP:
		p.x = vp.x - MARGIN - r.size.x
	if absf(p.y - MARGIN) < SNAP:
		p.y = MARGIN
	elif absf(vp.y - MARGIN - (p.y + r.size.y)) < SNAP:
		p.y = vp.y - MARGIN - r.size.y
	return clamp_rect(Rect2(p, r.size), vp)


## Position as fractions of the free space; (0.5, 0.5) when the window fills an axis.
static func to_fraction(r: Rect2, vp: Vector2) -> Vector2:
	var free := (vp - r.size).max(Vector2.ZERO)
	return Vector2(clampf(r.position.x / free.x, 0.0, 1.0) if free.x > 0.0 else 0.5, clampf(r.position.y / free.y, 0.0, 1.0) if free.y > 0.0 else 0.5)


## Rect of a window of `size` at fractions `f`, kept MARGIN from the edges when the fraction is 0 or 1.
static func from_fraction(f: Vector2, size: Vector2, vp: Vector2) -> Rect2:
	var s := fit_size(size, vp)
	var free := (vp - s).max(Vector2.ZERO)
	var lo := Vector2(minf(MARGIN, free.x * 0.5), minf(MARGIN, free.y * 0.5))
	var p := lo + (free - lo * 2.0) * Vector2(clampf(f.x, 0.0, 1.0), clampf(f.y, 0.0, 1.0))
	return Rect2(p, s)


## Fraction that from_fraction() maps back to this rect (the inverse, MARGIN-aware).
static func fraction_of(r: Rect2, vp: Vector2) -> Vector2:
	var free := (vp - r.size).max(Vector2.ZERO)
	var lo := Vector2(minf(MARGIN, free.x * 0.5), minf(MARGIN, free.y * 0.5))
	var span := free - lo * 2.0
	return Vector2(clampf((r.position.x - lo.x) / span.x, 0.0, 1.0) if span.x > 0.0 else 0.5, clampf((r.position.y - lo.y) / span.y, 0.0, 1.0) if span.y > 0.0 else 0.5)


## Default dock: right edge, vertically centred. If that overlaps the busy rects (2D instrument
## panel pieces, cards) move left of them at the same height, else try the other free spots;
## the least-overlapping candidate wins.
static func default_rect(size: Vector2, vp: Vector2, busy: Array) -> Rect2:
	var home := from_fraction(Vector2(1.0, 0.5), size, vp)
	var cands: Array = [home]
	var left_edge := home.position.x
	for b: Rect2 in busy:  # slide left of whatever overlaps the home spot vertically
		if b.intersects(home):
			left_edge = minf(left_edge, b.position.x - MARGIN - size.x)
	if left_edge < home.position.x:
		cands.append(Rect2(Vector2(left_edge, home.position.y), home.size))
	for fy in [0.0, 1.0]:
		cands.append(from_fraction(Vector2(1.0, fy), size, vp))
	cands.append(from_fraction(Vector2(0.0, 0.5), size, vp))
	var best: Rect2 = home
	var best_area := INF
	for c: Rect2 in cands:
		c = clamp_rect(c, vp)
		var area := 0.0
		for b: Rect2 in busy:
			area += c.intersection(b).get_area()
		if area <= 0.0:
			return c
		if area < best_area:
			best_area = area
			best = c
	return best


## Resize zone of a point (window-local): x, y in -1 (left / top edge), 0, +1 (right / bottom edge); (0, 0) = none.
static func zone_at(local: Vector2, size: Vector2) -> Vector2i:
	var z := Vector2i.ZERO
	var near_x := local.x < CORNER or local.x > size.x - CORNER
	var near_y := local.y < CORNER or local.y > size.y - CORNER
	if local.x < EDGE or (near_y and local.x < CORNER):
		z.x = -1
	elif local.x > size.x - EDGE or (near_y and local.x > size.x - CORNER):
		z.x = 1
	if local.y < EDGE or (near_x and local.y < CORNER):
		z.y = -1
	elif local.y > size.y - EDGE or (near_x and local.y > size.y - CORNER):
		z.y = 1
	return z


## Rect after dragging zone `z` of `start` by `delta`, limited to the size limits and the viewport.
static func resize(start: Rect2, z: Vector2i, delta: Vector2, vp: Vector2) -> Rect2:
	var hi := max_size(vp).min(vp)
	var lo := MIN_SIZE.min(hi)
	var r := start
	if z.x > 0:
		r.size.x = clampf(start.size.x + delta.x, lo.x, minf(hi.x, maxf(vp.x - start.position.x, lo.x)))
	elif z.x < 0:
		r.size.x = clampf(start.size.x - delta.x, lo.x, minf(hi.x, maxf(start.end.x, lo.x)))
		r.position.x = start.end.x - r.size.x
	if z.y > 0:
		r.size.y = clampf(start.size.y + delta.y, lo.y, minf(hi.y, maxf(vp.y - start.position.y, lo.y)))
	elif z.y < 0:
		r.size.y = clampf(start.size.y - delta.y, lo.y, minf(hi.y, maxf(start.end.y, lo.y)))
		r.position.y = start.end.y - r.size.y
	return clamp_rect(r, vp)


static func clamp_opacity(v: float) -> float:
	return clampf(v, OPACITY_MIN, OPACITY_MAX)
