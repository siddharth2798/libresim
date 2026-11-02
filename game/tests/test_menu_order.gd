extends Node
## Free flight step order (ui/menu/start_flow.gd): the aircraft comes first, so the airport page
## (air-start height and distance, runways long enough, stands that suit it) always shows what the
## chosen aircraft needs, with no extra step in between.

var _was_skip := false
var _keep := {}


func _open(aircraft := "c172") -> Control:
	_was_skip = Session.skip_menu
	_keep = Session.setup.duplicate(true)
	Session.skip_menu = false
	Session.setup = Session.DEFAULT.duplicate(true)
	Session.setup.aircraft = aircraft
	var s: Control = load("res://ui/menu/start_screen.tscn").instantiate()
	add_child(s)
	s.go("flight")
	return s


func _close(s: Control) -> void:
	s.free()
	Session.skip_menu = _was_skip
	Session.end_lesson()
	Session.setup = _keep


## Click this aircraft's chip on the aircraft page.
func _pick(page: Control, id: String) -> bool:
	return page.choose_id(id)


func test_menu_order_aircraft_then_airport_then_conditions() -> String:
	var s := _open()
	var f: Control = s.screen("flight")
	var names: Array = f.STEPS.map(func(st): return str(st[0]).get_slice(" (", 0))
	var err := ""
	if names != ["Aircraft", "Airport & start", "Weather & time", "Failures", "Recording"]:
		err = "step order: %s" % [names]
	elif f.cur != 0 or f.pages[0].get_script().resource_path != "res://ui/menu/aircraft_page.gd" or not f.pages[0].visible:
		err = "Free flight should open on the aircraft page (cur %d)" % f.cur
	elif f.pages[1].get_script().resource_path != "res://ui/menu/airport_page.gd":
		err = "step 2 should be the airport page"
	elif f.primary_btn.text.find("Airport") < 0 or not f.prompt.text.contains("Which aircraft"):
		err = "step 1: prompt '%s', next '%s'" % [f.prompt.text, f.primary_btn.text]
	_close(s)
	return err


func test_menu_order_aircraft_is_chosen_when_the_airport_page_shows() -> String:
	var s := _open("no_such_aircraft")  # a remembered aircraft that is gone
	var f: Control = s.screen("flight")
	var chosen: String = str(Session.setup.aircraft)
	var err := ""
	if not AircraftDef.list_ids().has(chosen):
		err = "an unknown aircraft must be replaced by a listed one, setup has '%s'" % chosen
	elif f.pages[0].selected_id() != chosen:
		err = "the aircraft page should show the setup's aircraft '%s' selected" % chosen
	_close(s)
	return err


func test_menu_order_airport_page_follows_the_aircraft_chosen_on_step_1() -> String:
	var s := _open()
	var f: Control = s.screen("flight")
	var air: Control = f.pages[1]
	var err := ""
	if not _pick(f.pages[0], "a320"):
		err = "no a320 in the aircraft list"
	else:
		f.on_primary()  # Next: the airport page, with no other step in between
		if f.cur != 1 or not air.visible:
			err = "Next from the aircraft page should show the airport page (cur %d)" % f.cur
		elif [air._alt.value, air._dist.value] != [3500.0, 11.0] or not air._air_note.text.contains("3,500 ft"):
			err = "A320 air start: %s ft, %s nm, note '%s'" % [air._alt.value, air._dist.value, air._air_note.text]
	if err == "":
		f.go_back()
		_pick(f.pages[0], "c172")
		f.on_primary()
		if [air._alt.value, air._dist.value] != [1500.0, 5.0] or not air._air_note.text.contains("1,500 ft"):
			err = "C172 air start after switching back: %s ft, %s nm, note '%s'" % [air._alt.value, air._dist.value, air._air_note.text]
	_close(s)
	return err


func test_aircraft_page_has_a_chip_and_a_picture_for_every_aircraft() -> String:
	var s := _open()
	var page: Control = s.screen("flight").pages[0]
	var err := ""
	for id in AircraftDef.list_ids():
		if not page._chips.has(id):
			err = "no chip for '%s'" % id
		elif AircraftDef.load_def(id).preview() == null:
			err = "'%s' has no preview.jpg (tests/render_aircraft_previews.gd renders it)" % id
		elif not page.choose_id(id) or page.selected_id() != id or not page._chips[id].button_pressed:
			err = "choosing '%s' did not select its chip" % id
		if err != "":
			break
	_close(s)
	return err


## The airport page is built once; after the aircraft page changes the aircraft, showing it again must re-mark the runways
## that are too short for the new aircraft and re-filter the stands.
func test_airport_page_refreshes_its_lists_for_a_new_aircraft() -> String:
	var keep := Session.setup.duplicate(true)
	Session.setup = Session.DEFAULT.duplicate(true)
	Session.setup.start = "runway"
	Session.setup.aircraft = "c172"
	var page: Control = load("res://ui/menu/airport_page.gd").new()
	add_child(page)
	var short_m := float(GroundParams.ground(AircraftDef.load_def("a320")).min_runway_m)
	var apt := {}
	for a in page._airports:
		for r in a.runways:
			if float(r.length) < short_m:
				apt = a
		if not apt.is_empty():
			break
	var err := ""
	if apt.is_empty():
		err = "no airport with a runway shorter than the A320's %d m in the data" % int(short_m)
	else:
		page._select(apt)
		var marked := func() -> int:
			var n := 0
			for i in page._rwy.item_count:
				n += 1 if page._rwy.get_item_text(i).contains("too short") else 0
			return n
		if marked.call() != 0:
			err = "the C172 should find no runway too short at %s" % apt.icao
		Session.setup.aircraft = "a320"  # what the aircraft page does
		page.hide()
		page.show()
		if err == "" and marked.call() == 0:
			err = "after switching to the A320 the runways of %s that are too short are not marked" % apt.icao
	page.free()
	Session.setup = keep
	return err
