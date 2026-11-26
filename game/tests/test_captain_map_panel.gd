extends Node
## The Captain Pack map on screen (ui/menu/captain_map_panel.gd and friends) with FAKE pads: the aircraft switch, assigning through the
## panel with the Controls page reading the same table and file, the read-only preview, Identify finding and teaching a number, the live
## glow, Esc, and the link. Scratch files only (the real bindings, options and learned numbers are never touched).

const SCRATCH := "user://test_captain_map_panel_bindings.json"
const LEARNED := "user://test_captain_map_panel_learned.json"
const PADS := [{"id": 0, "name": "TCA Sidestick X Copilot", "guid": "g-stick"}, {"id": 1, "name": "TCA Q-Eng 1&2", "guid": "g-quad"}]

var _nodes: Array = []
var _axes := {}
var _btns := {}
var _kept := false


func _begin(with_pads := true) -> void:
	_kept = true
	CaptainDetect.bindings_path = SCRATCH
	CaptainMap.learned_path = LEARNED
	CaptainMap.reload_learned()
	_clean()
	_axes = {}
	_btns = {}
	CaptainDetect.pads_provider = (func(): return PADS) if with_pads else (func(): return [])


func _clean() -> void:
	for f in [SCRATCH, LEARNED]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func teardown() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	if _kept:
		CaptainDetect.pads_provider = Callable()
		CaptainDetect.bindings_path = InputBindings.PATH
		CaptainMap.learned_path = "user://captain_map_learned.json"
		CaptainMap.reload_learned()
		_clean()
		_kept = false


func _controls(id: String) -> AircraftControls:
	return AircraftControls.for_def(AircraftDef.load_def(id))


func _open(table: Dictionary, page: Object = null, aircraft := "a320") -> CaptainMapPanel:
	var p := CaptainMapPanel.open(self, page, table, _controls(aircraft))
	_nodes.append(p.get_parent())
	p.save_path = SCRATCH
	p.read_axis = func(pad: int, axis: int) -> float: return _axes.get("%d:%d" % [pad, axis], 0.0)
	p.read_button = func(pad: int, button: int) -> bool: return _btns.get("%d:%d" % [pad, button], false)
	return p


func _page(table: Dictionary) -> HBoxContainer:
	InputBindings.save_to(table, SCRATCH)
	var page := HBoxContainer.new()
	page.set_script(load("res://ui/menu/controls_page.gd"))
	page.set("bindings_path", SCRATCH)
	page.set("controls", _controls("a320"))
	add_child(page)
	_nodes.append(page)
	return page


func _row(p: CaptainMapPanel, dev: String, id: String) -> String:
	return str(p.legends[dev].rows[id].label.text)


func test_the_aircraft_switch_changes_the_labels() -> String:
	_begin()
	var p := _open(InputBindings.defaults(InputProfiles.CAPTAIN_PACK))
	if p.aircraft_switch == null or p.aircraft_switch.get_value() != "a320":
		return "the aircraft switch should start on the aircraft given"
	var ids := AircraftDef.list_ids()
	if not ids.has("a320") or not ids.has("c172") or p.aircraft_switch._entries.size() != ids.size():
		return "the switch should list every aircraft folder, %s" % [ids]
	if not _row(p, "quadrant", "gear").contains("Landing gear") or not _row(p, "quadrant", "speedbrake").contains("Speed brake"):
		return "A320 labels wrong: %s / %s" % [_row(p, "quadrant", "gear"), _row(p, "quadrant", "speedbrake")]
	p.set_aircraft("c172")
	var gear := _row(p, "quadrant", "gear")
	if not gear.contains("not used on") or not _row(p, "quadrant", "speedbrake").contains("Mixture"):
		return "C172 labels wrong: %s / %s" % [gear, _row(p, "quadrant", "speedbrake")]
	return "" if p.legends.quadrant.rows.gear.dim else "a control the aircraft does not use should be dim"


func test_assign_through_the_panel_and_the_page_reads_the_same_table() -> String:
	_begin()
	var page := _page(InputBindings.defaults(InputProfiles.CAPTAIN_PACK))
	var p := _open({}, page)
	p.select("sidestick", "xbox")
	p.assign("flaps_down")
	if int(page.table.flaps_down.button) != 20:
		return "the page's table should hold the new binding: %s" % [page.table.flaps_down]
	if int(InputBindings.load_from(SCRATCH).flaps_down.button) != 20:
		return "the change should be saved to the page's file"
	if InputBindings.describe(page.table.flaps_down) != "Pad 0 · button 20" or not page._rows.flaps_down._bind_lbl.text.contains("button 20"):
		return "the page's row did not refresh: %s" % page._rows.flaps_down._bind_lbl.text
	if not p.msg.text.contains("Base key A"):
		return "the message should say what moved: %s" % p.msg.text
	return "" if _row(p, "sidestick", "key_a").contains("unbound") and _row(p, "sidestick", "xbox").contains("Flaps down") else "the legend did not follow"


