extends Node
## One display name for a stand everywhere it is printed or spoken: the real ref, else the made-up "Bay 3" / "Gate 4"
## (world/stand_names.gd label / name_of / prop_text). The rail value and chip, the home shortcut, the one-line summary,
## ATC's "where" and the taxi-to-the-apron instruction (and the ATC parser that reads it), the debug property ops/stand.
## Pure, no scene. A stand with a real ref keeps what it printed before.

const STANDS := [
	{"x": 100.0, "y": 0.0, "ref": "12", "jetbridge": false},
	{"x": 0.0, "y": 0.0, "ref": "", "jetbridge": true},   # made up: Gate 1 (west-most)
	{"x": 50.0, "y": 0.0, "ref": "", "jetbridge": false},  # made up: Bay 1
	{"x": 200.0, "y": 0.0, "ref": "Bay 40", "jetbridge": false},
]


func test_label_is_one_rule() -> String:
	var want := {"12": "stand 12", "GA3": "stand GA3", "Bay 3": "Bay 3", "bay 3": "bay 3", "Gate 4": "Gate 4", "Stand B": "Stand B",
		"Bay 12 (2)": "Bay 12 (2)", "  7 ": "stand 7", "": ""}
	for k in want:
		if StandNames.label(k) != want[k]:
			return "label('%s') = '%s', want '%s'" % [k, StandNames.label(k), want[k]]
	return ""


func test_name_of_gives_the_real_ref_or_the_made_up_name() -> String:
	var got := STANDS.map(func(st): return StandNames.name_of(STANDS, st))
	if got != ["12", "Gate 1", "Bay 1", "Bay 40"]:
		return "names %s" % [got]
	if StandNames.name_of(STANDS, {"x": 5.0, "y": 5.0, "ref": "zz"}) != "":
		return "a stand that is not in the list has no name"
	# a copy of a stand (same position) is found too
	if StandNames.name_of(STANDS, STANDS[1].duplicate()) != "Gate 1":
		return "a copy of the stand should resolve by position"
	return ""


func test_rail_chip_home_and_summary_say_the_same() -> String:
	var s := Session.DEFAULT.duplicate(true)
	s.airport = "VABB"
	s.start = "stand"
	var want := {"12": ["VABB · stand 12", "VABB stand 12", "stand 12"], "Bay 3": ["VABB · Bay 3", "VABB Bay 3", "Bay 3"],
		"Gate 4": ["VABB · Gate 4", "VABB Gate 4", "Gate 4"], "": ["VABB · gate", "VABB gate", "stand (gate)"]}
	for st in want:
		s.stand = st
		var got := [FlowValues.rail_value("airport", s), HomeShortcuts.where(s), ""]
		var saved: Dictionary = Session.setup
		Session.setup = s
		got[2] = Session.summary().split(" · ")[1]
		Session.setup = saved
		if FlowValues.chip_text("airport", s) != want[st][0]:
			return "chip for '%s': %s" % [st, FlowValues.chip_text("airport", s)]
		if got != want[st]:
			return "rail / home / summary for '%s': %s, want %s" % [st, got, want[st]]
	return ""


func test_atc_where_uses_the_display_name() -> String:
	var rw := [{"airport": "T", "length": 1000.0, "width": 30.0, "ends": [{"ident": "09", "x": -500.0, "y": 0.0, "heading_true": 90.0}, {"ident": "27", "x": 500.0, "y": 0.0, "heading_true": 270.0}]}]
	var cases := {"at 100 (ref 12)": [Vector2(100.0, 3.0), "stand 12"], "at 50 (made up)": [Vector2(50.0, 3.0), "Bay 1"],
		"at 0 (made up gate)": [Vector2(0.0, 3.0), "Gate 1"], "at 200 (Bay 40)": [Vector2(200.0, 3.0), "Bay 40"]}
	for k in cases:
		var w := AtcWorld.blank()
		w.merge({"pos": cases[k][0], "hdg": 0.0, "wind_kt": 0.0}, true)
		AtcWorld.geometry(w, rw, {"stands": STANDS})
		if not w.at_stand or w.where != cases[k][1]:
			return "%s: at_stand %s, where '%s', want '%s'" % [k, w.at_stand, w.where, cases[k][1]]
	var far := AtcWorld.blank()
	far.merge({"pos": Vector2(1000.0, 500.0), "hdg": 0.0, "wind_kt": 0.0}, true)
	AtcWorld.geometry(far, rw, {"stands": STANDS})
	if far.at_stand or far.where != "the apron":
		return "away from every stand ATC still says the apron: '%s'" % far.where
	return ""


func test_taxi_to_the_apron_names_the_stand_and_atc_reads_it_back() -> String:
	var cases := {"12": "Taxi to the apron (stand 12) via B", "Bay 3": "Taxi to the apron (Bay 3) via B", "Gate 4": "Taxi to the apron (Gate 4) via B",
		"": "Taxi to the apron via B"}
	for k in cases:
		var t := GroundOps.apron_text(k, ["B"])
		if t != cases[k]:
			return "text for '%s': '%s'" % [k, t]
		var back := AtcReplies.parse_route(t)
		var spoken := StandNames.label(k)
		if str(back.stand) != spoken or str(back.via) != " via B":
			return "AtcReplies.parse_route('%s') = %s, want stand '%s'" % [t, back, spoken]
	if GroundOps.apron_text("Bay 3", []) != "Taxi to the apron (Bay 3)":
		return "no route points: " + GroundOps.apron_text("Bay 3", [])
	return ""


func test_the_debug_property_prints_the_display_name() -> String:
	var got := [StandNames.prop_text("VABB", "Bay 3", "", false), StandNames.prop_text("VABB", "12", "12", true), StandNames.prop_text("VABB", "", "7", false)]
	if got != ["VABB Bay 3", "VABB 12 (jetbridge)", "VABB 7"]:
		return "ops/stand text %s" % [got]
	var ops := AirportOps.new()
	ops.data = {"VABB": {"stands": STANDS}}
	var names := STANDS.map(func(st): return ops.stand_name("VABB", st))
	ops.free()
	return "" if names == ["12", "Gate 1", "Bay 1", "Bay 40"] else "AirportOps.stand_name %s" % [names]
