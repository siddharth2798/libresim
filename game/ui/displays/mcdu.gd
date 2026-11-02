class_name MCDU
extends Display
## MCDU-lite: a 24-character text screen with line keys, a scratchpad and a keypad. Pages INIT
## (from / to, flight number, cruise level, cost index), F-PLN (the GPS route: line keys with a typed
## ident replace / append a waypoint) and PERF (V1 / VR / V2, FLEX temperature, flaps, trim). A line key
## with the scratchpad empty copies the field into it, with text it stores it (checked), the way the
## real unit works. Stores to Props mcdu/{page, scratch, init/*, perf/*}; F-PLN writes
## controls/gps/{target, route_next} (read by avionics/gps.gd). Reads those and avionics/gps/*.
## TODO (not modelled): DIR, PROG, RAD NAV, FUEL PRED, SEC F-PLN, airways / SID / STAR, VNAV
## predictions, keyboard input, multiple pages per list, the second unit.

const PAGE_IDS := ["INIT", "FPLN", "PERF"]
const TITLES := {"INIT": "INIT A", "FPLN": "F-PLN", "PERF": "TAKE OFF"}
const FIELDS := {  # page -> [[side, row 1..6, label, prop, kind "text" | "num", unit]]
	"INIT": [["l", 1, "FROM/TO", "mcdu/init/from_to", "text", ""], ["l", 2, "FLT NBR", "mcdu/init/flt_no", "text", ""],
		["l", 4, "COST INDEX", "mcdu/init/cost_index", "num", ""], ["r", 3, "CRZ FL", "mcdu/init/cruise_fl", "num", ""]],
	"PERF": [["l", 1, "V1", "mcdu/perf/v1", "num", ""], ["l", 2, "VR", "mcdu/perf/vr", "num", ""], ["l", 3, "V2", "mcdu/perf/v2", "num", ""],
		["r", 1, "FLEX TEMP", "mcdu/perf/flex_c", "num", "C"], ["r", 2, "FLAPS", "mcdu/perf/flaps", "num", ""], ["r", 3, "THS", "mcdu/perf/ths", "num", ""]],
}
const LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const SCREEN := Rect2(10, 10, 400, 320)
const MAX_SCRATCH := 22


func _init() -> void:
	design = Vector2(420, 600)


func page() -> String:
	var p := str(Props.get_v("mcdu/page", "INIT"))
	return p if p in PAGE_IDS else "INIT"


## Route lines of the F-PLN page: the active waypoint then the later ones (idents).
static func route() -> Array:
	var t := str(Props.get_v("controls/gps/target", ""))
	return ([t] if t != "" else []) + Array(Props.get_v("controls/gps/route_next", []))


## Replace waypoint `i` (0-based; past the end = append) with `ident`; the new route (pure).
static func with_waypoint(wps: Array, i: int, ident: String) -> Array:
	var out := wps.duplicate()
	if i >= out.size():
		out.append(ident)
	else:
		out[i] = ident
	return out


func _press(id: String, button: int, _p: Vector2) -> void:
	var s := str(Props.get_v("mcdu/scratch", ""))
	if id.begins_with("p_"):
		Props.set_v("mcdu/page", id.substr(2))
	elif id == "k_CLR":
		Props.set_v("mcdu/scratch", "" if button != MOUSE_BUTTON_LEFT else s.substr(0, maxi(s.length() - 1, 0)))
	elif id.begins_with("k_"):
		if s.length() < MAX_SCRATCH:
			Props.set_v("mcdu/scratch", s + id.substr(2))
	elif id.begins_with("l") or id.begins_with("r"):
		_line_key(id[0], int(id.substr(1)), s)


