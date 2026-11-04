class_name AirportDiagram
extends Control
## North-up airport diagram of the Airport step: runways (with idents), taxiways, the stands on offer, the chosen start
## (aircraft arrow) and a clickable surface: hover lights what is under the pointer, a click on a runway or its ident
## picks that end (runway_picked), a click on a stand picks it (stand_picked). The geometry is airport_map_math.gd
## (headless-testable); this control only draws and forwards the pointer. The legend is the page's.

signal runway_picked(ident: String)
signal stand_picked(stand: Dictionary)

const GATE := Color("4fc3ff")
const BAY := Color("ffc247")
const MARK := Color("ff5a4f")  # the start arrow

var runways: Array = []  # runways.json entries of this airport
var taxiways: Array = []  # [PackedVector2Array]
var stands: Array = []  # the stands on offer: dictionaries with x, y, heading_deg, jetbridge and name
var start := {}  # {"pos": Vector2, "heading": deg, "from": Vector2 or INF (air start: the dashed line), "label": String}
var selected_runway := ""  # ident
var selected_stand := ""  # stand name
var short_ends := {}  # ident -> true: the runway is too short for the aircraft (its ident is dimmed)
var hover := {}  # what AirportMapMath.pick found under the pointer
var read_only := false  # a picture only (the Training page): no hover, no clicks; set before add_child
var _view := {}


func _ready() -> void:
	if custom_minimum_size == Vector2.ZERO:  # a caller may have set a compact size
		custom_minimum_size = Vector2(300, 230)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE if read_only else Control.MOUSE_FILTER_STOP
	resized.connect(queue_redraw)


func show_airport(rw: Array, tw: Array, st: Array) -> void:
	runways = rw
	taxiways = tw
	stands = st
	hover = {}
	queue_redraw()


func set_start(pos: Vector2, heading_deg: float, from := Vector2.INF, label := "") -> void:
	start = {"pos": pos, "heading": heading_deg, "from": from, "label": label}
	queue_redraw()


func set_selection(runway: String, stand: String) -> void:
	selected_runway = runway
	selected_stand = stand
	queue_redraw()


func _fit() -> void:
	_view = AirportMapMath.view(AirportMapMath.bounds(runways, stands), size, 6.0)


func _gui_input(e: InputEvent) -> void:
	if runways.is_empty() or read_only:
		return
	if e is InputEventMouseMotion:
		_fit()
		var h := AirportMapMath.pick(_view, runways, stands, e.position)
		if h != hover:
			hover = h
			tooltip_text = _tip(h)
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not h.is_empty() else Control.CURSOR_ARROW
			queue_redraw()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_fit()
		var h := AirportMapMath.pick(_view, runways, stands, e.position)
		if h.get("kind", "") == "runway":
			runway_picked.emit(h.ident)
			accept_event()
		elif h.get("kind", "") == "stand":
			stand_picked.emit(stands[h.index])
			accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and not hover.is_empty():
		hover = {}
		queue_redraw()


func _tip(h: Dictionary) -> String:
	match h.get("kind", ""):
		"runway":
			var w: Dictionary = runways[h.runway]
			return "Runway %s  (%s m)" % [h.ident, AirportData.thousands(int(w.length))]
		"stand":
			var st: Dictionary = stands[h.index]
			return "%s  (%s)" % [st.get("name", st.get("ref", "stand")), "jetbridge gate" if st.get("jetbridge", false) else "remote stand"]
	return ""


func _draw() -> void:
	draw_style_box(MenuTheme.box(Color(0.02, 0.04, 0.06, 0.62), 8, MenuTheme.LINE), Rect2(Vector2.ZERO, size))
	if runways.is_empty():
		_text(size * 0.5, "no runway data", MenuTheme.DIM, 15)
		return
	_fit()
	var v := _view
	for t in taxiways:
		var pts := PackedVector2Array()
		for p in t:
			pts.append(AirportMapMath.to_screen(v, p))
		if pts.size() > 1:
			draw_polyline(pts, Color(0.77, 0.67, 0.36, 0.7), maxf(15.0 * v.scale, 1.5))
	for k in runways.size():
		_draw_runway(runways[k], k)
	for i in stands.size():
		_draw_stand(stands[i], i)
	_draw_start()
	_text(Vector2(size.x - 24, 18), "N ↑", MenuTheme.DIM, 14)


