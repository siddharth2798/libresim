extends Node
## Home screen shortcuts (ui/menu/home_shortcuts.gd, home_screen.gd, start_screen.gd): "Fly again" (the last
## Free-flight setup, user://last_flight.json) and "Continue: next lesson" (training progress) are shown only
## when their data exists, say what they are, use the same readiness path as Fly now, and survive a damaged save.
## Every file here is a scratch file: Session.save_path and TrainingLogic.save_path are redirected, saving is off.

const Home := preload("res://ui/menu/home_screen.gd")
const SAVE := "user://_home_shortcuts_last_flight.json"
const STARS := "user://_home_shortcuts_training.json"

var _keep := {}
var _nodes: Array[Node] = []


func _begin() -> void:
	if not _keep.is_empty():
		return
	_keep = {"setup": Session.setup, "skip": Session.skip_menu, "save": Session.save_path, "override": Session.interactive_override,
		"stars": TrainingLogic.save_path}
	Session.setup = Session.DEFAULT.duplicate(true)
	Session.skip_menu = false
	Session.save_path = SAVE
	Session.interactive_override = 0  # tests never write the player's files
	TrainingLogic.save_path = STARS
	_remove()


func teardown() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	if _keep.is_empty():
		return
	_remove()
	Session.end_lesson()
	Session.setup = _keep.setup
	Session.skip_menu = _keep.skip
	Session.save_path = _keep.save
	Session.interactive_override = _keep.override
	TrainingLogic.save_path = _keep.stars
	_keep = {}


func _remove() -> void:
	for p in [SAVE, STARS]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)


func _save_flight(extra := {}) -> void:
	var s := Session.DEFAULT.duplicate(true)
	s.airport = "ZZZZ"  # no runway data: only the weight and weather rules can ask
	s.runway = "09"
	s.wind_kt = 0.0
	for k in extra:
		s[k] = extra[k]
	_write(SAVE, JSON.stringify(s))


func _home() -> Control:
	var h: Control = Home.new()
	add_child(h)
	_nodes.append(h)
	return h


func _screen() -> Control:
	var s: Control = load("res://ui/menu/start_screen.tscn").instantiate()
	add_child(s)
	s.dry_run = true
	_nodes.append(s)
	return s


