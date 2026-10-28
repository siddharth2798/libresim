extends "res://tests/atc_fixture.gd"
## ATC airline profile (aircraft.json atc.profile = "airline"): call sign and its spoken form, the profile
## layer of phraseology.json, a whole departure and arrival with a synthetic airline AircraftDef, and the
## fallback to the GA phrases. The GA strings themselves are asserted in test_atc_flow.gd.


func _airline_def(wake := "M") -> AircraftDef:
	return AircraftDef.make("t_airliner", {"radio_type": "A320",
		"atc": {"profile": "airline", "wake": wake, "telephony": "Skyline", "flight_no": "123", "callsign_style": "airline"}}, "res://aircraft/c172")


func _airline_ctl() -> AtcController:
	var def := _airline_def()
	var c := AtcController.new(AtcProfile.radio_callsign(def), AtcPhraseology.new(), 7)
	AtcProfile.apply(c, def)
	c.delay = Vector2.ZERO
	c.readback_gap = 0.0
	c.hooks = _hooks()
	_calls.clear()
	return c


func _awd(mhz: float, over := {}) -> Dictionary:  # airline world: ILS on 27, a destination in the data
	return _world(mhz, {"ils": ["27"], "dest": "Delhi"}.merged(over, true))


func test_atc_airline_callsign_forms() -> String:
	var def := _airline_def()
	if AtcProfile.radio_callsign(def) != "Skyline 123":
		return "radio call sign: '%s'" % AtcProfile.radio_callsign(def)
	if AtcProfile.radio_callsign(_airline_def("H")) != "Skyline 123 heavy":
		return "heavy: '%s'" % AtcProfile.radio_callsign(_airline_def("H"))
	if AtcProfile.radio_callsign(AircraftDef.load_def("c172")) != "":
		return "a GA aircraft keeps its registration"
	if AtcProfile.radio_callsign(def, "skyline 456") != "Skyline 456" or AtcProfile.radio_callsign(def, "VT-FSM") != "Skyline 123":
		return "typed call sign: an airline form wins, a registration does not"
	for t in [["Skyline 123", "one two tree"], ["skyline 9051", "niner zero fife one"], ["Skyline 12A", "one two Alpha"]]:
		var want: String = "Skyline " + t[1]
		var got := AtcSpeech.callsign(AtcSpeech.normalize_airline_callsign(t[0]), true)
		if got != want:
			return "spoken '%s': '%s' (want '%s')" % [t[0], got, want]
	if AtcSpeech.callsign("Skyline 123 heavy", true) != "Skyline one two tree heavy" or AtcSpeech.callsign("Skyline 123", false) != "Skyline 123":
		return "heavy / written form"
	if AtcSpeech.callsign("VT-FSM", true) != "Victor Tango Foxtrot Sierra Mike":
		return "registrations are still spelled out"
	for bad in ["", "Skyline", "Skyline 12345", "12 123", "Sk 123", "Skyline abc", "SKYLINE123"]:
		if AtcSpeech.normalize_airline_callsign(bad) != "":
			return "'%s' must be rejected" % bad
	return ""


func test_atc_airline_profile_layer_falls_back_to_ga() -> String:
	var phr := AtcPhraseology.new()
	if phr.template("controller", "clearance", "DEL", 0, "airline") == phr.template("controller", "clearance", "DEL"):
		return "the airline clearance must differ from the VFR one"
	for k in [["pilot", "atis"], ["controller", "wrong_freq"], ["advisory", "takeoff_no_clr"], ["readback", "handoff"]]:
		if phr.template(k[0], k[1], "TWR", 0, "airline") != phr.template(k[0], k[1], "TWR"):
			return "%s.%s is not in the airline layer: it must fall back to the GA phrase" % [k[0], k[1]]
	if phr.template("controller", "clearance", "DEL", 0, "no_such_profile") != phr.template("controller", "clearance", "DEL"):
		return "an unknown profile is the GA profile"
	if phr.template("controller", "clearance", "DEL", 0, "ga") != phr.template("controller", "clearance", "DEL", 0):
		return "ga profile is the base"
	if not phr.has("controller", "depart_ifr", "airline") or phr.has("controller", "depart_ifr"):
		return "depart_ifr exists in the airline layer only"
	var sections := phr.all_templates().map(func(t): return str(t[0]))
	return "" if "airline/controller" in sections and "controller" in sections else "all_templates lists the profile layer: %s" % [sections.slice(-3)]


