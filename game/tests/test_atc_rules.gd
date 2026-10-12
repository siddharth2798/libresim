extends "res://tests/atc_fixture.gd"
## ATC rules (game/atc): the advisories (each once per flight), silence in training lessons,
## wrong-frequency guidance, uncontrolled fields, COM1 failure, ATIS letter, say again, save / load
## of the state, and the session publishing /atc/*. Fake world: atc_fixture.gd.


func test_atc_advisories_fire_once() -> String:
	# taking off without a clearance
	var c := _ctl()
	var mon := AtcMonitor.new(c)
	var w := _world(118.1, {"on_runway": true, "aligned": true, "rwy_dist": 0.0})
	var t := _pump(c, mon, w, 0.0, 1.0)
	if c.s.state != "lined_up":
		return "starts lined up on the runway: " + c.s.state
	w.gs = 22.0
	t = _pump(c, mon, w, t, 3.0)
	if _count(c, "advisory") != 1 or not _text(c).contains("no takeoff clearance has been given") or c.s.state != "takeoff":
		return "take-off without clearance:\n" + _text(c)
	# landing without a clearance: once per flight, again after parking
	c = _ctl()
	mon = AtcMonitor.new(c)
	w = _air_world(118.1, {"pos": Vector2(-5000, 5), "apt_dist": 5000.0, "apt_dist_nm": 2.7})
	t = _pump(c, mon, w, 0.0, 1.0)
	c.request("inbound", w, t)
	t = _pump(c, mon, w, t, 2.0)
	w.merge({"agl": 50.0, "vs": -2.0, "appr": {"ident": "27", "along": -600.0, "cross": 5.0, "tail_kt": -8.0}}, true)
	t = _pump(c, mon, w, t, 4.0)
	if _count(c, "advisory") != 1 or not _text(c).contains("no landing clearance has been given"):
		return "landing without clearance:\n" + _text(c)
	w.merge({"agl": 400.0, "vs": 3.0}, true)
	t = _pump(c, mon, w, t, 1.0)
	w.merge({"agl": 50.0, "vs": -2.0}, true)
	t = _pump(c, mon, w, t, 2.0)
	if _count(c, "advisory") != 1:
		return "a second low pass in the same flight does not repeat the note: %d" % _count(c, "advisory")
	mon._park(w)  # next flight: the note is armed again
	w.merge({"agl": 400.0, "vs": 3.0}, true)
	t = _pump(c, mon, w, t, 1.0)
	w.merge({"agl": 50.0, "vs": -2.0}, true)
	t = _pump(c, mon, w, t, 2.0)
	if _count(c, "advisory") != 2:
		return "after parking the note is shown again: %d" % _count(c, "advisory")
	# entering the runway without a clearance
	c = _ctl()
	mon = AtcMonitor.new(c)
	w = _world(118.1, {"pos": Vector2(100, 0), "rwy_dist": 60.0, "hold_dist": 10.0})
	t = _pump(c, mon, w, 0.0, 1.0)
	w.merge({"pos": Vector2(180, 0), "gs": 3.0, "rwy_dist": 0.0, "on_runway": true, "aligned": false}, true)
	t = _pump(c, mon, w, t, 3.0)
	if _count(c, "advisory") != 1 or not _text(c).contains("you are on runway 27 without a clearance"):
		return "runway entry without clearance:\n" + _text(c)
	return _clean(c)

