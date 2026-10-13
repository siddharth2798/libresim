extends "res://tests/atc_fixture.gd"
## Radio assist (game/atc/atc_assist.gd): the suggested next call and its "Next: ..." text along a
## whole departure and arrival, the short call list, and the automatic tuning with assist on / off.
## Fake world: atc_fixture.gd.


## Make the suggested call, as the pilot would; hooks that tune are applied to the fake world.
func _follow(c: AtcController, mon: AtcMonitor, w: Dictionary, t: float) -> float:
	var r := c.recommended(w)
	if r.is_empty():
		return -1.0
	var before := _calls.size()
	c.request(str(r.id), w, t)
	for call in _calls.slice(before):
		if str(call).begins_with("tune "):
			w.com1_mhz = float(str(call).substr(5))
	return _pump(c, mon, w, t, 3.0)


func test_atc_assist_suggests_the_whole_departure() -> String:
	var c := _ctl()
	c.assist = true
	var mon := AtcMonitor.new(c)
	var w := _world(118.1, {"at_stand": true, "where": "stand 12"})
	var t := _pump(c, mon, w, 0.0, 1.0)
	if c.recommended(w).get("id", "") != "atis" or c.next_hint(w) != "Next: listen to ATIS":
		return "parked: %s / '%s'" % [c.recommended(w), c.next_hint(w)]
	t = _follow(c, mon, w, t)
	if not _calls.has("tune 126.400") or not _text(c).contains("COM1 tuned to 126.400 Test ATIS."):
		return "the ATIS call tunes COM1 first: %s\n%s" % [_calls, _text(c)]
	if c.next_hint(w) != "Next: ask Delivery for clearance":
		return "after ATIS: '%s'" % c.next_hint(w)
	t = _follow(c, mon, w, t)
	if c.s.state != "clearance" or not _calls.has("tune 121.850") or c.next_hint(w) != "Next: ask Ground for taxi":
		return "after the clearance: %s %s '%s'\n%s" % [c.s.state, _calls, c.next_hint(w), _text(c)]
	t = _follow(c, mon, w, t)
	if c.s.state != "taxi" or not _calls.has("tune 121.900"):
		return "after the taxi call: %s %s" % [c.s.state, _calls]
	w.merge({"pos": Vector2(60, 0), "gs": 4.0, "at_stand": false}, true)
	t = _pump(c, mon, w, t, 1.0)
	if not c.recommended(w).is_empty() or c.next_hint(w) != "Next: taxi to runway 27, report ready":
		return "taxiing far from the runway: nothing to call, '%s'" % c.next_hint(w)
	w.merge({"pos": Vector2(200, 0), "gs": 0.5, "rwy_dist": 60.0, "hold_dist": 15.0}, true)
	t = _pump(c, mon, w, t, 1.5)
	if c.s.state != "hold_short" or c.recommended(w).get("label", "") != "Report ready for departure":
		return "holding point: %s %s" % [c.s.state, c.recommended(w)]
	t = _follow(c, mon, w, t)
	if not _calls.has("tune 118.100") or not c.s.lineup_ok:
		return "ready for departure on the tower: %s lineup_ok %s" % [_calls, c.s.lineup_ok]
	w.merge({"pos": Vector2(250, 10), "on_runway": true, "aligned": true, "rwy_dist": 0.0, "gs": 0.0}, true)
	t = _pump(c, mon, w, t, 1.0)
	if c.s.state != "lined_up" or c.recommended(w).get("label", "") != "Ask Tower for takeoff clearance":
		return "lined up: %s %s" % [c.s.state, c.recommended(w)]
	t = _pump(c, mon, w, t, 4.0)  # "line up and wait" was given: cleared as it goes
	if not c.s.cleared_takeoff or not c.recommended(w).is_empty() or c.next_hint(w) != "Next: you are cleared for takeoff":
		return "cleared: %s '%s'" % [c.s.cleared_takeoff, c.next_hint(w)]
	return _clean(c)


