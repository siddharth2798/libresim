extends Node
## The Captain Pack map's data and rules (core/captain_map.gd, ui/menu/captain_map/map.json): file integrity, that every number of the
## profile has a marker, what the table binds per aircraft, and the numbers the owner teaches with Identify. Scratch paths only.

const LEARNED := "user://test_captain_map_learned.json"
const SIDESTICK := {"id": 0, "name": "TCA Sidestick X Copilot", "guid": "g-stick"}
const QUADRANT := {"id": 1, "name": "TCA Q-Eng 1&2", "guid": "g-quad"}


func _begin() -> void:
	CaptainMap.learned_path = LEARNED
	_clean()
	CaptainMap.reload_learned()


func _clean() -> void:
	if FileAccess.file_exists(LEARNED):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEARNED))


func teardown() -> void:
	CaptainMap.learned_path = "user://captain_map_learned.json"
	_clean()
	CaptainMap.reload_learned()


func _controls(id: String) -> AircraftControls:
	return AircraftControls.for_def(AircraftDef.load_def(id))


## Every part of every marker as [device, marker, part].
func _parts() -> Array:
	var out := []
	for dev in CaptainMap.devices():
		for m in CaptainMap.markers(dev):
			for p in m.parts:
				out.append([dev, m, p])
	return out


func test_map_file_integrity() -> String:
	_begin()
	if CaptainMap.devices().size() != 2:
		return "expected two devices, got %s" % [CaptainMap.devices()]
	var sources: Dictionary = CaptainMap.data().sources
	for dev in CaptainMap.devices():
		var ids := {}
		var uids := {}
		for m in CaptainMap.markers(dev):
			if ids.has(m.id):
				return "%s: duplicate marker id %s" % [dev, m.id]
			ids[m.id] = true
			if m.has("x") != m.has("y") or (m.has("x") and not (0.0 <= float(m.x) and float(m.x) <= 1.0 and 0.0 <= float(m.y) and float(m.y) <= 1.0)):
				return "%s/%s: position outside 0..1" % [dev, m.id]
			if not str(m.get("kind", "")) in ["axis", "lever", "button", "switch"] or m.parts.is_empty():
				return "%s/%s: kind or parts" % [dev, m.id]
			for p in m.parts:
				if uids.has(CaptainMap.uid(m, p)):
					return "%s: duplicate part %s" % [dev, CaptainMap.uid(m, p)]
				uids[CaptainMap.uid(m, p)] = true
				if not CaptainMap.CONF_RANK.has(str(p.get("conf", ""))) or not sources.has(str(p.get("src", ""))):
					return "%s: %s has no valid conf / source" % [dev, CaptainMap.uid(m, p)]
				if p.has("key") and not (InputBindings.AXES.has(p.key) or InputBindings.BUTTONS.has(p.key)):
					return "%s: key %s is not an action" % [CaptainMap.uid(m, p), p.key]
	return ""


func test_no_number_on_two_parts() -> String:
	_begin()
	var seen := {}
	for t in _parts():
		var e := CaptainMap.effective(t[0], t[1], t[2], "macOS")
		for kind in ["axis", "button"]:
			if e[kind] >= 0:
				var k := "%s:%s:%d" % [t[0], kind, e[kind]]
				if seen.has(k):
					return "%s is on %s and %s" % [k, seen[k], CaptainMap.uid(t[1], t[2])]
				seen[k] = CaptainMap.uid(t[1], t[2])
	return ""


func test_every_profile_number_has_a_marker() -> String:
	_begin()
	var profile: Dictionary = InputProfiles.PROFILES[InputProfiles.CAPTAIN_PACK]
	for dev in profile:
		var spec: Dictionary = profile[dev]
		var covered := {"axis": {}, "button": {}}
		for m in CaptainMap.markers(dev):
			for p in m.parts:
				var e := CaptainMap.effective(dev, m, p, "macOS")
				for kind in ["axis", "button"]:
					covered[kind][e[kind]] = true
		for a in spec.axes:
			if not covered.axis.has(int(spec.axes[a].axis)):
				return "%s axis %d (%s) has no marker" % [dev, spec.axes[a].axis, a]
		for a in spec.buttons:
			if not covered.button.has(int(spec.buttons[a])):
				return "%s button %d (%s) has no marker" % [dev, spec.buttons[a], a]
	return ""


func test_quadrant_buttons_are_markers_or_listed_unmapped() -> String:
	_begin()
	var covered := {}
	for m in CaptainMap.markers("quadrant"):
		for p in m.parts:
			covered[CaptainMap.effective("quadrant", m, p, "macOS").button] = true
	for u in CaptainMap.data().devices.quadrant.unmapped:
		for b in u.buttons:
			covered[int(b)] = true
	for b in range(0, 31):  # the community list: 31 buttons, counted from 1
		if not covered.has(b):
			return "quadrant button %d is neither a marker nor listed as unmapped" % b
	return ""