## The same unclear situations with and without a lesson: only free flight gets a (calm) note.
func _unclear(silent: bool) -> Array:
	var landing := _ctl()
	var mon := AtcMonitor.new(landing)
	mon.silent = silent
	var w := _air_world(121.9, {"pos": Vector2(-5000, 5), "apt_dist": 5000.0, "apt_dist_nm": 2.7, "com1_ok": false, "com1_why": "failed"})
	var t := _pump(landing, mon, w, 0.0, 1.0)
	w.merge({"agl": 50.0, "vs": -2.0, "appr": {"ident": "27", "along": -600.0, "cross": 5.0, "tail_kt": -8.0}}, true)
	t = _pump(landing, mon, w, t, 4.0)
	var takeoff := _ctl()
	var mon2 := AtcMonitor.new(takeoff)
	mon2.silent = silent
	var w2 := _world(118.1, {"on_runway": true, "aligned": true, "rwy_dist": 0.0})
	t = _pump(takeoff, mon2, w2, 0.0, 1.0)
	w2.gs = 22.0
	t = _pump(takeoff, mon2, w2, t, 3.0)
	var entry := _ctl()  # runway entry from the holding point + a pending handover
	var mon3 := AtcMonitor.new(entry)
	mon3.silent = silent
	var w3 := _world(121.9, {"pos": Vector2(100, 0), "rwy_dist": 60.0, "hold_dist": 10.0})
	t = _pump(entry, mon3, w3, 0.0, 1.0)
	entry.s.handoff = "TWR"
	entry.s.handoff_at = t
	w3.merge({"pos": Vector2(180, 0), "gs": 3.0, "rwy_dist": 0.0, "on_runway": true, "aligned": false}, true)
	t = _pump(entry, mon3, w3, t, 30.0)
	return [landing, takeoff, entry]

func test_atc_lesson_keeps_atc_silent() -> String:
	var q := _unclear(true)
	for c in q:
		if not c.log.is_empty() or c.pending() != 0:
			return "in a lesson ATC says nothing, not even a note:\n" + _text(c)
		if not (c.s.cleared and c.s.lineup_ok and c.s.cleared_takeoff and c.s.cleared_land) or c.s.handoff != "":
			return "in a lesson clearances count as given: %s" % [c.s]
	if q[0].s.state != "final" or q[1].s.state != "takeoff":
		return "the state still follows the flight: %s / %s" % [q[0].s.state, q[1].s.state]
	var loud := _unclear(false)  # and without a lesson each note comes exactly once
	if _count(loud[0], "advisory") != 1 or _count(loud[1], "advisory") != 1 or _count(loud[2], "advisory") != 1:
		return "free flight: one note each: %d %d %d" % [_count(loud[0], "advisory"), _count(loud[1], "advisory"), _count(loud[2], "advisory")]
	for c in loud:
		for e in c.log:
			if e.kind == "advisory" and (e.text.contains("!") or e.text.to_lower().contains("stop")):
				return "notes are calm, not commands: '%s'" % e.text
	return ""

func test_atc_wrong_frequency_guidance() -> String:
	# tuned to another unit of the airport: it redirects the pilot
	var c := _ctl()
	var mon := AtcMonitor.new(c)
	var w := _world(127.9, {"at_stand": true})
	var t := _pump(c, mon, w, 0.0, 1.0)
	c.request("clearance", w, t)
	t = _pump(c, mon, w, t, 2.0)
	var err := _need(_text(c), ["You: Test Approach, VT-FSM, Cessna 172 at the apron", "Test Approach: VT-FSM, you are on the wrong frequency, contact Test Delivery 121.85."])
	if err != "" or c.s.cleared or c.s.state != "parked":
		return err if err != "" else "no state change on the wrong unit"
	# tuned to nothing: no reply, the radio says what to tune; the menu offers it
	w.com1_mhz = 118.0
	var m := c.menu(w)
	var tune: Dictionary = m.filter(func(e): return e.kind == "tune")[0]
	if tune.label != "Tune COM1 to Test Delivery 121.850":
		return "tune entry: %s" % tune.label
	c.request("clearance", w, t)
	t = _pump(c, mon, w, t, 4.0)
	if _need(_text(c), ["(radio): No reply on COM1 118.0. Test Delivery is on 121.85."]) != "":
		return "no reply guidance:\n" + _text(c)
	c.request("tune", w, t, tune.mhz, tune.name)
	t = _pump(c, mon, w, t, 1.0)
	if not _calls.has("tune 121.850") or not _text(c).contains("COM1 set to Test Delivery 121.85."):
		return "tune: %s\n%s" % [_calls, _text(c)]
	# after a handover the radio reminds the pilot once if COM1 is still on the old unit
	c = _ctl()
	mon = AtcMonitor.new(c)
	w = _world(121.9, {"pos": Vector2(0, 0)})
	t = _pump(c, mon, w, 0.0, 1.0)
	c.s.handoff = "TWR"
	c.s.handoff_at = t
	t = _pump(c, mon, w, t, 30.0)
	if _text(c).count("Tune COM1 to Test Tower 118.1") != 1:
		return "one reminder after 25 s:\n" + _text(c)
	return _clean(c)

