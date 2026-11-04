extends Node
## The day strip of the Weather step (ui/menu/day_math.gd, day_strip.gd): sunrise and sunset from the
## game's own sun, the night / twilight / day bands, the pixel <-> time maths and the input handling.
## Real-world reference (timeanddate.com, Mumbai): 14 Feb sunrise about 07:10, sunset about 18:40 IST;
## the game has one sky for the whole map (SkyTime.LAT / LON), so every airport shares these times.

const FEB := 45.0  # day of the year of the game's default date (14 Feb)
const JUN := 172.0


func _strip() -> DayStrip:
	var d := DayStrip.new()
	add_child(d)
	d.size = Vector2(412, 62)  # 6 px padding at each end: 400 px for 24 h
	return d


func _click(pos: Vector2, pressed := true) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	return e


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func test_strip_sun_times_are_the_games_own_values() -> String:
	for day in [1.0, FEB, JUN, 300.0, 365.0]:
		if DayMath.sun_times(day) != WeatherVisuals.sun_rise_set(day):
			return "day %d: the strip must show WeatherVisuals.sun_rise_set" % day
	return ""


func test_strip_sun_times_match_the_real_sun_within_a_few_minutes() -> String:
	var feb := DayMath.sun_times(FEB)
	if absf(feb.x - (7.0 + 10.0 / 60.0)) > 0.12 or absf(feb.y - (18.0 + 40.0 / 60.0)) > 0.12:
		return "14 Feb should be about 07:10 / 18:40, got %s / %s" % [DayMath.clock(feb.x), DayMath.clock(feb.y)]
	var jun := DayMath.sun_times(JUN)
	if absf(jun.x - 6.0) > 0.15:
		return "June sunrise should be about 06:00, got %s" % DayMath.clock(jun.x)
	if not (jun.y - jun.x > feb.y - feb.x - 0.5):
		return "June days are not shorter than February days in Mumbai by half an hour"
	return ""


func test_strip_phase_by_hour() -> String:
	var rs := DayMath.sun_times(FEB)
	if DayMath.phase_at(2.0, FEB) != DayMath.Phase.NIGHT or DayMath.phase_at(23.5, FEB) != DayMath.Phase.NIGHT:
		return "02:00 and 23:30 are night"
	if DayMath.phase_at(12.5, FEB) != DayMath.Phase.DAY:
		return "12:30 is day"
	if DayMath.phase_at(rs.x - 0.2, FEB) != DayMath.Phase.TWILIGHT or DayMath.phase_at(rs.y + 0.2, FEB) != DayMath.Phase.TWILIGHT:
		return "12 min before sunrise and after sunset is twilight"
	if DayMath.phase_at(rs.x + 0.1, FEB) != DayMath.Phase.DAY or DayMath.phase_at(rs.y - 0.1, FEB) != DayMath.Phase.DAY:
		return "6 min after sunrise and before sunset is day"
	return ""


func test_strip_bands_cover_the_day_in_order() -> String:
	for day in [FEB, JUN, 355.0]:
		var b := DayMath.bands(day)
		if b[0][0] != 0.0 or b[b.size() - 1][1] != 24.0:
			return "day %d: bands must run from 0 to 24" % day
		for i in b.size():
			if i > 0 and absf(b[i][0] - b[i - 1][1]) > 1e-6:
				return "day %d: gap between band %d and %d" % [day, i - 1, i]
			if i > 0 and b[i][2] == b[i - 1][2]:
				return "day %d: neighbouring bands should differ" % day
		var order := b.map(func(x): return x[2])
		if order != [DayMath.Phase.NIGHT, DayMath.Phase.TWILIGHT, DayMath.Phase.DAY, DayMath.Phase.TWILIGHT, DayMath.Phase.NIGHT]:
			return "day %d: night, twilight, day, twilight, night expected, got %s" % [day, order]
		var rs := DayMath.sun_times(day)
		if absf(b[2][0] - rs.x) > 0.1 or absf(b[2][1] - rs.y) > 0.1:
			return "day %d: the day band should run from sunrise to sunset (%s / %s)" % [day, b[2], rs]
	return ""


