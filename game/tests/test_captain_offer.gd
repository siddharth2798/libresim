extends Node
## The Captain Pack prompt (ui/menu/captain_offer.gd) and its wiring on the start screen (ui/menu/captain_watch.gd).
## Rules of the detection: tests/test_captain_detect.gd. Scratch paths only: never the real input_bindings.json or options.cfg.

const SCRATCH := "user://test_captain_offer_bindings.json"
const PADS := [{"id": 0, "name": "Thrustmaster TCA Sidestick X Copilot", "guid": "g-stick"}, {"id": 1, "name": "Thrustmaster TCA Q-Eng 1&2", "guid": "g-quad"}]

var _keep := {}
var _screen: Control
var _offer: CaptainOffer


func _begin(state := "") -> void:
	if _keep.is_empty():
		UserOptions.get_v("captain_pack")
		_keep = {"state": UserOptions._v.get("captain_pack", ""), "override": Session.interactive_override, "skip": Session.skip_menu,
			"save": Session.save_path, "setup": Session.setup.duplicate(true)}
	Session.interactive_override = 0
	Session.skip_menu = false
	Session.save_path = "user://_captain_offer_test.json"
	UserOptions._v["captain_pack"] = state
	CaptainDetect.bindings_path = SCRATCH
	CaptainDetect.pads_provider = func(): return PADS
	_clean()


func _clean() -> void:
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


func teardown() -> void:
	for n in [_offer, _screen]:
		if n != null and is_instance_valid(n):
			n.free()
	_offer = null
	_screen = null
	if _keep.is_empty():
		return
	UserOptions._v["captain_pack"] = _keep.state
	Session.interactive_override = _keep.override
	Session.skip_menu = _keep.skip
	Session.save_path = _keep.save
	Session.setup = _keep.setup
	CaptainDetect.pads_provider = Callable()
	CaptainDetect.bindings_path = InputBindings.PATH
	_keep = {}
	_clean()
	Session.end_lesson()


func _offer_node() -> CaptainOffer:
	_offer = CaptainOffer.new()
	_offer.bindings_path = SCRATCH
	add_child(_offer)
	return _offer


func _answer_with(btn: String) -> Array:
	var m := _offer_node()
	var got := []
	m.chosen.connect(func(w): got.append(w))
	(m.get(btn) as Button).pressed.emit()
	(m.get(btn) as Button).pressed.emit()  # a second press must not answer twice
	return got


func test_prompt_text_and_buttons() -> String:
	_begin()
	var m := _offer_node()
	if m.use_btn.text != "Use the Captain Pack profile" or m.later_btn.text != "Not now" or m.never_btn.text != "Don't ask again":
		return "buttons: %s / %s / %s" % [m.use_btn.text, m.later_btn.text, m.never_btn.text]
	if not m.body_label.text.contains("Reset: Airbus Captain Pack") or not m.body_label.text.contains("A320 and the C172"):
		return "body: %s" % m.body_label.text
	if CaptainOffer.body_text("Linux") != CaptainOffer.BODY + "\nLinux numbering is not verified for this hardware." \
			or CaptainOffer.body_text("macOS") != CaptainOffer.BODY or CaptainOffer.body_text("Windows").contains("Linux"):
		return "the Linux line belongs to Linux only"
	return ""


func test_prompt_focus_ring_and_escape() -> String:
	_begin()
	var m := _offer_node()
	var got := []
	m.chosen.connect(func(w): got.append(w))
	m.use_btn.grab_focus()  # the deferred grab of _ready has not run in a headless test
	if get_viewport().gui_get_focus_owner() != m.use_btn:
		return "focus should start on the filled Use button"
	var ring := [m.use_btn, m.later_btn, m.never_btn]
	for i in 3:
		var b: Button = ring[i]
		if b.get_node(b.focus_next) != ring[(i + 1) % 3] or b.get_node(b.focus_previous) != ring[(i + 2) % 3]:
			return "Tab ring broken at %s" % b.text
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE
	e.pressed = true
	m._input(e)
	return "" if got == ["later"] and CaptainDetect.state() == "" else "Esc should be Not now: %s, state '%s'" % [got, CaptainDetect.state()]


func test_use_applies_the_profile_to_the_scratch_file() -> String:
	_begin()
	InputBindings.save_to(InputBindings.defaults("joystick"), SCRATCH)
	var rev := int(Props.get_v("input/bindings_rev", 0))
	var got := _answer_with("use_btn")
	if got != ["use"]:
		return "signals %s" % [got]
	if not CaptainDetect.applied(InputBindings.load_from(SCRATCH)):
		return "the scratch file should hold the Captain Pack table"
	if CaptainDetect.state() != "applied" or int(Props.get_v("input/bindings_rev", 0)) != rev + 1:
		return "state '%s', revision bumped by %d" % [CaptainDetect.state(), int(Props.get_v("input/bindings_rev", 0)) - rev]
	return ""