func test_atc_airline_menu_labels() -> String:
	var c := _airline_ctl()
	var w := _awd(126.4, {"at_stand": true, "where": "stand 12"})
	var m := c.menu(w).filter(func(e): return e.kind == "call")
	if _ids(m) != ["atis", "clearance", "pushback", "taxi"]:
		return "same calls as GA: %s" % [_ids(m)]
	if m[1].label != "Ask Clearance for IFR clearance" and not str(m[1].label).contains("IFR clearance"):
		return "airline label: %s" % m[1].label
	var g := _ctl().menu(w).filter(func(e): return e.kind == "call")
	if g[1].label.contains("IFR") or str(g[1].label) != AtcMenu.label("clearance", w):
		return "GA label unchanged: %s" % g[1].label
	if AtcMenu.label("final", w, "", "airline") != "Report established on the approach" or AtcMenu.label("final", w) != "Report final":
		return "final label per profile"
	return ""


func test_atc_airline_full_departure() -> String:
	var c := _airline_ctl()
	var mon := AtcMonitor.new(c)
	var w := _awd(121.85, {"at_stand": true, "where": "stand 12"})
	var t := _pump(c, mon, w, 0.0, 1.0)
	c.request("clearance", w, t)
	t = _pump(c, mon, w, t, 3.0)
	var err := _need(_text(c), ["You: Test Delivery, Skyline 123, A320 at stand 12, request IFR clearance to Delhi",
		"Test Delivery: Skyline 123, cleared to Delhi via flight planned route, runway 27 departure, initial climb 5000 feet, squawk " + c.s.squawk + ", QNH 1012.",
		"Cleared to Delhi via flight planned route, runway 27, initial climb 5000 feet", "Skyline 123, readback correct."])
	if err != "":
		return err
	if _text(c).contains("VFR"):
		return "no VFR wording in an airline flight:\n" + _text(c)
	w.com1_mhz = 121.9
	c.request("pushback", w, t)
	t = _pump(c, mon, w, t, 2.0)
	err = _need(_text(c), ["Skyline 123, A320 at stand 12, ready for pushback, request start-up", "Test Ground: Skyline 123, push back approved, start-up at your discretion, report ready to taxi.",
		"Push back approved, start-up at our discretion, Skyline 123"])
	if err != "" or _calls != ["pushback"]:
		return err if err != "" else "pushback hook %s" % [_calls]
	c.request("taxi", w, t)
	t = _pump(c, mon, w, t, 2.0)
	err = _need(_text(c), ["Test Ground: Skyline 123, taxi via A, B to holding point runway 27, hold short, QNH 1012.", "Taxi via A, B to holding point runway 27, QNH 1012, Skyline 123"])
	if err != "" or c.s.state != "taxi":
		return err if err != "" else "after taxi: " + c.s.state
	w.merge({"pos": Vector2(60, 0), "gs": 4.0, "at_stand": false}, true)
	t = _pump(c, mon, w, t, 1.0)
	w.merge({"pos": Vector2(200, 0), "gs": 0.5, "rwy_dist": 60.0, "hold_dist": 15.0}, true)
	t = _pump(c, mon, w, t, 1.5)
	w.com1_mhz = 118.1
	t = _pump(c, mon, w, t, 1.0)
	c.request("ready", w, t)
	t = _pump(c, mon, w, t, 2.0)
	err = _need(_text(c), ["Skyline 123, holding point runway 27, ready for departure", "Test Tower: Skyline 123, runway 27, line up and wait.", "Line up and wait runway 27, Skyline 123"])
	if err != "":
		return err
	w.merge({"pos": Vector2(250, 10), "on_runway": true, "aligned": true, "rwy_dist": 0.0, "gs": 0.0}, true)
	t = _pump(c, mon, w, t, 5.0)
	err = _need(_text(c), ["Test Tower: Skyline 123, runway 27, wind 270 degrees 8 knots, cleared for takeoff."])
	if err != "" or not c.s.cleared_takeoff:
		return err if err != "" else "cleared for takeoff"
	w.merge({"pos": Vector2(330, 10), "gs": 22.0}, true)
	t = _pump(c, mon, w, t, 1.0)
	w.merge({"pos": Vector2(600, 10), "wow": false, "agl": 5.0, "gs": 36.0, "on_runway": false, "vs": 3.0}, true)
	t = _pump(c, mon, w, t, 2.0)
	w.merge({"pos": Vector2(900, 10), "agl": 200.0, "alt": 200.0}, true)
	t = _pump(c, mon, w, t, 2.0)
	if _need(_text(c), ["Test Tower: Skyline 123, contact Test Approach 127.9."]) != "" or c.s.handoff != "APP":
		return "departure handoff:\n" + _text(c)
	w.com1_mhz = 127.9
	w.merge({"agl": 800.0, "alt": 800.0}, true)
	t = _glide(c, mon, w, t, Vector2(2500, 10))
	t = _pump(c, mon, w, t, 2.0)
	err = _need(_text(c), ["Test Approach: Skyline 123, radar contact, climb flight level 100.", "Climb flight level 100, Skyline 123"])
	if err != "":
		return err
	t = _pump(c, mon, w, t, 3.0)
	if _text(c).count("radar contact") != 1 or _count(c, "advisory") != 0:
		return "the climb instruction comes once, no advisories:\n" + _text(c)
	return _clean(c)


