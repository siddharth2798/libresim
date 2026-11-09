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