func test_later_and_never() -> String:
	_begin()
	InputBindings.save_to(InputBindings.defaults("joystick"), SCRATCH)
	var rev := int(Props.get_v("input/bindings_rev", 0))
	var got := _answer_with("later_btn")
	if got != ["later"] or CaptainDetect.state() != "" or CaptainDetect.applied(InputBindings.load_from(SCRATCH)):
		return "Not now stores nothing and changes nothing: %s, state '%s'" % [got, CaptainDetect.state()]
	_offer.free()
	got = _answer_with("never_btn")
	if got != ["never"] or CaptainDetect.state() != "declined":
		return "Don't ask again stores declined: %s, state '%s'" % [got, CaptainDetect.state()]
	if CaptainDetect.applied(InputBindings.load_from(SCRATCH)) or int(Props.get_v("input/bindings_rev", 0)) != rev:
		return "Not now / Don't ask again must not touch the bindings"
	return ""


# ---- start screen ---------------------------------------------------------------------------

func _start() -> Control:
	var s: Control = load("res://ui/menu/start_screen.tscn").instantiate()
	add_child(s)
	s.dry_run = true
	_screen = s
	return s


func test_start_screen_offers_once() -> String:
	_begin()
	var s := _start()
	var w: CaptainWatch = s.captain_watch
	if w == null or w.auto:
		return "the watch should exist and stay manual in a test run"
	if not w.check() or w.offer == null or w.offer.get_parent() != s:
		return "first check should show the prompt on the start screen"
	if w.check() or s.get_children().filter(func(c): return c is CaptainOffer).size() != 1:
		return "never a second prompt while it is open"
	var open: CaptainOffer = w.offer
	open.later_btn.pressed.emit()
	if w.offer != null or not open.is_queued_for_deletion():
		return "the prompt should close after an answer"
	if w.check():
		return "once per launch, even after Not now"
	return ""


func test_start_screen_waits_for_pads_and_modals() -> String:
	_begin()
	var s := _start()
	var w: CaptainWatch = s.captain_watch
	CaptainDetect.pads_provider = func(): return []
	if w.check() or w.shown:
		return "no pads, no prompt, and it is not used up"
	CaptainDetect.pads_provider = func(): return PADS  # the pad shows up a moment later
	s.go("controls")
	if w.check():
		return "not over the Controls page"
	s.go("flight")
	s._confirm = FlyConfirm.make(["x"] as Array[String])
	s.add_child(s._confirm)
	if w.check():
		return "not while the Fly anyway question is open"
	s._close_confirm()
	s._confirm = null
	s.go("home")
	return "" if w.check() else "pad plugged in on the home screen should show the prompt"


func test_start_screen_silent_when_answered_or_applied() -> String:
	_begin("declined")
	var s := _start()
	if s.captain_watch.check():
		return "declined: no prompt"
	s.free()
	_begin("applied")
	s = _start()
	if s.captain_watch.check():
		return "applied: no prompt"
	s.free()
	_begin("")
	InputBindings.save_to(InputBindings.defaults(InputProfiles.CAPTAIN_PACK), SCRATCH)
	s = _start()
	if s.captain_watch.check() or CaptainDetect.state() != "applied":
		return "a table that already is the Captain Pack: no prompt, state applied (is '%s')" % CaptainDetect.state()
	return ""


func test_watch_polls_for_five_seconds_then_stops() -> String:
	_begin()
	var s := _start()
	var w: CaptainWatch = s.captain_watch
	CaptainDetect.pads_provider = func(): return []
	w.set_process(true)
	w._process(0.0)
	w._process(1.0)  # still looking
	CaptainDetect.pads_provider = func(): return PADS  # SDL lists the pad 2 s after start
	w._process(1.0)
	if not w.shown or w.is_processing():
		return "the poll should show the prompt when the pad appears and then stop (shown %s)" % w.shown
	var w2 := CaptainWatch.new()
	w2.host = s
	CaptainDetect.pads_provider = func(): return []
	w2.set_process(true)
	for i in 6:
		w2._process(1.0)
	var ok := not w2.is_processing() and not w2.shown
	w2.free()
	return "" if ok else "the poll should stop after %s s with no pad" % CaptainWatch.POLL_S
