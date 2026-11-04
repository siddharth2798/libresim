extends Node
## The Failures step (ui/menu/failures_page.gd, failure_row.gd, failures_armed.gd, failures_logic.gd): the pure armed-list
## logic, then the page driven through its controls: arming, the trigger and its value, the armed list and its remove
## button, Clear all, random failures, and the catalog following the aircraft. Looks: the page screenshots.

var _keep := {}
var _nodes: Array[Node] = []


func _begin(aircraft := "c172") -> void:
	if _keep.is_empty():
		_keep = {"setup": Session.setup}
	Session.setup = Session.DEFAULT.duplicate(true)
	Session.setup.aircraft = aircraft


func _page() -> Control:
	var p := HBoxContainer.new()
	p.set_script(load("res://ui/menu/failures_page.gd"))
	add_child(p)
	_nodes.append(p)
	return p


func teardown() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	if not _keep.is_empty():
		Session.setup = _keep.setup
		_keep = {}


func test_failures_logic_triggers() -> String:
	var f := {}
	FailuresLogic.set_trigger(f, "engine", 1)
	FailuresLogic.set_trigger(f, "alternator", 2)
	FailuresLogic.set_trigger(f, "flaps", 3, 1500.0)
	FailuresLogic.set_trigger(f, "trim", 4)
	if f != {"engine": [1, 0.0], "alternator": [2, 10.0], "flaps": [3, 1500.0], "trim": [4, 100.0]}:
		return "set_trigger: %s" % [f]
	FailuresLogic.set_trigger(f, "engine", 0)
	if f.has("engine") or FailuresLogic.mode_of(f, "engine") != 0 or FailuresLogic.value_of(f, "alternator") != 10.0:
		return "mode 0 disarms: %s" % [f]
	var want := ["At start", "After 10 min", "Above 1500 ft AGL", "Above 100 kt", "Off"]
	var got := [FailuresLogic.trigger_text(1, 0.0), FailuresLogic.trigger_text(2, 10.0), FailuresLogic.trigger_text(3, 1500.0),
		FailuresLogic.trigger_text(4, 100.0), FailuresLogic.trigger_text(0, 0.0)]
	return "" if got == want else "trigger_text: %s" % [got]


func test_failures_logic_armed_list_follows_the_catalog() -> String:
	var cats := [["Engine", [["engine", "Engine failure (total)"], ["mag_left", "Left magneto"]]], ["Fuel", [["fuel_leak_left", "Left tank leak"]]]]
	var f := {"fuel_leak_left": [3, 800.0], "engine": [2, 5.0], "gone": [1, 0.0]}
	var a := FailuresLogic.armed(f, cats)
	if a.size() != 2 or a[0].id != "engine" or a[1].id != "fuel_leak_left":
		return "catalog order, unknown ids left out: %s" % [a]
	if a[0].text != "After 5 min" or a[1].text != "Above 800 ft AGL" or a[1].category != "Fuel" or a[0].label != "Engine failure (total)":
		return "texts: %s" % [a]
	if FailuresLogic.armed_in(f, cats[0]) != 1 or FailuresLogic.armed_in(f, cats[1]) != 1 or FailuresLogic.armed_in({}, cats[0]) != 0:
		return "armed_in"
	return ""


func test_failures_logic_random_text_and_clear() -> String:
	var names := ["Engine", "Fuel", "Avionics"]
	var r := {"enabled": false, "count": 2, "from_min": 2.0, "to_min": 30.0, "categories": ["Engine", "Fuel", "Avionics"]}
	if FailuresLogic.random_text(r, names) != "":
		return "off = no line"
	r.enabled = true
	if FailuresLogic.random_text(r, names) != "2 random failures, 2 to 30 min in: any system":
		return FailuresLogic.random_text(r, names)
	r.categories = ["Fuel"]
	r.count = 1
	if FailuresLogic.random_text(r, names) != "1 random failure, 2 to 30 min in: Fuel":
		return FailuresLogic.random_text(r, names)
	r.categories = []
	if not FailuresLogic.random_text(r, names).ends_with("no system chosen"):
		return "no systems: " + FailuresLogic.random_text(r, names)
	var s := {"failures": {"engine": [1, 0.0]}, "random": r}
	if not FailuresLogic.any_armed(s):
		return "armed"
	FailuresLogic.clear_all(s)
	if not s.failures.is_empty() or s.random.enabled or FailuresLogic.any_armed(s):
		return "clear_all: %s" % [s]
	return ""