func test_atc_assist_suggests_the_whole_arrival() -> String:
	var c := _ctl()
	c.assist = true
	var mon := AtcMonitor.new(c)
	var w := _air_world(127.9, {"pos": Vector2(-55000, 400), "apt_dist": 55000.0, "apt_dist_nm": 29.7})
	var t := _pump(c, mon, w, 0.0, 1.0)
	if c.s.state != "enroute" or not c.recommended(w).is_empty() or not c.next_hint(w).begins_with("Next: fly on"):
		return "far from the airport: %s '%s'" % [c.s.state, c.next_hint(w)]
	t = _glide(c, mon, w, t, Vector2(-15000, 400))  # 8 nm out
	if c.recommended(w).get("label", "") != "Ask Approach for landing":
		return "near the airport: %s" % [c.recommended(w)]
	t = _follow(c, mon, w, t)
	if c.s.state != "inbound" or _calls.has("tune 127.900"):
		return "inbound on Approach needs no tuning: %s %s" % [c.s.state, _calls]
	if not c.recommended(w).is_empty() or c.next_hint(w) != "Next: join the circuit, report final":
		return "inbound far out: '%s'" % c.next_hint(w)
	t = _glide(c, mon, w, t, Vector2(-9000, 400))  # 4.9 nm: the controller asks for the report
	t = _pump(c, mon, w, t, 2.0)
	if c.recommended(w).get("label", "") != "Report final":
		return "report final is due: %s" % [c.recommended(w)]
	t = _follow(c, mon, w, t)
	if not _calls.has("tune 118.100") or not _text(c).contains("COM1 tuned to 118.100 Test Tower.") or c.s.state != "final" or not c.s.cleared_land:
		return "final on the tower: %s %s\n%s" % [c.s.state, _calls, _text(c)]
	if c.next_hint(w) != "Next: land, or report going around":
		return "on final: '%s'" % c.next_hint(w)
	c.s.state = "vacated"
	w.merge({"wow": true, "agl": 0.0, "gs": 5.0, "on_runway": false, "pos": Vector2(-100, 60)}, true)
	if c.recommended(w).get("label", "") != "Ask Ground for taxi to parking":
		return "vacated: %s" % [c.recommended(w)]
	return _clean(c)


func test_atc_assist_off_suggests_nothing_and_leaves_tuning_to_the_pilot() -> String:
	var c := _ctl()
	var mon := AtcMonitor.new(c)
	var w := _world(118.1, {"at_stand": true})
	var t := _pump(c, mon, w, 0.0, 1.0)
	if not c.recommended(w).is_empty() or c.next_hint(w) != "":
		return "no suggestion without assist: %s '%s'" % [c.recommended(w), c.next_hint(w)]
	var acts := c.actions(w)
	if acts.size() != 4 or acts[0].kind != "tune" or acts[0].label != "Tune COM1 to Test Delivery 121.850":
		return "the tune entry heads the list: %s" % [acts.map(func(a): return a.label)]
	c.request("clearance", w, t)  # the old behaviour: the tower sends you to Delivery
	t = _pump(c, mon, w, t, 2.0)
	if _calls.size() != 0 or not _text(c).contains("you are on the wrong frequency, contact Test Delivery 121.85."):
		return "no automatic tuning without assist: %s\n%s" % [_calls, _text(c)]
	w.com1_mhz = 121.85
	if c.actions(w).any(func(a): return a.kind == "tune"):
		return "on the right unit the tune entry goes away"
	return ""


