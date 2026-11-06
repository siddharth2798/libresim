class_name MCDU
extends Display
## MCDU-lite. Pages: INIT (FROM/TO, flight number, cost index, cruise level, DEP/ARR runway),
## F-PLN, DIR, PROG, PERF. A line key copies a field into the scratchpad, or stores typed text.
## Props: mcdu/{page, scratch, init/*, perf/*}. F-PLN and DIR write controls/gps/{target, route_next}
## and select NAV. INIT FROM/TO files the route (origin in controls/fms/origin) and expands an
## airway designator between two fixes (airway.gd). DEP/ARR RWY insert synthetic fixes and re-file.
## CRZ FL copies to the FCU altitude and selects managed vertical. PROG reads distance, bearing,
## phase and top of descent. F-PLN draws avionics/fms/legs. No published SID or STAR.
## Keyboard: this control, or Cockpit.forward_key / the outside card while the pointer is over it.
## TODO: RAD NAV, FUEL PRED, SEC F-PLN, SID/STAR, VNAV predictions, multi-page lists, the second unit.

const PAGE_IDS := ["INIT", "FPLN", "DIR", "PROG", "PERF"]
const TITLES := {"INIT": "INIT A", "FPLN": "F-PLN", "DIR": "DIR TO", "PROG": "PROGRESS", "PERF": "TAKE OFF"}
const DASH := "---"
const FIELDS := {  # page -> [[side, row 1..6, label, prop, kind "text" | "num", unit]]
	"INIT": [["l", 1, "FROM/TO", "mcdu/init/from_to", "text", ""], ["l", 2, "FLT NBR", "mcdu/init/flt_no", "text", ""],
		["l", 4, "COST INDEX", "mcdu/init/cost_index", "num", ""], ["l", 5, "DEP RWY", "mcdu/init/dep_rwy", "text", ""],
		["r", 3, "CRZ FL", "mcdu/init/cruise_fl", "num", ""], ["r", 5, "ARR RWY", "mcdu/init/arr_rwy", "text", ""]],
	"PERF": [["l", 1, "V1", "mcdu/perf/v1", "num", ""], ["l", 2, "VR", "mcdu/perf/vr", "num", ""], ["l", 3, "V2", "mcdu/perf/v2", "num", ""],
		["r", 1, "FLEX TEMP", "mcdu/perf/flex_c", "num", "C"], ["r", 2, "FLAPS", "mcdu/perf/flaps", "num", ""], ["r", 3, "THS", "mcdu/perf/ths", "num", ""]],
}
const LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const DIGITS := "0123456789"
const SCREEN := Rect2(10, 10, 400, 320)
const MAX_SCRATCH := 22


func _init() -> void:
	design = Vector2(420, 600)


func _ready() -> void:
	super._ready()
	focus_mode = FOCUS_CLICK


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


## Direct-to. `known` defaults to "any non-empty ident". See FlightPlan.direct.
static func direct_to(scratch: String, current: String, next: Array = [], known: Callable = Callable()) -> Dictionary:
	var k := known if known.is_valid() else (func(id: String) -> bool: return id != "")
	return FlightPlan.direct(scratch, current, next, k)


## PROG text. Missing distance or bearing (not published) is dashes. Pure.
static func prog_text(target: String, has_dist: bool, dist_nm: float, has_brg: bool, brg_deg: float) -> Dictionary:
	return {"target": target, "dist": ("%d NM" % roundi(dist_nm)) if has_dist else DASH,
		"brg": ("%03d" % roundi(brg_deg)) if has_brg else DASH}


static func prog_readout() -> Dictionary:
	var r := prog_text(str(Props.get_v("controls/gps/target", "")), Props.has("avionics/gps/dist_nm"),
		Props.get_f("avionics/gps/dist_nm"), Props.has("avionics/gps/brg_mag"), Props.get_f("avionics/gps/brg_mag"))
	var phase := str(Props.get_v("avionics/fms/phase", ""))
	var tod := float(Props.get_v("avionics/fms/tod_nm", -1.0))
	r["phase"] = phase if phase != "" else DASH
	r["tod"] = ("%d NM" % roundi(tod)) if tod >= 0.0 else DASH
	return r


