extends Node
## The taxi / pushback instruction on screen: it appears as one card at the top of the screen, fades
## by itself, can be dismissed (Backspace), goes when the aircraft starts taxiing / the route ends /
## a newer one replaces it, and stays readable in the radio History plus a tiny bar line.
## Logic: atc/taxi_banner_logic.gd; card: ui/taxi_banner.gd (in the notification stack).


func _key(k: Key, shift := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.shift_pressed = shift
	e.pressed = true
	return e


func test_taxi_banner_life_is_8_to_12_s() -> String:
	var txt := "Taxi to the apron (stand 3) via B"
	var plain := TaxiBannerLogic.life_for(txt, false, false)
	var first := TaxiBannerLogic.life_for(txt, true, false)
	var note := TaxiBannerLogic.life_for("No taxi route found", false, true)
	var long := TaxiBannerLogic.life_for("x".repeat(400), false, false)
	if plain < 8.0 or plain > 12.0 or long != 12.0 or TaxiBannerLogic.life_for("x", false, false) != 8.0:
		return "an instruction stays 8-12 s: plain %.1f long %.1f" % [plain, long]
	if first != 12.0 or first < plain:
		return "the first one after landing stays longest: %.1f" % first
	if note != 6.0:
		return "a plain note stays 6 s: %.1f" % note
	return ""


func test_taxi_banner_expires_and_can_be_dismissed() -> String:
	var k := TaxiBannerLogic.new()
	k.show("Taxi to the apron", 9.0, false, true)
	if not k.alive() or k.tick(8.0, 0.0) != "" or not k.alive():
		return "it is still there after 8 s of a 9 s life"
	if k.tick(1.5, 0.0) != "expired" or k.alive() or k.text != "":
		return "it expires by itself"
	k.show("Taxi to the apron", 9.0, true, true)
	k.dismiss()
	if k.alive():
		return "dismiss() removes it at once"
	k.show("Taxi to runway 27", 9.0, true, true)
	k.tick(7.0, 0.0)
	k.show("Taxi to runway 09", 9.0, true, true)
	if k.text != "Taxi to runway 09" or k.left != 9.0:
		return "a newer instruction replaces the old one and restarts the time"
	return ""


func test_taxi_banner_goes_when_taxiing_starts() -> String:
	var k := TaxiBannerLogic.new()
	k.show("Taxi to runway 27", 12.0, true, true)  # stood still when it appeared
	for i in 3:  # moving, but it has not had MIN_SHOWN s yet
		if k.tick(1.0, 3.0) != "":
			return "it stays until it has been readable for %.0f s" % TaxiBannerLogic.MIN_SHOWN
	var r := ""
	for i in 4:
		r = k.tick(1.0, 3.0)
		if r != "":
			break
	if r != "moving" or k.alive():
		return "it goes when the aircraft taxis under it: '%s'" % r
	k.show("Taxi to runway 27", 12.0, true, true)
	k.tick(5.0, 0.0)
	k.tick(1.5, 3.0)
	k.tick(0.5, 0.0)  # a stop resets the count
	if k.tick(1.0, 3.0) != "" or not k.alive():
		return "a brief roll does not dismiss it"
	k.show("Taxi to the apron", 12.0, false, true)  # rolling out after landing: only the clock
	for i in 8:
		if k.tick(1.0, 10.0) != "":
			return "an instruction that appears while rolling follows the clock only"
	if k.tick(5.0, 10.0) != "expired":
		return "and then it expires"
	return ""


func test_taxi_banner_hold_short_once() -> String:
	if TaxiBannerLogic.hold_short_due(120.0, true, false) or TaxiBannerLogic.hold_short_due(30.0, false, false):
		return "hold short is only for a runway route, near its end"
	if not TaxiBannerLogic.hold_short_due(30.0, true, false) or TaxiBannerLogic.hold_short_due(30.0, true, true):
		return "hold short is said once"
	return ""


## A Notifications stack and a banner in the tree; returns [notes, banner].
func _rig() -> Array:
	var notes := Notifications.new()
	add_child(notes)
	var b := TaxiBanner.new()
	add_child(b)
	return [notes, b]


func _find(notes: Notifications, key: String) -> Dictionary:
	for c in notes._cards:
		if c.key == key:
			return c
	return {}


func test_taxi_banner_card_lives_in_the_top_stack_and_fades() -> String:
	Props.set_v("fdm/groundspeed_mps", 0.0)
	var rig := _rig()
	var notes: Notifications = rig[0]
	var b: TaxiBanner = rig[1]
	var err := ""
	b.announce("Taxi to the apron (stand 3) via B")
	var c := _find(notes, "taxi")
	if c.is_empty() or b.text != "Taxi to the apron (stand 3) via B":
		err = "the instruction is one card of the notification stack"
	elif c.panel.get_parent() != notes._stack:
		err = "the card sits in the top-centre stack, not in a centred label"
	elif c.t < 8.0 or c.t > 12.0:
		err = "life %.1f" % c.t
	if err == "":
		b.announce("Taxi to runway 27 via A — hold short")
		if notes._cards.filter(func(x): return x.key == "taxi").size() != 1:
			err = "a newer instruction replaces the card instead of stacking another"
	if err == "":
		b._unhandled_key_input(_key(KEY_BACKSPACE))
		if b.text != "" or _find(notes, "taxi").t > 0.5:
			err = "Backspace dismisses it (it fades out at once)"
	if err == "":
		b.announce("Taxi to the apron")
		b.route_cleared()
		if b.text != "" or _find(notes, "taxi").t > 0.5:
			err = "the route ending (arrived / cleared with T) removes the banner"
	if err == "":
		b.say("No taxi route found")
		b.route_cleared()
		if b.text == "":
			err = "a note is not a route banner: clearing a route leaves it to fade"
	notes.free()
	b.free()
	return err


func test_taxi_banner_leaves_a_bar_line_and_a_history_line() -> String:
	Props.set_v("fdm/groundspeed_mps", 0.0)
	var rig := _rig()
	var b: TaxiBanner = rig[1]
	b.announce("Taxi to the apron (stand 3) via B")
	var msg: Dictionary = Props.get_v("ops/taxi_msg", {})
	var err := ""
	if str(msg.get("text", "")) != "Taxi to the apron (stand 3) via B":
		err = "the instruction is handed to the radio history: %s" % [msg]
	b.route_progress("Taxi to the apron (stand 3) via B", 240.4, false)
	var hint := str(Props.get_v("ops/taxi_hint", ""))
	if err == "" and (not hint.contains("stand 3") or not hint.contains("240 m")):
		err = "the bar keeps a tiny reminder with the distance: '%s'" % hint
	if err == "":
		var n := int(msg.n)
		b.route_progress("Taxi to runway 27", 30.0, true)
		if int(Props.get_v("ops/taxi_msg", {}).n) != n + 1 or not b.text.begins_with("Hold short"):
			err = "'Hold short' is a new instruction, logged once"
		b.route_progress("Taxi to runway 27", 20.0, true)
		if int(Props.get_v("ops/taxi_msg", {}).n) != n + 1:
			err = "'Hold short' is not repeated every frame"
	if err == "":
		b.route_cleared()
		if str(Props.get_v("ops/taxi_hint", "")) != "":
			err = "the bar line goes with the route"
	if err == "":
		b.say("Pushback in progress — P to stop", "Pushback in progress  ·  P to stop")
		if not str(Props.get_v("ops/taxi_hint", "")).begins_with("Pushback"):
			err = "pushback keeps a bar line while it runs"
		b.say("Pushback complete")
		if str(Props.get_v("ops/taxi_hint", "")) != "":
			err = "and loses it when it ends"
	rig[0].free()
	b.free()
	return err


func test_taxi_banner_radio_history_gets_the_instruction() -> String:
	var keep := {"__atc": Props.dump("atc/")}
	for k in ["fdm/position_enu", "fdm/wow", "fdm/groundspeed_mps", "fdm/heading_rad", "fdm/agl_m", "fdm/alt_m", "fdm/vs_mps"]:
		keep[k] = Props.get_v(k)
	Props.set_v("fdm/position_enu", Vector3(-500.0, 3.0, 5.0))
	Props.set_v("fdm/wow", true)
	Props.set_v("fdm/groundspeed_mps", 0.0)
	var airports := [{"icao": "TEST", "ident": "TEST", "name": "Test Aerodrome", "type": "medium_airport", "x": 0.0, "y": 0.0}]
	var p: Control = load("res://ui/atc_panel.gd").new()
	p.session = AtcSession.new()
	p.session.setup(AtcWorld.make_env(airports, {}, [], {}), {})
	add_child(p)
	Props.set_v("ops/taxi_msg", {})
	p._process(0.3)
	var before: int = p.session.c.log.size()
	Props.set_v("ops/taxi_msg", {"n": 1, "text": "Taxi to the apron (stand 3) via B"})
	p._process(0.3)
	p._process(0.3)
	var log: Array = p.session.c.log
	var ok: bool = log.size() == before + 1 and log[-1].kind == "system" and str(log[-1].text).contains("stand 3")
	var shown := str(p._model(p.session.c, p.session.w).taxi)
	Props.set_v("ops/taxi_hint", "Taxi to the apron  ·  240 m")
	var hint := str(p._model(p.session.c, p.session.w).taxi)
	p.free()
	Props.set_v("ops/taxi_msg", {})
	Props.set_v("ops/taxi_hint", "")
	Props.restore(keep.__atc)
	Props.set_v("atc/stamp", "")
	for k in keep:
		if k != "__atc" and keep[k] != null:
			Props.set_v(k, keep[k])
	if not ok:
		return "the instruction is written to the History once: %d -> %d lines" % [before, log.size()]
	if shown != "" or hint != "Taxi to the apron  ·  240 m":
		return "the bar model carries the reminder: '%s' / '%s'" % [shown, hint]
	return ""
