extends Node
## Keys for the ramp: jetway, cabin door, ground vehicles.


func teardown() -> void:
	for p in ["controls/ground/jetway_stowed", "controls/ground/crew_away", "controls/door_open", "systems/door_pos"]:
		Props.set_v(p, false if p != "systems/door_pos" else 0.0)


func test_ramp_actions_are_bound_and_offered_to_every_aircraft() -> String:
	var d := KeyBindings.defaults()
	for a in ["jetway_toggle", "door_toggle", "ground_crew_toggle"]:
		if not KeyBindings.PRESS.has(a) or not KeyBindings.LABELS.has(a) or d.get(a, []).is_empty():
			return "%s is not a bound key action" % a
		if ControlActions.group_of(a) != "":
			return "%s should be offered by every aircraft" % a
	return ""


func test_ramp_keys_flip_their_props() -> String:
	for a in ["jetway_toggle", "door_toggle", "ground_crew_toggle"]:
		var p: String = ControlActions.TOGGLES[a]
		ControlSteps.press(a)
		var on := Props.get_b(p)
		ControlSteps.press(a)
		if not on or Props.get_b(p):
			return "%s does not toggle %s" % [a, p]
	return ""


func test_ground_crew_key_sends_vehicles_away() -> String:
	var crew := RampCrew.new()
	Props.set_v("controls/ground/crew_away", true)
	var got := crew.parked_stand()
	crew.free()
	return "" if got.is_empty() else "crew still wanted after the key"


func test_cabin_door_eases_open_and_shut() -> String:
	var p := CabinDoor.step(0.0, true, CabinDoor.OPEN_S / 2.0)
	if absf(p - 0.5) > 0.001 or CabinDoor.step(1.0, true, 5.0) != 1.0 or CabinDoor.step(0.5, false, 99.0) != 0.0:
		return "door step %f" % p
	return ""


## Every ground operation is a rebindable key and joystick button that every aircraft offers, with a label and a
## default key; T and P are no longer fixed hotkeys (a binding on them is not a conflict).
func test_every_ground_operation_is_rebindable() -> String:
	var d := KeyBindings.defaults()
	for c in [AircraftControls.default_set(), AircraftControls.for_def(AircraftDef.load_def("a320"))]:
		for a in ControlActions.GROUND:
			if not a in c.press_keys() or not a in c.buttons():
				return "%s is not offered as a key and a button" % a
			if not KeyBindings.LABELS.has(a) or not InputBindings.LABELS.has(a) or d.get(a, []).is_empty():
				return "%s has no label or default key" % a
			if not ControlSteps.handles(a):
				return "%s does nothing when pressed" % a
	if KeyBindings.RESERVED.has(KEY_T) or KeyBindings.RESERVED.has(KEY_P):
		return "T / P are still fixed hotkeys"
	if not KeyBindings.conflicts(d).is_empty():
		return "default keys conflict: %s" % [KeyBindings.conflicts(d)]
	return ""


## The taxi and pushback keys ask GroundOps through a counter (no fixed T / P key handler any more).
func test_taxi_and_pushback_keys_reach_ground_ops() -> String:
	var g := FakeOps.new()
	g.set("_seen", GroundOps._requests())  # what setup() does: earlier presses are not replayed
	ControlSteps.press("taxi_route")
	ControlSteps.press("pushback")
	g.call("_poll_requests")
	g.call("_poll_requests")  # nothing new pressed: nothing new asked
	ControlSteps.press("pushback")
	g.call("_poll_requests")
	var calls: Array = g.calls
	g.free()
	return "" if calls == ["taxi", "push", "push"] else "GroundOps was asked %s" % [calls]


class FakeOps extends GroundOps:
	var calls := []

	func request_taxi() -> void:
		calls.append("taxi")

	func start_pushback() -> void:
		calls.append("push")


## The Controls page shows the ground operations in their own section, on the keyboard and the joystick tab.
func test_controls_page_has_a_ground_section() -> String:
	var keys := VBoxContainer.new()
	keys.set_script(load("res://ui/menu/key_bindings_section.gd"))
	keys.set("path", "user://test_ramp_no_such_keys.json")
	keys.set("controls", AircraftControls.default_set())
	add_child(keys)
	var bad := []
	for a in keys.get("_rows"):
		if (keys.section_of(a) == "ground") != (a in ControlActions.GROUND):
			bad.append(a)
	var shown: int = keys.filter("pushback")
	var head_ok: bool = keys.get("_ground_head").visible and not keys.get("_flight_head").visible
	keys.free()
	if not bad.is_empty():
		return "wrong section: %s" % [bad]
	if shown != 1 or not head_ok:
		return "search 'pushback': %d rows, headings %s" % [shown, head_ok]
	var page := HBoxContainer.new()
	page.set_script(load("res://ui/menu/controls_page.gd"))
	page.set("bindings_path", "user://test_ramp_no_such_bindings.json")
	page.set("controls", AircraftControls.default_set())
	add_child(page)
	var heads: Array = page.get("_heads").map(func(h): return str(h.text).to_lower())
	var rows: Dictionary = page.get("_rows")
	var ok := heads.has("ground operations") and ControlActions.GROUND.all(func(a): return rows.has(a))
	page.free()
	return "" if ok else "joystick tab heads %s" % [heads]