func test_atc_airline_departure_without_separate_approach() -> String:
	var c := _airline_ctl()
	var mon := AtcMonitor.new(c)
	var w := _world(123.5, {"wow": false, "agl": 200.0, "alt": 200.0, "gs": 70.0, "pos": Vector2(900, 10)}, "twr")
	var t := _pump(c, mon, w, 0.0, 0.5)
	c.s.state = "departed"
	c.s.flags = {}
	t = _pump(c, mon, w, t, 2.0)
	if _need(_text(c), ["Test Tower: Skyline 123, radar contact, climb flight level 100, leaving frequency approved.", "Climb flight level 100, leaving frequency, Skyline 123"]) != "":
		return "tower-only departure:\n" + _text(c)
	return _clean(c)


func test_atc_airline_full_arrival() -> String:
	var c := _airline_ctl()
	var mon := AtcMonitor.new(c)
	var w := _air_world(127.9, {"ils": ["27"], "dest": "Delhi"})
	var t := _pump(c, mon, w, 0.0, 1.0)
	c.request("inbound", w, t)
	t = _pump(c, mon, w, t, 2.0)
	var err := _need(_text(c), ["You: Test Approach, Skyline 123, A320, 6 miles west of the field, 2300 feet, request ILS approach runway 27",
		"Test Approach: Skyline 123, runway 27 in use, descend 3000 feet, QNH 1012, cleared ILS approach runway 27, contact Test Tower 118.1.",
		"Descend 3000 feet, QNH 1012, cleared ILS approach runway 27, contact Test Tower 118.1, Skyline 123"])
	if err != "" or c.s.state != "inbound":
		return err if err != "" else "inbound: " + c.s.state
	if _text(c).contains("circuit") or _text(c).contains("downwind"):
		return "no circuit wording in an airline flight:\n" + _text(c)
	w.com1_mhz = 118.1
	t = _glide(c, mon, w, t, Vector2(-9000, 400))
	t = _pump(c, mon, w, t, 2.0)
	if _need(_text(c), ["Test Tower: Skyline 123, continue approach runway 27, report established."]) != "":
		return "tower asks to report established:\n" + _text(c)
	if _ids(c.menu(w)).slice(0, 1) != ["final"] or c.menu(w)[0].label != "Report established on the approach":
		return "airline menu on approach: %s" % [c.menu(w)]
	c.request("final", w, t)
	t = _pump(c, mon, w, t, 2.0)
	err = _need(_text(c), ["You: Test Tower, Skyline 123, established ILS runway 27", "Test Tower: Skyline 123, wind 270 degrees 8 knots, runway 27, cleared to land."])
	if err != "" or not c.s.cleared_land:
		return err if err != "" else "cleared to land"
	c.request("goaround", w, t)
	t = _pump(c, mon, w, t, 2.0)
	if _need(_text(c), ["Test Tower: Skyline 123, roger, climb straight ahead 3000 feet, expect vectors", "Climb straight ahead, 3000 feet, Skyline 123"]) != "" or c.s.state != "inbound":
		return "go-around:\n" + _text(c)
	w.merge({"agl": 0.0, "wow": true, "on_runway": true, "aligned": true, "gs": 30.0, "vs": 0.0, "appr": {}}, true)
	t = _glide(c, mon, w, t, Vector2(-700, 3))
	t = _pump(c, mon, w, t, 1.0)
	w.gs = 12.0
	t = _glide(c, mon, w, t, Vector2(-200, 3))
	t = _pump(c, mon, w, t, 1.5)
	if _need(_text(c), ["Test Tower: Skyline 123, vacate runway 27 when able, contact Test Ground 121.9."]) != "":
		return "vacate:\n" + _text(c)
	w.merge({"on_runway": false, "gs": 8.0, "pos": Vector2(-100, 60), "com1_mhz": 121.9}, true)
	t = _pump(c, mon, w, t, 1.0)
	c.request("taxi_stand", w, t)
	t = _pump(c, mon, w, t, 2.0)
	err = _need(_text(c), ["Skyline 123, runway 27 vacated, request taxi to the stand", "Test Ground: Skyline 123, taxi via B to stand 3.", "Taxi via B to stand 3, Skyline 123"])
	if err != "":
		return err
	return _clean(c)