func test_strip_night_is_drawn_darker_than_day() -> String:
	var n: Color = DayStrip.COLORS[DayMath.Phase.NIGHT]
	var t: Color = DayStrip.COLORS[DayMath.Phase.TWILIGHT]
	var d: Color = DayStrip.COLORS[DayMath.Phase.DAY]
	if not (n.get_luminance() < t.get_luminance() and t.get_luminance() < d.get_luminance()):
		return "night < twilight < day in brightness"
	var b := DayMath.bands(FEB)
	var at_22 := -1
	for i in b.size():
		if 22.0 >= b[i][0] and 22.0 < b[i][1]:
			at_22 = i
	if at_22 < 0 or b[at_22][2] != DayMath.Phase.NIGHT or DayStrip.COLORS[b[at_22][2]] != n:
		return "22:00 should fall in the night band"
	return ""


func test_strip_time_from_x_maths() -> String:
	if DayMath.time_from_x(6.0, 412.0, 6.0) != 0.0 or DayMath.time_from_x(-50.0, 412.0, 6.0) != 0.0:
		return "the left end (and beyond) is 00:00"
	if absf(DayMath.time_from_x(206.0, 412.0, 6.0) - 12.0) > 1e-6:
		return "the middle is 12:00, got %s" % DayMath.time_from_x(206.0, 412.0, 6.0)
	if DayMath.time_from_x(900.0, 412.0, 6.0) != DayMath.MAX_H:
		return "the right end is the last quarter hour, got %s" % DayMath.time_from_x(900.0, 412.0, 6.0)
	var t := DayMath.time_from_x(6.0 + 400.0 * 10.1 / 24.0, 412.0, 6.0)
	if t != 10.0:
		return "10.1 h snaps to the quarter hour 10.0, got %s" % t
	for h in [0.0, 3.25, 7.5, 12.0, 21.75]:
		if DayMath.time_from_x(DayMath.x_from_time(h, 412.0, 6.0), 412.0, 6.0) != h:
			return "x_from_time and time_from_x should round-trip %s" % h
	return ""


func test_strip_clock_text() -> String:
	if DayMath.clock(7.1667) != "07:10" or DayMath.clock(0.0) != "00:00" or DayMath.clock(23.75) != "23:45" or DayMath.clock(12.5) != "12:30":
		return "clock text: %s %s %s %s" % [DayMath.clock(7.1667), DayMath.clock(0.0), DayMath.clock(23.75), DayMath.clock(12.5)]
	return ""


func test_strip_click_and_drag_set_the_time() -> String:
	var d := _strip()
	var got := []
	d.time_picked.connect(func(h): got.append(h))
	d._gui_input(_click(Vector2(206, 30)))  # middle: noon
	var m := InputEventMouseMotion.new()
	m.position = Vector2(6.0 + 400.0 * 18.0 / 24.0, 30)
	d._gui_input(m)  # dragging: 18:00
	d._gui_input(_click(Vector2(0, 0), false))
	m.position = Vector2(300, 30)
	d._gui_input(m)  # released: nothing
	var ok: bool = got == [12.0, 18.0]
	d.free()
	return "" if ok else "press at the middle then drag to 18:00, motion after release nothing: %s" % [got]


func test_strip_keys_move_by_quarter_hours_and_hours() -> String:
	var d := _strip()
	d.set_state(10.0, FEB)
	var got := []
	d.time_picked.connect(func(h): got.append(h))
	d._gui_input(_key(KEY_RIGHT))
	d._gui_input(_key(KEY_LEFT))
	d._gui_input(_key(KEY_PAGEUP))
	d._gui_input(_key(KEY_PAGEDOWN))
	d.set_state(0.0, FEB)
	d._gui_input(_key(KEY_LEFT))  # clamped at 00:00
	d.set_state(DayMath.MAX_H, FEB)
	d._gui_input(_key(KEY_PAGEUP))  # clamped at the last quarter hour
	d._gui_input(_key(KEY_A))
	var ok: bool = got == [10.25, 9.75, 11.0, 9.0, 0.0, DayMath.MAX_H]
	d.free()
	return "" if ok else "keys: %s" % [got]