func test_clear_and_invert() -> String:
	_begin()
	var page := _page(InputBindings.defaults(InputProfiles.CAPTAIN_PACK))
	var p := _open({}, page)
	p.select("quadrant", "gear")
	p.set_invert(false)
	if page.table.gear_switch.get("invert") != false or not p.invert_btn.visible:
		return "a latching switch bound to a switch action has the invert option"
	p.clear_selected()
	if int(page.table.gear_switch.button) != -1 or not _row(p, "quadrant", "gear").contains("unbound"):
		return "clear should unbind the gear lever"
	p.select("sidestick", "pitch")
	return "" if not p.invert_btn.visible else "an axis has no switch invert here (Tune has its own)"


func test_the_preview_is_read_only_until_the_profile_is_loaded() -> String:
	_begin(false)
	var saved := InputBindings.defaults("gamepad")
	var p := _open(saved)
	if not p.preview or not p.choose_btn.disabled:
		return "with no pack and no profile the map is a read-only preview"
	p.select("sidestick", "xbox")
	p.assign("flaps_down")
	if int(saved.flaps_down.button) == 20:
		return "the preview wrote to the saved table"
	if not _row(p, "quadrant", "gear").contains("Landing gear"):
		return "the preview should show the profile's default mapping"
	p.reset_profile()
	if not p.preview:
		return "one press only asks"
	p.reset_profile()
	return "" if not p.preview and CaptainDetect.applied(saved) and not p.choose_btn.disabled else "the second press should load the profile into the saved table"


func test_identify_selects_the_pressed_control_and_teaches_unknown_numbers() -> String:
	_begin()
	var p := _open(InputBindings.defaults(InputProfiles.CAPTAIN_PACK))
	p.set_identify(true)
	_btns["0:14"] = true  # hat right: documented as unconfirmed
	p._process(0.05)
	if p.selected != ["sidestick", "hat"] or p.sel_part != "right":
		return "button 14 should select the hat's right part, got %s %s" % [p.selected, p.sel_part]
	_btns.clear()
	p._process(0.05)
	_btns["0:32"] = true  # not on the map
	p._process(0.05)
	if not p.ident_row.visible or not p.ident_label.text.contains("not on the map yet"):
		return "an unknown button should offer 'This is:', got %s" % p.ident_label.text
	var want := -1
	for i in p.ident_parts.size():
		if p.ident_parts[i][2].id == "upper":
			want = i
	if want < 0 or p.ident_parts[0][2].conf != "unconfirmed":
		return "the list should offer the blank key and put unconfirmed controls first"
	p.ident_pick.select(want)
	p.save_identified()
	var hit := CaptainMap.find_part("sidestick", "button", 32)
	if hit.is_empty() or hit.part.id != "upper" or not FileAccess.file_exists(LEARNED):
		return "button 32 should now be the blank key and kept in the learned file"
	_btns.clear()
	p._process(0.05)
	_btns["1:9"] = true  # a virtual lever zone button of the quadrant
	p._process(0.05)
	return "" if p.msg.text.contains("zone") and not p.ident_row.visible else "a virtual zone button should say so: %s" % p.msg.text


func test_markers_glow_while_held_or_moving() -> String:
	_begin()
	var p := _open(InputBindings.defaults(InputProfiles.CAPTAIN_PACK))
	p._process(0.05)
	_btns["0:0"] = true  # the trigger
	_axes["0:0"] = 0.7  # roll
	p._process(0.05)
	if p.pictures.sidestick.lit.get("trigger", 0.0) != 1.0 or p.legends.sidestick.rows.trigger.lit != 1.0:
		return "a held button should be fully lit"
	if p.pictures.sidestick.lit.get("roll", 0.0) <= 0.0 or p.legends.sidestick.rows.roll.bar_v != 0.7:
		return "a moving axis should glow and show its value"
	_btns.clear()
	_axes.clear()
	for i in 30:
		p._process(0.05)
	return "" if p.pictures.sidestick.lit.get("trigger", 1.0) == 0.0 and p.pictures.sidestick.lit.get("roll", 1.0) == 0.0 else "the glow should fade out"


func test_esc_closes_and_the_pack_never_drives_the_menu() -> String:
	_begin()
	var p := _open(InputBindings.defaults(InputProfiles.CAPTAIN_PACK))
	var got := [0]
	p.closed.connect(func(): got[0] += 1)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	p._input(esc)
	_nodes.erase(p.get_parent())
	p.get_parent().free()
	return "" if got[0] == 1 else "Esc should close the panel once, closed fired %d times" % got[0]


func test_the_link_says_what_it_opens() -> String:
	_begin()
	var box := VBoxContainer.new()
	add_child(box)
	_nodes.append(box)
	var link := CaptainMapLink.add_to(box, null)
	if box.get_child_count() != 2 or link.text != CaptainMapLink.TEXT_FOUND:
		return "with a pack the link reads Captain Pack map, got %s" % link.text
	CaptainDetect.pads_provider = func(): return []
	link.refresh()
	return "" if link.text == CaptainMapLink.TEXT_NONE else "without a pack it says it is a preview, got %s" % link.text