func test_failures_page_starts_with_zero_armed() -> String:
	_begin()
	var p := _page()
	if p._armed.count_label.text != "0 armed":
		return "count label: %s" % p._armed.count_label.text
	if p._armed.clear_btn.visible:
		return "Clear all only when something is armed"
	if p._armed.list.get_child_count() != 1 or not (p._armed.list.get_child(0) as Label).text.begins_with("Nothing scheduled"):
		return "the empty state should say nothing is scheduled"
	if p._rows.size() != FailureCatalog.all_ids().size() or p._tabs.size() != FailureCatalog.categories().size():
		return "one row per failure and one tab per category: %d / %d" % [p._rows.size(), p._tabs.size()]
	if p._rows["engine"].trigger.get_value() != null or p._rows["engine"].spin.visible:
		return "an unarmed row shows no trigger"
	return ""


func test_failures_page_arm_trigger_value_and_remove() -> String:
	_begin()
	var p := _page()
	var changes := [0]
	p.changed.connect(func(): changes[0] += 1)
	var row: FailureRow = p._rows["engine"]
	row.switch.toggled.emit(true)
	if Session.setup.failures != {"engine": [1, 0.0]} or not row.switch.is_on() or row.trigger.get_value() != 1 or row.spin.visible:
		return "arming = at start: %s" % [Session.setup.failures]
	if p._armed.count_label.text != "1 armed" or p._armed.list.get_child_count() != 1:
		return "the armed list should show it: %s" % p._armed.count_label.text
	if (p._tabs["Engine"][1] as Label).text != "1" or (p._tabs["Fuel"][1] as Label).text != "":
		return "the Engine tab should carry a 1"
	row.trigger.selected.emit(2)
	if Session.setup.failures.engine != [2, 10.0] or not row.spin.visible or row.spin.suffix != "min" or row.spin.value != 10.0:
		return "after time starts at 10 min: %s suffix '%s'" % [Session.setup.failures, row.spin.suffix]
	row.spin.value_changed.emit(25.0)
	if Session.setup.failures.engine != [2, 25.0]:
		return "the value is stored: %s" % [Session.setup.failures]
	row.trigger.selected.emit(3)
	if Session.setup.failures.engine != [3, 1000.0] or row.spin.suffix != "ft AGL":
		return "altitude defaults to 1000 ft: %s '%s'" % [Session.setup.failures, row.spin.suffix]
	row.trigger.selected.emit(4)
	if Session.setup.failures.engine != [4, 100.0] or row.spin.suffix != "kt":
		return "airspeed defaults to 100 kt"
	var x: Button = null
	for b in p._armed.list.find_children("*", "Button", true, false):
		x = b
	if x == null or x.text != "×":
		return "the armed row needs a remove button"
	x.pressed.emit()
	if not Session.setup.failures.is_empty() or row.switch.is_on() or row.trigger.get_value() != null or p._armed.count_label.text != "0 armed":
		return "remove disarms it and the row follows: %s" % [Session.setup.failures]
	if changes[0] < 5:
		return "the page should report each edit (%d)" % changes[0]
	return ""


