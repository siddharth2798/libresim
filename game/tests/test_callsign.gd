extends Node
## The call sign / registration (core/callsign.gd, ui/menu/callsign_field.gd) and the Aircraft step that carries it
## (ui/menu/aircraft_page.gd, aircraft_details.gd): what an untouched call sign is, that a typed one survives a change of
## aircraft, validation, the painter plan of both aircraft, the field's binding / sync / signal, the "Full specification"
## overlay and the over-weight message. Tests never write the player's files.

var _keep := {}


func _begin(aircraft := "c172", extra := {}) -> void:
	_keep = {"setup": Session.setup, "override": Session.interactive_override}
	Session.interactive_override = 0
	Session.setup = Session.DEFAULT.duplicate(true)
	Session.setup.aircraft = aircraft
	Session.apply_payload_defaults(AircraftDef.load_def(aircraft))
	Session.setup.merge(extra, true)


func teardown() -> void:
	if not _keep.is_empty():
		Session.setup = _keep.setup
		Session.interactive_override = _keep.override
		_keep = {}


func _type(f: CallsignField, text: String) -> void:  # what typing into the field does
	f.edit.text = text
	f.edit.text_changed.emit(text)


func _page() -> Control:
	var p: Control = load("res://ui/menu/aircraft_page.gd").new()
	add_child(p)
	return p


# ---------------------------------------------------------------- the pure rules

func test_clean_upper_case_dash_and_invalid() -> String:
	for c in [["vt-abc", "VT-ABC"], [" n172sp ", "N172SP"], ["vt abc", "VTABC"], ["VT-ABCDE", "VT-ABCDE"], ["", ""], ["V", ""],
			["VT-ABCDEF", ""], ["VT--ABC", ""], ["VT_ABC", ""], ["ab", ""], ["<b>x", ""]]:
		if Callsign.clean(c[0]) != c[1]:
			return "clean('%s') = '%s', wanted '%s'" % [c[0], Callsign.clean(c[0]), c[1]]
	return ""


func test_filter_typing_keeps_only_letters_digits_dash_and_caps_the_length() -> String:
	for c in [["vt-abc", "VT-ABC"], ["v t!a$b", "VTAB"], ["", ""], ["abcdefghijkl", "ABCDEFGH"], ["ü-1", "-1"]]:
		if Callsign.filter_typing(c[0]) != c[1]:
			return "filter_typing('%s') = '%s'" % [c[0], Callsign.filter_typing(c[0])]
	if Callsign.problem("V") == "" or Callsign.problem("") != "" or Callsign.problem("VT-ABC") != "":
		return "problem(): a half-typed text has a reason, empty and valid have none"
	return ""


func test_untouched_default_follows_the_aircraft_and_a_typed_one_stays() -> String:
	_begin("c172")
	if Callsign.typed() != "" or not Callsign.is_untouched() or Callsign.effective(AircraftDef.current()) != "VT-LBR":
		return "untouched C172 = VT-LBR, got '%s'" % Callsign.effective(AircraftDef.current())
	Session.setup.aircraft = "a320"
	if Callsign.effective(AircraftDef.current()) != "VT-ZZA":
		return "untouched call sign follows the aircraft to the A320: '%s'" % Callsign.effective(AircraftDef.current())
	if not Callsign.store("vt-sid") or Callsign.is_untouched():
		return "store a typed call sign"
	for id in ["c172", "a320", "c172"]:
		Session.setup.aircraft = id
		if Callsign.effective(AircraftDef.current()) != "VT-SID":
			return "a typed call sign stays on %s: '%s'" % [id, Callsign.effective(AircraftDef.current())]
	if Callsign.store("!!") or Callsign.typed() != "VT-SID":
		return "an invalid text is refused and changes nothing"
	if not Callsign.store("") or Callsign.typed() != "" or Callsign.effective(AircraftDef.current()) != "VT-LBR":
		return "an empty text goes back to the aircraft's own"
	return ""