func _draw_runway(w: Dictionary, k: int) -> void:
	var v := _view
	var a := AirportMapMath.to_screen(v, Vector2(w.ends[0].x, w.ends[0].y))
	var z := AirportMapMath.to_screen(v, Vector2(w.ends[1].x, w.ends[1].y))
	var hot: bool = hover.get("kind", "") == "runway" and hover.runway == k
	var sel := selected_runway in [str(w.ends[0].ident), str(w.ends[1].ident)]
	var px := AirportMapMath.strip_px(v, w)
	if hot:
		draw_line(a, z, Color(MenuTheme.ACCENT, 0.5), px + 7.0)
	draw_line(a, z, Color(0.81, 0.84, 0.86), px)
	if sel:
		draw_line(a, z, Color(MenuTheme.ACCENT, 0.9), 2.0)
	for i in 2:
		var id := str(w.ends[i].ident)
		var on := id == selected_runway
		var col := MenuTheme.ACCENT if on else (MenuTheme.FAINT if short_ends.has(id) else MenuTheme.TEXT)
		if hot and hover.ident == id:
			col = Color.WHITE
			draw_circle(AirportMapMath.end_label_pos(v, w, i), 13.0, Color(MenuTheme.ACCENT, 0.35))
		_text(AirportMapMath.end_label_pos(v, w, i), id, col, 15, "bold" if on else "medium")


func _draw_stand(st: Dictionary, i: int) -> void:
	var p := AirportMapMath.to_screen(_view, Vector2(st.x, st.y))
	var col := GATE if st.get("jetbridge", false) else BAY
	var sel := str(st.get("name", "")) == selected_stand and selected_stand != ""
	var hot: bool = hover.get("kind", "") == "stand" and hover.index == i
	if hot:
		draw_circle(p, 9.0, Color(1, 1, 1, 0.35))
	draw_circle(p, 6.0 if sel else (4.5 if hot else 3.0), col)
	if sel:
		draw_arc(p, 6.5, 0.0, TAU, 20, Color.WHITE, 1.5)


func _draw_start() -> void:
	if start.is_empty():
		return
	var p := AirportMapMath.to_screen(_view, start.pos)
	var room := Rect2(Vector2(14, 14), size - Vector2(28, 28))
	var inside := room.has_point(p)
	if start.from != Vector2.INF:  # air start: the final approach track, dashed, stopping where it leaves the map
		var q := AirportMapMath.to_screen(_view, start.from)
		if not inside:
			var lo := 0.0
			var hi := 1.0
			for _i in 14:
				var mid := (lo + hi) * 0.5
				if room.has_point(q.lerp(p, mid)):
					lo = mid
				else:
					hi = mid
			p = q.lerp(p, lo)
		var n := maxi(int(q.distance_to(p) / 12.0), 1)
		for i in n:
			if i % 2 == 0:
				draw_line(q.lerp(p, float(i) / n), q.lerp(p, float(i + 1) / n), Color(MARK, 0.9), 2.0)
	p = p.clamp(Vector2(14, 14), size - Vector2(14, 14))
	var h := deg_to_rad(float(start.heading))
	var f := Vector2(sin(h), -cos(h))
	var r := f.orthogonal()
	var tri := PackedVector2Array([p + f * 14.0, p - f * 9.0 + r * 8.0, p - f * 9.0 - r * 8.0])
	draw_colored_polygon(tri, MARK)
	draw_polyline(tri + PackedVector2Array([tri[0]]), Color.WHITE, 1.5)
	if str(start.label) != "":  # top left, where nothing is drawn
		var t: String = "Your start: " + str(start.label) + ("" if inside else " (off the map)")
		draw_string(MenuTheme.font("semibold"), Vector2(10, 20), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("ffb4ad"))


func _text(centre: Vector2, t: String, col: Color, fsize := 14, weight := "regular") -> void:
	var f := MenuTheme.font(weight)
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	draw_string(f, centre + Vector2(-w * 0.5, fsize * 0.35), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
