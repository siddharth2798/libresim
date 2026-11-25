class_name FCU
extends Display
## Flight control unit (glareshield autopilot panel) as a 2D card, shown in the outside views (ui/panel_overlay.gd forwards the
## mouse into the panel viewport): SPD / HDG / ALT / V/S windows with knobs, the LOC AP1 AP2 A/THR APPR pushbuttons (EXPED dim and
## disabled: not modelled), the SPD/MACH, HDG-V/S / TRK-FPA, METRIC ALT and ALT 100/1000 selectors and the captain's FD and LS.
## Where everything is: FcuLayout. What a click does: FcuActions, which runs the code of the cockpit controls (no logic here).
## One mouse scheme for all four knobs, the same as the 3D cockpit knobs:
##   mouse wheel over the knob = one detent (up = more);  drag up / down = turn;  click = push (managed / level off);
##   Shift+click = pull (selected / fly V/S).  Pushbuttons act on the press.
## The windows show what the glareshield FCU shows (FcuWindows: dashes and dots for managed, V/S dashes outside V/S mode unless
## just preset, the 10 s / 45 s previews). Lamps follow what the autopilot did, ap/{ap1, ap2, athr, loc, appr} (the control
## flag while the autoflight does not publish them), never the press itself: a refused press springs back.

const DRAG_SCALE := 0.5  # cockpit step_px and CLICK_PX count pointer px; the card is drawn smaller, so a design px counts half
const LAMP_BTNS := ["loc", "ap1", "ap2", "athr", "appr"]
const DIM := Color(0.42, 0.43, 0.46)

var _grab := {}  # the knob under the pointer: {key, item, last (design y), moved, shift}


func _init() -> void:
	design = FcuLayout.DESIGN