func test_atc_uncontrolled_field_only_blind_calls() -> String:
	var c := _ctl()
	var mon := AtcMonitor.new(c)
	var w := _world(122.8, {"pos": Vector2(0, 0), "at_stand": true}, "none")
	w.ctl = "uncontrolled"
	var t := _pump(c, mon, w, 0.0, 1.0)
	var ids := _ids(c.menu(w))
	if ids != ["pushback", "taxi"] or not c.menu(w)[1].label.begins_with("Blind call"):
		return "uncontrolled menu: %s %s" % [ids, c.menu(w)]
	c.request("taxi", w, t)
	t = _pump(c, mon, w, t, 3.0)
	if _count(c, "atc") != 0 or _count(c, "pilot") != 1 or not _text(c).contains("You: Test traffic, VT-FSM, Cessna 172 at the apron, taxiing to runway 27"):
		return "blind taxi call:\n" + _text(c)
	if c.s.state != "taxi" or not _calls.has("taxi"):
		return "the pilot's own state still moves on: %s %s" % [c.s.state, _calls]
	c.request("taxi", w, t)
	t = _pump(c, mon, w, t, 2.0)
	if _text(c).count("no air traffic service") != 1:
		return "the no-ATC note comes once:\n" + _text(c)
	# no advisories or clearances are needed without a controller
	w.merge({"on_runway": true, "aligned": true, "gs": 25.0, "rwy_dist": 0.0}, true)
	t = _pump(c, mon, w, t, 3.0)
	if _count(c, "advisory") != 0 or _count(c, "atc") != 0:
		return "uncontrolled: nothing to tell off:\n" + _text(c)
	return _clean(c)

func test_atc_unpublished_controlled_field_answers_on_any_frequency() -> String:
	var c := _ctl()
	var mon := AtcMonitor.new(c)
	var w := _world(99.9, {"at_stand": true}, "none")
	w.ctl = "any"
	var t := _pump(c, mon, w, 0.0, 1.0)
	c.request("clearance", w, t)
	t = _pump(c, mon, w, t, 3.0)
	if _need(_text(c), ["Test Tower: VT-FSM, cleared VFR, departure runway 27"]) != "" or not c.s.cleared:
		return "any-frequency field:\n" + _text(c)
	if not _ids(c.menu(w)).has("taxi") or _ids(c.menu(w)).has("tune"):
		return "no tune entry without published frequencies: %s" % [_ids(c.menu(w))]
	return _clean(c)

func test_atc_com1_failure() -> String:
	var c := _ctl()
	var mon := AtcMonitor.new(c)
	var w := _world(118.1, {"com1_ok": false, "at_stand": true})
	var t := _pump(c, mon, w, 0.0, 3.0)
	if _count(c, "system") != 1 or not _text(c).contains("COM1 is dead") or not _text(c).contains("Squawk 7600"):
		return "COM1 failure note once:\n" + _text(c)
	c.request("clearance", w, t)
	t = _pump(c, mon, w, t, 2.0)
	if _count(c, "pilot") != 0 or _count(c, "system") != 2:
		return "no call can be made with a dead radio:\n" + _text(c)
	w.com1_ok = true
	t = _pump(c, mon, w, t, 1.0)
	w.com1_ok = false
	t = _pump(c, mon, w, t, 1.0)
	return "" if _count(c, "system") == 3 else "a second failure is announced again: %d" % _count(c, "system")