## True for one scratchpad character: letter, digit, space, slash, period, or Backspace. Not flight keys.
static func wants_key(event: InputEvent) -> bool:
	if event == null or not (event is InputEventKey):
		return false
	var e := event as InputEventKey
	if not e.pressed or e.echo or e.ctrl_pressed or e.alt_pressed or e.meta_pressed:
		return false
	return _glyph(e) != ""


## The scratchpad character for `event`, or "" when wants_key is false. "\b" deletes one.
static func typed_char(event: InputEvent) -> String:
	return _glyph(event as InputEventKey) if wants_key(event) else ""


static func _glyph(e: InputEventKey) -> String:
	var code := e.keycode
	if code == KEY_BACKSPACE:
		return "\b"
	if code >= KEY_A and code <= KEY_Z:
		return LETTERS[code - KEY_A]
	if e.shift_pressed:
		return ""
	if code >= KEY_0 and code <= KEY_9:
		return DIGITS[code - KEY_0]
	if code >= KEY_KP_0 and code <= KEY_KP_9:
		return DIGITS[code - KEY_KP_0]
	if code == KEY_SPACE:
		return " "
	if code == KEY_SLASH:
		return "/"
	if code == KEY_PERIOD or code == KEY_KP_PERIOD:
		return "."
	return ""


## Scratchpad after typing `ch` ("\b" deletes one character). Pure; capped at MAX_SCRATCH.
static func scratch_after(scratch: String, ch: String) -> String:
	if ch == "\b":
		return scratch.substr(0, maxi(scratch.length() - 1, 0))
	if ch == "":
		return scratch
	return (scratch + ch).substr(0, MAX_SCRATCH)


func _press(id: String, button: int, _p: Vector2) -> void:
	var s := str(Props.get_v("mcdu/scratch", ""))
	if id.begins_with("p_"):
		Props.set_v("mcdu/page", id.substr(2))
	elif id == "k_CLR":
		Props.set_v("mcdu/scratch", "" if button != MOUSE_BUTTON_LEFT else scratch_after(s, "\b"))
	elif id.begins_with("k_"):
		Props.set_v("mcdu/scratch", scratch_after(s, id.substr(2)))
	elif id.begins_with("l") or id.begins_with("r"):
		_line_key(id[0], int(id.substr(1)), s)


func type_key(e: InputEvent) -> bool:
	if not wants_key(e):
		return false
	_type_char(typed_char(e))
	return true


## True when `ident` is an airport, VOR or NDB. With no nav database (unit tests) any ident is accepted.
func _db() -> Object:
	if not is_inside_tree():
		return null
	var nav := get_tree().root.find_child("Nav", true, false)
	return nav.get("db") if nav != null else null


func _known(ident: String) -> bool:
	if ident == "":
		return false
	var db := _db()
	if db == null or not db.has_method("position_of"):
		return true
	return db.position_of(ident) != null


func _airways() -> Dictionary:
	var db := _db()
	if db == null:
		return {}
	var aw = db.get("airways")
	return aw if typeof(aw) == TYPE_DICTIONARY else {}


func _commit(target: String, next: Array, engage: bool) -> void:
	Props.set_v("controls/gps/target", target)
	Props.set_v("controls/gps/route_next", next)
	Props.set_v("mcdu/scratch", "")
	if engage:
		Props.set_v("controls/fcu/hdg_managed", true)


