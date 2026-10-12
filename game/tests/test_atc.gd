extends Node
## ATC building blocks (game/atc): number and spelling formatters, call-sign validation,
## the phrase file (every template fills cleanly), which unit COM1 reaches, runway geometry
## from the world snapshot, panel placement. The flows are in tests/test_atc_flow.gd.


func _rwys() -> Array:  # one runway 09/27 along the east axis, 2 km long, centred on the origin
	return [{"airport": "TEST", "width": 45.0, "length": 2000.0, "ends": [
		{"ident": "09", "x": -1000.0, "y": 0.0, "heading_true": 90.0},
		{"ident": "27", "x": 1000.0, "y": 0.0, "heading_true": 270.0}]}]


func test_atc_digits_and_runway_words() -> String:
	var cases := [
		[AtcSpeech.digits("0123456789"), "zero one two tree four fife six seven eight niner"],
		[AtcSpeech.digits("118.1"), "one one eight decimal one"],
		[AtcSpeech.runway("09"), "zero niner"], [AtcSpeech.runway("27L"), "two seven left"],
		[AtcSpeech.runway("10R"), "one zero right"], [AtcSpeech.runway("18C"), "one eight centre"],
		[AtcSpeech.qnh(1012.0, true), "one zero one two"], [AtcSpeech.qnh(1012.4, false), "1012"],
		[AtcSpeech.digits("4521"), "four fife two one"],
	]
	for c in cases:
		if c[0] != c[1]:
			return "'%s' should be '%s'" % [c[0], c[1]]
	return ""


func test_atc_altitude_frequency_temperature() -> String:
	var cases := [
		[AtcSpeech.altitude(2500.0), "two thousand five hundred"], [AtcSpeech.altitude(800.0), "eight hundred"],
		[AtcSpeech.altitude(1000.0), "one thousand"], [AtcSpeech.altitude(12500.0), "one two thousand five hundred"],
		[AtcSpeech.altitude(2540.0), "two thousand five hundred"],
		[AtcSpeech.frequency(118.1, true), "one one eight decimal one"],
		[AtcSpeech.frequency(122.95, true), "one two two decimal niner fife"],
		[AtcSpeech.frequency(123.5, true), "one two tree decimal fife"],
		[AtcSpeech.frequency_text(118.1), "118.1"], [AtcSpeech.frequency_text(121.725), "121.725"],
		[AtcSpeech.temperature(-5.0, true), "minus fife"], [AtcSpeech.temperature(30.0, false), "30"],
		[AtcSpeech.visibility(20000.0, false), "10 kilometres or more"], [AtcSpeech.visibility(6000.0, false), "6 kilometres"],
		[AtcSpeech.visibility(800.0, true), "eight hundred metres"],
	]
	for c in cases:
		if c[0] != c[1]:
			return "'%s' should be '%s'" % [c[0], c[1]]
	return ""


func test_atc_wind_words() -> String:
	var cases := [
		[AtcSpeech.wind(270.0, 8.0, 0.0, false), "270 degrees 8 knots"],
		[AtcSpeech.wind(272.0, 8.0, 0.0, true), "two seven zero degrees eight knots"],
		[AtcSpeech.wind(90.0, 15.0, 25.0, true), "zero niner zero degrees one fife knots gusting two fife"],
		[AtcSpeech.wind(0.0, 10.0, 0.0, false), "360 degrees 10 knots"],
		[AtcSpeech.wind(180.0, 1.0, 0.0, false), "calm"],
		[AtcSpeech.wind(180.0, 10.0, 12.0, false), "180 degrees 10 knots"],  # a 2 kt gust is not worth saying
	]
	for c in cases:
		if c[0] != c[1]:
			return "'%s' should be '%s'" % [c[0], c[1]]
	return ""


func test_atc_callsign_spelling_and_validation() -> String:
	if AtcSpeech.callsign("VT-FSM", true) != "Victor Tango Foxtrot Sierra Mike":
		return "spoken call sign: " + AtcSpeech.callsign("VT-FSM", true)
	if AtcSpeech.callsign("N172SP", true) != "November one seven two Sierra Papa":
		return "spoken N172SP: " + AtcSpeech.callsign("N172SP", true)
	for ok in [["vt-fsm", "VT-FSM"], ["N172SP", "N172SP"], ["VT FSM", "VTFSM"], ["g-abcd", "G-ABCD"], ["  VT-ABC ", "VT-ABC"]]:
		if AtcSpeech.normalize_callsign(ok[0]) != ok[1]:
			return "'%s' should normalise to '%s', got '%s'" % [ok[0], ok[1], AtcSpeech.normalize_callsign(ok[0])]
	for bad in ["", "x", "VT-", "VT-F", "A-BCDEFGH", "VT-FS$M", "--ABC"]:
		if AtcSpeech.normalize_callsign(bad) != "":
			return "'%s' must be rejected" % bad
	return ""


