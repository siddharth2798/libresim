extends Node
## The radio screen (ui/atc_panel.gd, atc_box.gd, atc_card.gd): message-card lifetime logic, the card
## text, where the bar sits, the box in its three looks, the keys of the open radio (and that the
## arrow keys then do not pitch the aircraft), lessons, and the assist option.

const VIEWPORTS := [Vector2(1280, 720), Vector2(1920, 1080)]


func _entry(kind: String, who: String, text: String) -> Dictionary:
	return {"kind": kind, "who": who, "text": text}


func test_atc_card_logic_joins_the_exchange_and_fades() -> String:
	var k := AtcCardLogic.new()
	if not k.feed(_entry("pilot", "You", "Pune Ground, VT-FSM, request taxi")):
		return "the pilot's call starts the card"
	k.tick(1.0)
	if k.feed(_entry("atc", "Pune Ground", "VT-FSM, taxi to holding point runway 27.")):
		return "the reply joins the card, it does not start another"
	k.tick(1.3)
	if k.feed(_entry("pilot", "You", "Taxi to holding point runway 27, VT-FSM")) or k.lines.size() != 3:
		return "the read-back joins too: %d lines" % k.lines.size()
	if k.bar_line() != "Pune Ground: VT-FSM, taxi to holding point runway 27.":
		return "the bar shows the controller's words, not yours: '%s'" % k.bar_line()
	if k.left < AtcCardLogic.MIN_LIFE or k.left > AtcCardLogic.MAX_LIFE:
		return "a card stays 6-8 s after its last line: %.1f" % k.left
	k.tick(AtcCardLogic.MAX_LIFE + 0.1)
	if k.alive() or not k.lines.is_empty():
		return "the card is gone after its time"
	if k.bar_line() == "" or k.bar_left > AtcCardLogic.BAR_LIFE - 8.0:
		return "the bar keeps the message longer than the card: %.1f s left" % k.bar_left
	k.tick(AtcCardLogic.BAR_LIFE)
	if k.bar_line() != "":
		return "the bar message ends after %d s" % int(AtcCardLogic.BAR_LIFE)
	if not k.feed(_entry("atc", "Pune Tower", "VT-FSM, wind calm, cleared for takeoff.")):
		return "a message after the fade is a new card"
	return ""


func test_atc_card_logic_life_and_header() -> String:
	var short := AtcCardLogic.life_for([_entry("atc", "x", "Roger.")])
	var long := AtcCardLogic.life_for([_entry("atc", "x", "x".repeat(300))])
	if short != AtcCardLogic.MIN_LIFE or long != AtcCardLogic.MAX_LIFE:
		return "life: short %.1f long %.1f" % [short, long]
	var k := AtcCardLogic.new()
	for i in 6:
		k.feed(_entry("atc", "Tower", "line %d" % i))
	if k.lines.size() != AtcCardLogic.MAX_LINES or k.lines[-1].text != "line 5":
		return "a card keeps its last %d lines: %d" % [AtcCardLogic.MAX_LINES, k.lines.size()]
	if AtcCardLogic.head_of([_entry("system", "(radio)", "No reply."), _entry("atc", "Pune Tower", "Hello")]).text != "Pune Tower":
		return "the controller heads a card that also holds a radio note"
	if AtcCardLogic.head_of([_entry("system", "(radio)", "No reply.")]).text != "Radio" or AtcCardLogic.head_of([_entry("advisory", "ATC note", "Note")]).text != "ATC note":
		return "headers of radio notes and advisories"
	if AtcCardLogic.head_of([_entry("pilot", "You", "x")]).text != "":
		return "a card with only your call has no header"
	return ""


func test_atc_card_text_mutes_your_own_lines() -> String:
	var lines := [_entry("pilot", "You", "Pune Ground, VT-FSM [taxi]"), _entry("atc", "Pune Ground", "Taxi to holding point."),
		_entry("system", "(radio)", "COM1 tuned to 121.900 Pune Ground.")]
	var m := AtcCard.markup(lines, "Pune Ground")
	if not m.contains("[font_size=14]") or not m.contains("You: Pune Ground, VT-FSM [lb]taxi]") or m.contains("[b]Pune Ground:[/b]"):
		return "markup: " + m
	var card := AtcCard.new()
	add_child(card)
	card.show_lines(lines)
	var shown: String = card.find_children("*", "RichTextLabel", true, false)[0].get_parsed_text()
	card.free()
	return "" if shown.contains("Taxi to holding point.") and shown.contains("You: Pune Ground") else "card text: " + shown


