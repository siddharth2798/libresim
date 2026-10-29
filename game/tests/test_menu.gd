extends Node
## Start screen flow (ui/menu): the home screen asks Free flight or Training first, each
## choice shows only its own path, and every other page has a Back to the home screen.
## Built headless (no frames), so this checks structure and behaviour; the layout is checked
## by tests/debug_menu.gd screenshots and tests/e2e/e2e_menu.gd.

const Home := preload("res://ui/menu/home_screen.gd")

var _was_skip := false


func _open() -> Control:
	_was_skip = Session.skip_menu
	Session.skip_menu = false  # command-line options (--only=...) would otherwise skip the menu
	var s: Control = load("res://ui/menu/start_screen.tscn").instantiate()
	add_child(s)
	return s


func _close(s: Control) -> void:
	s.free()
	Session.skip_menu = _was_skip
	Session.end_lesson()


func _visible_ids(s: Control) -> Array:
	return s._screens.keys().filter(func(k): return s._screens[k].visible)


func _key(code: Key, ctrl := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.ctrl_pressed = ctrl
	get_viewport().push_input(e)


func test_menu_opens_on_the_home_screen_only() -> String:
	var s := _open()
	var err := ""
	if s.cur != "home" or _visible_ids(s) != ["home"]:
		err = "expected only the home screen, got %s / %s" % [s.cur, _visible_ids(s)]
	elif s._screens.size() != 1:
		err = "no other screen should be built yet: %s" % [s._screens.keys()]
	elif s._brand.visible:
		err = "the small top-bar logo should be hidden on the home screen"
	elif s.screen("home")._cards.size() != 2:
		err = "home needs exactly the Free flight and Training cards"
	_close(s)
	return err


func test_menu_home_choices_and_secondary_actions_emit() -> String:
	var h: Control = Home.new()
	add_child(h)
	var got := []
	h.choose.connect(func(m): got.append(m))
	h.open_page.connect(func(p): got.append(p))
	h._cards[0].pressed.emit()
	h._cards[1].pressed.emit()
	for b in h._more:
		b.pressed.emit()
	h.free()
	if got != ["flight", "training", "saves", "controls", "options"]:
		return "unexpected signals: %s" % [got]
	return ""


func test_menu_home_keys_and_remembered_choice() -> String:
	var s := _open()
	var h: Control = s.screen("home")
	var keep = UserOptions.get_v("start_mode")
	UserOptions._v["start_mode"] = "training"  # in memory only: do not touch the player's options.cfg
	h.enter()
	var err := ""
	if get_viewport().gui_get_focus_owner() != h._cards[1]:
		err = "the remembered Training card should have the focus"
	_key(KEY_1)
	if err == "" and get_viewport().gui_get_focus_owner() != h._cards[0]:
		err = "key 1 should focus Free flight"
	_key(KEY_2)
	if err == "" and get_viewport().gui_get_focus_owner() != h._cards[1]:
		err = "key 2 should focus Training"
	UserOptions._v["start_mode"] = keep
	_close(s)
	return err


func test_menu_free_flight_is_a_linear_stepper() -> String:
	var s := _open()
	s.go("flight")
	var f: Control = s.screen("flight")
	var err := ""
	if s.cur != "flight" or _visible_ids(s) != ["flight"] or not s._brand.visible:
		err = "only the flight flow should show: %s" % [_visible_ids(s)]
	elif f.pages.size() != f.STEPS.size() or f.STEPS.size() != 5:
		err = "expected 5 pages for Airport, Aircraft, Weather, Failures, Recording"
	elif f.primary_btn.text.find("Aircraft") < 0:
		err = "Next should name the next step: %s" % f.primary_btn.text
	for i in f.STEPS.size():
		f.show_step(i)
		var shown: Array = f.pages.filter(func(p): return p.visible)
		if err == "" and (shown.size() != 1 or shown[0] != f.pages[i]):
			err = "step %d should show only its own page" % [i + 1]
		if err == "" and (i == f.STEPS.size() - 1) != (f.primary_btn.text.find("FLY") >= 0):
			err = "FLY should appear on the last step only (step %d: %s)" % [i + 1, f.primary_btn.text]
	f.show_step(2)
	f.go_back()
	if err == "" and f.cur != 1:
		err = "Back should step back, at step %d" % f.cur
	f.go_back()
	f.go_back()  # on the first step: leave for the home screen
	if err == "" and s.cur != "home":
		err = "Back on the first step should return home, at %s" % s.cur
	_close(s)
	return err


func test_menu_free_flight_keys_and_fly_signal() -> String:
	var s := _open()
	s.go("flight")
	var f: Control = s.screen("flight")
	var flown := [0]
	for c in f.fly_requested.get_connections():  # the real handler would load the flight scene
		f.fly_requested.disconnect(c.callable)
	f.fly_requested.connect(func(): flown[0] += 1)
	var err := ""
	_key(KEY_3)
	if f.cur != 2:
		err = "key 3 should jump to step 3, at %d" % [f.cur + 1]
	_key(KEY_PAGEDOWN)
	if err == "" and f.cur != 3:
		err = "Page Down should step on"
	_key(KEY_PAGEUP)
	if err == "" and f.cur != 2:
		err = "Page Up should step back"
	_key(KEY_ENTER, true)
	f.show_step(f.STEPS.size() - 1)
	f.on_primary()
	if err == "" and flown[0] != 2:
		err = "Ctrl+Enter and the FLY button should each ask to fly (%d)" % flown[0]
	_key(KEY_ESCAPE)  # Esc is Back: last step -> previous step
	if err == "" and f.cur != f.STEPS.size() - 2:
		err = "Esc should step back"
	_close(s)
	return err


func test_menu_training_page_has_its_own_start_button() -> String:
	var s := _open()
	s.go("training")
	var t: Control = s.screen("training")
	var err := ""
	if _visible_ids(s) != ["training"] or s._screens.has("flight"):
		err = "Training should show alone, without the free-flight stepper"
	elif not t.primary_btn.visible or t.primary_btn.text.find("START LESSON") < 0:
		err = "the bar needs a START LESSON button"
	elif t.summary.text.find("Takeoff") < 0:
		err = "the bar should name the chosen lesson: %s" % t.summary.text
	if err == "":
		var page: Control = t.pages[0]
		var started := [false]
		for c in page.start_requested.get_connections():  # the real handler would load the flight scene
			page.start_requested.disconnect(c.callable)
		page.start_requested.connect(func(): started[0] = true)
		t.primary_btn.pressed.emit()
		if not started[0] or Session.training != "takeoff":
			err = "START LESSON should begin the takeoff lesson (training=%s)" % Session.training
	_close(s)
	return err


func test_menu_other_pages_return_home() -> String:
	var s := _open()
	var err := ""
	for id in ["saves", "controls", "options", "training"]:
		s.go(id)
		if _visible_ids(s) != [id] or s.screen(id).pages.size() != 1:
			err = "%s should show alone" % id
			break
		s.screen(id).back_btn.pressed.emit()
		if s.cur != "home":
			err = "Back on %s should return to the home screen" % id
			break
		_key(KEY_ESCAPE)  # Esc on the home screen does nothing
		if s.cur != "home":
			err = "Esc on the home screen should stay home"
			break
	_close(s)
	return err


func test_menu_cold_and_dark_exists_only_where_it_is_a_choice() -> String:
	var s := _open()
	s.go("flight")
	var p: Control = s.screen("flight").pages[0]
	var setup: Dictionary = Session.setup
	var keep := setup.duplicate(true)
	p._cur = {"stands": [{"ref": "A1"}], "runways": []}  # headless: no airport data may be loaded
	var err := ""
	setup.start = "runway"
	setup.cold = true
	p._refresh()
	if not p._cold.visible or not p._cold.button_pressed or p._cold.disabled:
		err = "runway start: the cold & dark box should be shown, enabled and keep its value"
	setup.start = "air"
	p._refresh()
	if err == "" and (p._cold.visible or setup.cold):
		err = "air start: no cold & dark control, and cold must be forced off (cold=%s)" % setup.cold
	if err == "" and p._cold.get_parent().get_children().filter(func(c): return c.visible and c is CheckBox).size() != 0:
		err = "air start: no check box should take up room"
	setup.start = "stand"
	p._refresh()
	if err == "" and (p._cold.visible or not p._stand_note.visible):
		err = "stand start: the box is replaced by the always-cold note"
	setup.start = "runway"
	p._refresh()
	if err == "" and (not p._cold.visible or p._stand_note.visible):
		err = "back on a runway: the box returns and the stand note goes"
	Session.setup = keep
	_close(s)
	return err


func test_menu_conditions_highlight_follows_the_values() -> String:
	var s := _open()
	s.go("flight")
	var page: Control = s.screen("flight").pages[2]
	var setup: Dictionary = Session.setup
	var keep := setup.duplicate(true)
	var err := ""
	setup.day_of_year = 45.0
	page._time_row.picked.emit("Noon")
	page._wind_row.picked.emit("Moderate")
	page._weather_row.picked.emit("Overcast")
	if page._time_row.selected() != "Noon" or page._wind_row.selected() != "Moderate" or page._weather_row.selected() != "Overcast":
		err = "clicked presets should be highlighted: %s / %s / %s" % [page._time_row.selected(), page._wind_row.selected(), page._weather_row.selected()]
	if err == "":  # sliders, the month and the other rows change the values: highlights follow
		page._sl.time_h.value = 13.0
		page._sl.gust_kt.value = 21.0
		page._sl.precip.value = 0.5
		if page._time_row.selected() != "" or page._wind_row.selected() != "" or page._weather_row.selected() != "" or setup.weather != "Custom":
			err = "manual values should clear all three highlights (weather=%s)" % setup.weather
	if err == "":
		page._time_row.picked.emit("Dawn")
		page._month.item_selected.emit(5)  # June: sunrise moves, so 'Dawn' no longer matches
		if page._time_row.selected() != "":
			err = "Dawn highlight should clear when the month moves sunrise"
	if err == "":  # leaving and re-entering (or loading a setup) restores the highlights from the values
		page._time_row.select("")
		page._wind_row.select("")
		setup.merge({"time_h": 9.0, "wind_kt": 6.0, "gust_kt": 0.0, "turbulence": 0.1}, true)
		s.screen("flight").show_step(3)  # leave the page, then come back to it
		s.screen("flight").show_step(2)
		if page._time_row.selected() != "Morning" or page._wind_row.selected() != "Light":
			err = "re-entering should restore Morning / Light, got %s / %s" % [page._time_row.selected(), page._wind_row.selected()]
	Session.setup = keep
	_close(s)
	return err


func test_menu_fly_now_everywhere_and_optional_steps_are_named() -> String:
	var s := _open()
	s.go("flight")
	var f: Control = s.screen("flight")
	var flown := [0]
	for c in f.fly_requested.get_connections():  # the real handler would load the flight scene
		f.fly_requested.disconnect(c.callable)
	f.fly_requested.connect(func(): flown[0] += 1)
	var err := ""
	for i in f.STEPS.size():
		f.show_step(i)
		if err == "" and f.fly_btn.visible != (i < f.STEPS.size() - 1):
			err = "step %d: Fly now should show on every step but the last (the main button is FLY there)" % [i + 1]
	if err == "" and (not str(f.STEPS[3][0]).contains("optional") or not str(f.STEPS[4][0]).contains("optional")):
		err = "Failures and Recording should be named optional: %s / %s" % [f.STEPS[3][0], f.STEPS[4][0]]
	f.show_step(0)
	f.fly_btn.pressed.emit()
	if err == "" and flown[0] != 1:
		err = "Fly now should ask to fly (%d)" % flown[0]
	_close(s)
	return err


func test_menu_more_weather_is_collapsed_and_remembered() -> String:
	var s := _open()
	s.go("flight")
	var page: Control = s.screen("flight").pages[2]
	var err := ""
	if page._more.visible or page._more_btn.text.find("More") < 0:
		err = "'More weather' should start collapsed"
	page._more_btn.pressed.emit()
	if err == "" and not page._more.visible:
		err = "the toggle should open the advanced sliders"
	for k in ["cloud_cover", "visibility_m", "turbulence", "convection", "storms", "icing", "gust_kt", "time_rate"]:
		if err == "" and not page._sl.has(k):
			err = "advanced slider %s must still exist" % k
	page._more_btn.pressed.emit()
	if err == "" and page._more.visible:
		err = "the toggle should close it again"
	_close(s)
	return err