func test_atc_spoken_text_helpers() -> String:
	if AtcSpeech.speak_text("Cessna 172 at stand 12") != "Cessna one seven two at stand one two":
		return "speak_text: " + AtcSpeech.speak_text("Cessna 172 at stand 12")
	if AtcSpeech.taxiways(" via A, B2") != " via Alpha, Bravo two":
		return "taxiways: " + AtcSpeech.taxiways(" via A, B2")
	return ""


func test_atc_every_phrase_fills_cleanly() -> String:
	var phr := AtcPhraseology.new()
	var all := phr.all_templates()
	if all.size() < 60:
		return "phraseology.json looks empty: %d templates" % all.size()
	for t in all:
		var tpl: String = t[3]
		var where := "%s.%s.%s" % [t[0], t[1], t[2]]
		for n in AtcPhraseology.slot_names(tpl):
			if not AtcPhraseology.SAMPLE.has(n):
				return "%s uses the unknown slot {%s}" % [where, n]
		if tpl == "":
			if not (t[0] == "pilot" and t[1] == "atis" and t[2] == "ATIS"):
				return where + " is empty"
			continue
		for spoken in [false, true]:
			var out := phr.fill(tpl, AtcPhraseology.SAMPLE, spoken)
			if out.contains("{") or out.contains("}") or out.contains("  ") or out.contains(" ,") or out.contains(",,") or out.begins_with(","):
				return "%s fills badly (%s): '%s'" % [where, "spoken" if spoken else "written", out]
			if spoken and RegEx.create_from_string("\\d").search(out) != null:
				return "%s still has digits when spoken: '%s'" % [where, out]
	return ""


func test_atc_phrase_filling_rules() -> String:
	var phr := AtcPhraseology.new()
	if phr.fill("runway {rwy}{opt_via}, QNH {qnh}", {"rwy": "27", "opt_via": "", "qnh": 1012.0}) != "runway 27, QNH 1012":
		return "empty optional slot: " + phr.fill("runway {rwy}{opt_via}, QNH {qnh}", {"rwy": "27", "opt_via": "", "qnh": 1012.0})
	if phr.fill("runway {rwy}", {"rwy": "09"}, true) != "runway zero niner":
		return "spoken runway"
	if not phr.fill("x {nope}", {}).contains("{nope}"):
		return "a missing slot must stay visible so tests catch it"
	var a := phr.template("pilot", "inbound", "TWR", 0)
	var b := phr.template("pilot", "inbound", "TWR", 1)
	if a == b or a == "" or b == "":
		return "variants: '%s' / '%s'" % [a, b]
	if phr.template("pilot", "atis", "ATIS") != "" or phr.template("pilot", "atis", "TWR") == "":
		return "ATIS broadcast has no pilot call, an information request does"
	return ""


func _coms(kind: String) -> Array:
	match kind:
		"full": return [{"type": "ATIS", "desc": "X ATIS", "mhz": 126.4}, {"type": "CLD", "desc": "X CLR DELIVERY", "mhz": 121.85},
			{"type": "GND", "desc": "X GND", "mhz": 121.9}, {"type": "TWR", "desc": "X TWR", "mhz": 118.1},
			{"type": "APP", "desc": "X APP", "mhz": 127.9}, {"type": "ACC", "desc": "X", "mhz": 120.5},
			{"type": "RDO", "desc": "X RDO", "mhz": 1008.4}]
		"twr": return [{"type": "TWR", "desc": "POONA TWR", "mhz": 123.5}]
	return []


func _w(kind: String, mhz: float) -> Dictionary:
	var w := AtcWorld.blank()
	var coms := _coms(kind)
	w.merge({"apt": "TEST", "apt_name": "Test", "apt_type": "medium_airport", "coms": coms, "com1_mhz": mhz,
		"ctl": AtcFacilities.control_mode(coms, "medium_airport", "TEST")}, true)
	return w


func test_atc_facility_for_each_frequency() -> String:
	var roles := {126.4: "ATIS", 121.85: "DEL", 121.9: "GND", 118.1: "TWR", 127.9: "APP", 118.0: ""}
	for f in roles:
		var t := AtcFacilities.tuned(_w("full", f))
		if t.role != roles[f]:
			return "COM1 %.3f should be '%s', got '%s'" % [f, roles[f], t.role]
	var t2 := AtcFacilities.tuned(_w("full", 118.1))
	if t2.label != "TEST Tower 118.100" or t2.name != "Test Tower":
		return "label/name: %s / %s" % [t2.label, t2.name]
	if AtcFacilities.tuned(_w("full", 118.0)).label != "no facility on this frequency":
		return "label of an unknown frequency"
	if AtcFacilities.entries(_coms("full")).size() != 5:
		return "non-VHF and area-control entries must be dropped: %d" % AtcFacilities.entries(_coms("full")).size()
	return ""


