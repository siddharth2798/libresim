extends Control
## Centre radio stack: GPS line, 2x KX-155 COM/NAV, KR-87 ADF, KT-76A transponder,
## KI-266 DME. Standby frequencies tune with the mouse wheel (COM 25 kHz, NAV 50 kHz,
## ADF 1 kHz; Shift = 1 MHz / 100 kHz), clicking the swap arrow flips active/standby.
## Transponder: wheel over a digit changes it (0-7), click the mode box cycles OFF/SBY/ON/ALT.

const AMBER := Color(1.0, 0.62, 0.15)
const DIM := Color(0.55, 0.4, 0.15)
const UNIT := Color(0.13, 0.13, 0.14)

var font: Font
var _zones: Array = []  # [Rect2, kind, key]


func _ready() -> void:
	font = ThemeDB.fallback_font
	mouse_filter = MOUSE_FILTER_STOP


func _text(p: Vector2, t: String, fs: int, col: Color) -> void:
	draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _unit(y: float, h: float, title: String) -> Rect2:
	var r := Rect2(Vector2(4, y), Vector2(size.x - 8, h - 4))
	draw_rect(r, UNIT)
	draw_rect(r, Color(0.3, 0.3, 0.32), false, 1.0)
	_text(r.position + Vector2(6, 13), title, 10, Color(0.7, 0.7, 0.7))
	return r


func _freq(r: Rect2, x: float, key: String, fmt: String, active: bool, kind: String) -> void:
	var v := Props.get_f(key)
	var on := Props.get_b("systems/electrical/avionics_powered", true)
	var col := (AMBER if active else DIM) if on else Color(0.1, 0.1, 0.1)
	var p := r.position + Vector2(x, r.size.y * 0.68)
	_text(p, fmt % v, int(minf(r.size.y * 0.4, r.size.x * 0.052)), col)
	if not active:
		_zones.append([Rect2(p + Vector2(0, -r.size.y * 0.45), Vector2(r.size.x * 0.24, r.size.y * 0.5)), kind, key])


func _swap(r: Rect2, x: float, a: String, b: String) -> void:
	var box := Rect2(r.position + Vector2(x, r.size.y * 0.3), Vector2(r.size.x * 0.06, r.size.y * 0.45))
	draw_rect(box, Color(0.25, 0.25, 0.27))
	_text(box.position + Vector2(2, box.size.y * 0.75), "⇄", int(box.size.y * 0.7), Color.WHITE)
	_zones.append([box, "swap", [a, b]])