func _line_key(side: String, row: int, s: String) -> void:
	var p := page()
	var known := Callable(self, "_known")
	if p == "FPLN":
		if side == "l" and row >= 1:
			var ed := FlightPlan.edit(route(), row - 1, s, known)
			if ed.error != "":
				Props.set_v("mcdu/scratch", ed.error)
			elif s == "":
				Props.set_v("mcdu/scratch", ed.scratch)
			elif not ed.wps.is_empty():
				_commit(str(ed.wps[0]), ed.wps.slice(1), true)
		return
	if p == "DIR":
		if side == "l" and row == 1:
			var d := FlightPlan.direct(s, str(Props.get_v("controls/gps/target", "")), Array(Props.get_v("controls/gps/route_next", [])), known)
			Props.set_v("controls/gps/target", d.target)
			Props.set_v("controls/gps/route_next", d.next)
			Props.set_v("mcdu/scratch", d.scratch)
			if s != "" and d.error == "":
				Props.set_v("controls/fcu/hdg_managed", true)
		return
	if p == "PROG":
		return
	for f in FIELDS.get(p, []):
		if f[0] != side or f[1] != row:
			continue
		if s == "":
			Props.set_v("mcdu/scratch", _shown(f))
		elif f[4] == "num" and not s.is_valid_float():
			Props.set_v("mcdu/scratch", "FORMAT ERROR")
		else:
			Props.set_v(f[3], float(s) if f[4] == "num" else s)
			Props.set_v("mcdu/scratch", "")
			_after_field(str(f[3]), s)


func _after_field(prop: String, s: String) -> void:
	if prop == "mcdu/init/from_to":
		_file_route(s)
	elif prop == "mcdu/init/dep_rwy" or prop == "mcdu/init/arr_rwy":
		var ft := str(Props.get_v("mcdu/init/from_to", ""))
		if ft != "":
			_file_route(ft)
	elif prop == "mcdu/init/cruise_fl":
		Props.set_v("controls/fcu/alt_ft", clampf(float(s), 1.0, 450.0) * 100.0)
		Props.set_v("controls/fcu/vs_managed", true)
		Props.set_v("controls/fcu/vert_select", "MANAGED")


func _file_route(text: String) -> void:
	var exp := Airway.expand(FlightPlan.split_from_to(text), _airways())
	if not exp.ok:
		Props.set_v("mcdu/scratch", exp.error)
		return
	var filed := FlightPlan.file(exp.parts, Callable(self, "_known"))
	if not filed.ok:
		Props.set_v("mcdu/scratch", filed.error)
		return
	filed = FlightPlan.with_procedures(filed, str(Props.get_v("mcdu/init/dep_rwy", "")), str(Props.get_v("mcdu/init/arr_rwy", "")))
	if not _route_known(filed):
		Props.set_v("mcdu/scratch", FlightPlan.NOT_IN_DB)
		return
	_commit(str(filed.target), filed.next, true)
	Props.set_v("controls/fms/origin", filed.origin)


func _route_known(filed: Dictionary) -> bool:
	if not _known(str(filed.target)):
		return false
	for id in filed.next:
		if not _known(str(id)):
			return false
	return true


static func _shown(f: Array) -> String:
	var v: Variant = Props.get_v(f[3], null)
	if v == null:
		return ""
	return str(roundi(float(v))) if f[4] == "num" else str(v)


func _gui_input(e: InputEvent) -> void:
	if wants_key(e):
		_type_char(typed_char(e))
		accept_event()
		return
	if e is InputEventMouseButton and e.pressed and is_inside_tree():
		grab_focus()
	super._gui_input(e)


func _unhandled_input(e: InputEvent) -> void:
	if not wants_key(e) or not _pointer_over():
		return
	_type_char(typed_char(e))
	get_viewport().set_input_as_handled()


func _type_char(ch: String) -> void:
	if ch == "":
		return
	Props.set_v("mcdu/scratch", scratch_after(str(Props.get_v("mcdu/scratch", "")), ch))
	queue_redraw()


func _pointer_over() -> bool:
	if not is_inside_tree():
		return false
	return get_global_rect().has_point(get_global_mouse_position())



func _paint() -> void:
	fill(SCREEN, Color.BLACK)
	frame(SCREEN.grow(2), GREY, 2.0)
	txt(Vector2(210, 26), TITLES[page()], 20, WHITE, 0)
	MCDUDraw.paint(self)