func test_atc_services_by_unit() -> String:
	# full airport: each service is answered by exactly its own unit
	var want := {"atis": 126.4, "clearance": 121.85, "ground": 121.9, "tower": 118.1, "approach": 127.9}
	for svc in want:
		for f in [126.4, 121.85, 121.9, 118.1, 127.9, 118.0]:
			var ok := AtcFacilities.handles(_w("full", f), svc)
			if ok != (f == want[svc]):
				return "service %s on %.3f: handles=%s" % [svc, f, ok]
	# tower-only airport (Pune): the tower does everything, ATIS request = airport information
	for svc in ["atis", "clearance", "ground", "tower", "approach"]:
		if not AtcFacilities.handles(_w("twr", 123.5), svc) or AtcFacilities.handles(_w("twr", 118.1), svc):
			return "tower-only airport: service %s" % svc
	if AtcFacilities.role_for(_w("twr", 123.5), "atis") != "TWR":
		return "no ATIS: the tower gives airport information"
	var f := AtcFacilities.facility_for(_w("twr", 118.1), "clearance")
	if f.role != "TWR" or absf(f.mhz - 123.5) > 0.001:
		return "tune hint at a tower-only airport: %s" % [f]
	if not AtcFacilities.separate(_w("full", 118.1), "APP") or AtcFacilities.separate(_w("twr", 118.1), "APP"):
		return "separate approach unit"
	return ""


func test_atc_uncontrolled_and_unpublished_fields() -> String:
	if AtcFacilities.control_mode([], "small_airport", "VA1M") != "uncontrolled":
		return "a small field without frequencies is uncontrolled"
	if AtcFacilities.control_mode([], "heliport", "IN-0021") != "uncontrolled":
		return "a heliport is uncontrolled"
	if AtcFacilities.control_mode([], "large_airport", "VANM") != "any" or AtcFacilities.control_mode([], "small_airport", "VAJJ") != "any":
		return "controlled fields without published frequencies answer on any frequency (VANM large, VAJJ listed)"
	if AtcFacilities.control_mode(_coms("twr"), "small_airport", "X") != "published":
		return "published frequencies win"
	var u := _w("none", 118.1)
	u.ctl = "uncontrolled"
	var a := _w("none", 99.9)
	a.ctl = "any"
	if AtcFacilities.handles(u, "tower") or not AtcFacilities.handles(a, "tower") or AtcFacilities.tuned(a).name != "Test Tower":
		return "uncontrolled: nobody handles; any: the tower on every frequency"
	if AtcFacilities.apt_name("VAJJ", "Juhu Aerodrome") != "Juhu" or AtcFacilities.apt_name("VAPO", "Pune International Airport") != "Pune" \
			or AtcFacilities.apt_name("VABB", "Chhatrapati Shivaji Maharaj International Airport") != "Mumbai" \
			or AtcFacilities.apt_name("VAAV", "Aamby Valley Airport") != "Aamby Valley":
		return "airport names: %s %s" % [AtcFacilities.apt_name("VAJJ", "Juhu Aerodrome"), AtcFacilities.apt_name("VAAV", "Aamby Valley Airport")]
	return ""