func test_failures_page_clear_all_and_random() -> String:
	_begin()
	var p := _page()
	p._rows["alternator"].switch.toggled.emit(true)
	p._rows["flaps"].switch.toggled.emit(true)
	p._armed.random_switch.toggled.emit(true)
	if not Session.setup.random.enabled or not p._armed._random_box.visible or p._armed.count_label.text != "2 armed + random":
		return "random on: %s" % p._armed.count_label.text
	if p._armed._chips.size() != FailureCatalog.categories().size() or not (p._armed._chips["Engine"] as Button).button_pressed:
		return "one chip per system, the default systems lit"
	(p._armed._chips["Engine"] as Button).toggled.emit(false)
	if "Engine" in Session.setup.random.categories:
		return "unlighting a chip removes the system"
	(p._armed._spins["count"] as SpinBox).value_changed.emit(3.0)
	if int(Session.setup.random.count) != 3:
		return "how many"
	if not p._armed.clear_btn.visible:
		return "Clear all should be offered"
	p._armed.clear_btn.pressed.emit()
	if not Session.setup.failures.is_empty() or Session.setup.random.enabled or p._rows["flaps"].switch.is_on() or p._armed.random_switch.is_on():
		return "Clear all empties the schedule, turns random off and the controls follow"
	p._armed.notify_switch.toggled.emit(false)
	if Session.setup.notify:
		return "tell-me switch writes Session.setup.notify"
	return ""


func test_failures_page_catalog_follows_the_aircraft() -> String:
	_begin("c172")
	var p := _page()
	if not p._rows.has("mag_left") or p._rows.has("engine_2"):
		return "the C172 has magnetos and one engine"
	Session.setup.aircraft = "a320"
	p.refresh()
	if p._rows.has("mag_left") or not p._rows.has("engine_2") or not p._rows.has("hyd_G"):
		return "the A320 has no magnetos, two engines and hydraulics (rows: %s)" % [p._rows.keys().size()]
	var hidden: Array = AircraftDef.load_def("a320").section("failures").get("disabled", [])
	for id in hidden:
		if p._rows.has(id):
			return "a disabled failure (%s) must stay hidden" % id
	return ""


func _armed_page(ids: Array) -> Control:
	_begin()
	var p := _page()
	for id in ids:
		p._rows[id].switch.toggled.emit(true)
	return p


func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()


func test_failures_focus_moves_to_the_next_armed_row_after_a_remove() -> String:
	var p := _armed_page(["engine", "mag_left", "mag_right"])
	var ids: Array = p._armed.remove_btns.keys()
	if ids.size() != 3:
		return "three armed rows: %s" % [ids]
	(p._armed.remove_btns[ids[0]] as Button).grab_focus()
	(p._armed.remove_btns[ids[0]] as Button).pressed.emit()
	if _focus() != p._armed.remove_btns[ids[1]]:
		return "after removing the first row the focus should be on the next row's x, is %s" % [_focus()]
	(p._armed.remove_btns[ids[2]] as Button).grab_focus()  # the last row: the previous one is next in line
	(p._armed.remove_btns[ids[2]] as Button).pressed.emit()
	if _focus() != p._armed.remove_btns[ids[1]]:
		return "after removing the last row the focus should be on the previous row's x, is %s" % [_focus()]
	return ""


func test_failures_focus_falls_back_to_clear_all_then_the_first_switch() -> String:
	var p := _armed_page(["engine"])
	p._armed.random_switch.toggled.emit(true)
	var x: Button = p._armed.remove_btns["engine"]
	x.grab_focus()
	x.pressed.emit()
	if _focus() != p._armed.clear_btn or not p._armed.clear_btn.visible:
		return "with random failures still on, Clear all stays and takes the focus, is %s" % [_focus()]
	p._armed.clear_btn.pressed.emit()  # Clear all hides itself: the focus goes to the first failure switch of the area
	var first: FailureRow = (p._lists[p._cur] as Control).get_children().filter(func(r): return r is FailureRow)[0]
	if _focus() != first.switch:
		return "nothing armed any more: the first failure switch should have the focus, is %s" % [_focus()]
	return ""


func test_failures_page_is_narrower_than_the_room_next_to_the_rail() -> String:
	var p := _armed_page(["engine", "alternator", "pitot_blocked"])
	var w := p.get_combined_minimum_size().x
	if w > 835.0:  # 821 headless (813 in the screenshots with the menu theme), was 853 there; the room at 1280 x 720 is about 880
		return "the page needs %.0f px" % w
	return ""
