extends "res://tests/fcu_panel_base.gd"
## The A320 autopilot disconnect controls and the autopilot failure: default keys (no clash with any keyboard binding,
## listed on the F1 card, the Controls page and the joystick list), the key and the FCU card's AP DISC button run the same
## code as the FCU AP buttons turning off (the warning rules of the autoflight: a pilot's own disconnect warns for 1.5 s, any
## other until the button is pressed again), the E/WD and PFD show the warning, the tone repeats while it lasts, and the
## "Autopilot" failure (F9 list, scheduler, saves) disconnects both autopilots and refuses engagement.

const AP_KEY := "fcu_ap_disc"
const ATHR_KEY := "fcu_athr_disc"


func _key(code: int, ctrl := false, shift := false, alt := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code as Key
	e.physical_keycode = code as Key
	e.ctrl_pressed = ctrl
	e.shift_pressed = shift
	e.alt_pressed = alt
	e.pressed = true
	return e


func _rig() -> AfRig:
	_begin()
	for k in ["environment/wind_ned", "environment/gust_pqr"]:
		Props.set_v(k, Vector3.ZERO)
	return AfRig.new(250.0, 10000.0, 0.0)


## AP1 engaged in the rig.
func _engaged(r: AfRig) -> bool:
	r.fcu("ap1", true)
	r.run(1.0)
	return Props.get_b("ap/ap1")


# ---- keys ----------------------------------------------------------------------------------------------

func test_the_disconnect_actions_have_default_keys_that_clash_with_nothing() -> String:
	var t := KeyBindings.defaults()
	var ap: Dictionary = t[AP_KEY][0]
	var athr: Dictionary = t[ATHR_KEY][0]
	if t[AP_KEY].size() != 1 or int(ap.key) != KEY_BACKSPACE or not ap.ctrl or ap.shift or ap.alt:
		return "AP disconnect should default to Ctrl+Backspace: %s" % [t[AP_KEY]]
	if t[ATHR_KEY].size() != 1 or int(athr.key) != KEY_BACKSPACE or not athr.ctrl or not athr.shift or athr.alt:
		return "A/THR disconnect should default to Ctrl+Shift+Backspace: %s" % [t[ATHR_KEY]]
	if not KeyBindings.conflicts(t).is_empty():
		return "default keys clash: %s" % [KeyBindings.conflicts(t)]
	for a in t:  # nothing else uses a Backspace chord, and the unmodified Backspace stays the taxi message key
		if a == AP_KEY or a == ATHR_KEY:
			continue
		for s in t[a]:
			if int(s.key) == KEY_BACKSPACE:
				return "%s also uses Backspace: %s" % [a, KeyBindings.describe(s)]
	var k := KeyboardControls.new()  # Shift matters on Backspace now (two bindings): each chord reaches only its own action
	k.keys = t
	k._shifted = KeyBindings.shifted_keys(t)
	var plain := _key(KEY_BACKSPACE, true)
	var shifted := _key(KEY_BACKSPACE, true, true)
	var got := [KeyBindings.matches(t, AP_KEY, plain, k._shifted), KeyBindings.matches(t, ATHR_KEY, plain, k._shifted),
		KeyBindings.matches(t, AP_KEY, shifted, k._shifted), KeyBindings.matches(t, ATHR_KEY, shifted, k._shifted)]
	k.free()
	return "" if got == [true, false, false, true] else "Ctrl+Backspace / Ctrl+Shift+Backspace matches %s" % [got]


func test_the_keys_are_on_the_f1_card_the_controls_page_and_the_joystick_list() -> String:
	var t := KeyBindings.defaults()
	var a320 := AircraftControls.for_def(AircraftDef.load_def("a320"))
	var rows: Array = ControlHelp.rows(a320, t).filter(func(r): return str(r[1]).begins_with("AP disconnect"))
	if rows.size() != 1 or not str(rows[0][0]).contains("Ctrl+Backspace") or not str(rows[0][0]).contains("Shift+Backspace"):
		return "F1 card row: %s" % [rows]
	if not ControlHelp.rows(AircraftControls.default_set(), t).filter(func(r): return str(r[1]).begins_with("AP disconnect")).is_empty():
		return "the Cessna card must not list the autopilot disconnect"
	for a in [AP_KEY, ATHR_KEY]:
		if not a320.offers(a) or not a in a320.press_keys() or not a in a320.buttons():
			return "%s is not a key and a button of the A320 (Controls page)" % a
		if AircraftControls.default_set().offers(a):
			return "the Cessna must not offer %s" % a
		if not KeyBindings.LABELS.has(a) or not InputBindings.LABELS.has(a) or not a in InputBindings.BUTTONS:
			return "%s has no label or joystick button row" % a
		for prof in ["gamepad", "joystick"]:
			if not InputBindings.defaults(prof).has(a):
				return "%s defaults have no %s entry (a button can be bound to it)" % [prof, a]
	return ""


func test_a_joystick_button_bound_to_the_disconnect_runs_the_action() -> String:
	_begin()
	for a in [AP_KEY, ATHR_KEY]:
		if not ControlSteps.handles(a):
			return "%s is not a shared press action (a joystick button press would do nothing)" % a
	Props.set_v("controls/fcu/ap_disc", false)
	Props.set_v("controls/fcu/athr_disc", false)
	ControlSteps.press(AP_KEY)
	ControlSteps.press(ATHR_KEY)
	return "" if Props.get_b("controls/fcu/ap_disc") and Props.get_b("controls/fcu/athr_disc") else "the pulses are not raised"


func test_the_key_event_raises_the_same_request_as_the_card_button() -> String:
	_begin()
	var k := KeyboardControls.new()
	k.keys = KeyBindings.defaults()
	k._shifted = KeyBindings.shifted_keys(k.keys)
	Props.set_v("controls/fcu/ap_disc", false)
	Props.set_v("controls/fcu/athr_disc", false)
	k._unhandled_key_input(_key(KEY_BACKSPACE, true))
	var ap := Props.get_b("controls/fcu/ap_disc") and not Props.get_b("controls/fcu/athr_disc")
	Props.set_v("controls/fcu/ap_disc", false)
	k._unhandled_key_input(_key(KEY_BACKSPACE, true, true))
	var athr := Props.get_b("controls/fcu/athr_disc") and not Props.get_b("controls/fcu/ap_disc")
	k._unhandled_key_input(_key(KEY_BACKSPACE))  # no modifier: the taxi message key, not the disconnect
	var plain := Props.get_b("controls/fcu/ap_disc")
	k.free()
	if not ap or not athr or plain:
		return "key chords: AP %s, A/THR %s, plain Backspace raised AP disc %s" % [ap, athr, plain]
	Props.set_v("controls/fcu/ap_disc", false)
	_new_card()
	_click("btn_ap_disc")
	return "" if Props.get_b("controls/fcu/ap_disc") else "the FCU card's AP DISC button raises no request"


# ---- behaviour ----------------------------------------------------------------------------------------

func test_the_key_disconnects_like_turning_the_ap_button_off_and_a_second_press_cancels_the_warning() -> String:
	var r := _rig()
	if not _engaged(r):
		return "AP1 did not engage"
	var n := int(Props.get_v("ap/disconnect_count", 0))
	ControlSteps.press(AP_KEY)  # what the key does
	r.run(0.2)
	if Props.get_b("ap/ap1") or Props.get_b("controls/fcu/ap1") or Props.get_b("controls/fcu/ap_disc"):
		return "the key left AP1 on or the pulse unconsumed"
	if int(Props.get_v("ap/disconnect_count", 0)) != n + 1 or not Props.get_b("ap/disconnect_warning") or not Props.get_b("ap/disconnect"):
		return "no disconnect pulse and warning after the key"
	r.run(2.0)
	if Props.get_b("ap/disconnect_warning") or Props.get_b("ap/disconnect"):
		return "a pilot's own disconnect warns for 1.5 s only"
	if not _engaged(r):  # the same disconnect by the AP1 button
		return "AP1 did not engage again"
	var by_button := int(Props.get_v("ap/disconnect_count", 0))
	r.fcu("ap1", false)
	r.run(0.2)
	if int(Props.get_v("ap/disconnect_count", 0)) != by_button + 1 or not Props.get_b("ap/disconnect_warning"):
		return "the AP1 button does not give the same disconnect (count %s, warning %s)" % [Props.get_v("ap/disconnect_count", 0), Props.get_b("ap/disconnect_warning")]
	ControlSteps.press(AP_KEY)  # second press while the warning shows: cancels it, engages nothing
	r.run(0.2)
	return "" if not Props.get_b("ap/disconnect_warning") and not Props.get_b("ap/ap1") else "a second press should cancel the warning"


func test_the_ecam_and_the_fma_show_the_warning_and_the_tone_repeats_while_it_lasts() -> String:
	var r := _rig()
	Props.set_v("fdm/wow", false)
	var w := AirlinerWarnings.new()
	add_child(w)
	w.update()
	if str(Props.get_v("ewd/warnings_text", "")).contains("AUTO FLT AP"):
		w.free()
		return "an AP message with no AP trouble"
	if not _engaged(r):
		w.free()
		return "AP1 did not engage"
	Props.set_v("failures/ap", true)  # involuntary: the warning lasts until the button is pressed
	r.run(3.0)
	w.update()
	var text := str(Props.get_v("ewd/warnings_text", ""))
	var red := Props.get_b("ewd/master_warning")
	ControlSteps.press(AP_KEY)
	r.run(0.2)
	w.update()
	var after := str(Props.get_v("ewd/warnings_text", ""))
	w.free()
	if not text.contains("AUTO FLT AP OFF") or not red:
		return "E/WD after a failure disconnect: [%s] master warning %s" % [text, red]
	if after.contains("AUTO FLT AP OFF") or not after.contains("AUTO FLT AP FAULT"):
		return "after the cancel the E/WD should keep only the fault line: [%s]" % after
	var s := Gpws.new_state()
	var tones := []
	for i in 12:  # 0.2 s steps: the edge, then every 0.6 s while the warning lasts, nothing after
		tones.append(Gpws.step(s, {"agl_ft": 5000.0, "vs_fpm": 0.0, "wow": false, "stall": false,
			"ap_disconnect_edge": i == 0, "ap_warning": i < 7}, 0.2))
	var want := ["ap", "", "", "ap", "", "", "ap", "", "", "", "", ""]
	return "" if tones == want else "cavalry charge cues %s, want %s" % [tones, want]


# ---- the Autopilot failure -----------------------------------------------------------------------------

func test_the_autopilot_failure_is_listed_for_the_airliner_only() -> String:
	_begin()
	FailureCatalog._cache.clear()
	var jet: Array = FailureCatalog.categories().filter(func(c): return c[0] == "Autopilot")
	var ids: Array = FailureCatalog.all_ids()
	var label := FailureCatalog.label("ap")
	Session.setup.aircraft = "c172"
	FailureCatalog._cache.clear()
	var gone := not "ap" in FailureCatalog.all_ids() and FailureCatalog.category_names().filter(func(c): return c == "Autopilot").is_empty()
	FailureCatalog._cache.clear()
	if jet.size() != 1 or not "ap" in ids or label == "ap":
		return "the A320 list has no labelled Autopilot failure: %s" % [jet]
	return "" if gone else "the Cessna list must not have an Autopilot failure"


func test_the_autopilot_failure_trips_when_scheduled_or_chosen_at_random() -> String:
	_begin()
	FailureCatalog._cache.clear()
	Session.setup = Session.DEFAULT.duplicate(true)
	Session.setup.aircraft = "a320"
	Session.setup.failures = {"ap": [1, 0.0]}
	Props.set_v("failures/ap", false)
	var m := FailureManager.new()
	m._ready()
	m.restart()
	var scheduled := Props.get_b("failures/ap")
	Session.setup.failures = {}
	Session.setup.random = {"enabled": true, "count": 1, "from_min": 1.0, "to_min": 2.0, "categories": ["Autopilot"]}
	m.restart()
	var pool: Array = m.armed.map(func(a): return a.id)
	m.elapsed = 130.0
	m._check()
	var random := Props.get_b("failures/ap")
	m.free()
	FailureCatalog.clear_all()
	if not scheduled:
		return "an 'at start' Autopilot failure did not trip"
	return "" if pool == ["ap"] and random else "random Autopilot failure: armed %s, tripped %s" % [pool, random]


func test_a_failed_autopilot_disconnects_both_refuses_engagement_and_the_flight_director_stays() -> String:
	var r := _rig()
	if not _engaged(r):
		return "AP1 did not engage"
	r.fcu("ap2", true)
	r.run(0.5)
	Props.set_v("failures/ap", true)
	r.run(0.5)
	if Props.get_b("ap/ap1") or Props.get_b("ap/ap2") or Props.get_b("ap/cmd/active"):
		return "an autopilot is still on after the failure"
	if not Props.get_b("ap/disconnect_warning") or int(Props.get_v("ap/disconnect_count", 0)) < 1:
		return "no warning after the failure disconnect"
	if not Props.get_b("ap/fd"):
		return "the flight director should stay"
	r.run(3.0)
	if not Props.get_b("ap/disconnect_warning"):
		return "the warning of an involuntary disconnect lasts until the button is pressed"
	r.fcu("ap1", true)
	r.fcu("ap2", true)
	r.run(0.5)
	if Props.get_b("ap/ap1") or Props.get_b("ap/ap2") or Props.get_b("controls/fcu/ap1") or Props.get_b("controls/fcu/ap2"):
		return "a press must be refused and spring back dark: ap1 %s request %s" % [Props.get_b("ap/ap1"), Props.get_b("controls/fcu/ap1")]
	Props.set_v("failures/ap", false)  # repaired: the next press engages
	r.fcu("ap1", true)
	r.run(1.0)
	return "" if Props.get_b("ap/ap1") else "AP1 did not engage after the repair"


func test_the_failure_and_its_warning_survive_a_save() -> String:
	_begin()
	Props.set_v("failures/ap", true)
	var saved := Props.dump("failures/")
	for k in saved:
		saved[k] = Situation._dec(Situation._enc(saved[k]))
	Props.set_v("failures/ap", false)
	Props.restore(saved)
	var back := Props.get_b("failures/ap")
	var logic := AfLogic.new({})
	logic.warning = true
	logic.disconnect_count = 3
	var copy := AfLogic.new({})
	copy.load_state(JSON.parse_string(JSON.stringify(logic.save_state())))
	if not "failures/" in Situation.PROP_PREFIXES or not back:
		return "failures/ap was not restored (prefix saved: %s)" % ("failures/" in Situation.PROP_PREFIXES)
	return "" if copy.warning and copy.disconnect_count == 3 else "the pending warning is lost by save and load"


func test_a_key_file_saved_before_the_defaults_existed_gets_them_but_a_chosen_empty_slot_stays() -> String:
	var path := "user://test_ap_keys.json"
	var old := KeyBindings.defaults()
	old[AP_KEY] = []
	old[ATHR_KEY] = []
	old["gear_toggle"] = []  # the player cleared this one on purpose
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "keys": old}))
	f.close()
	var v1 := KeyBindings.load_from(path)
	KeyBindings.save_to(old, path)  # saved now: version 2, the empty slots are the player's choice
	var v2 := KeyBindings.load_from(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if v1[AP_KEY].size() != 1 or v1[ATHR_KEY].size() != 1:
		return "an old file's empty disconnect slots should take the new keys: %s %s" % [v1[AP_KEY], v1[ATHR_KEY]]
	if not v1["gear_toggle"].is_empty() or not v2[AP_KEY].is_empty() or not v2[ATHR_KEY].is_empty():
		return "a cleared slot was refilled: gear %s, AP %s, A/THR %s" % [v1["gear_toggle"], v2[AP_KEY], v2[ATHR_KEY]]
	return ""
