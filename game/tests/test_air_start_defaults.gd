extends Node
## The "In the air" start follows the aircraft: aircraft/air_start.gd (aircraft.json start.air and the
## derived defaults), Session.apply_air_defaults and the air_custom flag, the command line, lessons,
## the start-screen controls. The real flight scene is checked by tests/debug_air_start.tscn.


func _keep() -> Dictionary:
	return {"setup": Session.setup.duplicate(true), "skip": Session.skip_menu, "training": Session.training}


func _restore(k: Dictionary) -> void:
	Session.end_lesson()
	Session.setup = k.setup
	Session.skip_menu = k.skip
	Session.training = k.training


func _fresh(aircraft: String) -> void:
	Session.setup = Session.DEFAULT.duplicate(true)
	Session.setup.aircraft = aircraft


func _vals() -> Array:
	return [Session.setup.air_ft, Session.setup.air_nm, Session.setup.air_kt, Session.setup.air_custom]


func _bare(start: Dictionary, limits := {}) -> AircraftDef:  # an aircraft built in code
	return AircraftDef.make("x", {"start": start, "limits": limits}, "res://aircraft/c172")


func test_air_start_c172_defaults_are_unchanged() -> String:
	var a := AircraftDef.load_def("c172").air_start()
	if [a.alt_ft, a.dist_nm, a.kias, a.gear, a.flaps] != [1500.0, 5.0, 90.0, "down", 0]:
		return "c172 start %s" % [a]
	if a.limits != {"alt_ft": [300.0, 12000.0], "dist_nm": [1.0, 25.0]}:
		return "c172 limits %s" % [a.limits]
	if [Session.DEFAULT.air_ft, Session.DEFAULT.air_nm, Session.DEFAULT.air_kt] != [1500.0, 5.0, 90.0] or Session.DEFAULT.air_custom:
		return "Session.DEFAULT must stay 1500 / 5 / 90, not custom"
	return ""


func test_air_start_a320_defaults_come_from_its_data() -> String:
	var a := AircraftDef.load_def("a320").air_start()
	if [a.alt_ft, a.dist_nm, a.kias, a.gear, a.flaps] != [3500.0, 11.0, 205.0, "up", 0]:
		return "a320 start %s" % [a]
	if a.limits != {"alt_ft": [1000.0, 15000.0], "dist_nm": [3.0, 40.0]}:
		return "a320 limits %s" % [a.limits]
	var path := rad_to_deg(atan(Units.ft_to_m(a.alt_ft) / (a.dist_nm * 1852.0)))
	if absf(path - 3.0) > 0.25:
		return "the A320 start should be on a 3 degree path, it is %.2f" % path
	return ""


func test_air_start_derived_from_the_speeds() -> String:
	var a := AirStart.of(_bare({}, {"vs1_kias": 50.0}))  # approach 65 kt: light
	if [a.kias, a.dist_nm, a.alt_ft] != [65.0, 5.0, 1600.0]:
		return "light: %s" % [a]
	a = AirStart.of(_bare({}, {"vs1_kias": 100.0}))  # approach 130 kt: 8 nm
	if [a.kias, a.dist_nm, a.alt_ft] != [130.0, 8.0, 2500.0]:
		return "medium: %s" % [a]
	a = AirStart.of(_bare({}, {"vs1_kias": 134.0}))  # approach 174 kt: 11 nm
	if [a.kias, a.dist_nm, a.alt_ft] != [175.0, 11.0, 3500.0]:
		return "airliner: %s" % [a]
	a = AirStart.of(_bare({}))  # no speeds at all: the C172 numbers with a 3 degree height
	if [a.kias, a.dist_nm, a.gear, a.flaps] != [90.0, 5.0, "down", 0]:
		return "nothing: %s" % [a]
	a = AirStart.of(_bare({"air_kt": 250.0}, {"vs1_kias": 134.0}))  # the older key is the speed
	if a.kias != 250.0 or a.dist_nm != 11.0:
		return "air_kt fallback: %s" % [a]
	a = AirStart.of(_bare({"air": {"dist_nm": 6.0}}, {"vs1_kias": 50.0}))  # a partial block: the rest derived
	if [a.dist_nm, a.alt_ft, a.kias] != [6.0, 1900.0, 65.0]:
		return "partial block: %s" % [a]
	return ""