func test_atc_airline_visual_approach_without_ils() -> String:
	var c := _airline_ctl()
	var w := _air_world(127.9, {"ils": [], "dest": ""})
	c.request("inbound", w, 0.0)
	c.update(5.0)
	return _need(_text(c), ["request visual approach runway 27", "cleared visual approach runway 27"])


func test_atc_airline_destination_from_data() -> String:
	var airports := [{"icao": "TEST", "ident": "TEST", "name": "Test Aerodrome", "type": "medium_airport", "x": 0.0, "y": 0.0},
		{"icao": "NEAR", "ident": "NEAR", "name": "Near Airport", "type": "large_airport", "x": 20000.0, "y": 0.0},
		{"icao": "FARL", "ident": "FARL", "name": "Delhi International Airport", "type": "large_airport", "x": 400000.0, "y": 0.0},
		{"icao": "FAR2", "ident": "FAR2", "name": "Chennai Airport", "type": "large_airport", "x": 900000.0, "y": 0.0}]
	var env := AtcWorld.make_env(airports, {}, [], {})
	var d := AtcProfile.dest_for(env, "TEST", Vector2.ZERO)
	if d != "Delhi":
		return "nearest large airport at least 100 km away (not the field next door): '%s'" % d
	if AtcProfile.dest_for(AtcWorld.make_env([], {}, [], {}), "TEST", Vector2.ZERO) != "" or AtcProfile.dest_text({}) != "the filed destination":
		return "no destination: generic wording"
	return ""


func test_atc_airline_ga_c172_has_ga_profile() -> String:
	var a := AtcProfile.of(AircraftDef.load_def("c172"))
	if a.profile != "ga" or a.wake != "L" or AtcProfile.is_airline(a.profile):
		return "c172 atc section: %s" % [a]
	if AtcProfile.of(null).profile != "ga" or AtcProfile.of(AircraftDef.make("x", {}, "")).profile != "ga":
		return "no section = GA"
	return ""
