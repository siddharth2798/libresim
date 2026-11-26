class_name CaptainMapOutline
extends RefCounted
## The drawn stand-in for the product photos of the Captain Pack map (ui/menu/captain_map_picture.gd): a plain silhouette of the
## sidestick or the quadrant, in the same 0..1 coordinates as the markers of captain_map/map.json. Used when a picture is missing
## (delete the photos and the map still works).

const BODY := Color(0.30, 0.45, 0.62)
const DARK := Color(0.07, 0.09, 0.12)
const LINE := Color(1, 1, 1, 0.35)


static func draw(ci: CanvasItem, device: String, r: Rect2) -> void:
	if device == "sidestick":
		_sidestick(ci, r)
	else:
		_quadrant(ci, r)


static func _p(r: Rect2, x: float, y: float) -> Vector2:
	return r.position + Vector2(x * r.size.x, y * r.size.y)


static func _box(ci: CanvasItem, r: Rect2, x0: float, y0: float, x1: float, y1: float, col: Color) -> void:
	var b := Rect2(_p(r, x0, y0), Vector2((x1 - x0) * r.size.x, (y1 - y0) * r.size.y))
	var sb := MenuTheme.box(col, 10, LINE, 0.0)
	ci.draw_style_box(sb, b)


static func _sidestick(ci: CanvasItem, r: Rect2) -> void:
	var base := PackedVector2Array()
	for i in 40:
		var a := TAU * i / 40.0
		base.append(_p(r, 0.5 + 0.47 * cos(a), 0.82 + 0.13 * sin(a)))
	ci.draw_colored_polygon(base, BODY)
	ci.draw_polyline(base + PackedVector2Array([base[0]]), LINE, 1.5)
	_box(ci, r, 0.27, 0.56, 0.67, 0.6, DARK)
	_box(ci, r, 0.38, 0.02, 0.62, 0.58, DARK)
	_box(ci, r, 0.46, 0.58, 0.54, 0.66, DARK)
	ci.draw_circle(_p(r, 0.655, 0.115), r.size.x * 0.025, Color(0.85, 0.15, 0.12))


static func _quadrant(ci: CanvasItem, r: Rect2) -> void:
	_box(ci, r, 0.02, 0.3, 0.96, 0.95, BODY)
	for x in [0.23, 0.39, 0.55, 0.77]:  # speed brake, thrust 1, thrust 2, flaps slots
		_box(ci, r, x, 0.1, x + 0.1, 0.55, DARK)
	_box(ci, r, 0.05, 0.42, 0.33, 0.8, Color(0.24, 0.38, 0.54))
	_box(ci, r, 0.33, 0.45, 0.62, 0.8, Color(0.26, 0.41, 0.57))
	_box(ci, r, 0.62, 0.45, 0.9, 0.8, Color(0.24, 0.38, 0.54))