func test_air_start_own_numbers_are_clamped_and_bad_limits_ignored() -> String:
	var a := AirStart.of(_bare({"air": {"alt_ft": 20000, "dist_nm": 0.2, "limits": {"alt_ft": [500, 9000], "dist_nm": [2, 2]}}}))
	if a.limits != {"alt_ft": [500.0, 9000.0], "dist_nm": [1.0, 25.0]}:
		return "limits: a bad pair is ignored, a good one kept: %s" % [a.limits]
	if a.alt_ft != 9000.0 or a.dist_nm != 1.0:
		return "values must lie inside the limits: %s" % [a]
	if AirStart.of(null).kias != 90.0:
		return "no aircraft: the default start"
	return ""


func test_air_start_session_follows_the_aircraft_until_the_pilot_chooses() -> String:
	var k := _keep()
	_fresh("a320")
	Session.apply_air_defaults()
	var err := ""
	if _vals() != [3500.0, 11.0, 205.0, false]:
		err = "a320 chosen: %s" % [_vals()]
	Session.setup.aircraft = "c172"
	Session.apply_air_defaults()
	if err == "" and _vals() != [1500.0, 5.0, 90.0, false]:
		err = "back to the c172: %s" % [_vals()]
	Session.setup.air_custom = true  # the pilot sets 2,000 ft, 7 nm
	Session.setup.air_ft = 2000.0
	Session.setup.air_nm = 7.0
	Session.setup.aircraft = "a320"
	Session.apply_air_defaults()
	if err == "" and _vals() != [2000.0, 7.0, 90.0, true]:
		err = "custom numbers must stay when valid: %s" % [_vals()]
	Session.setup.air_ft = 500.0
	Session.setup.air_nm = 1.0
	Session.apply_air_defaults()
	if err == "" and _vals() != [1000.0, 3.0, 90.0, true]:
		err = "custom numbers are clamped into the a320 limits: %s" % [_vals()]
	_restore(k)
	return err


func test_air_start_old_saves_without_the_flag() -> String:
	var s := {"air_ft": 1500.0, "air_nm": 5.0, "air_kt": 90.0}
	Session.legacy_air_custom(s)
	if s.air_custom:
		return "the C172 defaults in an old save are not a choice"
	for key in ["air_ft", "air_nm", "air_kt"]:
		s = {"air_ft": 1500.0, "air_nm": 5.0, "air_kt": 90.0}
		s[key] += 10.0
		Session.legacy_air_custom(s)
		if not s.air_custom:
			return "an old save with another %s was chosen by the pilot" % key
	return ""


func test_air_start_command_line() -> String:
	var k := _keep()
	var err := ""
	var cases := [
		[["--air=2000"], [2000.0, 5.0, 90.0, true]],
		[["--air"], [1500.0, 5.0, 90.0, false]],
		[["--aircraft=a320", "--air"], [3500.0, 11.0, 205.0, false]],
		[["--air", "--aircraft=a320"], [3500.0, 11.0, 205.0, false]],
		[["--aircraft=a320", "--air=8000"], [8000.0, 11.0, 205.0, true]],
		[["--aircraft=a320", "--air=250", "--air-nm=1.3", "--air-kt=140"], [250.0, 1.3, 140.0, true]],
		[["--aircraft=a320", "--air-kt=90"], [3500.0, 11.0, 90.0, true]],
		[["--aircraft=c172", "--air=950", "--air-nm=3"], [950.0, 3.0, 90.0, true]],
	]
	for c in cases:
		Session._parse_args(PackedStringArray(c[0]))
		if _vals() != c[1]:
			err = "%s -> %s, expected %s" % [c[0], _vals(), c[1]]
			break
	_restore(k)
	return err


func test_air_start_lessons_keep_their_numbers() -> String:
	var k := _keep()
	var err := ""
	for lesson in TrainingLogic.load_lessons():
		var want: Dictionary = lesson.setup
		_fresh("a320")  # a lesson is written for the c172: the aircraft switches, the numbers are the lesson's
		Session.apply_air_defaults()
		TrainingLogic.begin(lesson, "full")
		var s: Dictionary = Session.setup
		for key in ["air_ft", "air_nm", "air_kt"]:
			var expect: float = float(want[key]) if want.has(key) else float(Session.DEFAULT[key])
			if not is_equal_approx(float(s[key]), expect):
				err = "lesson %s: %s is %s, expected %s" % [lesson.id, key, s[key], expect]
		if err == "" and s.aircraft != "c172":
			err = "lesson %s did not switch to the c172 (%s)" % [lesson.id, s.aircraft]
		if err == "" and bool(s.air_custom) != (want.has("air_ft") or want.has("air_nm") or want.has("air_kt")):
			err = "lesson %s: air_custom %s" % [lesson.id, s.air_custom]
		Session.end_lesson()
		if err == "" and (Session.setup.aircraft != "a320" or _vals() != [3500.0, 11.0, 205.0, false]):
			err = "lesson %s: ending it must give back the free-flight setup, got %s %s" % [lesson.id, Session.setup.aircraft, _vals()]
		if err != "":
			break
	_restore(k)
	return err