func test_atc_switched_off_radio_is_not_a_failure() -> String:
	var c := _ctl()
	var mon := AtcMonitor.new(c)
	var w := _world(118.1, {"com1_ok": false, "com1_why": "unpowered", "at_stand": true})
	var t := _pump(c, mon, w, 0.0, 3.0)
	if _count(c, "system") != 0:
		return "a cold and dark cockpit is silent:\n" + _text(c)
	c.request("clearance", w, t)
	t = _pump(c, mon, w, t, 1.0)
	if _count(c, "system") != 1 or not _text(c).contains("COM1 is off: there is no power") or _text(c).contains("7600"):
		return "asking with the avionics off:\n" + _text(c)
	return ""

func test_atc_information_letter_follows_weather() -> String:
	var c := _ctl()
	var mon := AtcMonitor.new(c)
	var w := _world(126.4)
	var t := _pump(c, mon, w, 0.0, 1.0)
	c.request("atis", w, t)
	t = _pump(c, mon, w, t, 1.0)
	if c.info_word() != "Alpha" or not c.s.info_heard:
		return "starts at Alpha, heard"
	w.wind_dir = 274.0  # a small shift is not a new report
	t = _pump(c, mon, w, t, 1.0)
	if c.info_word() != "Alpha":
		return "small wind shift keeps the letter"
	w.merge({"wind_dir": 180.0, "qnh": 1008.0}, true)
	t = _pump(c, mon, w, t, 1.0)
	if c.info_word() != "Bravo" or c.s.info_heard:
		return "material change gives Bravo and must be listened to again: %s" % c.info_word()
	c.request("atis", w, t)
	t = _pump(c, mon, w, t, 1.0)
	return "" if _text(c).contains("information Bravo. Runway") else "new ATIS letter:\n" + _text(c)

func test_atc_say_again_repeats_the_last_instruction() -> String:
	var c := _ctl()
	var mon := AtcMonitor.new(c)
	var w := _world(121.9, {"at_stand": true})
	var t := _pump(c, mon, w, 0.0, 1.0)
	if _ids(c.menu(w)).has("say_again"):
		return "nothing to repeat yet"
	c.request("taxi", w, t)
	t = _pump(c, mon, w, t, 2.0)
	var instr := str(c.s.last_instr)
	if not instr.to_lower().contains("taxi to holding point runway 27") or not _ids(c.menu(w)).has("say_again"):
		return "instruction not remembered: '%s'" % instr
	c.request("say_again", w, t)
	t = _pump(c, mon, w, t, 2.0)
	var last: Dictionary = c.log[-1]
	return "" if last.text == instr and c.log[-2].text.contains("say again") else "repeat:\n" + _text(c)

func test_atc_jump_resets_to_the_new_situation() -> String:
	var c := _ctl()
	var mon := AtcMonitor.new(c)
	var w := _world(118.1, {"on_runway": true, "aligned": true, "gs": 25.0})
	var t := _pump(c, mon, w, 0.0, 1.0)
	c.s.state = "final"
	c.s.cleared_land = true
	var squawk := str(c.s.squawk)
	w.merge({"pos": Vector2(5000, 0), "gs": 0.0, "on_runway": false, "aligned": false, "at_stand": true}, true)  # F5 or a load
	t = _pump(c, mon, w, t, 0.5)
	if c.s.state != "parked" or c.s.cleared_land or c.s.squawk != squawk:
		return "after the jump: %s, squawk kept: %s" % [c.s.state, c.s.squawk == squawk]
	return ""