func test_atc_assist_tunes_before_the_call_and_says_so() -> String:
	var c := _ctl()
	c.assist = true
	var w := _world(118.1, {"at_stand": true})
	c.request("clearance", w, 0.0)  # tuned to the tower, Delivery answers clearance
	c.update(10.0)
	var txt := _text(c)
	if _calls != ["tune 121.850"]:
		return "tune call: %s" % [_calls]
	var err := _need(txt, ["(radio): COM1 tuned to 121.850 Test Delivery.", "You: Test Delivery, VT-FSM", "Test Delivery: VT-FSM, cleared VFR"])
	if err != "":
		return err
	if txt.find("COM1 tuned") > txt.find("You: Test Delivery"):
		return "the tuning note comes before the call:\n" + txt
	if _count(c, "system") != 1 or not c.s.cleared:
		return "one note, and the call works: system %d cleared %s" % [_count(c, "system"), c.s.cleared]
	_calls.clear()
	w.com1_mhz = 121.85  # already on the right unit: nothing to tune, no note
	c.request("clearance", w, 11.0)
	c.update(30.0)
	if not _calls.is_empty() or _count(c, "system") != 1:
		return "right unit already tuned: %s system %d" % [_calls, _count(c, "system")]
	# fields without published frequencies are answered on any frequency: nothing to tune
	var d := _ctl()
	d.assist = true
	var any := _world(99.9, {"at_stand": true}, "none")
	any.ctl = "any"
	d.request("clearance", any, 0.0)
	d.update(10.0)
	if not _calls.is_empty() or _count(d, "system") != 0 or not d.s.cleared:
		return "any-frequency field: %s system %d" % [_calls, _count(d, "system")]
	return _clean(c)


func test_atc_assist_list_is_short_ordered_and_plain() -> String:
	var c := _ctl()
	c.assist = true
	var w := _world(126.4, {"at_stand": true})
	_pump(c, AtcMonitor.new(c), w, 0.0, 1.0)
	var acts := c.actions(w)
	var ids := _ids(acts)
	if ids != ["atis", "clearance", "pushback", "taxi"]:
		return "parked list: %s" % [ids]
	c.s.info_heard = true
	c.s.cleared = true
	c.s.state = "clearance"
	acts = c.actions(w)
	if acts[0].id != "taxi" or acts.size() > 4 or _ids(acts).has("say_again") or _ids(acts).has("tune"):
		return "the suggested call heads the list, no say again or tune: %s" % [_ids(acts)]
	var long_labels := []
	for id in AtcState.INTENTS:
		for role in ["Delivery", "Ground", "Tower", "Approach"]:
			for key in ["label", "label_info", "label_lined"]:
				var label: String = str(AtcState.INTENTS[id].get(key, "")).replace("{who}", role)
				if label.length() > 36 or label.contains("{"):
					long_labels.append(label)
		var blind: String = str(AtcState.INTENTS[id].blind)
		if blind.length() > 36:
			long_labels.append(blind)
	if not long_labels.is_empty():
		return "labels should stay short and plain: %s" % [long_labels]
	c.s.state = "takeoff"
	if not c.actions(w).is_empty() or c.recommended(w).has("id"):
		return "nothing to call while rolling: %s" % [c.actions(w)]
	return ""


func test_atc_assist_hints_cover_every_state() -> String:
	var c := _ctl()
	c.assist = true
	var w := _world(118.1, {"at_stand": false, "rwy_dist": 800.0})
	for st in AtcState.STATES:
		c.s.state = st
		w.wow = st in ["parked", "clearance", "taxi", "hold_short", "lined_up", "takeoff", "landed", "vacated"]
		var hint := c.next_hint(w)
		if not hint.begins_with("Next: ") or hint.contains("{") or hint.length() > 42:  # the bar is 40 characters wide at 1280x720
			return "%s: hint '%s'" % [st, hint]
	c.s.state = "final"
	w.wow = false
	c.set_flag("land_wait")
	if c.next_hint(w) != "Next: wait for the landing clearance":
		return "waiting for the landing clearance: '%s'" % c.next_hint(w)
	w.com1_ok = false
	w.com1_why = "unpowered"
	if c.next_hint(w) != "Radio off: switch on avionics (Shift+V)":
		return "dead radio: '%s'" % c.next_hint(w)
	w.com1_ok = true
	w.apt = ""
	if c.next_hint(w) != "No airport in radio range":
		return "no airport: '%s'" % c.next_hint(w)
	return ""
