extends "res://tests/fcu_panel_base.gd"
## Every click on the 2D FCU card writes exactly what its cockpit twin writes: the same start state, once through the card's
## injected mouse events and once through CockpitPick on the A320's aircraft.json cockpit.levers item (the 3D glareshield), and the
## properties must come out equal: pushbuttons, a wheel notch, click (push), Shift+click (pull), a drag, at the ends of the
## range and with the ALT 100 / 1000 selector both ways. Right and middle click do nothing; EXPED (not modelled) writes nothing.


func test_pushbuttons_write_what_the_cockpit_buttons_write() -> String:
	_begin()
	_new_card()
	for b in BUTTON_ITEMS:
		for start in [false, true]:
			_base()
			Props.set_v(_drive(b), start)
			_click("btn_" + b)
			var card := _snap()
			_base()
			Props.set_v(_drive(b), start)
			CockpitPick.commit(_item(BUTTON_ITEMS[b]))
			var diff := _same(card, _snap())
			if diff != "":
				return "%s from %s: %s" % [b, start, diff]
			if Props.get_b(_drive(b)) == start:
				return "%s did not toggle" % b
	return ""


func test_the_wheel_turns_each_knob_like_a_cockpit_detent() -> String:
	_begin()
	_new_card()
	for key in ["spd", "hdg", "alt", "vs"]:
		var item := _item(key + "_sel")
		for alt_step in [false, true]:
			for start in [[250.0, 90.0, 10000.0, 0.0], [399.0, 359.0, 39000.0, 6000.0], [100.0, 0.0, 100.0, -6000.0]]:
				for up in [true, false]:
					_base(alt_step, start[0], start[1], start[2], start[3])
					_wheel("knob_" + key, up)
					var card := _snap()
					_base(alt_step, start[0], start[1], start[2], start[3])
					var px := float(item.get("step_px", 6.0))
					CockpitPick.apply_motion(_item(key + "_sel"), [], Vector2(0, -px if up else px))
					CockpitPick.release(_item(key + "_sel"), false)
					var diff := _same(card, _snap())
					if diff != "":
						return "%s wheel %s alt1000 %s from %s: %s" % [key, "up" if up else "down", alt_step, start, diff]
	_base(false, 250.0, 359.0)
	_wheel("knob_hdg", true)
	if Props.get_f("controls/fcu/hdg_deg") != 0.0:
		return "the heading wraps at 360"
	_base(true, 250.0, 90.0, 10000.0)
	_wheel("knob_alt", true)
	return "" if Props.get_f("controls/fcu/alt_ft") == 11000.0 else "ALT turns in 1000 ft steps with the 1000 selector"


func test_click_pushes_and_shift_click_pulls_like_the_cockpit_knobs() -> String:
	_begin()
	_new_card()
	for key in ["spd", "hdg", "alt", "vs"]:
		for shift in [false, true]:
			for start_managed in [false, true]:
				_base(false, 250.0, 90.0, 10000.0, -700.0)
				Props.set_v("controls/fcu/%s_managed" % ("vs" if key == "alt" else key), start_managed)
				_click("knob_" + key, shift)
				var card := _snap()
				_base(false, 250.0, 90.0, 10000.0, -700.0)
				Props.set_v("controls/fcu/%s_managed" % ("vs" if key == "alt" else key), start_managed)
				CockpitPick.release(_item(key + "_sel"), shift)
				var diff := _same(card, _snap())
				if diff != "":
					return "%s %s: %s" % [key, "pull" if shift else "push", diff]
	_base()
	_click("knob_spd")
	if not Props.get_b("controls/fcu/spd_managed"):
		return "a click on SPD pushes: managed"
	_click("knob_spd", true)
	if Props.get_b("controls/fcu/spd_managed"):
		return "Shift+click on SPD pulls: selected"
	_click("knob_vs", true)
	if str(Props.get_v("controls/fcu/vert_select")) != "VS":
		return "Shift+click on V/S asks to fly it"
	_click("knob_vs")
	return "" if Props.get_f("controls/fcu/vs_fpm") == 0.0 and str(Props.get_v("controls/fcu/vert_select")) == "LEVEL" else "a click on V/S levels off"


func test_a_drag_turns_like_the_cockpit_drag_and_is_no_click() -> String:
	_begin()
	_new_card()
	for key in ["spd", "hdg", "alt", "vs"]:
		for dy in [-48.0, 48.0, -3.0]:
			_base(false, 250.0, 90.0, 10000.0, 0.0)
			_drag("knob_" + key, dy)
			var card := _snap()
			_base(false, 250.0, 90.0, 10000.0, 0.0)
			CockpitPick.apply_motion(_item(key + "_sel"), [], Vector2(0, dy * FCU.DRAG_SCALE))
			CockpitPick.release(_item(key + "_sel"), false)
			if _same(card, _snap()) != "":
				return "%s drag %s: %s" % [key, dy, _same(card, _snap())]
	_base()
	_drag("knob_hdg", -48.0)
	if Props.get_f("controls/fcu/hdg_deg") <= 90.0 or Props.get_b("controls/fcu/hdg_managed"):
		return "dragging up turns the heading up and does not push"
	_base()
	_mouse(_centre("knob_hdg"), MOUSE_BUTTON_LEFT, true)
	_mouse(_centre("knob_hdg") + Vector2(1, 1), MOUSE_BUTTON_LEFT, false)
	return "" if Props.get_b("controls/fcu/hdg_managed") else "a press with a little jitter is still a click"


func test_the_other_mouse_buttons_do_nothing() -> String:
	_begin()
	_new_card()
	_base()
	var before := _snap()
	for b in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		for id in ["knob_spd", "btn_ap1"]:
			_mouse(_centre(id), b, true)
			_mouse(_centre(id), b, false)
	return "" if _same(before, _snap()) == "" else "right / middle click changed %s" % _same(before, _snap())


func test_exped_is_disabled_and_writes_nothing() -> String:
	_begin()
	_new_card()
	var before := Props.dump("")
	_click("btn_exped")
	_click("btn_exped", true)
	_wheel("btn_exped", true)
	if str(Props.dump("")) != str(before):
		return "EXPED changed the property tree"
	if FcuActions.press("exped") or FcuActions.press("nope"):
		return "EXPED / an unknown button must report no press"
	var tip := FcuTips.text("btn_exped", KeyBindings.defaults())
	return "" if tip.contains("Not modelled") and tip.contains("Disabled") else "EXPED note: %s" % tip
