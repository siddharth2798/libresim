extends Node
## The Free-flight chrome (ui/menu/start_flow.gd, flow_rail.gd, flow_chips.gd, flow_values.gd): the left rail with a
## live value and status per step, the footer chips, Next and the one Fly button (normal, or amber "Fly anyway" when
## SetupChecks finds a bad problem), the keys, and Fly going through the "Fly anyway?" question only when asked.
## Built headless (no layout pass); the look is checked with tests/debug_menu.tscn screenshots.
## The start screen runs with dry_run (it counts the flight but does not load the flight scene).

var _keep := {}
var _screen: Control


## A free-flight setup with nothing to complain about (no runway data at "ZZZZ": only weight and weather can ask).
func _setup(aircraft := "c172", extra := {}) -> Dictionary:
	var s := Session.DEFAULT.duplicate(true)
	s.merge(Session.WEATHER.Clear, true)
	s.aircraft = aircraft
	s.airport = "ZZZZ"
	s.wind_kt = 0.0
	s.gust_kt = 0.0
	s.time_h = 12.5
	if aircraft == "a320":
		s.fuel_gal = 8500.0  # total kg
		s.cabin_kg = 10500.0
		s.cargo_kg = 1500.0
	s.merge(extra, true)
	return s


func _over_weight() -> Dictionary:
	return {"fuel_gal": 19400.0, "cabin_kg": 14000.0, "cargo_kg": 5000.0}


func _open(setup: Dictionary) -> Control:
	_keep = {"setup": Session.setup.duplicate(true), "skip": Session.skip_menu, "save": Session.save_path, "override": Session.interactive_override}
	Session.skip_menu = false
	Session.save_path = "user://_flow_chrome_test.json"
	Session.interactive_override = 0  # tests never write the player's files
	Session.setup = setup
	var s: Control = load("res://ui/menu/start_screen.tscn").instantiate()
	add_child(s)
	s.dry_run = true
	s.go("flight")
	_screen = s
	return s


func teardown() -> void:
	if _screen != null and is_instance_valid(_screen):
		_screen.free()
	_screen = null
	if not _keep.is_empty():
		Session.setup = _keep.setup
		Session.skip_menu = _keep.skip
		Session.save_path = _keep.save
		Session.interactive_override = _keep.override
		_keep = {}
	Session.end_lesson()