func test_confidence_counts() -> String:
	_begin()
	var n := {"measured": 0, "documented": 0, "unconfirmed": 0}
	for t in _parts():
		n[CaptainMap.part_conf(t[0], t[1], t[2])] += 1
	return "" if n == {"measured": 30, "documented": 7, "unconfirmed": 13} else "counts changed: %s" % [n]


func test_labels_follow_the_aircraft() -> String:
	_begin()
	var table := InputBindings.defaults(InputProfiles.CAPTAIN_PACK)
	var pads := [SIDESTICK, QUADRANT]
	var brake := CaptainMap.marker("quadrant", "speedbrake")
	var a320 := CaptainMap.actions_for("quadrant", brake, table, pads, _controls("a320"))
	var c172 := CaptainMap.actions_for("quadrant", brake, table, pads, _controls("c172"))
	if a320.now != ["speedbrake"] or c172.now != ["mixture"]:
		return "the speed brake lever should be speedbrake / mixture, got %s / %s" % [a320.now, c172.now]
	var gear := CaptainMap.actions_for("quadrant", CaptainMap.marker("quadrant", "gear"), table, pads, _controls("c172"))
	var d := CaptainMap.describe(gear, "Cessna 172S")
	if not d.unused or d.text != "not used on Cessna 172S":
		return "gear lever on the C172 should read not used, got %s" % [d]
	var free := CaptainMap.describe(CaptainMap.actions_for("sidestick", CaptainMap.marker("sidestick", "xbox"), table, pads, _controls("a320")))
	return "" if free.unbound and free.text == "unbound" else "the Xbox button is unbound in the profile: %s" % [free]


func test_a_rebound_control_shows_its_new_action() -> String:
	_begin()
	var table := InputBindings.defaults(InputProfiles.CAPTAIN_PACK)
	table.toggle_map.button = -1
	table.gear_toggle.button = 5
	table.gear_toggle.name = "sidestick"
	var acts := CaptainMap.actions_for("sidestick", CaptainMap.marker("sidestick", "key_x"), table, [SIDESTICK, QUADRANT], _controls("a320"))
	return "" if acts.now == ["gear_toggle"] else "key X should show gear_toggle, got %s" % [acts]


func test_a_binding_on_the_other_pad_does_not_count() -> String:
	_begin()
	var table := InputBindings.defaults(InputProfiles.CAPTAIN_PACK)
	table.view_next.name = "q-eng"  # button 19 of the QUADRANT is the park brake switch, not the sidestick's change view
	var acts := CaptainMap.actions_for("sidestick", CaptainMap.marker("sidestick", "view"), table, [SIDESTICK, QUADRANT], _controls("a320"))
	return "" if not "view_next" in acts.now else "a q-eng binding showed on the sidestick"


func test_compact_names() -> String:
	var cases := [[["Auto brake BTV", "Auto brake LOW", "Auto brake 2"], "Auto brake BTV / LOW / 2"], [["Throttle"], "Throttle"],
		[["Roll", "Pitch"], "Roll, Pitch"], [["Trim nose up", "Trim nose down"], "Trim nose up / down"]]
	for c in cases:
		var got := CaptainMap.compact(PackedStringArray(c[0]))
		if got != c[1]:
			return "compact(%s) = %s, want %s" % [c[0], got, c[1]]
	return ""


func test_a_taught_number_wins_and_is_taken_from_the_other_part() -> String:
	_begin()
	var hat := CaptainMap.marker("sidestick", "hat")
	var right: Dictionary = hat.parts[3]
	if CaptainMap.effective("sidestick", hat, right, "macOS").button != 14:
		return "hat right should start as 14"
	var blank := CaptainMap.marker("sidestick", "blank")
	if not CaptainMap.learn("sidestick", CaptainMap.uid(blank, blank.parts[0]), "button", 14):
		return "the learned file was not written"
	var hit := CaptainMap.find_part("sidestick", "button", 14, "macOS")
	if hit.is_empty() or hit.part != blank.parts[0]:
		return "button 14 should now be the blank key, got %s" % [hit.get("part", {}).get("id", "none")]
	if CaptainMap.effective("sidestick", hat, right, "macOS").button != -1:
		return "hat right kept a number the owner gave to another key"
	if CaptainMap.part_conf("sidestick", blank, blank.parts[0]) != "measured":
		return "a taught number counts as measured"
	CaptainMap.reload_learned()  # from the file again
	return "" if CaptainMap.find_part("sidestick", "button", 14, "macOS").part == blank.parts[0] else "the correction was not kept in the file"
