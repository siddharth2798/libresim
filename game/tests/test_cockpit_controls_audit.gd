extends Node
## Every cockpit lever and switch has a row on the Controls page of the aircraft that has it.


func test_cockpit_controls_are_listed_for_their_aircraft() -> String:
	var a320 := AircraftControls.for_def(AircraftDef.load_def("a320"))
	var c172 := AircraftControls.for_def(AircraftDef.load_def("c172"))
	var a_rows: Array = a320.key_actions() + a320.axes() + a320.buttons()
	var c_rows: Array = c172.key_actions() + c172.axes() + c172.buttons()
	for need in ["tiller", "tiller_left", "tiller_right", "beacon", "nav_lights", "strobes", "landing_light",
			"taxi_light", "wing_lights", "logo_lights", "takeoff_light", "turnoff_lights", "anti_ice_wing",
			"anti_ice_eng_1", "anti_ice_eng_2", "fcu_hdg_left", "engine_master_1", "apu_master", "rudder_trim_axis"]:
		if not need in a_rows:
			return "A320 controls page is missing %s" % need
	for need in ["alternate_static", "beacon", "fuel_selector", "fuel_shutoff", "magnetos_next", "pitot_heat",
			"master", "avionics", "parking_brake"]:
		if not need in c_rows:
			return "C172 controls page is missing %s" % need
	if "tiller" in c_rows or "tiller_left" in c_rows or "alternate_static" in a_rows:
		return "a control is listed on the aircraft that does not have it"
	var page := HBoxContainer.new()
	page.set_script(load("res://ui/menu/controls_page.gd"))
	page.set("bindings_path", "user://test_cockpit_controls_audit.json")
	page.set("controls", a320)
	add_child(page)
	var joy: Array = page.get("_rows").keys()
	var keys: Array = page.keys.get("_rows").keys()
	page.free()
	if not "tiller" in joy or not "tiller_left" in keys or not "beacon" in joy or not "wing_lights" in joy:
		return "the page did not build the tiller and overhead rows"
	var help := ControlHelp.rows(a320, KeyBindings.defaults()).map(func(r): return r[1])
	if not "tiller" in help:
		return "key help omits the tiller"
	var was_b: bool = Props.get_b("controls/lights/beacon")
	var was_bat: bool = Props.get_b("controls/electrical/master_bat")
	var was_alt: bool = Props.get_b("controls/electrical/master_alt")
	Props.set_v("controls/lights/beacon", false)
	Props.set_v("controls/electrical/master_bat", false)
	Props.set_v("controls/electrical/master_alt", false)
	var joypad := JoystickControls.new()
	joypad._press("beacon")
	var lit: bool = Props.get_b("controls/lights/beacon")
	joypad._press("master")
	var masters: bool = Props.get_b("controls/electrical/master_bat") and Props.get_b("controls/electrical/master_alt")
	Props.set_v("controls/lights/beacon", was_b)
	Props.set_v("controls/electrical/master_bat", was_bat)
	Props.set_v("controls/electrical/master_alt", was_alt)
	joypad.free()
	if not lit or not masters:
		return "a joystick button did not move the cockpit switch"
	if not _other_has_panel():
		return "panel lights are not on Other keys"
	return ""


func _other_has_panel() -> bool:
	var ref: Script = load("res://ui/menu/keyboard_reference.gd")
	for row in ref.KEYS:
		if str(row[1]).contains("Panel lights"):
			return true
	return false


## Props an action moves (key, joystick button or axis), for the audits below.
static func _action_props(a: String) -> Array:
	var out := []
	for table in [ControlActions.TOGGLES, KeyBindings.SWITCHES, InputBindings.AXES]:
		if table.has(a):
			out.append(table[a])
	for table in [ControlActions.CYCLES, ControlActions.STEPS, ControlActions.LEVELS, ControlActions.KNOBS]:
		if table.has(a):
			out.append(table[a][0])
	for r in ControlActions.RATE_PROPS:
		if a in [r.neg, r.pos]:
			out.append("controls/" + r.prop)
	for s in ControlActions.SELECTORS.values():
		if s.positions.has(a):
			out.append(s.prop)
	match a:  # actions handled in code rather than through a table
		"master": out += ["controls/electrical/master_bat", "controls/electrical/master_alt"]
		"throttle_1_up", "throttle_1_down": out.append("controls/throttle_1")
		"throttle_2_up", "throttle_2_down": out.append("controls/throttle_2")
		"reverse": out += ["controls/reverse_1", "controls/reverse_2"]
		"apu_start": out.append("controls/apu_start")
		"nd_range_up", "nd_range_down": out.append("controls/nd/range_nm")
	return out


static func _page_props(ctl: AircraftControls) -> Dictionary:
	var out := {}
	for a in ctl.key_actions() + ctl.axes() + ctl.buttons():
		for p in _action_props(a):
			out[p] = a
	return out


## Every control the A320 cockpit moves, and every switch on the C172 switch row, can be worked from that aircraft's
## Controls page (the C172 PANEL dimmer is the fixed L key on Other keys; outputs such as fdm/stabilizer_deg are not controls).
func test_every_cockpit_control_has_a_controls_page_row() -> String:
	var a320 := _page_props(AircraftControls.for_def(AircraftDef.load_def("a320")))
	for pivot in AircraftDef.load_def("a320").data.cockpit.levers.values():
		for term in CockpitLevers.parse_drive(str(pivot.drive)):
			var p := str(term[1])
			if p.begins_with("controls/") and not a320.has(p):
				return "the A320 cockpit moves %s but no Controls page row does" % p
	var c172 := _page_props(AircraftControls.for_def(AircraftDef.load_def("c172")))
	var row: Script = load("res://ui/gauges/switch_row.gd")
	for sw in row.ITEMS:
		var p := str(sw[1])
		if p != "controls/lights/panel" and not c172.has(p):
			return "the C172 switch row has %s but no Controls page row does" % p
	return "" if _other_has_panel() else "panel lights are not on Other keys"
