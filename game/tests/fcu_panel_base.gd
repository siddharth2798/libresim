extends Node
## Shared by tests/test_fcu_panel.gd and test_fcu_panel_twin.gd (the clickable 2D FCU card, ui/displays/fcu.gd): a card in the
## tree drawn at its design size, injected mouse events at the middle of a zone, the A320 cockpit.levers items (the card's
## 3D twins) and a snapshot of the FCU properties. Not a suite itself (it has no tests).

const CFG := "user://test_fcu_panel_ui.cfg"
const BUTTON_ITEMS := {"loc": "loc", "ap1": "ap1", "ap2": "ap2", "athr": "athr", "appr": "appr", "spd_mach": "spd_mach",
	"trk_fpa": "trk_fpa", "metric_alt": "metric_alt", "alt_inc": "alt_inc", "fd": "fd_cpt", "ls": "ls_cpt"}
const WATCH := ["controls/fcu/ap1", "controls/fcu/ap2", "controls/fcu/athr", "controls/fcu/loc", "controls/fcu/appr",
	"controls/fcu/spd_mach", "controls/fcu/trk_fpa", "controls/fcu/metric_alt", "controls/fcu/alt_inc_1000", "controls/fcu/fd",
	"controls/efis/ls", "controls/fcu/spd_kt", "controls/fcu/hdg_deg", "controls/fcu/alt_ft", "controls/fcu/vs_fpm",
	"controls/fcu/spd_managed", "controls/fcu/hdg_managed", "controls/fcu/vs_managed", "controls/fcu/vert_select"]

var _saved := {}
var _aircraft := ""
var _card: FCU
var _cfg_was := ""


func _begin() -> void:
	_saved = Props.dump("")
	_aircraft = str(Session.setup.get("aircraft", ""))
	Session.setup.aircraft = "a320"
	InstrumentPanel.clear_cache()
	_cfg_was = ScreenLayout.cfg_path
	ScreenLayout.cfg_path = CFG


func teardown() -> void:
	if _saved.is_empty():
		return
	Props._p.clear()
	Props.restore(_saved)
	_saved = {}
	Session.setup.aircraft = _aircraft
	InstrumentPanel.clear_cache()
	ScreenLayout.cfg_path = _cfg_was
	if FileAccess.file_exists(CFG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	if _card != null:
		_card.free()
		_card = null


func _new_card() -> FCU:
	_card = FCU.new()
	add_child(_card)
	_card._scale = 1.0  # drawn at its design size: a point of the event is a design point
	return _card


func _centre(id: String) -> Vector2:
	for z in FcuLayout.zones():
		if z.id == id:
			return (z.rect as Rect2).get_center()
	return Vector2(-1, -1)


func _mouse(at: Vector2, button: int, down: bool, shift := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = down
	e.position = at
	e.shift_pressed = shift
	_card._gui_input(e)


func _click(id: String, shift := false) -> void:
	_mouse(_centre(id), MOUSE_BUTTON_LEFT, true, shift)
	_mouse(_centre(id), MOUSE_BUTTON_LEFT, false, shift)


func _wheel(id: String, up: bool) -> void:
	_mouse(_centre(id), MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN, true)


func _drag(id: String, dy: float) -> void:
	var at := _centre(id)
	_mouse(at, MOUSE_BUTTON_LEFT, true)
	for i in 4:  # quarter steps: every partial detent adds up exactly in floats
		var mm := InputEventMouseMotion.new()
		mm.position = at + Vector2(0, dy * (i + 1) / 4.0)
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		_card._gui_input(mm)
	_mouse(at + Vector2(0, dy), MOUSE_BUTTON_LEFT, false)


func _snap() -> Dictionary:
	var s := {}
	for p in WATCH:
		s[p] = Props.get_v(p, null)
	return s


## A known FCU state, `alt_step` is the ALT 100 / 1000 selector.
func _base(alt_step := false, spd := 250.0, hdg := 90.0, alt := 10000.0, vs := 0.0) -> void:
	for p in WATCH:
		Props.set_v(p, false)
	Props.set_v("controls/fcu/spd_kt", spd)
	Props.set_v("controls/fcu/hdg_deg", hdg)
	Props.set_v("controls/fcu/alt_ft", alt)
	Props.set_v("controls/fcu/vs_fpm", vs)
	Props.set_v("controls/fcu/vert_select", "")
	Props.set_v("controls/fcu/alt_inc_1000", alt_step)


## The cockpit twin of control `name`: a private copy of its aircraft.json item, as CockpitLevers hands it to CockpitPick.
func _item(name: String) -> Dictionary:
	return (AircraftDef.load_def("a320").section("cockpit").levers[name] as Dictionary).duplicate(true)


func _drive(button: String) -> String:
	return str(_item(BUTTON_ITEMS[button]).drive)


func _same(a: Dictionary, b: Dictionary) -> String:
	for k in a:
		if str(a[k]) != str(b[k]):
			return "%s: card %s, cockpit %s" % [k, a[k], b[k]]
	return ""
