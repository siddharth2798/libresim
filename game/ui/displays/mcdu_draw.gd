class_name MCDUDraw
extends RefCounted
## Page body and keypad of the lite MCDU. Drawing only; the key actions stay in mcdu.gd.


static func paint(d: MCDU) -> void:
	var p := d.page()
	if p == "FPLN":
		_fpln(d)
	elif p == "DIR":
		_dir(d)
	elif p == "PROG":
		_prog(d)
	else:
		for f in MCDU.FIELDS[p]:
			_field(d, f)
	var s := str(Props.get_v("mcdu/scratch", ""))
	var bad := s.begins_with("FORMAT") or s == FlightPlan.NOT_IN_DB
	d.txt(Vector2(16, 318), s if s != "" else "[    ]", 20, MCDU.AMBER if bad else MCDU.WHITE)
	for i in 6:
		d.hot(Rect2(8, 44 + i * 44, 56, 42), "l%d" % (i + 1))
		d.hot(Rect2(356, 44 + i * 44, 56, 42), "r%d" % (i + 1))
	_keys(d)


static func _field(d: MCDU, f: Array) -> void:
	var y: float = 50.0 + (f[1] - 1) * 44.0
	var right: bool = f[0] == "r"
	var x := 400.0 if right else 16.0
	var al := 1 if right else -1
	d.txt(Vector2(x, y), f[2], 12, MCDU.WHITE, al)
	var v := MCDU._shown(f)
	d.txt(Vector2(x, y + 20), (v + f[5]) if v != "" else ("[ ]" if f[4] == "text" else "[  ]"), 20, MCDU.CYAN if v != "" else Color(0.4, 0.6, 0.7), al)


static func _fpln(d: MCDU) -> void:
	var wps := MCDU.route()
	var legs: Array = Props.get_v("avionics/fms/legs", [])
	for i in 6:
		var y := 50.0 + i * 44.0
		if i < wps.size():
			d.txt(Vector2(16, y + 20), str(wps[i]), 20, MCDU.MAGENTA if i == 0 else MCDU.GREEN)
			if i < legs.size():
				var lg: Dictionary = legs[i]
				d.txt(Vector2(400, y + 20), "%03d %dNM" % [roundi(lg.get("course", 0)), roundi(lg.get("dist_nm", 0))], 16, MCDU.GREEN, 1)
		elif i == wps.size():
			d.txt(Vector2(16, y + 20), "[    ]", 20, Color(0.4, 0.6, 0.7))


static func _dir(d: MCDU) -> void:
	var t := str(Props.get_v("controls/gps/target", ""))
	d.txt(Vector2(16, 50), "DIR TO", 12, MCDU.WHITE)
	d.txt(Vector2(16, 70), t if t != "" else "[    ]", 20, MCDU.MAGENTA if t != "" else Color(0.4, 0.6, 0.7))


static func _prog(d: MCDU) -> void:
	var r := MCDU.prog_readout()
	var t := str(r["target"])
	d.txt(Vector2(16, 50), "TO", 12, MCDU.WHITE)
	d.txt(Vector2(16, 70), t if t != "" else "----", 20, MCDU.MAGENTA if t != "" else Color(0.4, 0.6, 0.7))
	d.txt(Vector2(400, 50), "DIST", 12, MCDU.WHITE, 1)
	_nav(d, 70, str(r["dist"]))
	d.txt(Vector2(400, 94), "BRG", 12, MCDU.WHITE, 1)
	_nav(d, 114, str(r["brg"]))
	d.txt(Vector2(16, 150), "VERT", 12, MCDU.WHITE)
	d.txt(Vector2(16, 170), str(r.get("phase", MCDU.DASH)), 20, MCDU.GREEN if str(r.get("phase", MCDU.DASH)) != MCDU.DASH else Color(0.4, 0.6, 0.7))
	d.txt(Vector2(400, 150), "TOD", 12, MCDU.WHITE, 1)
	_nav(d, 170, str(r.get("tod", MCDU.DASH)))


static func _nav(d: MCDU, y: float, s: String) -> void:
	d.txt(Vector2(400, y), s, 20, MCDU.GREEN if s != MCDU.DASH else Color(0.4, 0.6, 0.7), 1)


static func _keys(d: MCDU) -> void:
	var n := MCDU.PAGE_IDS.size()
	var gap := 6.0
	var w := (400.0 - gap * (n - 1)) / n
	for i in n:
		var id: String = MCDU.PAGE_IDS[i]
		d.button(Rect2(10.0 + i * (w + gap), 344, w, 30), "p_" + id, id.replace("FPLN", "F-PLN"), d.page() == id, MCDU.GREEN, 12)
	for i in 11:
		var c := "789456123.0"[i]
		d.button(Rect2(12 + (i % 3) * 52, 386 + (i / 3) * 40, 46, 34), "k_" + c, c, false, MCDU.GREEN, 18)
	d.button(Rect2(12 + 2 * 52, 386 + 3 * 40, 46, 34), "k_/", "/", false, MCDU.GREEN, 18)
	d.button(Rect2(12, 386 + 4 * 40, 98, 30), "k_CLR", "CLR", false, MCDU.GREEN, 14)
	d.button(Rect2(116, 386 + 4 * 40, 46, 30), "k_-", "+/-", false, MCDU.GREEN, 12)
	for i in 26:
		d.button(Rect2(176 + (i % 6) * 40, 386 + (i / 6) * 40, 36, 34), "k_" + MCDU.LETTERS[i], MCDU.LETTERS[i], false, MCDU.GREEN, 16)