func test_atc_bar_sits_clear_of_the_other_ui() -> String:
	for vp in VIEWPORTS:
		var w := AtcLayout.bar_width(vp)
		var home := AtcLayout.home(vp)
		if w < 300.0 or w > 440.0 or home != Vector2(8, 10):
			return "%s: width %.0f home %s" % [vp, w, home]
		for size in [Vector2(w, 92), Vector2(w, 270), Vector2(w, 300)]:  # bar, open list, history
			for r in AtcLayout.reserved(vp):
				if Rect2(home, size).intersects(r):
					return "%s: %s at the top-left overlaps %s" % [vp, size, r]
	if AtcLayout.home(Vector2(1000, 700)).y != AtcLayout.TOP:
		return "a window too narrow to sit beside the flight-data bar goes below it"
	return ""


func _model(open := false, history := false, acts := ["Ask Ground for taxi", "Listen to ATIS"]) -> Dictionary:
	return {"width": 350.0, "open": open, "history": history, "freq": "121.900", "unit": "Pune Ground", "tone": "ok",
		"hint": "Next: ask Ground for taxi", "msg": "Pune Ground: VT-FSM, taxi to holding point.", "actions": acts, "sel": 0,
		"note": "Assist will tune COM1 to 121.900 (Pune Ground)", "log": [_entry("atc", "Pune Ground", "Cleared."), _entry("pilot", "You", "Request.")],
		"can_again": true, "voice": "Voice off", "keys": "keys"}


func test_atc_box_looks() -> String:
	var b := AtcBox.new()
	add_child(b)
	b.show_model(_model())
	var err := ""
	if not b.visible or b.menu.visible:
		err = "the bar is visible and the list is not"
	var rows := b.rows()
	if err == "":
		b.show_model(_model(true))
		if not b.menu.visible or not rows[0].visible or not rows[1].visible or rows[2].visible or b.history_view().visible:
			err = "open: the list shows its two calls only"
		elif rows[0].text != "1   Ask Ground for taxi":
			err = "row text '%s'" % rows[0].text
	if err == "":
		b.show_model(_model(true, true))
		if not b.history_view().visible or rows[0].is_visible_in_tree() or not b.history_view().get_parsed_text().contains("Pune Ground: Cleared."):
			err = "history replaces the list"
	if err == "":
		b.show_model(_model(true, false, []))
		if rows[0].visible:
			err = "an empty list shows no rows"
	b.free()
	return err


## A panel wired to a fake session: parked at a stand of a controlled airport without published frequencies.
func _panel() -> Array:
	var keep := {"__atc": Props.dump("atc/")}
	for k in ["fdm/position_enu", "fdm/wow", "fdm/groundspeed_mps", "fdm/heading_rad", "fdm/agl_m", "fdm/alt_m", "fdm/vs_mps", "controls/com1/freq_mhz"]:
		keep[k] = Props.get_v(k)
	Props.set_v("fdm/position_enu", Vector3(-500.0, 3.0, 5.0))
	Props.set_v("fdm/wow", true)
	Props.set_v("fdm/groundspeed_mps", 0.0)
	Props.set_v("fdm/heading_rad", 0.0)
	var airports := [{"icao": "TEST", "ident": "TEST", "name": "Test Aerodrome", "type": "medium_airport", "x": 0.0, "y": 0.0}]
	var rw := [{"airport": "TEST", "width": 45.0, "length": 2000.0, "ends": [{"ident": "09", "x": -1000.0, "y": 0.0, "heading_true": 90.0},
		{"ident": "27", "x": 1000.0, "y": 0.0, "heading_true": 270.0}]}]
	var p: Control = load("res://ui/atc_panel.gd").new()
	p.session = AtcSession.new()
	p.session.setup(AtcWorld.make_env(airports, {}, rw, {}), {})
	add_child(p)
	p._process(0.3)
	return [p, keep]


func _done(p: Control, keep: Dictionary) -> void:
	p.free()
	Props.set_v("ui/radio_open", false)
	Props.restore(keep.__atc)
	Props.set_v("atc/stamp", "")
	for k in keep:
		if k != "__atc" and keep[k] != null:
			Props.set_v(k, keep[k])