func _gui_input(e: InputEvent) -> void:
	if not (e is InputEventMouse) or _scale <= 0.0:
		return
	var p: Vector2 = e.position / _scale
	if e is InputEventMouseMotion:
		if not _grab.is_empty() and (e as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT == 0:
			_grab = {}  # the button came up where we could not see it
		elif not _grab.is_empty():
			_drag(p)
			accept_event()
		return
	var id := FcuLayout.zone_at(p)
	var b := e as InputEventMouseButton
	if b.button_index == MOUSE_BUTTON_LEFT and not b.pressed:
		if not _grab.is_empty():
			_release(b.shift_pressed)
			accept_event()
		return
	if not b.pressed or id == "":
		return
	match b.button_index:
		MOUSE_BUTTON_LEFT:
			_left_down(id, p, b.shift_pressed)
		MOUSE_BUTTON_WHEEL_UP:
			_wheel(id, 1.0)
		MOUSE_BUTTON_WHEEL_DOWN:
			_wheel(id, -1.0)
		_:
			return
	accept_event()
	queue_redraw()


## A left press: a pushbutton acts now, a knob starts a grab (a click on release, a turn when dragged).
func _left_down(id: String, p: Vector2, shift: bool) -> void:
	if id.begins_with("btn_"):
		FcuActions.press(id.substr(4))
		return
	var key := id.substr(5)
	_grab = {"key": key, "item": FcuActions.knob_item(key), "last": p.y, "moved": 0.0, "net": 0.0, "shift": shift}


func _drag(p: Vector2) -> void:
	var dy: float = p.y - float(_grab.last)
	var was_drag := float(_grab.moved) * DRAG_SCALE >= CockpitPick.CLICK_PX
	_grab.last = p.y
	_grab.moved += absf(dy)
	_grab.net += dy
	if float(_grab.moved) * DRAG_SCALE >= CockpitPick.CLICK_PX and not (_grab.item as Dictionary).is_empty():
		CockpitKnob.turn(_grab.item, (dy if was_drag else float(_grab.net)) * DRAG_SCALE)  # the jitter before the drag counts too
		queue_redraw()


func _release(shift: bool) -> void:
	if float(_grab.moved) * DRAG_SCALE < CockpitPick.CLICK_PX:
		FcuActions.click(str(_grab.key), shift or bool(_grab.shift))
	_grab = {}
	queue_redraw()


## Display's own click entry (tests/test_displays.gd calls it): a plain left click, no Shift: a button presses, a knob pushes.
func _press(id: String, button: int, _p: Vector2) -> void:
	if button != MOUSE_BUTTON_LEFT:
		return
	if id.begins_with("btn_"):
		FcuActions.press(id.substr(4))
	elif id.begins_with("knob_"):
		FcuActions.click(id.substr(5), false)


func _wheel(id: String, dir: float) -> void:
	if id.begins_with("knob_"):
		FcuActions.turn(id.substr(5), int(dir))


func _lit(k: String) -> bool:
	return Props.get_b("ap/" + k, Props.get_b("controls/fcu/" + k))


func _paint() -> void:
	fill(Rect2(Vector2.ZERO, design), Color(0.1, 0.11, 0.13))
	frame(Rect2(2, 2, design.x - 4, design.y - 4), Color(0.3, 0.32, 0.36), 2.0)
	var shown := [FcuWindows.spd(), FcuWindows.hdg(), FcuWindows.alt(), FcuWindows.vs()]  # the glareshield's own rules
	for i in 4:
		var key: String = FcuLayout.KNOBS[i]
		var win := FcuLayout.window_rect(key)
		var w: Dictionary = shown[i]
		txt(Vector2(win.get_center().x, 16), str(w.label), 18, WHITE, 0)
		var dashed := str(w.text).begins_with("--")
		window(win, str(w.text) if FcuWindows.powered() else "", AMBER if not dashed else Color(0.5, 0.35, 0.05), 40)
		if key != "vs":
			dot(Vector2(win.end.x - 12, win.position.y + 10), 5.0, AMBER if bool(w.dot) else Color(0.25, 0.2, 0.05))
	for z in FcuLayout.zones():
		hot(z.hit, z.id)
		if z.kind != "knob":
			_paint_button(str(z.id).substr(4), z.rect)


func _paint_button(b: String, r: Rect2) -> void:
	var lit := false
	var title := b.to_upper()
	var sub := ""
	match b:
		"athr": title = "A/THR"
		"exped": title = "EXPED"
		"spd_mach":
			title = "SPD/MACH"
			sub = FcuWindows.spd().label
		"trk_fpa":
			title = "HDG V/S / TRK FPA"
			sub = FcuWindows.mode_label()
		"metric_alt":
			title = "METRIC ALT"
			sub = "ON" if Props.get_b("controls/fcu/metric_alt") else "OFF"
			lit = Props.get_b("controls/fcu/metric_alt")
		"alt_inc":
			title = "ALT STEP"
			sub = "1000" if Props.get_b("controls/fcu/alt_inc_1000") else "100"
		"fd":
			lit = Props.get_b("controls/fcu/fd")
		"ls":
			lit = Props.get_b("controls/efis/ls")
	if b in LAMP_BTNS:
		lit = _lit(b)  # every FCU pushbutton light is green
	var off := b == "exped"
	fill(r, Color(0.14, 0.15, 0.17) if off else (Color(0.22, 0.28, 0.24) if lit else Color(0.2, 0.21, 0.24)))
	frame(r, Color(0.3, 0.31, 0.34) if off else GREY, 1.5)
	if lit:
		fill(Rect2(r.position + Vector2(6, 5), Vector2(r.size.x - 12, 6)), GREEN)
	var fs := 22 if b in LAMP_BTNS or off or b in ["fd", "ls"] else 16
	txt(r.get_center() + Vector2(0, -9 if sub != "" else 5), title, fs, DIM if off else WHITE, 0)
	if sub != "":
		txt(r.get_center() + Vector2(0, 15), sub, 18, CYAN, 0)