func _key(code: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	get_viewport().push_input(e)


func test_shortcuts_absent_without_data() -> String:
	_begin()
	var h := _home()
	for c in h._cards:
		if c.action_btn.visible:
			return "no shortcut may show without history (%s)" % c.action_btn.text
	if not HomeShortcuts.last_flight().is_empty() or HomeShortcuts.has_saved_flight():
		return "no file, no saved flight"
	if h._hint.text != Home.HINT:
		return "the hint should not name keys that do nothing: %s" % h._hint.text
	return ""


func test_fly_again_shown_with_what_it_is() -> String:
	_begin()
	_save_flight({"aircraft": "a320", "airport": "VOMM", "runway": "09", "cold": true, "fuel_gal": 8000.0})
	var h := _home()
	var c: Button = h._cards[0]
	if not c.action_btn.visible or c.action_btn.text != "Fly again  (R)":
		return "Fly again should show with its key: '%s' visible %s" % [c.action_btn.text, c.action_btn.visible]
	var info := HomeShortcuts.fly_again_info(HomeShortcuts.last_flight())
	if info.title != "A320-family · VOMM runway 09 · cold & dark":
		return "title is '%s'" % info.title
	if c._box_lines[1].text != info.title or c._box_lines[0].text != "Last flight":
		return "the card box should show the flight: '%s'" % c._box_lines[1].text
	if not c._box.visible:
		return "the box with the last flight should be visible"
	if not h._hint.text.contains("R fly again"):
		return "the bottom hint should name the key: " + h._hint.text
	if h._cards[1].action_btn.visible:
		return "no training progress, no Continue"
	return ""


func test_start_texts_for_runway_stand_and_air() -> String:
	var rw := HomeShortcuts.where({"airport": "VAJJ", "start": "runway", "runway": "27"})
	var st := HomeShortcuts.where({"airport": "VABB", "start": "stand", "stand": "12"})
	var gate := HomeShortcuts.where({"airport": "VABB", "start": "stand", "stand": ""})
	var air := HomeShortcuts.where({"airport": "VAJJ", "start": "air", "air_ft": 1500.0, "air_nm": 5.0})
	if rw != "VAJJ runway 27" or st != "VABB stand 12" or gate != "VABB gate" or air != "VAJJ · 1,500 ft · 5 nm final":
		return "texts: %s | %s | %s | %s" % [rw, st, gate, air]
	return ""


func test_continue_shown_with_the_next_lesson() -> String:
	_begin()
	_write(STARS, JSON.stringify({"takeoff": 2}))
	var h := _home()
	var c: Button = h._cards[1]
	if not c.action_btn.visible or c.action_btn.text != "Continue: Cruise  (C)":
		return "Continue should name the lesson after the last one flown: '%s'" % c.action_btn.text
	if c._box_lines[1].text != "Takeoff ★★☆" or c._box_lines[0].text != "1 of 3 lessons flown":
		return "progress box: '%s' / '%s'" % [c._box_lines[0].text, c._box_lines[1].text]
	if h._cards[0].action_btn.visible:
		return "no saved flight, no Fly again"
	if not h._hint.text.contains("C continue"):
		return "the bottom hint should name the key: " + h._hint.text
	return ""


func test_continue_follows_the_last_lesson_flown_and_ends_with_the_final_one() -> String:
	var list := HomeShortcuts.lessons("c172")
	if list.size() < 3:
		return "expected at least three lessons, got %d" % list.size()
	var ids: Array = list.map(func(l): return l.id)
	if not HomeShortcuts.next_lesson(list, {}).is_empty():
		return "nothing flown: no Continue"
	if HomeShortcuts.next_lesson(list, {ids[0]: 0}).get("id", "") != "":
		return "0 stars is not flown"
	if HomeShortcuts.next_lesson(list, {ids[0]: 1}).get("id", "") != ids[1]:
		return "after the first comes the second"
	if HomeShortcuts.next_lesson(list, {ids[1]: 3}).get("id", "") != ids[2]:
		return "the last lesson flown counts, not the first unflown (flown only the second): next is the third"
	if HomeShortcuts.next_lesson(list, {ids[0]: 3, ids[1]: 1, ids[2]: 1}).get("id", "") != "":
		return "nothing comes after the last lesson"
	var all := {}
	for id in ids:
		all[id] = 1
	_begin()
	_write(STARS, JSON.stringify(all))
	var h := _home()
	var c: Button = h._cards[1]
	if c.action_btn.visible:
		return "all lessons flown: no Continue button"
	if c._box_lines[0].text != "%d of %d lessons flown" % [ids.size(), ids.size()]:
		return "progress should still show: '%s'" % c._box_lines[0].text
	return ""


func test_damaged_stars_file_means_no_continue() -> String:
	_begin()
	_write(STARS, "[1, 2, oops")
	var h := _home()
	if h._cards[1].action_btn.visible:
		return "a damaged progress file must not offer Continue"
	return ""


func test_malformed_last_flight_is_ignored_or_repaired() -> String:
	_begin()
	for text in ["", "not json at all", "[1, 2, 3]", "{}", '{"aircraft": 5, "wind_kt": "x"}', '{"airport": "VAJJ"', "null"]:
		_write(SAVE, text)
		if HomeShortcuts.has_saved_flight() or not HomeShortcuts.last_flight().is_empty():
			return "'%s' must count as no saved flight" % text
		var h := _home()
		var shown: bool = h._cards[0].action_btn.visible
		h.free()
		if shown:
			return "'%s' must not show Fly again" % text
	# some good keys among bad values: the bad ones fall back to the defaults, an unknown aircraft to the default aircraft
	_write(SAVE, '{"aircraft": "zz_gone", "airport": "ZZZZ", "wind_kt": "gale", "fuel_gal": 12, "failures": {}, "mystery": 1}')
	var s := HomeShortcuts.last_flight()
	if s.is_empty() or s.aircraft != AircraftDef.DEFAULT_ID or s.airport != "ZZZZ" or float(s.wind_kt) != Session.DEFAULT.wind_kt:
		return "repaired setup wrong: %s %s %s" % [s.get("aircraft"), s.get("airport"), s.get("wind_kt")]
	if s.has("mystery") or float(s.fuel_gal) != 12.0:
		return "unknown keys are dropped and good numbers kept"
	var h2 := _home()
	if not h2._cards[0].action_btn.visible or not h2._cards[0]._box_lines[1].text.begins_with("Cessna 172S"):
		return "an unknown aircraft shows the default one: '%s'" % h2._cards[0]._box_lines[1].text
	return ""


func test_reading_the_save_leaves_the_live_setup_alone() -> String:
	_begin()
	_save_flight({"airport": "VABB", "wind_kt": 22.0})
	Session.setup.airport = "VAJJ"
	Session.setup.wind_kt = 3.0
	var before := Session.setup.duplicate(true)
	var s := HomeShortcuts.last_flight()
	if s.airport != "VABB" or float(s.wind_kt) != 22.0:
		return "the saved setup was not read: %s" % s.airport
	if Session.setup != before:
		return "reading the last flight must not change Session.setup"
	return ""


func test_fly_again_ready_setup_flies_at_once() -> String:
	_begin()
	_save_flight({"airport": "ZZZZ", "visibility_m": 800.0})  # low visibility only warns
	Session.setup.airport = "VAJJ"
	var s := _screen()
	var h: Control = s.screen("home")
	h.fly_again.emit()
	if s.flights_started != 1 or s._confirm != null:
		return "a ready saved setup should fly at once (started %d)" % s.flights_started
	if Session.setup.airport != "ZZZZ" or Session.training != "":
		return "the flight should use the saved setup (airport %s)" % Session.setup.airport
	return ""


func test_fly_again_asks_when_the_saved_setup_is_bad() -> String:
	_begin()
	_save_flight({"aircraft": "a320", "fuel_gal": 19400.0, "cabin_kg": 14000.0, "cargo_kg": 5000.0})
	Session.setup.airport = "VAJJ"
	var s := _screen()
	var h: Control = s.screen("home")
	h._cards[0].action_btn.pressed.emit()
	if s._confirm == null or s.flights_started != 0:
		return "an over-weight A320 save must ask first (dialog %s, started %d)" % [s._confirm, s.flights_started]
	var want := SetupChecks.reasons(SetupChecks.checks(HomeShortcuts.last_flight()))
	if want.is_empty() or s._confirm.reasons != want:
		return "dialog lists %s, expected %s" % [s._confirm.reasons, want]
	h.fly_again.emit()
	if s.flights_started != 0:
		return "pressing again while the question is open must not fly"
	s._confirm.go_back_btn.pressed.emit()
	if s._confirm != null or s.flights_started != 0:
		return "Go back should close the question and not fly"
	if Session.setup.aircraft != "c172" or Session.setup.airport != "VAJJ":
		return "Go back should put the live setup back (%s, %s)" % [Session.setup.aircraft, Session.setup.airport]
	h.fly_again.emit()
	s._confirm.fly_btn.pressed.emit()
	if s.flights_started != 1 or Session.setup.aircraft != "a320":
		return "Fly anyway should fly the saved A320 (started %d, %s)" % [s.flights_started, Session.setup.aircraft]
	return ""


func test_fly_again_with_a_damaged_save_does_not_crash_or_fly_wrongly() -> String:
	_begin()
	_write(SAVE, '{"aircraft": "zz_gone", "airport": "ZZZZ", "wind_kt": [1], "start": 7}')
	var s := _screen()
	var h: Control = s.screen("home")
	h.fly_again.emit()
	if s.flights_started != 1 or Session.setup.aircraft != AircraftDef.DEFAULT_ID or Session.setup.start != "runway":
		return "a damaged save should fly with defaults for the bad parts (started %d, %s, %s)" % [s.flights_started, Session.setup.aircraft, Session.setup.start]
	_write(SAVE, "garbage")
	h.fly_again.emit()  # the file went bad after the screen was built: nothing happens
	return "" if s.flights_started == 1 else "garbage must not start a flight"


func test_continue_starts_the_next_lesson() -> String:
	_begin()
	_write(STARS, JSON.stringify({"takeoff": 3}))
	var s := _screen()
	var h: Control = s.screen("home")
	h._cards[1].action_btn.pressed.emit()
	if s.lessons_started != 1 or Session.training != "cruise" or Session.assist != "full":
		return "Continue should start Cruise with full help (started %d, '%s', %s)" % [s.lessons_started, Session.training, Session.assist]
	return ""


func test_keys_r_and_c_use_the_shortcuts_only_when_shown() -> String:
	_begin()
	var h := _home()
	var got := []
	h.fly_again.connect(func(): got.append("fly"))
	h.continue_lesson.connect(func(id): got.append(id))
	_key(KEY_R)
	_key(KEY_C)
	if not got.is_empty():
		return "R and C do nothing without data: %s" % [got]
	_save_flight()
	_write(STARS, JSON.stringify({"takeoff": 1}))
	h.refresh()
	_key(KEY_R)
	_key(KEY_C)
	if got != ["fly", "cruise"]:
		return "R then C should fly again and continue: %s" % [got]
	_key(KEY_1)
	_key(KEY_2)
	if got.size() != 2 or get_viewport().gui_get_focus_owner() != h._cards[1]:
		return "1 and 2 still pick the cards"
	return ""


func test_focus_order_is_cards_then_shortcuts_then_links() -> String:
	_begin()
	var h := _home()
	var order := func() -> Array:
		var seen := []
		var c: Control = h._cards[0]
		for i in 12:
			seen.append(c)
			c = c.get_node(c.focus_next)
			if c == h._cards[0]:
				break
		return seen
	var plain: Array = order.call()
	if plain != h._cards + h._more:
		return "without data: cards then links, got %d controls" % plain.size()
	_save_flight()
	_write(STARS, JSON.stringify({"takeoff": 1}))
	h.refresh()
	var full: Array = order.call()
	var want: Array = h._cards + [h._cards[0].action_btn, h._cards[1].action_btn] + h._more
	if full != want:
		return "with data: cards, shortcuts, links; got %d controls, wanted %d" % [full.size(), want.size()]
	var down: Control = h._cards[0].get_node(h._cards[0].focus_neighbor_bottom)
	if down != h._cards[0].action_btn or h._cards[0].action_btn.get_node(h._cards[0].action_btn.focus_neighbor_bottom) != h._more[0]:
		return "Down goes card, shortcut, first link"
	if h._more[2].get_node(h._more[2].focus_neighbor_top) != h._cards[1].action_btn:
		return "Up from the last link goes to the Training shortcut"
	return ""


func test_quiet_links_still_emit_and_saved_flights_says_what_is_there() -> String:
	_begin()
	var h := _home()
	var got := []
	h.open_page.connect(func(p): got.append(p))
	for b in h._more:
		b.pressed.emit()
	if got != ["saves", "controls", "options"]:
		return "links emit %s" % [got]
	if HomeShortcuts.saves_line([]) != "No saves yet" or HomeShortcuts.saves_line([{"name": "Pune", "date": "2026-11-04 10:22"}]) != "Pune · 11-04":
		return "saves line: %s | %s" % [HomeShortcuts.saves_line([]), HomeShortcuts.saves_line([{"name": "Pune", "date": "2026-11-04 10:22"}])]
	return ""


func test_training_card_lists_every_lessons_stars() -> String:
	_begin()
	_write(STARS, JSON.stringify({"takeoff": 3, "cruise": 1}))
	var before := FileAccess.get_file_as_string(STARS)
	var h := _home()
	var c: Button = h._cards[1]
	if c.marks_text() != "Takeoff ★★★ · Cruise ★☆☆ · Landing ☆☆☆":
		return "star row: '%s'" % c.marks_text()
	if not c._marks.visible or c._marks.get_child_count() != 3:
		return "the star row should show one cell per lesson"
	var marks := HomeShortcuts.lesson_marks(HomeShortcuts.lessons("c172"), {"takeoff": 9, "cruise": -2})
	if marks.map(func(m): return m.stars) != [3, 0, 0]:
		return "stars are clamped to 0..3: %s" % [marks]
	h.refresh()  # visiting again rebuilds the row, it does not add to it
	if c._marks.get_child_count() != 3:
		return "refresh should replace the row, not grow it (%d)" % c._marks.get_child_count()
	if FileAccess.get_file_as_string(STARS) != before:
		return "showing the stars must not write the training file"
	return ""


func test_star_row_is_hidden_until_a_lesson_is_flown_and_follows_new_stars() -> String:
	_begin()
	var h := _home()
	var c: Button = h._cards[1]
	if c._marks.visible or c.marks_text() != "":
		return "no lesson flown: no star row ('%s')" % c.marks_text()
	_write(STARS, JSON.stringify({"landing": 2}))
	h.refresh()
	return "" if c._marks.visible and c.marks_text().ends_with("Landing ★★☆") else "after a flight the row should show: '%s'" % c.marks_text()


func test_home_scale_follows_the_room_and_the_links_scale_with_it() -> String:
	var big := Home.scale_for(Vector2(1920, 1080))
	var base := Home.scale_for(Vector2(1280, 720))
	var s150 := Home.scale_for(Vector2(1280, 720) / 1.5)  # 1280x720 window at UI scale 150 %
	var s200 := Home.scale_for(Vector2(1280, 720) / 2.0)
	if not is_equal_approx(base, 1.0) or not is_equal_approx(big, Home.MAX_K):
		return "design size 1.0 and a big window %.2f capped at %.1f, got %.2f / %.2f" % [big, Home.MAX_K, base, big]
	if not (s200 < s150 and s150 < 1.0 and s200 >= Home.MIN_K):
		return "a bigger UI scale leaves fewer units, so the home screen must shrink: %.2f %.2f" % [s150, s200]
	if Home.scale_for(Vector2(1000, 2000)) * Home.CARDS_W > 1000.0 - Home.MARGIN_X + 1.0:
		return "a narrow window must cap the scale so both cards fit"
	_begin()
	var h := _home()
	var t: Button = h._more[0]
	t.set_scale_k(1.0)
	var icon1: Vector2 = t._icon.custom_minimum_size
	var w1 := t.custom_minimum_size
	t.set_scale_k(0.6)
	if not t._icon.custom_minimum_size.is_equal_approx(icon1 * 0.6) or not t.custom_minimum_size.is_equal_approx(w1 * 0.6):
		return "the quiet-link icon and tile must scale below 1.0: %s vs %s" % [t._icon.custom_minimum_size, icon1 * 0.6]
	return ""