func test_air_start_summary_text() -> String:
	var k := _keep()
	_fresh("c172")
	Session.setup.start = "air"
	Session.apply_air_defaults()
	var err := ""
	if not Session.summary().contains("1500 ft, 5 nm final"):
		err = "c172: " + Session.summary()
	Session.setup.aircraft = "a320"
	Session.apply_air_defaults()
	if err == "" and not Session.summary().contains("3500 ft, 11 nm final"):
		err = "a320: " + Session.summary()
	Session.setup.air_nm = 1.5
	if err == "" and not Session.summary().contains("1.5 nm final"):
		err = "a fractional distance must show: " + Session.summary()
	_restore(k)
	return err


func test_air_start_controls_show_the_aircraft_defaults() -> String:
	var k := _keep()
	_fresh("c172")
	Session.setup.start = "air"
	var page: Control = load("res://ui/menu/airport_page.gd").new()
	add_child(page)
	var err := ""
	if [page._alt.value, page._dist.value, page._alt.max_value, page._dist.max_value] != [1500.0, 5.0, 12000.0, 25.0]:
		err = "c172 controls: %s" % [[page._alt.value, page._dist.value, page._alt.max_value, page._dist.max_value]]
	# the aircraft page changes the aircraft; the airport page shows again
	var ap: Control = load("res://ui/menu/aircraft_page.gd").new()
	add_child(ap)
	for i in ap._list.item_count:
		if ap._list.get_item_metadata(i).get("id", "") == "a320":
			ap._list.item_selected.emit(i)
	if err == "" and Session.setup.aircraft != "a320":
		err = "the aircraft page did not select the a320"
	if err == "" and _vals() != [3500.0, 11.0, 205.0, false]:
		err = "the aircraft page must apply the air defaults: %s" % [_vals()]
	page.hide()
	page.show()
	if err == "" and [page._alt.value, page._dist.value, page._alt.min_value, page._alt.max_value, page._dist.min_value, page._dist.max_value] != [3500.0, 11.0, 1000.0, 15000.0, 3.0, 40.0]:
		err = "a320 controls: %s" % [[page._alt.value, page._dist.value, page._alt.min_value, page._alt.max_value]]
	if err == "" and (Session.setup.air_custom or not page._air_note.text.contains("3,500 ft, 11 nm")):
		err = "showing the defaults is not an edit; note '%s', custom %s" % [page._air_note.text, Session.setup.air_custom]
	page._alt.value = 4000.0  # an edit by the pilot
	if err == "" and (not Session.setup.air_custom or Session.setup.air_ft != 4000.0):
		err = "editing the height must set air_custom: %s" % [_vals()]
	Session.setup.aircraft = "c172"
	page.hide()
	page.show()
	if err == "" and (page._alt.value != 4000.0 or page._alt.max_value != 12000.0 or page._dist.value != 11.0):
		err = "the pilot's numbers stay when the aircraft changes: %s" % [_vals()]
	page.free()
	ap.free()
	_restore(k)
	return err


func test_air_start_flaps_snap_to_the_detent() -> String:
	for id in ["c172", "a320"]:
		var f := FDM.new(AircraftDef.load_def(id))
		f.fcs.flap_cmd = 2  # (the A320's detent 1 is slats only)
		f.fcs.snap_flaps()
		if f.fcs.flap_deg <= 0.0:
			return "%s: flaps at detent 2 must be out after snap_flaps (%.1f deg)" % [id, f.fcs.flap_deg]
		f.fcs.flap_cmd = 0
		f.fcs.snap_flaps()
		if f.fcs.flap_deg != 0.0:
			return "%s: detent 0 is flaps up" % id
	return ""
