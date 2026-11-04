extends Node
## Controls page extras (ui/menu/controls_filter.gd, controls_header.gd, controls_page.gd): the search words, the
## "Controls for" aircraft switch (it changes the listed actions and nothing else), the "No match" note, and the sticky
## tab bar (the rows scroll, the bar does not). Bindings go to a throw-away file; nothing is saved, no key is rebound.

const BINDINGS := "user://test_controls_filter_bindings.json"

var _keep_setup := {}


func teardown() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BINDINGS))
	if not _keep_setup.is_empty():
		Session.setup = _keep_setup
		_keep_setup = {}


func _page(extra := {}) -> Control:
	if _keep_setup.is_empty():
		_keep_setup = Session.setup
		Session.setup = Session.DEFAULT.duplicate(true)
	var p := HBoxContainer.new()
	p.set_script(load("res://ui/menu/controls_page.gd"))
	p.set("bindings_path", BINDINGS)
	for k in extra:
		p.set(k, extra[k])
	add_child(p)
	return p


func _shown_rows(p: Control) -> Array:
	var out := []
	var rows: Dictionary = p.get("_rows")
	for a in rows:
		if (rows[a] as Control).visible:
			out.append(a)
	return out


func _shown_keys(p: Control) -> Array:
	return (p.keys.get("_rows") as Dictionary).keys().filter(func(a): return (p.keys.get("_rows")[a] as Control).visible)


# ---- pure rules -------------------------------------------------------------------------------

func test_words_are_lower_case_and_split_at_spaces() -> String:
	if ControlsFilter.words("  Pitch   UP ") != PackedStringArray(["pitch", "up"]) or not ControlsFilter.words("   ").is_empty():
		return "words: %s" % [ControlsFilter.words("  Pitch   UP ")]
	return ""


func test_every_word_must_be_found_case_blind() -> String:
	var texts := ["Pitch up", "pitch_up", "W"]
	var cases := {"": true, "pitch": true, "PITCH UP": true, "up pitch": true, "pitch w": true, "yaw": false, "pitch yaw": false,
		"pitch up": true, "w": true, "zz": false, "  ": true}
	for q in cases:
		if ControlsFilter.matches(q, texts) != cases[q]:
			return "query '%s' gave %s, expected %s" % [q, not cases[q], cases[q]]
	return ""


func test_underscore_ids_match_as_spaces_and_empty_texts_are_safe() -> String:
	if not ControlsFilter.matches("fuel selector", ["", "fuel_selector"]) or ControlsFilter.matches("x", []):
		return "an id with underscores should match its words, and nothing matches an empty row"
	return ""


func test_count_and_summary() -> String:
	var rows := [["Pitch up", "W"], ["Pitch down", "S"], ["Flaps", "F"]]
	if ControlsFilter.count("pitch", rows) != 2 or ControlsFilter.count("", rows) != 3 or ControlsFilter.count("zz", rows) != 0:
		return "count wrong"
	if ControlsFilter.summary("", 3, 3) != "" or ControlsFilter.summary("pitch", 2, 3) != "2 of 3" or ControlsFilter.summary("zz", 0, 3) != ControlsFilter.NO_MATCH:
		return "summary wrong"
	return ""


# ---- the page --------------------------------------------------------------------------------

func test_typing_hides_rows_on_every_tab_and_clearing_restores_them() -> String:
	var p := _page()
	var all_keys: int = p.keys.call("row_count")
	var all_joy: int = (p.get("_rows") as Dictionary).size()
	p.search.text = "pitch"
	p.search.text_changed.emit("pitch")
	var some_keys := _shown_keys(p).size()
	var some_joy := _shown_rows(p).size()
	var pitch_only: bool = _shown_keys(p).all(func(a): return KeyBindings.LABELS[a].to_lower().contains("pitch") or a.contains("pitch"))
	p.search.text = ""
	p.search.text_changed.emit("")
	var back_keys := _shown_keys(p).size()
	var back_joy := _shown_rows(p).size()
	p.free()
	if some_keys == 0 or some_keys >= all_keys or some_joy == 0 or some_joy >= all_joy:
		return "'pitch' should leave some but not all rows (keys %d of %d, joystick %d of %d)" % [some_keys, all_keys, some_joy, all_joy]
	if not pitch_only:
		return "a row that does not mention pitch stayed visible"
	return "" if back_keys == all_keys and back_joy == all_joy else "clearing the search should show every row again"


func test_no_match_note_shows_only_when_a_tab_is_empty() -> String:
	var p := _page()
	var note_k: Control = p.get("_empties")["keyboard"]
	var note_j: Control = p.get("_empties")["joystick"]
	var hidden0 := not note_k.visible and not note_j.visible
	var left: int = p.apply_filter("zzzqqq")
	var shown: bool = note_k.visible and note_j.visible and p.get("_empties")["other"].visible
	var heads_hidden: bool = not (p.get("_heads") as Array)[0].visible and not (p.get("_heads") as Array)[1].visible
	p.apply_filter("pitch")
	var hidden1 := not note_k.visible
	p.free()
	if not hidden0:
		return "the note should be hidden while the search box is empty"
	if left != 0 or not shown or not heads_hidden:
		return "a query that matches nothing should show 'No match' on every tab and hide the Axes / Buttons headings"
	return "" if hidden1 else "the note should go away when something matches"


