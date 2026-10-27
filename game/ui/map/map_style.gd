class_name MapStyle
extends RefCounted
## Colours and small drawing helpers shared by the moving map's layers.

const ROUTE := Color("c040ff")  # MSFS-style magenta/purple route line
const ROUTE_DIM := Color("a24fd6")
const OUTLINE := Color(0.04, 0.02, 0.09, 0.92)
const PANEL := Color(0.06, 0.07, 0.1, 0.82)
const AIRPORT := Color(0.45, 0.85, 1.0)
const AIRCRAFT := Color(1.0, 0.86, 0.15)


## Text with a dark halo so it reads on any imagery. pos is the baseline's left end.
static func text(ci: CanvasItem, font: Font, s: String, pos: Vector2, size: int, col: Color) -> void:
	ci.draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, OUTLINE)
	ci.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## Screen rect of text drawn with `text` (pos = baseline left).
static func text_rect(font: Font, s: String, pos: Vector2, size: int) -> Rect2:
	return Rect2(pos.x, pos.y - font.get_ascent(size), font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x, font.get_height(size))


static func is_free(r: Rect2, taken: Array) -> bool:
	for t in taken:
		if t.intersects(r.grow(2.0)):
			return false
	return true


## `text`, but only where it overlaps nothing already placed (taken: Array of Rect2); a label
## that is drawn is added to `taken`. Call in priority order. Returns whether it was drawn.
static func text_free(ci: CanvasItem, font: Font, s: String, pos: Vector2, size: int, col: Color, taken: Array) -> bool:
	var r := text_rect(font, s, pos, size)
	if not is_free(r, taken):
		return false
	taken.append(r)
	text(ci, font, s, pos, size, col)
	return true


## Pill rect for text centred at `centre`.
static func pill_rect(font: Font, s: String, centre: Vector2, size: int) -> Rect2:
	var ts := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	return Rect2(centre - Vector2(ts.x * 0.5 + 6.0, ts.y * 0.5 + 2.0), Vector2(ts.x + 12.0, ts.y + 4.0))


## Text on a dark pill centred at `centre`; returns the pill rect.
static func pill(ci: CanvasItem, font: Font, s: String, centre: Vector2, size: int, col: Color, border: Color) -> Rect2:
	var r := pill_rect(font, s, centre, size)
	ci.draw_rect(r, PANEL)
	ci.draw_rect(r, border, false, 1.5)
	ci.draw_string(font, Vector2(r.position.x + 6.0, r.position.y + 2.0 + font.get_ascent(size)), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	return r


## A closed polygon with a dark outline.
static func poly(ci: CanvasItem, pts: PackedVector2Array, fill: Color, outline_w := 2.5) -> void:
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, OUTLINE, outline_w + 2.0, true)
	ci.draw_colored_polygon(pts, fill)
