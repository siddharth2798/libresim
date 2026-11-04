extends Node
## The Saved flights page (ui/menu/saves_page.gd, save_card.gd, saves_logic.gd): the texts, the two-step delete, the
## list and the empty state. Saves are written to a scratch folder (SituationStore.dir is redirected), never to the
## player's user://saves/.

const DIR := "user://_saves_page_test/"

var _keep_dir := ""
var _keep_setup := {}
var _nodes: Array[Node] = []


func _begin() -> void:
	if _keep_dir == "":
		_keep_dir = SituationStore.dir
		_keep_setup = Session.setup
	SituationStore.dir = DIR
	_wipe()


func _wipe() -> void:
	var da := DirAccess.open(DIR)
	if da != null:
		for f in da.get_files():
			DirAccess.remove_absolute(DIR + f)


func _save(name: String, unix: float, extra := {}) -> void:
	var meta := {"name": name, "unix": unix, "date": "2026-10-2%d 18:05" % int(unix), "airport": "VABB", "alt_ft": 1450.0, "agl_ft": 1410.0,
		"ias_kt": 88.0, "on_ground": false, "aircraft": "c172"}
	meta.merge(extra, true)
	SituationStore.write({"meta": meta, "setup": {"weather": "Fair", "time_h": 18.0833, "wind_dir_deg": 270.0, "wind_kt": 8.0}}, name)


func _page() -> Control:
	var p := HBoxContainer.new()
	p.set_script(load("res://ui/menu/saves_page.gd"))
	add_child(p)
	_nodes.append(p)
	return p


func teardown() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	if _keep_dir != "":
		_wipe()
		DirAccess.remove_absolute(DIR)  # the empty scratch folder
		SituationStore.dir = _keep_dir
		Session.setup = _keep_setup
		_keep_dir = ""


func test_saves_logic_texts() -> String:
	var m := {"name": "Evening circuit", "file": "Evening circuit", "date": "2026-10-28 18:05", "airport": "VABB", "alt_ft": 1450.0, "agl_ft": 1410.0,
		"ias_kt": 88.4, "on_ground": false, "aircraft": "c172"}
	if SavesLogic.title(m) != "Evening circuit" or SavesLogic.title({"file": "q1"}) != "q1":
		return "title falls back to the file name"
	if SavesLogic.subline(m) != "VABB · Cessna 172S · 2026-10-28 18:05":
		return "subline: " + SavesLogic.subline(m)
	if SavesLogic.where_text(m) != "1,450 ft (1,410 ft above ground), 88 KIAS":
		return "where: " + SavesLogic.where_text(m)
	m.on_ground = true
	if SavesLogic.where_text(m) != "On the ground":
		return "where on the ground"
	if SavesLogic.aircraft_name("") != "Cessna 172S" or SavesLogic.aircraft_name("zz_gone") != "zz_gone":
		return "aircraft name: '' = the first aircraft, unknown = as it is"
	if SavesLogic.conditions({"weather": "Fair", "time_h": 18.0833, "wind_dir_deg": 270.0, "wind_kt": 8.0}) != "Fair · 18:05 IST · wind 270/8":
		return "conditions: " + SavesLogic.conditions({"weather": "Fair", "time_h": 18.0833, "wind_dir_deg": 270.0, "wind_kt": 8.0})
	var rows := SavesLogic.rows(m, {})
	if rows.map(func(r): return r[0]) != ["Near", "Aircraft", "Where", "Saved"]:
		return "without a setup there is no Conditions row: %s" % [rows]
	return ""


func test_saves_guard_asks_before_deleting() -> String:
	var g := SavesLogic.Guard.new()
	if g.confirm("a"):
		return "nothing asked: no delete"
	g.ask("a")
	if g.is_asked("b") or not g.is_asked("a") or g.is_asked(""):
		return "the question is about one save"
	if g.confirm("b") or g.asked != "":
		return "confirming another save is refused and forgets the question"
	g.ask("a")
	g.cancel()
	if g.confirm("a"):
		return "cancelled"
	g.ask("a")
	if not g.confirm("a") or g.is_asked("a"):
		return "the second press deletes once"
	return ""


func test_saves_page_lists_newest_first_and_selects() -> String:
	_begin()
	_save("Old one", 1.0)
	_save("New one", 3.0, {"aircraft": "a320", "airport": "VOCI"})
	var p := _page()
	if p._cards.size() != 2 or p._cards[0].meta.name != "New one" or p._cards[1].meta.name != "Old one":
		return "newest first: %d cards" % p._cards.size()
	if p._sel != p._cards[0].meta.file or not p._cards[0].button_pressed or p._title.text != "New one":
		return "the newest is selected: " + p._title.text
	var rows: Array = p._table.get_children().map(func(c): return (c as Label).text)
	if rows[0] != "Near" or rows[1] != "VOCI" or rows[3] != "A320-family" or not "Conditions" in rows:
		return "detail table: %s" % [rows]
	p._cards[1].pressed.emit()
	if p._title.text != "Old one" or p._sel != p._cards[1].meta.file:
		return "picking the second shows it: " + p._title.text
	if not p._fly.visible or p._fly.disabled:
		return "Fly from this save is ready"
	return ""


func test_saves_page_delete_asks_first() -> String:
	_begin()
	_save("First", 1.0)
	_save("Second", 2.0)
	var p := _page()
	var file: String = p._sel  # "Second"
	p._del.pressed.emit()
	if not p._keep.visible or p._del.text != "Yes, delete" or not FileAccess.file_exists(DIR + file + ".json"):
		return "the first press only asks (file still there: %s)" % FileAccess.file_exists(DIR + file + ".json")
	p._keep.pressed.emit()
	if p._keep.visible or p._del.text != "Delete" or not FileAccess.file_exists(DIR + file + ".json"):
		return "Keep it forgets the question"
	p._del.pressed.emit()
	p._cards[1].pressed.emit()  # another save selected: the question does not follow
	if p._keep.visible or p._del.text != "Delete":
		return "selecting another save forgets the question"
	p._cards[0].pressed.emit()
	p._del.pressed.emit()
	p._del.pressed.emit()
	if FileAccess.file_exists(DIR + file + ".json") or p._cards.size() != 1 or p._cards[0].meta.name != "First":
		return "the second press deletes it: %d cards left" % p._cards.size()
	if p._title.text != "First":
		return "the next save is selected: " + p._title.text
	return ""


func test_saves_page_empty_state() -> String:
	_begin()
	var p := _page()
	if not p._empty.visible or p._detail.visible or p._left.visible:
		return "no saves: the empty note shows, not the list and details"
	_save("Late", 5.0)
	p._refresh()
	if p._empty.visible or not p._detail.visible or p._cards.size() != 1:
		return "after a save the list shows"
	p._del.pressed.emit()
	p._del.pressed.emit()
	if not p._empty.visible or p._cards.size() != 0:
		return "deleting the last save shows the empty state"
	return ""


func test_saves_page_unreadable_save_says_so() -> String:
	_begin()
	_save("Doomed", 1.0)
	var p := _page()
	DirAccess.remove_absolute(DIR + p._sel + ".json")
	p._fly_save()
	if p._info.text != "Cannot read this save." or p._fly.text != "Fly from this save  ▶":
		return "info: '%s'" % p._info.text
	return ""
