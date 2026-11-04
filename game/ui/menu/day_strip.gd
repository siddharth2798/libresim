class_name DayStrip
extends Control
## Day strip of the Weather step: a 24 h bar coloured night / twilight / day for the chosen date from
## the game's own sun (DayMath), sunrise and sunset above it, and the time of day as a sun (or moon)
## marker. Click or drag to set the time (quarter hours); with the strip focused Left / Right move it
## by 15 min and Page Up / Page Down by an hour. It holds no setup of its own: the page calls
## set_state() and listens to time_picked.

signal time_picked(h: float)

const PAD := 6.0
const BAR_Y := 20.0
const BAR_H := 20.0
const COLORS := {
	DayMath.Phase.NIGHT: Color("101a2e"),
	DayMath.Phase.TWILIGHT: Color("8a6272"),
	DayMath.Phase.DAY: Color("4f93c9"),
}

var time_h := 10.0
var day_of_year := 45.0
var _bands: Array = []
var _bands_day := -1.0
var _drag := false


func _ready() -> void:
	custom_minimum_size = Vector2(200, 62)
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_HSIZE
	tooltip_text = "Click or drag to set the time of day. Colours: night, twilight, day for the chosen month."


func set_state(h: float, day: float) -> void:
	time_h = h
	day_of_year = day
	queue_redraw()


func time_at(x: float) -> float:
	return DayMath.time_from_x(x, size.x, PAD)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		_drag = ev.pressed
		if ev.pressed:
			grab_focus()
			time_picked.emit(time_at(ev.position.x))
		accept_event()
	elif ev is InputEventMouseMotion and _drag:
		time_picked.emit(time_at(ev.position.x))
		accept_event()
	elif ev is InputEventKey and ev.pressed:
		var d := 0.0
		match ev.keycode:
			KEY_RIGHT: d = DayMath.STEP_H
			KEY_LEFT: d = -DayMath.STEP_H
			KEY_PAGEUP: d = 1.0
			KEY_PAGEDOWN: d = -1.0
		if d != 0.0:
			time_picked.emit(clampf(time_h + d, 0.0, DayMath.MAX_H))
			accept_event()


func _draw() -> void:
	if _bands_day != day_of_year:  # the bands only depend on the date
		_bands = DayMath.bands(day_of_year)
		_bands_day = day_of_year
	var font := get_theme_default_font()
	for b in _bands:
		var x0 := DayMath.x_from_time(b[0], size.x, PAD)
		var x1 := DayMath.x_from_time(b[1], size.x, PAD)
		draw_rect(Rect2(x0, BAR_Y, x1 - x0, BAR_H), COLORS[b[2]])
	for t in range(0, 25, 3):
		var x := DayMath.x_from_time(float(t), size.x, PAD)
		var s := "%02d" % t
		var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var tx := clampf(x - w * 0.5, 0.0, size.x - w)
		draw_string(font, Vector2(tx, BAR_Y + BAR_H + 16.0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MenuTheme.DIM)
	var rs := DayMath.sun_times(day_of_year)
	_label_at(font, rs.x, "↑ " + DayMath.clock(rs.x), Color("ffd9a0"))
	_label_at(font, rs.y, DayMath.clock(rs.y) + " ↓", Color("ffb4a0"))
	var mx := DayMath.x_from_time(time_h, size.x, PAD)
	var day := DayMath.phase_at(time_h, day_of_year) == DayMath.Phase.DAY
	draw_line(Vector2(mx, BAR_Y - 3.0), Vector2(mx, BAR_Y + BAR_H + 3.0), Color.WHITE, 2.0)
	draw_circle(Vector2(mx, BAR_Y + BAR_H * 0.5), 8.0, Color("ffd45a") if day else Color("dfe6f2"))
	draw_arc(Vector2(mx, BAR_Y + BAR_H * 0.5), 8.0, 0.0, TAU, 24, Color.WHITE, 1.5, true)
	if has_focus():
		draw_rect(Rect2(Vector2.ZERO, size).grow(-1.0), MenuTheme.ACCENT, false, float(MenuTheme.FOCUS_WIDTH))


func _label_at(font: Font, h: float, text: String, col: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var x := clampf(DayMath.x_from_time(h, size.x, PAD) - w * 0.5, 0.0, size.x - w)
	draw_string(font, Vector2(x, 13.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