func _line_key(side: String, row: int, s: String) -> void:
	if page() == "FPLN":
		if side == "l" and s != "" and row >= 1:
			var wps := with_waypoint(route(), row - 1, s)
			Props.set_v("controls/gps/target", wps[0])
			Props.set_v("controls/gps/route_next", wps.slice(1))
			Props.set_v("mcdu/scratch", "")
		return
	for f in FIELDS.get(page(), []):
		if f[0] != side or f[1] != row:
			continue
		if s == "":
			Props.set_v("mcdu/scratch", _shown(f))
		elif f[4] == "num" and not s.is_valid_float():
			Props.set_v("mcdu/scratch", "FORMAT ERROR")
		else:
			Props.set_v(f[3], float(s) if f[4] == "num" else s)
			Props.set_v("mcdu/scratch", "")


static func _shown(f: Array) -> String:
	var v: Variant = Props.get_v(f[3], null)
	if v == null:
		return ""
	return str(roundi(float(v))) if f[4] == "num" else str(v)


func _paint() -> void:
	fill(SCREEN, Color.BLACK)
	frame(SCREEN.grow(2), GREY, 2.0)
	txt(Vector2(210, 26), TITLES[page()], 20, WHITE, 0)
	if page() == "FPLN":
		_fpln()
	else:
		for f in FIELDS[page()]:
			_field(f)
	var s := str(Props.get_v("mcdu/scratch", ""))
	txt(Vector2(16, 318), s if s != "" else "[    ]", 20, AMBER if s.begins_with("FORMAT") else WHITE)
	for i in 6:
		hot(Rect2(8, 44 + i * 44, 56, 42), "l%d" % (i + 1))
		hot(Rect2(356, 44 + i * 44, 56, 42), "r%d" % (i + 1))
	_keys()


func _field(f: Array) -> void:
	var y: float = 50.0 + (f[1] - 1) * 44.0
	var right: bool = f[0] == "r"
	var x := 400.0 if right else 16.0
	var al := 1 if right else -1
	txt(Vector2(x, y), f[2], 12, WHITE, al)
	var v := _shown(f)
	txt(Vector2(x, y + 20), (v + f[5]) if v != "" else ("[ ]" if f[4] == "text" else "[  ]"), 20, CYAN if v != "" else Color(0.4, 0.6, 0.7), al)


func _fpln() -> void:
	var wps := route()
	for i in 6:
		var y := 50.0 + i * 44.0
		txt(Vector2(16, y), "FROM" if i == 0 else "", 12, WHITE)
		if i < wps.size():
			txt(Vector2(16, y + 20), str(wps[i]), 20, MAGENTA if i == 0 else GREEN)
		elif i == wps.size():
			txt(Vector2(16, y + 20), "[    ]", 20, Color(0.4, 0.6, 0.7))
	if Props.get_b("avionics/gps/valid") and wps.size() > 0:
		txt(Vector2(400, 50), "DIST", 12, WHITE, 1)
		txt(Vector2(400, 70), "%d NM" % roundi(Props.get_f("avionics/gps/dist_nm")), 20, GREEN, 1)
		txt(Vector2(400, 94), "ETE", 12, WHITE, 1)
		txt(Vector2(400, 114), str(Props.get_v("avionics/gps/ete", "--")), 20, GREEN, 1)


func _keys() -> void:
	for i in PAGE_IDS.size():
		var r := Rect2(12 + i * 100, 344, 92, 30)
		button(r, "p_" + PAGE_IDS[i], PAGE_IDS[i].replace("FPLN", "F-PLN"), page() == PAGE_IDS[i], GREEN, 14)
	for i in 11:
		var c := "789456123.0"[i]
		var r := Rect2(12 + (i % 3) * 52, 386 + (i / 3) * 40, 46, 34)
		button(r, "k_" + c, c, false, GREEN, 18)
	button(Rect2(12 + 2 * 52, 386 + 3 * 40, 46, 34), "k_/", "/", false, GREEN, 18)
	button(Rect2(12, 386 + 4 * 40, 98, 30), "k_CLR", "CLR", false, GREEN, 14)
	button(Rect2(116, 386 + 4 * 40, 46, 30), "k_-", "+/-", false, GREEN, 12)
	for i in 26:
		var r := Rect2(176 + (i % 6) * 40, 386 + (i / 6) * 40, 36, 34)
		button(r, "k_" + LETTERS[i], LETTERS[i], false, GREEN, 16)
