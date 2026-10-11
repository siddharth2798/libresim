extends Control
## Lower switch panel: rocker switches (click to toggle) and rotary selectors
## (click left/right half, or wheel). Each item maps to a Props path. PANEL is the
## instrument-light dimmer knob (0..1, also L / Shift+L).

const ITEMS := [
	# [label, prop, kind ("sw" toggle | "rot" rotary | "dim" 0..1 knob), options for rot]
	["BAT", "controls/electrical/master_bat", "sw", []],
	["ALT", "controls/electrical/master_alt", "sw", []],
	["AVN", "controls/electrical/avionics", "sw", []],
	["BCN", "controls/lights/beacon", "sw", []],
	["LAND", "controls/lights/landing", "sw", []],
	["TAXI", "controls/lights/taxi", "sw", []],
	["NAV", "controls/lights/nav", "sw", []],
	["STRB", "controls/lights/strobe", "sw", []],
	["PANEL", "controls/lights/panel", "dim", []],
	["PITOT HT", "controls/electrical/pitot_heat", "sw", []],
	["MAGS", "controls/magnetos", "rot", ["OFF", "R", "L", "BOTH"]],
	["FUEL", "controls/fuel/selector", "rot", ["OFF", "LEFT", "RIGHT", "BOTH"]],
	["SHUTOFF", "controls/fuel/shutoff", "sw", []],
	["ALT STAT", "systems/alternate_static", "sw", []],
]
const MAG_ORDER := [0, 2, 1, 3]  # dial order OFF-R-L-BOTH -> controls/magnetos values (1 = L, 2 = R)

var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font
	mouse_filter = MOUSE_FILTER_STOP


func _cell(i: int) -> Rect2:
	var w := size.x / ITEMS.size()
	return Rect2(Vector2(i * w, 0), Vector2(w, size.y))


func _rot_index(it: Array) -> int:
	var v: int = int(Props.get_v(it[1], 3))
	return MAG_ORDER.find(v) if it[0] == "MAGS" else v


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.12, 0.12, 0.13))
	var low := Props.get_b("systems/electrical/low_volts")
	for i in ITEMS.size():
		var it: Array = ITEMS[i]
		var r := _cell(i).grow(-4)
		var c := r.get_center()
		if it[2] == "sw":
			var on := Props.get_b(it[1])
			var sw := Rect2(c - Vector2(9, 18), Vector2(18, 30))
			draw_rect(sw, Color(0.05, 0.05, 0.05))
			var half := Rect2(sw.position + (Vector2(0, 0) if on else Vector2(0, 15)), Vector2(18, 15))
			draw_rect(half, Color(0.85, 0.85, 0.8) if not it[0] in ["BAT", "ALT"] else Color(0.85, 0.2, 0.15))
		elif it[2] == "dim":
			var v := Props.get_f(it[1])
			var kc := c + Vector2(0, -4)
			draw_arc(kc, 14, PI * 0.75, PI * 2.25, 24, Color(0.3, 0.3, 0.3), 2)
			draw_arc(kc, 14, PI * 0.75, PI * (0.75 + 1.5 * v), 24, Color(1, 0.85, 0.4), 2)
			draw_circle(kc, 10, Color(0.05, 0.05, 0.05))
			var a := PI * (0.75 + 1.5 * v)
			draw_line(kc, kc + Vector2(cos(a), sin(a)) * 9, Color.WHITE, 2)
			_text(c + Vector2(0, 22), "%d%%" % roundi(v * 100.0), 10, Color(1, 0.85, 0.4))
		else:
			var idx := _rot_index(it)
			var opts: Array = it[3]
			draw_circle(c + Vector2(0, -4), 14, Color(0.05, 0.05, 0.05))
			var a := lerpf(-1.0, 1.0, float(idx) / (opts.size() - 1))
			draw_line(c + Vector2(0, -4), c + Vector2(0, -4) + Vector2(sin(a), -cos(a)) * 13, Color.WHITE, 3)
			_text(c + Vector2(0, 22), opts[idx], 10, Color(1, 0.85, 0.4))
		_text(Vector2(c.x, r.end.y - 4), it[0], 10, Color(0.85, 0.85, 0.8))
	if low:
		_text(Vector2(size.x - 40, 12), "VOLTS", 11, Color(1, 0.2, 0.15))


func _text(p: Vector2, t: String, fs: int, col: Color) -> void:
	var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, p - Vector2(w * 0.5, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _gui_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed):
		return
	var i := int(e.position.x / (size.x / ITEMS.size()))
	if i < 0 or i >= ITEMS.size():
		return
	var it: Array = ITEMS[i]
	if it[2] == "sw":
		if e.button_index == MOUSE_BUTTON_LEFT:
			Props.set_v(it[1], not Props.get_b(it[1]))
		return
	var d := 0
	if it[2] == "dim":
		match e.button_index:
			MOUSE_BUTTON_LEFT: d = -1 if e.position.x < _cell(i).get_center().x else 1
			MOUSE_BUTTON_WHEEL_UP: d = 1
			MOUSE_BUTTON_WHEEL_DOWN: d = -1
		Props.set_v(it[1], LightLogic.step_panel(Props.get_f(it[1]), d))
		return
	match e.button_index:
		MOUSE_BUTTON_LEFT: d = -1 if e.position.x < _cell(i).get_center().x else 1
		MOUSE_BUTTON_WHEEL_UP: d = 1
		MOUSE_BUTTON_WHEEL_DOWN: d = -1
	var n: int = (it[3] as Array).size()
	var idx := clampi(_rot_index(it) + d, 0, n - 1)
	Props.set_v(it[1], MAG_ORDER[idx] if it[0] == "MAGS" else idx)