func _key(code: Key, ctrl := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.ctrl_pressed = ctrl
	get_viewport().push_input(e)


func _fill(b: Button) -> Color:
	return (b.get_theme_stylebox("normal") as StyleBoxFlat).bg_color


# ---- live values (pure) ---------------------------------------------------------------------

func test_flow_values_for_the_c172() -> String:
	var s := _setup("c172", {"airport": "VABB", "runway": "27"})
	var got := {}
	for k in FlowValues.KEYS:
		got[k] = FlowValues.rail_value(k, s)
	var want := {"aircraft": "Cessna 172S · 34 gal fuel", "airport": "VABB 27", "weather": "Clear · 12:30 · wind 270/0", "failures": "0 armed", "recording": "Off"}
	if got != want:
		return "rail values %s" % [got]
	s.merge({"start": "stand", "stand": "12", "cold": true}, true)
	if FlowValues.rail_value("airport", s) != "VABB · stand 12":
		return "stand start: " + FlowValues.rail_value("airport", s)
	s.merge({"start": "air", "air_ft": 1500.0, "air_nm": 5.0}, true)
	if FlowValues.rail_value("airport", s) != "VABB · 1,500 ft · 5 nm":
		return "air start: " + FlowValues.rail_value("airport", s)
	s.merge({"start": "runway", "cold": true, "wind_kt": 8.0, "gust_kt": 15.0, "visibility_m": 1000.0}, true)
	if FlowValues.rail_value("airport", s) != "VABB 27 · cold & dark" or FlowValues.chip_text("airport", s) != "VABB 27 · cold":
		return "cold start: %s / %s" % [FlowValues.rail_value("airport", s), FlowValues.chip_text("airport", s)]
	if FlowValues.rail_value("weather", s) != "Custom · 12:30 · wind 270/8G15":  # the visibility no longer matches a preset
		return "custom weather: " + FlowValues.rail_value("weather", s)
	s.merge({"failures": {"engine": [1, 0.0], "left_brake": [0, 0.0]}, "record": true, "record_height": 1080, "record_fps": 60}, true)
	s.random.enabled = true
	if FlowValues.rail_value("failures", s) != "1 armed + random" or FlowValues.chip_text("failures", s) != "1 failure + random":
		return "failures: %s / %s" % [FlowValues.rail_value("failures", s), FlowValues.chip_text("failures", s)]
	if FlowValues.rail_value("recording", s) != "On · 1080p 60 fps" or FlowValues.chip_text("recording", s) != "● REC 1080p 60 fps":
		return "recording: %s / %s" % [FlowValues.rail_value("recording", s), FlowValues.chip_text("recording", s)]
	return ""


func test_flow_values_for_the_a320() -> String:
	var s := _setup("a320", {"airport": "VABB", "runway": "27"})
	if FlowValues.rail_value("aircraft", s) != "A320-family · 8500 kg fuel":
		return "rail: " + FlowValues.rail_value("aircraft", s)
	if FlowValues.chip_text("aircraft", s) != "A320 · 63.8 t":  # 43277 empty + 8500 + 10500 + 1500
		return "chip: " + FlowValues.chip_text("aircraft", s)
	return ""


func test_flow_levels_come_from_the_setup_checks() -> String:
	var s := _setup("a320", _over_weight())
	var list := SetupChecks.checks(s)
	var got := FlowValues.KEYS.map(func(k): return FlowValues.level(k, s, list))
	if got != ["bad", "ok", "ok", "none", "none"]:
		return "over-weight levels %s" % [got]
	if not FlowValues.tooltip("aircraft", s, list, 0).contains("Over maximum takeoff weight"):
		return "tooltip lacks the reason: " + FlowValues.tooltip("aircraft", s, list, 0)
	if FlowValues.tooltip("weather", s, list, 2).contains("Problem"):
		return "a step without a problem should list none"
	if FlowValues.fly_label(list) != "Fly anyway  ▶" or FlowValues.ready_text(list)[0] != "Check before flying":
		return "label %s / %s" % [FlowValues.fly_label(list), FlowValues.ready_text(list)]
	s = _setup("c172", {"visibility_m": 800.0, "failures": {"x": [2, 5.0]}, "record": true})
	list = SetupChecks.checks(s)
	got = FlowValues.KEYS.map(func(k): return FlowValues.level(k, s, list))
	if got != ["ok", "ok", "warn", "ok", "ok"] or FlowValues.fly_label(list) != "Fly now  ▶":
		return "warn levels %s, label %s" % [got, FlowValues.fly_label(list)]
	return ""


# ---- the rail and the chips -----------------------------------------------------------------

func test_flow_rail_entries_and_chips_each_jump_to_their_step() -> String:
	var f: Control = _open(_setup()).screen("flight")
	if f.rail.entries.size() != 5 or f.chips.chips.size() != 5:
		return "rail %d entries, %d chips" % [f.rail.entries.size(), f.chips.chips.size()]
	for i in 5:
		f.show_step((i + 2) % 5)  # start somewhere else, then jump
		f.rail.entries[i].pressed.emit()
		if f.cur != i or f.rail.current != i or not f.pages[i].visible:
			return "rail entry %d: step %d, highlighted %d" % [i + 1, f.cur + 1, f.rail.current + 1]
		f.show_step((i + 3) % 5)
		f.chips.chips[i].pressed.emit()
		if f.cur != i or f.rail.current != i:
			return "chip %d: step %d" % [i + 1, f.cur + 1]
	return ""


func test_flow_rail_shows_the_live_value_status_and_current_step() -> String:
	var f: Control = _open(_setup("a320", _over_weight())).screen("flight")
	f.refresh_chrome()
	var r: Control = f.rail
	if r._values[0].text != "A320-family · 19400 kg fuel" or r._dots[0].level != "bad" or r._dots[1].level != "ok" or r._dots[3].level != "none":
		return "rail: %s, dots %s %s %s" % [r._values[0].text, r._dots[0].level, r._dots[1].level, r._dots[3].level]
	if r.ready_title.text != "Check before flying":
		return "ready box: " + r.ready_title.text
	if not r.entries[0].tooltip_text.contains("Over maximum takeoff weight") or not f.chips.chips[0].tooltip_text.contains("Over maximum takeoff weight"):
		return "the rail and the chip should list the reason"
	if f.chips.chips[0].text != "A320 · 81.7 t" or f.chips._dots[0].level != "bad":
		return "chip: %s / %s" % [f.chips.chips[0].text, f.chips._dots[0].level]
	var here: Color = r.entries[0].get_theme_stylebox("normal").bg_color
	if here.a < 0.1 or r.entries[1].get_theme_stylebox("normal").bg_color.a > 0.0:
		return "only the current step should be highlighted"
	return ""


func test_flow_next_names_the_next_step_and_is_hidden_on_the_last() -> String:
	var f: Control = _open(_setup()).screen("flight")
	var want := ["Airport & start", "Weather & time", "Failures", "Recording"]
	for i in 4:
		f.show_step(i)
		if not f.primary_btn.visible or not f.primary_btn.text.contains(want[i]) or f.primary_btn.text.contains("optional"):
			return "step %d: Next is '%s' (visible %s)" % [i + 1, f.primary_btn.text, f.primary_btn.visible]
	f.show_step(4)
	if f.primary_btn.visible or not f.fly_btn.visible:
		return "on the last step Next is hidden and Fly stays (Next %s, Fly %s)" % [f.primary_btn.visible, f.fly_btn.visible]
	return ""


# ---- Fly ------------------------------------------------------------------------------------

func test_flow_fly_is_amber_anyway_when_bad_and_normal_once_fixed() -> String:
	var s := _open(_setup("a320", _over_weight()))
	var f: Control = s.screen("flight")
	f.refresh_chrome()
	if f.fly_btn.disabled or not f.fly_btn.text.begins_with("Fly anyway") or _fill(f.fly_btn) != MenuTheme.WARN:
		return "bad setup: Fly '%s' disabled %s fill %s" % [f.fly_btn.text, f.fly_btn.disabled, _fill(f.fly_btn)]
	Session.setup.merge(_setup("a320"), true)  # fix the load
	f.pages[0].changed.emit()
	if not f.fly_btn.text.begins_with("Fly now") or _fill(f.fly_btn) != MenuTheme.ACCENT:
		return "fixed setup: Fly '%s' fill %s" % [f.fly_btn.text, _fill(f.fly_btn)]
	for i in 5:
		f.show_step(i)
		if not f.fly_btn.visible:
			return "Fly should show on step %d" % [i + 1]
	return ""


func test_flow_chips_and_rail_follow_a_page_change() -> String:
	var f: Control = _open(_setup("c172", {"airport": "VABB", "runway": "27"})).screen("flight")
	f.refresh_chrome()
	Session.setup.wind_kt = 12.0
	Session.setup.gust_kt = 20.0
	f.pages[2].changed.emit()
	if f.chips.chips[2].text != "Clear · 12:30 · 270/12G20" or f.rail._values[2].text != "Clear · 12:30 · wind 270/12G20":
		return "weather after a change: '%s' / '%s'" % [f.chips.chips[2].text, f.rail._values[2].text]
	Session.setup.record = true
	f.pages[4].changed.emit()
	if f.chips.chips[4].text.find("REC") < 0 or f.rail._dots[4].level != "ok":
		return "recording after a change: '%s' / %s" % [f.chips.chips[4].text, f.rail._dots[4].level]
	Session.setup.fuel_gal = 5.0  # a change nobody announced: the frame loop notices it
	f._process(0.0)
	if f.rail._values[0].text != "Cessna 172S · 10 gal fuel":
		return "an unannounced setup change was not picked up: " + f.rail._values[0].text
	return ""


func test_flow_keys_step_and_fly() -> String:
	var s := _open(_setup())
	var f: Control = s.screen("flight")
	var flown := [0]
	for c in f.fly_requested.get_connections():
		f.fly_requested.disconnect(c.callable)
	f.fly_requested.connect(func(): flown[0] += 1)
	_key(KEY_4)
	if f.cur != 3 or f.rail.current != 3:
		return "key 4: step %d" % [f.cur + 1]
	_key(KEY_PAGEDOWN)
	_key(KEY_PAGEDOWN)  # already on the last step: stays
	if f.cur != 4:
		return "Page Down twice from step 4 should end on 5, at %d" % [f.cur + 1]
	_key(KEY_PAGEUP)
	if f.cur != 3:
		return "Page Up should step back, at %d" % [f.cur + 1]
	_key(KEY_ENTER, true)
	if flown[0] != 1:
		return "Ctrl+Enter should fly (%d)" % flown[0]
	_key(KEY_ESCAPE)
	if f.cur != 2:
		return "Esc should step back, at %d" % [f.cur + 1]
	f.show_step(0)
	_key(KEY_ESCAPE)
	if s.cur != "home":
		return "Esc on the first step should leave for home, at '%s'" % s.cur
	return ""


func test_flow_fly_asks_only_when_the_setup_is_bad() -> String:
	var s := _open(_setup("a320", _over_weight()))
	var f: Control = s.screen("flight")
	f.refresh_chrome()
	f.fly_btn.pressed.emit()
	if s._confirm == null or s.flights_started != 0:
		return "a bad setup should ask first (dialog %s, started %d)" % [s._confirm, s.flights_started]
	s._confirm.go_back_btn.pressed.emit()
	Session.setup.merge(_setup("a320"), true)
	f.pages[0].changed.emit()
	f.fly_btn.pressed.emit()
	if s._confirm != null or s.flights_started != 1:
		return "a ready setup should fly at once (dialog %s, started %d)" % [s._confirm, s.flights_started]
	return ""


# ---- structure ------------------------------------------------------------------------------

func test_flow_focus_ring_and_order_are_kept() -> String:
	var f: Control = _open(_setup()).screen("flight")
	for b in f.rail.entries + f.chips.chips + [f.fly_btn, f.primary_btn, f.back_btn]:
		if b.has_theme_stylebox_override("focus"):
			return "a button overrides 'focus', which would hide the ring"
	if not f.chips is HFlowContainer:
		return "chips should wrap (HFlowContainer)"
	var rail_i: int = f.rail.get_parent().get_index()
	var foot_i: int = f.footer.get_parent().get_index()
	if rail_i != 0 or foot_i <= rail_i or f.rail.get_index() != 0 or f.content.get_parent() != f.rail.get_parent().get_child(1):
		return "tree order should be rail, page, footer"
	var order := [f.back_btn.get_index(), f.chips.get_index(), f.primary_btn.get_index(), f.fly_btn.get_index()]
	if not (order[0] < order[1] and order[1] < order[2] and order[2] < order[3]) or f.summary.visible:  # (the hidden summary label sits between)
		return "footer order Back, chips, Next, Fly: %s" % [order]
	var r: FlowRail = f.rail
	if r.entries[0].focus_neighbor_top != r.entries[0].get_path() or r.entries[4].focus_neighbor_bottom != r.entries[4].get_path() \
			or r.entries[2].focus_neighbor_top != r.entries[1].get_path() or r.entries[2].focus_neighbor_bottom != r.entries[3].get_path():
		return "Up / Down should stay inside the rail"
	return ""