func _draw() -> void:
	_zones.clear()
	var h := size.y / 6.2
	var y := 0.0
	# GPS (direct-to readout)
	var g := _unit(y, h * 0.7, "GPS")
	var tgt: String = str(Props.get_v("avionics/gps/ident", ""))
	_text(g.position + Vector2(40, g.size.y * 0.7), ("D→ %s  %03.0f°  %.1f nm  ETE %s" % [tgt, Props.get_f("avionics/gps/brg_mag"), Props.get_f("avionics/gps/dist_nm"), Props.get_v("avionics/gps/ete", "--")]) if tgt != "" else "N: map, click an airport / navaid for direct-to", 12, Color(0.5, 1, 0.6))
	y += h * 0.7
	for i in [1, 2]:
		var r := _unit(y, h, "KX-155  COM%d / NAV%d" % [i, i])
		_freq(r, r.size.x * 0.02, "controls/com%d/freq_mhz" % i, "%.3f", true, "")
		_swap(r, r.size.x * 0.25, "controls/com%d/freq_mhz" % i, "controls/com%d/standby_mhz" % i)
		_freq(r, r.size.x * 0.32, "controls/com%d/standby_mhz" % i, "%.3f", false, "com")
		_freq(r, r.size.x * 0.54, "controls/nav%d/freq_mhz" % i, "%.2f", true, "")
		_swap(r, r.size.x * 0.75, "controls/nav%d/freq_mhz" % i, "controls/nav%d/standby_mhz" % i)
		_freq(r, r.size.x * 0.82, "controls/nav%d/standby_mhz" % i, "%.2f", false, "nav")
		y += h
	var a := _unit(y, h, "KR-87  ADF")
	_freq(a, a.size.x * 0.05, "controls/adf/freq_khz", "%.0f", true, "")
	_swap(a, a.size.x * 0.32, "controls/adf/freq_khz", "controls/adf/standby_khz")
	_freq(a, a.size.x * 0.42, "controls/adf/standby_khz", "%.0f", false, "adf")
	y += h
	var t := _unit(y, h, "KT-76A  XPDR")
	var code := "%04d" % int(Props.get_v("controls/xpdr/code", 7000))
	for k in 4:
		var p := t.position + Vector2(t.size.x * (0.08 + k * 0.1), t.size.y * 0.72)
		_text(p, code[k], int(t.size.y * 0.5), AMBER)
		_zones.append([Rect2(p + Vector2(0, -t.size.y * 0.5), Vector2(t.size.x * 0.09, t.size.y * 0.55)), "digit", k])
	var modes := ["OFF", "SBY", "ON", "ALT"]
	var mb := Rect2(t.position + Vector2(t.size.x * 0.6, t.size.y * 0.3), Vector2(t.size.x * 0.3, t.size.y * 0.5))
	draw_rect(mb, Color(0.25, 0.25, 0.27))
	_text(mb.position + Vector2(8, mb.size.y * 0.75), modes[int(Props.get_v("controls/xpdr/mode", 3))], int(mb.size.y * 0.6), Color.WHITE)
	_zones.append([mb, "mode", 0])
	y += h
	var d := _unit(y, h * 0.8, "KI-266  DME (NAV1)")
	var nm := Props.get_f("avionics/nav1/dme_nm", -1.0)
	_text(d.position + Vector2(d.size.x * 0.1, d.size.y * 0.72), ("%.1f NM" % nm) if nm >= 0.0 else "---.- NM", int(d.size.y * 0.45), Color(1, 0.3, 0.2))


func _gui_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed):
		return
	var delta := 0
	match e.button_index:
		MOUSE_BUTTON_WHEEL_UP: delta = 1
		MOUSE_BUTTON_WHEEL_DOWN: delta = -1
		MOUSE_BUTTON_LEFT: delta = 0
		_: return
	for z in _zones:
		if not (z[0] as Rect2).has_point(e.position):
			continue
		match z[1]:
			"swap":
				if delta == 0:
					var a = Props.get_v(z[2][0])
					Props.set_v(z[2][0], Props.get_v(z[2][1]))
					Props.set_v(z[2][1], a)
			"com", "nav", "adf":
				var big := Input.is_key_pressed(KEY_SHIFT)
				var step: float = {"com": 0.025, "nav": 0.05, "adf": 1.0}[z[1]]
				if big:
					step = 100.0 if z[1] == "adf" else 1.0
				var lim: Array = {"com": [118.0, 136.975], "nav": [108.0, 117.95], "adf": [190.0, 1799.0]}[z[1]]
				var v := Props.get_f(z[2]) + step * (delta if delta != 0 else 1)
				if v > lim[1]:
					v = lim[0]
				elif v < lim[0]:
					v = lim[1]
				Props.set_v(z[2], snappedf(v, 0.005 if z[1] != "adf" else 1.0))
			"digit":
				var code := "%04d" % int(Props.get_v("controls/xpdr/code", 7000))
				var dgt := (int(code[z[2]]) + (delta if delta != 0 else 1) + 8) % 8
				code = code.substr(0, z[2]) + str(dgt) + code.substr(z[2] + 1)
				Props.set_v("controls/xpdr/code", int(code))
			"mode":
				Props.set_v("controls/xpdr/mode", (int(Props.get_v("controls/xpdr/mode", 3)) + 1) % 4)
		accept_event()
		return