func test_a_default_of_an_aircraft_without_a_registration_is_the_last_resort() -> String:
	var def := AircraftDef.make("t", {"id": "t"}, "res://aircraft/c172")
	return "" if Callsign.default_of(def) == Callsign.FALLBACK and Callsign.default_of(null) == Callsign.FALLBACK else "fallback"


func test_legacy_options_call_sign_moves_once() -> String:
	for c in [["", "VT-SID", "VT-SID"], ["", "VT-FSM", ""], ["", "junk!!", ""], ["VT-ABC", "VT-SID", ""], ["", "", ""], ["", "n172sp", "N172SP"]]:
		if Callsign.legacy_to_adopt(c[0], c[1]) != c[2]:
			return "legacy_to_adopt(%s) = '%s'" % [c.slice(0, 2), Callsign.legacy_to_adopt(c[0], c[1])]
	return ""


# ---------------------------------------------------------------- the data and the painter

func test_a320_registration_is_a_call_sign_with_vt_zza_as_default() -> String:
	var sec := AircraftDef.load_def("a320").section("registration")
	var c := AircraftDef.load_def("c172").section("registration")
	if sec.get("source") != "callsign" or sec.get("text") != "VT-ZZA" or sec.has("baked"):
		return "A320 registration: %s" % [sec.keys()]
	if c.get("source") != "callsign" or c.get("text") != "VT-LBR" or c.get("baked") != "4X-CHV":
		return "C172 registration: source %s text %s baked %s" % [c.get("source"), c.get("text"), c.get("baked")]
	return ""


func test_typed_call_sign_changes_the_registration_plan_of_both_aircraft() -> String:
	_begin("a320")
	for id in ["a320", "c172"]:
		Session.setup.aircraft = id
		var sec := AircraftDef.load_def(id).section("registration")
		var own := RegistrationPaint.plan(sec, RegistrationPaint.text_for(sec))
		Callsign.store("vt-abc")
		var typed := RegistrationPaint.plan(sec, RegistrationPaint.text_for(sec))
		Callsign.store("")
		if own.is_empty() or own.size() != typed.size() or typed[0].text != "VT-ABC" or own[0].text != Callsign.default_of(AircraftDef.load_def(id)):
			return "%s: untouched '%s', typed '%s'" % [id, own[0].text if not own.is_empty() else "-", typed[0].text if not typed.is_empty() else "-"]
		if typed.any(func(s): return s.text != "VT-ABC") or typed[0].box != own[0].box:
			return "%s: every target carries the typed text in the same boxes" % id
	return ""


func test_untouched_registration_plan_and_the_baked_number() -> String:
	_begin("c172")
	var def := AircraftDef.load_def("c172")
	var sec := def.section("registration")
	if not RegistrationPaint.is_baked(sec, "4x-chv") or RegistrationPaint.is_baked(sec, RegistrationPaint.text_for(sec)):
		return "the C172's baked number is 4X-CHV, its default VT-LBR is painted"
	Callsign.store("4X-CHV")
	var baked := PaintPipeline.plan(def, RegistrationPaint.text_for(sec), {})
	Callsign.store("")
	if not baked.is_empty():
		return "typing the number the atlas carries repaints nothing: %s" % [baked.map(func(a): return a.rel)]
	# the A320 atlas carries no number at all (tools/24_a320_textures.py): its default is painted like any other
	Session.setup.aircraft = "a320"
	var a := AircraftDef.load_def("a320")
	var plan := PaintPipeline.plan(a, RegistrationPaint.text_for(a.section("registration")), {})
	return "" if plan.size() == 1 and plan[0].steps.size() == 2 else "A320 default plan: %s" % [plan]


