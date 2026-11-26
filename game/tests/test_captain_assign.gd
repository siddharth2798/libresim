extends Node
## Assigning a Captain Pack control to an action (core/captain_assign.gd): what gets written to the binding table, what it replaces, what
## it reports as moved, which actions an aircraft offers for which kind of control. Pure over tables; the panel and the Controls page
## agreeing on the same table is in tests/test_captain_map_panel.gd.

const PADS := [{"id": 0, "name": "TCA Sidestick X Copilot", "guid": "g-stick"}, {"id": 1, "name": "TCA Q-Eng 1&2", "guid": "g-quad"}]


func _table() -> Dictionary:
	return InputBindings.defaults(InputProfiles.CAPTAIN_PACK)


func _controls(id: String) -> AircraftControls:
	return AircraftControls.for_def(AircraftDef.load_def(id))


## Pad numbers of one part of the map.
func _e(dev: String, marker: String, part: String) -> Dictionary:
	var m := CaptainMap.marker(dev, marker)
	for p in m.parts:
		if p.id == part:
			return CaptainMap.effective(dev, m, p, "macOS")
	return {}


func test_assign_writes_the_binding_and_frees_the_old_control() -> String:
	var t := _table()
	var r := CaptainAssign.assign(t, "sidestick", _e("sidestick", "xbox", "key"), "flaps_down", _controls("a320"), PADS)
	if not r.ok or int(t.flaps_down.button) != 20 or str(t.flaps_down.name) != "sidestick":
		return "flaps_down should be on sidestick button 20, got %s %s" % [r, t.flaps_down]
	if r.from.is_empty() or CaptainAssign.describe_from(r.from, PADS) != "Base key A":
		return "the move should be reported as coming from Base key A, got %s" % CaptainAssign.describe_from(r.from, PADS)
	var old := CaptainMap.part_actions("sidestick", CaptainMap.marker("sidestick", "key_a"), CaptainMap.marker("sidestick", "key_a").parts[0], t, PADS, _controls("a320"))
	return "" if old.now.is_empty() else "base key A still has %s" % [old.now]


func test_assign_replaces_what_the_control_did_and_reports_it() -> String:
	var t := _table()
	var r := CaptainAssign.assign(t, "sidestick", _e("sidestick", "key_x", "key"), "gear_switch", _controls("a320"), PADS)
	if r.cleared != ["toggle_map"] or int(t.toggle_map.button) != -1:
		return "the map action should be cleared off key X, got %s button %s" % [r.cleared, t.toggle_map.button]
	if CaptainAssign.describe_from(r.from, PADS) != "Gear lever":
		return "gear_switch should be reported as moved from the Gear lever, got %s" % CaptainAssign.describe_from(r.from, PADS)
	if int(t.gear_switch.button) != 5 or bool(t.gear_switch.get("invert", false)):
		return "gear_switch should be plain on button 5 (the lever's invert stays with the lever): %s" % [t.gear_switch]
	var lever := CaptainMap.part_actions("quadrant", CaptainMap.marker("quadrant", "gear"), CaptainMap.marker("quadrant", "gear").parts[0], t, PADS, _controls("a320"))
	return "" if lever.now.is_empty() else "the gear lever still has %s" % [lever.now]


func test_a_control_gets_its_profile_binding_back() -> String:
	var t := _table()
	var lever := _e("quadrant", "lever1", "axis")
	CaptainAssign.clear(t, "quadrant", lever, _controls("a320"), PADS)
	if int(t.throttle.axis) != -1 or t.throttle.has("clicks"):
		return "clear should drop the lever's binding and its calibration"
	var r := CaptainAssign.assign(t, "quadrant", lever, "throttle", _controls("a320"), PADS)
	var want: Dictionary = InputProfiles.captain_pack("macOS").throttle
	return "" if r.ok and t.throttle.get("lo") == want.lo and t.throttle.get("clicks") == want.clicks else "the profile calibration (lo, clicks) did not come back: %s" % [t.throttle]


func test_actions_of_other_aircraft_stay_on_the_control() -> String:
	var t := _table()
	var brake := _e("quadrant", "speedbrake", "axis")
	if int(t.speedbrake.axis) != 5 or int(t.mixture.axis) != 5:
		return "the profile has the speed brake lever on both"
	var gone := CaptainAssign.clear(t, "quadrant", brake, _controls("c172"), PADS)
	if gone != ["mixture"] or int(t.speedbrake.axis) != 5:
		return "clearing on the C172 should only free the mixture, got %s and speedbrake axis %s" % [gone, t.speedbrake.axis]
	return ""


func test_wrong_kind_and_unknown_number_are_refused() -> String:
	var t := _table()
	var c := _controls("a320")
	if CaptainAssign.assign(t, "quadrant", _e("quadrant", "lever1", "axis"), "flaps_down", c, PADS).ok:
		return "a button action on an axis was accepted"
	if CaptainAssign.assign(t, "sidestick", _e("sidestick", "key_x", "key"), "pitch", c, PADS).ok:
		return "an axis action on a button was accepted"
	var r := CaptainAssign.assign(t, "sidestick", _e("sidestick", "grip_left", "key"), "flaps_down", c, PADS)
	return "" if not r.ok and str(r.error).contains("not known") else "a control with no known number should say so: %s" % [r]


func test_choices_are_typed_and_only_what_the_aircraft_offers() -> String:
	var a320 := CaptainAssign.choices(_controls("a320"), "button", true)
	var c172 := CaptainAssign.choices(_controls("c172"), "button", true)
	var axes := CaptainAssign.choices(_controls("a320"), "axis")
	var flat := func(sections: Array) -> Array:
		var out := []
		for s in sections:
			out.append_array(s[1])
		return out
	if not "gear_switch" in flat.call(a320) or "gear_switch" in flat.call(c172) or "autobrake_hi" in flat.call(c172):
		return "gear and auto brake belong to the A320 only"
	if "throttle" in flat.call(a320) or flat.call(axes).any(func(a): return not InputBindings.is_axis(a)):
		return "buttons and axes must not mix"
	if a320[0][0] != CaptainAssign.SWITCHES or not "engine_master_1_switch" in a320[0][1]:
		return "a latching switch lists its switch actions first, got %s" % a320[0][0]
	var last: String = a320[a320.size() - 1][0]
	return "" if last == "Ground operations" else "ground operations should come last, got %s" % last


func test_clear_returns_the_names_and_leaves_a_clean_binding() -> String:
	var t := _table()
	var gone := CaptainAssign.clear(t, "quadrant", _e("quadrant", "gear", "key"), _controls("a320"), PADS)
	var b: Dictionary = t.gear_switch
	if gone != ["gear_switch"] or int(b.button) != -1 or str(b.name) != "" or b.has("invert"):
		return "clear left %s" % [b]
	return "" if CaptainAssign.clear(t, "quadrant", _e("quadrant", "gear", "key"), _controls("a320"), PADS).is_empty() else "second clear found something"