func test_atc_world_runway_geometry() -> String:
	var w := AtcWorld.blank()
	w.merge({"pos": Vector2(-500, 3), "hdg": 92.0, "wind_dir": 270.0, "wind_kt": 10.0}, true)
	AtcWorld.geometry(w, _rwys(), {})
	if not w.on_runway or not w.aligned or w.rwy != "27":
		return "on the runway, aligned, into-wind 27: %s %s %s" % [w.on_runway, w.aligned, w.rwy]
	w = AtcWorld.blank()
	w.merge({"pos": Vector2(-500, 3), "hdg": 20.0, "wind_dir": 90.0, "wind_kt": 10.0}, true)
	AtcWorld.geometry(w, _rwys(), {})
	if not w.on_runway or w.aligned or w.rwy != "09":
		return "across the runway is not aligned; wind from 090 gives 09: %s %s %s" % [w.on_runway, w.aligned, w.rwy]
	w = AtcWorld.blank()
	w.merge({"pos": Vector2(0, 100), "hdg": 0.0, "wind_kt": 0.0}, true)
	AtcWorld.geometry(w, _rwys(), {"holds": [{"x": 0.0, "y": 70.0}, {"x": 0.0, "y": 900.0}], "stands": [{"x": 5.0, "y": 100.0, "ref": "12"}]})
	if w.on_runway or absf(w.rwy_dist - (100.0 - 22.5 - 3.0)) > 0.1:
		return "edge distance 74.5 m, got %.1f (on=%s)" % [w.rwy_dist, w.on_runway]
	if absf(w.hold_dist - 30.0) > 0.1 or not w.at_stand or w.where != "stand 12":
		return "hold %.1f, at_stand %s, where %s" % [w.hold_dist, w.at_stand, w.where]
	if w.rwy != "09":
		return "calm wind: first runway end wins ties, got " + w.rwy
	w = AtcWorld.blank()
	w.merge({"pos": Vector2(-4000, 20), "hdg": 90.0, "wind_dir": 270.0, "wind_kt": 10.0}, true)
	AtcWorld.geometry(w, _rwys(), {})
	if w.appr.is_empty() or w.appr.ident != "09" or absf(w.appr.along + 3000.0) > 0.1 or absf(w.appr.tail_kt - 10.0) > 0.1:
		return "approach corridor to 09, 3 km out, 10 kt tailwind: %s" % [w.appr]
	w.hdg = 270.0  # flying away from 09: not on its approach
	AtcWorld.geometry(w, _rwys(), {})
	if not w.appr.is_empty():
		return "heading away from the runway is not an approach: %s" % [w.appr]
	return ""


func test_atc_world_nearest_airport_and_context() -> String:
	var airports := [{"icao": "TEST", "ident": "TEST", "name": "Test Aerodrome", "type": "small_airport", "x": 0.0, "y": 0.0},
		{"icao": "", "ident": "IN-1", "name": "Heli", "type": "heliport", "x": 100.0, "y": 0.0},
		{"icao": "FAR1", "ident": "FAR1", "name": "Far", "type": "medium_airport", "x": 50000.0, "y": 0.0}]
	var env := AtcWorld.make_env(airports, {"TEST": _coms("twr")}, _rwys(), {})
	if AtcWorld.nearest_airport(env, Vector2(300, 0), 8000.0).get("icao", "") != "TEST":
		return "nearest airport with a runway (heliports have none)"
	if not AtcWorld.nearest_airport(env, Vector2(30000, 0), 8000.0).is_empty():
		return "nothing within the ground range"
	return ""


func test_atc_panel_placement_avoids_busy_regions() -> String:
	var vp := Vector2(1280, 720)
	var size := Vector2(360, 420)
	var free := AtcLayout.place(size, vp, AtcLayout.reserved(vp))
	if free != Vector2(8, 64):
		return "free screen: top-left first, got %s" % free
	var busy := AtcLayout.reserved(vp) + [Rect2(0, 60, 420, 600)]
	var right := AtcLayout.place(size, vp, busy)
	if Rect2(right, size).intersects(Rect2(0, 60, 420, 600)) or right.x < 400:
		return "left busy: should move to the right, got %s" % right
	for i in 3:  # whatever is busy, the panel stays on screen and clear of the notification region
		var p := AtcLayout.place(size, vp, busy + [Rect2(vp.x - 420, 0, 420, 700), Rect2(0, 400, 1280, 320)])
		if p.x < 0 or p.y < 0 or p.x + size.x > vp.x or p.y + size.y > vp.y:
			return "placement off screen: %s" % p
	for res in [Vector2(1280, 720), Vector2(1920, 1080)]:
		var q := AtcLayout.place(size, res, AtcLayout.reserved(res))
		for r in AtcLayout.reserved(res):
			if Rect2(q, size).intersects(r):
				return "%s: overlaps the flight bar / notifications at %s" % [res, q]
	return ""


func test_atc_transcript_and_options_widgets() -> String:
	var t := AtcTranscript.new()
	add_child(t)
	t.show_log([{"kind": "pilot", "who": "You", "text": "Tower, VT-FSM [x]"}, {"kind": "atc", "who": "Pune Tower", "text": "VT-FSM, cleared"},
		{"kind": "system", "who": "(radio)", "text": "No reply"}], 8)
	var plain := t.get_parsed_text()
	t.free()
	if not plain.contains("You: Tower, VT-FSM [x]") or not plain.contains("Pune Tower: VT-FSM, cleared") or not plain.contains("No reply"):
		return "transcript text: " + plain
	var box := AtcOptionsBox.new()
	add_child(box)
	var n := box.get_child_count()
	box.free()
	return "" if n >= 3 else "options box has %d children" % n


func test_atc_voice_is_silent_when_off() -> String:
	var v := AtcVoice.new()
	v.speak({"kind": "atc", "spoken": "test"})  # must not crash without a voice / with the option off
	return ""