func test_atc_call_sign_follows_the_same_rule() -> String:
	_begin("c172")
	if AtcSession.callsign() != "VT-LBR":
		return "untouched C172 radio call sign: %s" % AtcSession.callsign()
	Session.setup.callsign = "vt-sid"
	if AtcSession.callsign() != "VT-SID" or AtcSession.radio_callsign() != "VT-SID":
		return "typed: %s / %s" % [AtcSession.callsign(), AtcSession.radio_callsign()]
	Session.setup.callsign = ""
	Session.setup.aircraft = "a320"
	if AtcSession.callsign() != "VT-ZZA" or not AtcSession.radio_callsign().begins_with("Skyline"):
		return "A320: tail %s, radio %s (an airliner is called by its airline name)" % [AtcSession.callsign(), AtcSession.radio_callsign()]
	return ""


func test_every_valid_call_sign_fits_every_registration_box() -> String:
	var font := ThemeDB.fallback_font
	for id in AircraftDef.list_ids():
		var sec := AircraftDef.load_def(id).section("registration")
		for text in ["A1B", "N172SP", "VT-ABC", "VT-ABCDE", "WWWWWWWW"]:
			if Callsign.clean(text) == "" and text != "WWWWWWWW":
				return "'%s' should be valid" % text
			var src := Vector2i(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, RegistrationPaint.FONT_PX).ceil())
			for st in RegistrationPaint.plan(sec, text):
				var g := src if st.rotate % 180 == 0 else Vector2i(src.y, src.x)
				var r := RegistrationPaint.fit(st.box, st.align, g)
				if not st.box.encloses(r) or r.size.x < 8 or r.size.y < 8:
					return "%s '%s' in %s: %s" % [id, text, st.box, r]
	return ""


# ---------------------------------------------------------------- the field

func test_field_stores_a_valid_call_sign_and_emits() -> String:
	_begin("c172")
	var f := CallsignField.new().setup("Registration")
	add_child(f)
	var got := []
	f.callsign_changed.connect(func(v): got.append(v))
	if f.edit.text != "" or f.edit.placeholder_text != "VT-LBR":
		return "untouched: text '%s' placeholder '%s'" % [f.edit.text, f.edit.placeholder_text]
	_type(f, "vt abc")
	if Session.setup.callsign != "VTABC" or f.edit.text != "VTABC" or got != ["VTABC"]:
		return "typed 'vt abc': stored '%s', shown '%s', signals %s" % [Session.setup.callsign, f.edit.text, got]
	_type(f, "vt-sid")
	if Session.setup.callsign != "VT-SID" or f.edit.text != "VT-SID" or got.back() != "VT-SID":
		return "typed 'vt-sid': %s %s" % [Session.setup.callsign, f.edit.text]
	_type(f, "")
	var cleared: bool = Session.setup.callsign == "" and got.back() == ""
	f.free()
	return "" if cleared else "clearing goes back to untouched: '%s' %s" % [Session.setup.callsign, got]


func test_field_half_typed_text_is_not_stored_and_reverts() -> String:
	_begin("c172")
	Session.setup.callsign = "VT-SID"
	var f := CallsignField.new()
	add_child(f)
	_type(f, "V")
	var hint: String = f._hint.text
	var warned: bool = hint == CallsignField.WARN_TEXT
	var kept: bool = Session.setup.callsign == "VT-SID"
	f.edit.focus_exited.emit()
	var back: String = f.edit.text
	var hint_back: String = f._hint.text
	f.free()
	if not warned or not kept:
		return "half typed: hint '%s', stored '%s'" % [hint, Session.setup.callsign]
	return "" if back == "VT-SID" and hint_back.begins_with("Painted on the tail") else "revert: '%s' / '%s'" % [back, hint_back]


