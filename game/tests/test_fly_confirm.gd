extends Node
## The "Fly anyway?" dialog (ui/menu/fly_confirm.gd) and its wiring in the start screen (start_screen.gd _fly):
## a ready setup flies at once, a "bad" one asks first. Logic of the checks: tests/test_setup_checks.gd.
## The start screen runs with dry_run (it counts the flight but does not load the flight scene).

var _keep := {}
var _screen: Control


func _setup(aircraft := "c172", extra := {}) -> Dictionary:
	var s := Session.DEFAULT.duplicate(true)
	s.aircraft = aircraft
	s.wind_kt = 0.0
	s.gust_kt = 0.0
	s.visibility_m = 20000.0
	if aircraft == "a320":
		s.fuel_gal = 12000.0  # total kg
		s.cabin_kg = 6000.0
		s.cargo_kg = 1000.0
	for k in extra:
		s[k] = extra[k]
	return s


func test_fly_confirm_lists_exactly_the_reasons_and_emits() -> String:
	var reasons: Array[String] = ["Crosswind 25 kt, above 15 kt", "CG outside the envelope"]
	var m := FlyConfirm.make(reasons)
	add_child(m)
	var got := []
	m.confirmed.connect(func(): got.append("confirmed"))
	m.cancelled.connect(func(): got.append("cancelled"))
	var err := ""
	var shown := m.reason_labels.map(func(l): return l.text.trim_prefix("•  "))
	if shown != reasons:
		err = "dialog lists %s" % [shown]
	elif m.go_back_btn.text != "Go back" or not m.fly_btn.text.begins_with("Fly anyway"):
		err = "buttons: %s / %s" % [m.go_back_btn.text, m.fly_btn.text]
	else:
		m.go_back_btn.pressed.emit()
		m.fly_btn.pressed.emit()
		if got != ["cancelled", "confirmed"]:
			err = "signals %s" % [got]
	m.free()
	return err


func test_fly_confirm_escape_is_go_back_and_focus_starts_there() -> String:
	var m := FlyConfirm.make(["x"] as Array[String])
	add_child(m)
	var got := []
	m.cancelled.connect(func(): got.append("cancelled"))
	m.confirmed.connect(func(): got.append("confirmed"))
	m.go_back_btn.grab_focus()  # the deferred grab in _ready has not run in a headless test
	var err := ""
	if get_viewport().gui_get_focus_owner() != m.go_back_btn:
		err = "focus should be on Go back"
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.pressed = true
	m._input(e)
	if err == "" and got != ["cancelled"]:
		err = "Esc should cancel: %s" % [got]
	m.free()
	return err


# ---- Fly paths of the start screen ---------------------------------------------------------

func _open_flight() -> Control:
	_keep = {"setup": Session.setup.duplicate(true), "skip": Session.skip_menu, "save": Session.save_path, "override": Session.interactive_override}
	Session.skip_menu = false
	Session.save_path = "user://_setup_checks_test.json"
	Session.interactive_override = 0  # tests never write the player's files
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


func test_fly_goes_straight_through_when_ready() -> String:
	var s := _open_flight()
	Session.setup = _setup("c172", {"airport": "ZZZZ"})  # no runway data: only the weight and weather checks can ask
	s._fly()
	if s.flights_started != 1 or s._confirm != null:
		return "a ready setup should fly at once (started %d, dialog %s)" % [s.flights_started, s._confirm]
	Session.setup.visibility_m = 800.0  # a warning only
	s._fly()
	if s.flights_started != 2 or s._confirm != null:
		return "low visibility must not ask"
	return ""


func test_fly_asks_on_bad_and_flies_only_on_confirm() -> String:
	var s := _open_flight()
	Session.setup = _setup("c172", {"airport": "ZZZZ", "fuel_gal": 20.0, "copilot_kg": 120.0, "rear_kg": 200.0, "baggage_kg": 54.0})
	s._fly()
	if s._confirm == null or s.flights_started != 0:
		return "an over-weight setup should ask first (dialog %s, started %d)" % [s._confirm, s.flights_started]
	var asked: FlyConfirm = s._confirm
	var want := SetupChecks.reasons(SetupChecks.checks(Session.setup))
	if asked.reasons != want or asked.reason_labels.size() != want.size():
		return "dialog reasons %s, expected %s" % [asked.reasons, want]
	s._fly()  # Ctrl+Enter while it is open
	if s.flights_started != 0:
		return "a second Fly while the dialog is open must not fly"
	asked.go_back_btn.pressed.emit()
	if s._confirm != null or s.flights_started != 0:
		return "Go back should close the dialog and not fly"
	s._fly()
	s._confirm.fly_btn.pressed.emit()
	if s._confirm != null or s.flights_started != 1:
		return "Fly anyway should fly (started %d)" % s.flights_started
	return ""


func test_fly_dialog_takes_the_keys_and_esc_is_go_back() -> String:
	var s := _open_flight()
	Session.setup = _setup("c172", {"airport": "ZZZZ", "fuel_gal": 20.0, "copilot_kg": 120.0, "rear_kg": 200.0, "baggage_kg": 54.0})
	var f: Control = s.screen("flight")
	s._fly()
	var before: int = f.cur
	var k := InputEventKey.new()
	k.keycode = KEY_3
	k.pressed = true
	get_viewport().push_input(k)
	if f.cur != before:
		return "a step key must not reach the setup behind the dialog"
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.pressed = true
	get_viewport().push_input(e)
	if s._confirm != null or s.flights_started != 0:
		return "Esc should close the dialog (Go back)"
	return ""
