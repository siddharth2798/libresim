class_name WindDial
extends Control
## Wind dial of the Weather step: a compass with the chosen runway drawn on it and the wind arrow.
## Click or drag anywhere on the dial to set the direction the wind blows FROM (10 degree steps; the
## arrow's tail sits on that bearing); with the dial focused the arrow keys turn it by 10 degrees.
## The arrow is blue, amber near the aircraft's crosswind limit and red over it (or with a tailwind
## above 5 kt): the colour is WindMath.level, the readiness check's own rule. Without a runway
## (stand start) the runway bar and the level colouring are left out. It holds no setup of its own:
## the page calls set_state() and listens to direction_picked.

signal direction_picked(deg: float)

var wind_dir := 270.0
var wind_kt := 8.0
var gust_kt := 0.0
var runway_heading := -1.0  # degrees true of the chosen runway end; < 0 = no runway
var runway_ident := ""
var limit_kt := 15.0  # the aircraft's max crosswind
var _drag := false


func _ready() -> void:
	custom_minimum_size = Vector2(132, 132)
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	tooltip_text = "Click or drag to turn the wind. It blows from the arrow's tail towards the centre."


func set_state(dir_deg: float, kt: float, gust: float, rwy_heading: float, rwy_ident: String, limit: float) -> void:
	wind_dir = dir_deg
	wind_kt = kt
	gust_kt = gust
	runway_heading = rwy_heading
	runway_ident = rwy_ident
	limit_kt = limit
	queue_redraw()


## Level of the current wind against the runway and limit (OK without a runway).
func level() -> WindMath.Level:
	if runway_heading < 0.0:
		return WindMath.Level.OK
	return WindMath.level(WindMath.components(wind_dir, wind_kt, runway_heading), limit_kt)


func _center() -> Vector2:
	return size * 0.5


func _radius() -> float:
	return minf(size.x, size.y) * 0.5 - 3.0


## Direction a click at `pos` (control coordinates) means; -1 at the centre.
func dir_at(pos: Vector2) -> float:
	return WindMath.dir_from_offset(pos - _center())


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		_drag = ev.pressed
		if ev.pressed:
			grab_focus()
			_pick(ev.position)
		accept_event()
	elif ev is InputEventMouseMotion and _drag:
		_pick(ev.position)
		accept_event()
	elif ev is InputEventKey and ev.pressed:
		var d := 0.0
		if ev.keycode in [KEY_RIGHT, KEY_UP]:
			d = WindMath.SNAP_DEG
		elif ev.keycode in [KEY_LEFT, KEY_DOWN]:
			d = -WindMath.SNAP_DEG
		if d != 0.0:
			direction_picked.emit(fposmod(wind_dir + d, 360.0))
			accept_event()


func _pick(pos: Vector2) -> void:
	var d := dir_at(pos)
	if d >= 0.0:
		direction_picked.emit(d)


func _draw() -> void:
	var c := _center()
	var r := _radius()
	var font := get_theme_default_font()
	draw_circle(c, r, Color(0, 0, 0, 0.3))
	draw_arc(c, r, 0.0, TAU, 64, Color(1, 1, 1, 0.22), 2.0, true)
	for d in range(0, 360, 30):
		var u := WindMath.offset_of(float(d))
		var l := 9.0 if d % 90 == 0 else 5.0
		draw_line(c + u * r, c + u * (r - l), Color(1, 1, 1, 0.4), 1.0)
	for t in [["N", 0.0], ["E", 90.0], ["S", 180.0], ["W", 270.0]]:
		var p: Vector2 = c + WindMath.offset_of(t[1]) * (r - 18.0)
		var w := font.get_string_size(t[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, p + Vector2(-w * 0.5, 5), t[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MenuTheme.DIM)
	if runway_heading >= 0.0:
		_draw_runway(c, r)
	_draw_wind(c, r, font)
	if has_focus():
		draw_arc(c, r + 2.0, 0.0, TAU, 64, MenuTheme.ACCENT, float(MenuTheme.FOCUS_WIDTH), true)


func _draw_runway(c: Vector2, r: float) -> void:
	var u := WindMath.offset_of(runway_heading)
	var half := r * 0.45
	var side := u.orthogonal() * 7.0
	var quad := PackedVector2Array([c - u * half + side, c + u * half + side, c + u * half - side, c - u * half - side])
	draw_colored_polygon(quad, Color(0.81, 0.84, 0.86))
	var f := MenuTheme.font("semibold")  # the ident in dark ink on the bar, centred
	var w := f.get_string_size(runway_ident, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(f, c + Vector2(-w * 0.5, 4.5), runway_ident, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("16191d"))


func _draw_wind(c: Vector2, r: float, font: Font) -> void:
	var col := WindMath.color(level())
	var u := WindMath.offset_of(wind_dir)
	var length := minf(r * 0.3 + minf(wind_kt, 40.0) * r * 0.012, r * 0.78)
	var tail := c + u * (r - 8.0)
	var head := tail - u * length
	if wind_kt > 0.0:
		draw_line(tail, head, col, 4.0, true)
		var side := u.orthogonal()
		draw_colored_polygon(PackedVector2Array([head - u * 9.0, head + u * 3.0 + side * 8.0, head + u * 3.0 - side * 8.0]), col)
	draw_circle(tail, 5.0, col)
	var txt := "%d kt" % roundi(wind_kt)
	if gust_kt > wind_kt:
		txt += " G%d" % roundi(gust_kt)
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(font, Vector2(size.x - w - 2.0, 14.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, MenuTheme.TEXT)