func test_two_fields_stay_in_sync_and_follow_the_aircraft() -> String:
	_begin("c172")
	var a := CallsignField.new()
	var b := CallsignField.new()
	add_child(a)
	add_child(b)
	_type(a, "vt-sid")
	var synced: bool = b.edit.text == "VT-SID"
	_type(b, "")
	var back: bool = a.edit.text == "" and a.edit.placeholder_text == "VT-LBR"
	Session.setup.aircraft = "a320"
	a.refresh()
	b.refresh()
	var a320: bool = a.edit.placeholder_text == "VT-ZZA" and b.edit.placeholder_text == "VT-ZZA" and a._hint.text.contains("Skyline")
	a.free()
	b.free()
	if not synced or not back or not a320:
		return "sync %s, clear %s, A320 placeholder %s" % [synced, back, a320]
	return ""


# ---------------------------------------------------------------- the Aircraft step

func test_aircraft_page_carries_the_call_sign_field_for_both_aircraft() -> String:
	_begin("c172")
	var p := _page()
	var err := ""
	if not p.callsign is CallsignField or not p.callsign.is_inside_tree():
		err = "no CallsignField on the page"
	elif p.callsign.edit.placeholder_text != "VT-LBR":
		err = "C172 placeholder %s" % p.callsign.edit.placeholder_text
	else:
		p.choose_id("a320")
		if p.callsign.edit.placeholder_text != "VT-ZZA":
			err = "A320 placeholder %s" % p.callsign.edit.placeholder_text
		_type(p.callsign, "vt-sid")
		p.choose_id("c172")
		if Session.setup.callsign != "VT-SID" or p.callsign.edit.text != "VT-SID":
			err = "a typed call sign stays after switching aircraft: %s / %s" % [Session.setup.callsign, p.callsign.edit.text]
	p.free()
	return err


func test_details_overlay_opens_shows_the_specification_and_closes() -> String:
	_begin("a320")
	var p := _page()
	var d: AircraftDetails = p._details
	var err := ""
	if d.visible or d.opened:
		err = "the overlay starts closed"
	p._details_btn.pressed.emit()
	if err == "" and (not d.visible or not d.opened):
		err = "Full specification opens it"
	var txt := " ".join(d.find_children("*", "Label", true, false).map(func(l): return l.text))
	if err == "" and (not txt.contains("Airbus") or not txt.contains("Registration: VT-ZZA") or d._grid.get_child_count() < 2 * 4):
		err = "the overlay has the description, the registration note and the specification rows: %d cells" % d._grid.get_child_count()
	if err == "" and not d.top_level:
		err = "the overlay is a top-level control, it takes no room in the page"
	var closed := []
	d.closed.connect(func(): closed.append(true))
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	d._input(esc)
	if err == "" and (d.visible or d.opened or closed.size() != 1):
		err = "Esc closes it"
	p._show_details(true)
	p._show_details(false)
	if err == "" and d.visible:
		err = "_show_details(false) closes it"
	p.free()
	return err


func test_over_weight_message_is_on_the_page_and_names_the_check() -> String:
	_begin("c172", {"fuel_gal": 20.0, "rear_kg": 200.0, "baggage_kg": 54.0, "copilot_kg": 120.0})
	var p := _page()
	var items := SetupChecks.checks(Session.setup, p.NO_RUNWAY).filter(func(c): return c.step == "aircraft")
	var err := ""
	if items.is_empty():
		err = "the test setup is not over weight"
	elif not p._issue.visible or not p._issue.text.contains(items[0].text) or not p._badge.text.contains("OVER MTOW"):
		err = "over weight: issue '%s' visible %s badge '%s'" % [p._issue.text, p._issue.visible, p._badge.text]
	else:
		Session.apply_payload_defaults(AircraftDef.load_def("c172"))
		Session.setup.rear_kg = 0.0
		Session.setup.baggage_kg = 0.0
		Session.setup.copilot_kg = 0.0
		p._sliders.fuel_gal.value = 17.0
		if p._issue.visible or not p._badge.text.contains("WITHIN LIMITS"):
			err = "a normal loading shows no message: '%s' '%s'" % [p._issue.text, p._badge.text]
	p.free()
	return err
