extends Node
## The airport search box (ui/menu/airport_search.gd): the filter on ICAO / name / city, the keys (Up, Down, Enter, Esc),
## picking, and the text the box shows for the chosen airport.

var _boxes: Array = []


func teardown() -> void:
	for b in _boxes:
		if is_instance_valid(b):
			b.free()
	_boxes = []


func _items() -> Array:
	var raw := [["VABB", "Chhatrapati Shivaji Maharaj International Airport", "Mumbai"], ["VAJJ", "Juhu Aerodrome", "Mumbai (Juhu)"],
		["VAPO", "Pune International Airport", "Pune"], ["VOCI", "Cochin International Airport", "Kochi"], ["VOCL", "Calicut International Airport", "Kozhikode"]]
	return raw.map(func(r): return {"id": r[0], "ident": r[0], "name": r[1], "city": r[2], "text": "%s  %s · %s" % r, "note": "", "short": false})


func _box() -> AirportSearch:
	var b := AirportSearch.new()
	add_child(b)
	b.size = Vector2(400, 36)
	b.set_items(_items())
	b.set_current("VABB")
	_boxes.append(b)
	return b


func _key(b: Control, k: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	b.gui_input.emit(e)


func _ids(list: Array) -> Array:
	return list.map(func(e): return e.id)


func test_airport_search_filters_on_icao_name_and_city() -> String:
	var it := _items()
	var cases := {"": ["VABB", "VAJJ", "VAPO", "VOCI", "VOCL"], "mumbai": ["VABB", "VAJJ"], "KOZHI": ["VOCL"], "calicut": ["VOCL"],
		"pune int": ["VAPO"], "international": ["VABB", "VAPO", "VOCI", "VOCL"], "zzz": [], "  vapo ": ["VAPO"], "juhu mumbai": ["VAJJ"]}
	for q in cases:
		var got := _ids(AirportSearch.filter(it, q))
		if got != cases[q]:
			return "filter '%s': %s, want %s" % [q, got, cases[q]]
	return ""


func test_airport_search_icao_matches_come_first() -> String:
	var it := [{"id": "B", "ident": "ZZZ", "name": "xxa town", "city": ""}, {"id": "A", "ident": "XXA", "name": "Bar", "city": ""},
		{"id": "C", "ident": "AXX", "name": "Qux", "city": ""}]
	var got := _ids(AirportSearch.filter(it, "xx"))
	return "" if got == ["A", "C", "B"] else "ranking: ICAO prefix, ICAO contains, then name: %s" % [got]


func test_airport_search_shows_the_chosen_airport_and_lists_all_when_opened() -> String:
	var b := _box()
	if b.text != "VABB · Chhatrapati Shivaji Maharaj International":
		return "box text '%s'" % b.text
	b.set_current("VOCI")
	if b.text != "VOCI · Cochin International":
		return "set_current did not change the text: '%s'" % b.text
	b._open()  # the box shows the chosen airport: opening it lists them all, not a filter on that text
	return "" if b.shown.size() == 5 and b.is_open() else "opened with %d rows, open %s" % [b.shown.size(), b.is_open()]


func test_airport_search_typing_filters_and_keys_pick() -> String:
	var b := _box()
	var got := []
	b.picked.connect(func(id): got.append(id))
	b.text = "mum"
	b.text_changed.emit("mum")
	if _ids(b.shown) != ["VABB", "VAJJ"] or not b.is_open():
		return "typing 'mum': %s open %s" % [_ids(b.shown), b.is_open()]
	_key(b, KEY_DOWN)
	if b._active != 1:
		return "Down should move to the second row (%d)" % b._active
	_key(b, KEY_DOWN)
	if b._active != 0:
		return "Down at the last row wraps to the first (%d)" % b._active
	_key(b, KEY_UP)
	if b._active != 1:
		return "Up from the first wraps to the last (%d)" % b._active
	_key(b, KEY_ENTER)
	if got != ["VAJJ"]:
		return "Enter on the second row picked %s" % [got]
	if b.is_open() or b.text != "VAJJ · Juhu":
		return "after a pick the list closes and the box shows the airport: open %s, '%s'" % [b.is_open(), b.text]
	return ""


func test_airport_search_escape_closes_and_restores_the_text() -> String:
	var b := _box()
	var got := []
	b.picked.connect(func(id): got.append(id))
	b.text = "pun"
	b.text_changed.emit("pun")
	if not b.is_open():
		return "typing should open the list"
	_key(b, KEY_ESCAPE)
	if b.is_open() or b.text != "VABB · Chhatrapati Shivaji Maharaj International" or not got.is_empty():
		return "Esc: open %s, text '%s', picks %s" % [b.is_open(), b.text, got]
	return ""


func test_airport_search_enter_with_no_match_picks_nothing() -> String:
	var b := _box()
	var got := []
	b.picked.connect(func(id): got.append(id))
	b.text = "qqq"
	b.text_changed.emit("qqq")
	_key(b, KEY_ENTER)
	return "" if b.shown.is_empty() and got.is_empty() else "no match: shown %d, picks %s" % [b.shown.size(), got]


func test_airport_search_a_click_on_a_row_picks_it() -> String:
	var b := _box()
	var got := []
	b.picked.connect(func(id): got.append(id))
	b.text = "o"
	b.text_changed.emit("o")  # VOCI, VOCL (ICAO contains) and the 'International' names
	var i := _ids(b.shown).find("VOCL")
	if i < 0:
		return "VOCL not in %s" % [_ids(b.shown)]
	b._pick(i)
	return "" if got == ["VOCL"] and b.current == "VOCL" else "click picked %s, current %s" % [got, b.current]