func _key(k: Key, shift := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.shift_pressed = shift
	e.pressed = true
	return e


func test_atc_panel_keys() -> String:
	var keep_assist: Variant = UserOptions.get_v("radio_assist")
	UserOptions.set_v("radio_assist", true)
	var pk := _panel()
	var p: Control = pk[0]
	var err := ""
	p._unhandled_key_input(_key(KEY_QUOTELEFT))
	if not p._open or not Props.get_b("ui/radio_open") or not p.menu.visible:
		err = "` opens the radio and tells the keyboard controls"
	elif p._actions.size() < 2 or p._sel != 0:
		err = "the open list: %s" % [p._actions.map(func(a): return a.label)]
	if err == "":
		p._input(_key(KEY_DOWN))
		var first: String = p._actions[0].id
		if p._sel != 1:
			err = "Down moves the highlight: %d" % p._sel
		else:
			p._input(_key(KEY_UP))
			p._input(_key(KEY_UP))
			if p._sel != p._actions.size() - 1:
				err = "Up wraps round: %d" % p._sel
		if err == "":
			p._input(_key(KEY_ENTER))
			if p._open or Props.get_b("ui/radio_open") or p.session.c.pending() == 0 or p.session.c.pending() > 4:
				err = "Enter makes the highlighted call and closes the list (first was %s): pending %d" % [first, p.session.c.pending()]
	if err == "":
		p._unhandled_key_input(_key(KEY_QUOTELEFT))
		p._input(_key(KEY_ESCAPE))
		if p._open:
			err = "Esc closes"
		p._unhandled_key_input(_key(KEY_QUOTELEFT))
		p._input(_key(KEY_H))
		var n: int = p.session.c.pending()
		p._input(_key(KEY_1))
		if not p._history or p.session.c.pending() != n or not p._open:
			err = "H shows the history; the numbers do nothing there"
		p._input(_key(KEY_H))
		p._input(_key(KEY_V, true))  # Shift+V is the avionics switch: not the radio's
		if p._history or not p._open:
			err = "H goes back to the calls and Shift+V is left alone"
		p._input(_key(KEY_QUOTELEFT))
		if p._open:
			err = "` closes it again"
	if err == "":
		p._unhandled_key_input(_key(KEY_QUOTELEFT))
		p._input(_key(KEY_1))
		if p._open or p.session.c.pending() == 0:
			err = "1 calls the first entry directly"
	_done(p, pk[1])
	UserOptions.set_v("radio_assist", keep_assist)
	return err


func test_atc_panel_stays_out_of_lessons_until_opened() -> String:
	var keep: String = Session.training
	var pk := _panel()
	var p: Control = pk[0]
	var err := ""
	p._refresh()
	if not p._box.visible:
		err = "free flight: the bar is always there"
	Session.training = "landing"
	p._refresh()
	if err == "" and p._box.visible:
		err = "a lesson hides the radio bar"
	p._unhandled_key_input(_key(KEY_QUOTELEFT))
	if err == "" and not p._box.visible:
		err = "` still opens the radio in a lesson"
	Session.training = keep
	_done(p, pk[1])
	return err


func test_atc_open_radio_keeps_the_arrow_keys_off_the_pitch() -> String:
	var k := KeyboardControls.new()
	k.keys = KeyBindings.defaults()
	k._shifted = KeyBindings.shifted_keys(k.keys)
	var down := InputEventKey.new()
	down.keycode = KEY_DOWN
	down.physical_keycode = KEY_DOWN
	down.pressed = true
	Input.parse_input_event(down)
	Input.flush_buffered_events()
	Props.set_v("ui/radio_open", false)
	k._process(0.1)
	var free_pitch := k.pitch
	k.pitch = 0.0
	Props.set_v("ui/radio_open", true)
	k._process(0.1)
	var open_pitch := k.pitch
	Props.set_v("ui/radio_open", false)
	var up: InputEventKey = down.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	k.free()
	if absf(free_pitch) < 0.05:
		return "the test needs the arrow key to pitch when the radio is closed (%.2f)" % free_pitch
	return "" if absf(open_pitch) < 0.001 else "arrow keys pitched the aircraft with the radio open: %.2f" % open_pitch


func test_atc_assist_option_is_on_by_default_and_on_the_options_page() -> String:
	if UserOptions.DEFAULTS.get("radio_assist", null) != true:
		return "radio assist defaults to on"
	var box := AtcOptionsBox.new()
	add_child(box)
	var checks := box.find_children("*", "CheckBox", true, false).map(func(c): return c.text)
	box.free()
	return "" if checks.any(func(t): return str(t).begins_with("Radio assist")) else "the Options page has no assist checkbox: %s" % [checks]
