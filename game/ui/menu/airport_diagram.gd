extends Control
## North-up airport diagram for the start screen: runways (with idents), taxiways,
## parking stands, and the chosen start point (aircraft arrow).

var runways: Array = []  # runways.json entries of this airport
var taxiways: Array = []  # [PackedVector2Array]
var stands: Array = []
var start := {}  # {"pos": Vector2, "heading": deg}
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	custom_minimum_size = Vector2(220, 260)
	clip_contents = true


func show_airport(rw: Array, tw: Array, st: Array) -> void:
	runways = rw
	taxiways = tw
	stands = st
	queue_redraw()


func set_start(pos: Vector2, heading_deg: float) -> void:
	start = {"pos": pos, "heading": heading_deg}
	queue_redraw()


func _bounds() -> Rect2:
	var r := Rect2()
	var first := true
	for w in runways:
		for e in w.ends:
			var p := Vector2(e.x, e.y)
			r = Rect2(p, Vector2.ZERO) if first else r.expand(p)
			first = false
	for s in stands:
		r = r.expand(Vector2(s.x, s.y)) if not first else Rect2(Vector2(s.x, s.y), Vector2.ZERO)
		first = false
	return r.grow(300.0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.05, 0.07, 0.6))
	if runways.is_empty():
		_label(size * 0.5, "no runway data", Color(0.7, 0.7, 0.7))
		return
	var b := _bounds()
	var s := minf(size.x / b.size.x, size.y / b.size.y)
	var c := b.get_center()
	var to := func(p: Vector2) -> Vector2: return size * 0.5 + Vector2(p.x - c.x, c.y - p.y) * s
	for t in taxiways:
		var pts := PackedVector2Array()
		for p in t:
			pts.append(to.call(p))
		if pts.size() > 1:
			draw_polyline(pts, Color(0.55, 0.5, 0.3, 0.8), maxf(15.0 * s, 1.5))
	for w in runways:
		var a: Vector2 = to.call(Vector2(w.ends[0].x, w.ends[0].y))
		var z: Vector2 = to.call(Vector2(w.ends[1].x, w.ends[1].y))
		draw_line(a, z, Color(0.75, 0.78, 0.8), maxf(float(w.width) * s, 4.0))
		for i in 2:
			var e: Dictionary = w.ends[i]
			var p: Vector2 = to.call(Vector2(e.x, e.y))
			var away := (p - (z if i == 0 else a)).normalized()
			_label(p + away * 16.0, str(e.ident), Color.WHITE)
	for st in stands:
		draw_circle(to.call(Vector2(st.x, st.y)), 2.5, Color(0.3, 0.8, 1.0) if st.jetbridge else Color(1.0, 0.8, 0.3))
	if not start.is_empty():
		var p: Vector2 = to.call(start.pos)
		p = p.clamp(Vector2(14, 14), size - Vector2(14, 14))
		var h := deg_to_rad(float(start.heading))
		var f := Vector2(sin(h), -cos(h))
		var r := f.orthogonal()
		var tri := PackedVector2Array([p + f * 14.0, p - f * 9.0 + r * 8.0, p - f * 9.0 - r * 8.0])
		draw_colored_polygon(tri, Color(1.0, 0.3, 0.25))
		draw_polyline(tri + PackedVector2Array([tri[0]]), Color.WHITE, 1.5)
	_label(Vector2(size.x - 18, 18), "N ↑", Color(0.8, 0.8, 0.8))
	draw_string(_font, Vector2(8, size.y - 8), "● gate (jetbridge)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.3, 0.8, 1.0))
	draw_string(_font, Vector2(140, size.y - 8), "● remote / GA stand", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1.0, 0.8, 0.3))


func _label(p: Vector2, t: String, col: Color) -> void:
	var w := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(_font, p + Vector2(-w * 0.5, 5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