func test_filter_also_finds_a_row_by_its_bound_key() -> String:
	var p := _page()
	var first: String = (p.keys.get("table") as Dictionary).keys()[0]
	var key_text := ""
	for s in p.keys.get("table")[first]:
		key_text = KeyBindings.describe(s)
		break
	if key_text == "":
		p.free()
		return "no bound key found to search for"
	var n: int = p.keys.call("filter", key_text)
	var has_row := first in _shown_keys(p)
	p.free()
	return "" if n >= 1 and has_row else "searching for '%s' should keep the action bound to it (%s)" % [key_text, first]


func test_hotkey_list_filters_too() -> String:
	var p := _page()
	var ref: GridContainer = p.get("_other")
	var all: int = ref.call("filter", "")
	var map: int = ref.call("filter", "moving map")
	p.free()
	return "" if all >= 10 and map == 1 else "Other keys: %d hotkeys, 'moving map' left %d" % [all, map]


# ---- the aircraft switch ------------------------------------------------------------------------

func test_switch_lists_every_installed_aircraft_and_lights_the_current_one() -> String:
	var p := _page()
	var sw: Segmented = p.aircraft_switch
	var ids := AircraftDef.list_ids()
	var err := ""
	if sw == null or ids.size() < 2:
		err = "no 'Controls for' switch with %d aircraft installed" % ids.size()
	elif sw.get_value() != AircraftDef.current().id:
		err = "the switch should light the current aircraft (%s), not %s" % [AircraftDef.current().id, sw.get_value()]
	else:
		for id in ids:
			if sw.button_of(id) == null:
				err = "no segment for %s" % id
	p.free()
	return err


func test_switching_changes_the_listed_actions_and_not_the_setup() -> String:
	var p := _page()
	var before := Session.setup.duplicate(true)
	var c172_keys := _shown_keys(p).size()
	var c172_rows := (p.get("_rows") as Dictionary).keys()
	var c172_ctl: AircraftControls = p.controls
	p.aircraft_switch.button_of("a320").pressed.emit()
	var a320_rows: Array = (p.get("_rows") as Dictionary).keys()
	var a320_keys: int = p.keys.call("row_count")
	var lit: Variant = p.aircraft_switch.get_value()
	var same_setup: bool = Session.setup.hash() == before.hash() and Session.setup.aircraft == "c172"
	var lists_a320: bool = p.controls.id == "a320" and p.controls != c172_ctl
	var kb_rebuilt: bool = p.tabs.page("keyboard") == p.keys
	p.aircraft_switch.button_of("c172").pressed.emit()
	var back_rows: Array = (p.get("_rows") as Dictionary).keys()
	var back_keys: int = p.keys.call("row_count")
	p.free()
	if not same_setup:
		return "switching the 'Controls for' aircraft must not change the flight setup"
	if not lists_a320 or lit != "a320":
		return "the page should list the A320's controls and light its segment"
	if a320_rows == c172_rows and a320_keys == c172_keys:
		return "the A320 and C172 action lists should differ"
	if not kb_rebuilt:
		return "the keyboard tab was not rebuilt for the new aircraft"
	return "" if back_rows == c172_rows and back_keys == c172_keys else "switching back should restore the C172 list"


func test_switch_keeps_the_search_words_and_the_selected_tab() -> String:
	var p := _page({"start_tab": "joystick"})
	p.apply_filter("throttle")
	p.aircraft_switch.button_of("a320").pressed.emit()
	var tab: String = p.tabs.current()
	var rows := _shown_rows(p)
	var ok_rows: bool = not rows.is_empty() and rows.all(func(a): return a.contains("throttle") or InputBindings.LABELS[a].to_lower().contains("throttle") or InputBindings.LABELS[a].to_lower().contains("thrust"))
	var text_kept: bool = p.search.text == "" and p.get("_query") == "throttle"  # typed text lives in the box; the rule is re-applied
	p.free()
	if tab != "joystick":
		return "the selected tab changed to %s" % tab
	return "" if ok_rows and text_kept else "the search should still apply after switching aircraft (rows %s)" % [rows]


func test_switch_cancels_a_binding_capture_and_ignores_unknown_ids() -> String:
	var p := _page({"start_tab": "joystick"})
	p._start_capture("throttle")
	p.show_aircraft("a320")
	var cancelled: bool = p.get("_capture") == ""
	var id_before: String = p.controls.id
	p.show_aircraft("no_such_aircraft")
	var same: bool = p.controls.id == id_before
	p.free()
	return "" if cancelled and same else "a switch should cancel a capture (%s) and an unknown aircraft is ignored (%s)" % [cancelled, same]


# ---- sticky bar --------------------------------------------------------------------------------

func test_tab_bar_sits_outside_the_scroll_area() -> String:
	var p := _page()
	var tabs: MenuTabs = p.tabs
	var sc := tabs.scroll
	var err := ""
	if sc == null or not sc.follow_focus:
		err = "the sticky tabs need a scroll area that follows the focus"
	elif sc.is_ancestor_of(tabs.header) or sc.is_ancestor_of(tabs.button("keyboard")) or sc.is_ancestor_of(p.search):
		err = "the tab bar and the search box must not be inside the scroll area"
	elif not sc.is_ancestor_of(p.keys) or not sc.is_ancestor_of(tabs.page("joystick")):
		err = "the tab pages must scroll inside it"
	p.free()
	return err


func test_options_rail_is_sticky_too() -> String:
	var p := HBoxContainer.new()
	p.set_script(load("res://ui/menu/options_page.gd"))
	add_child(p)
	var tabs: MenuTabs = p.tabs
	var ok: bool = tabs.scroll != null and not tabs.scroll.is_ancestor_of(tabs.button("sound")) and tabs.scroll.is_ancestor_of(tabs.page("sound"))
	p.free()
	return "" if ok else "the Options rail should stay while its page scrolls"
