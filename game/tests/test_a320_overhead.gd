extends Node
## The A320 overhead system controls (tools/blender/a320_panel_systems.py): ELEC, HYD, FUEL, AIR pushbuttons and the
## SIGNS rotaries move in the 3D cockpit, toggle on a click, light their OFF / ON caption, and have a key action.

const NEW := {"bat1": "controls/electrical/bat1", "bat2": "controls/electrical/bat2", "gen1": "controls/electrical/gen1",
	"gen2": "controls/electrical/gen2", "apu_gen": "controls/electrical/apu_gen", "ext_pwr": "controls/electrical/ext_pwr",
	"green_edp": "controls/hyd/green_edp", "yellow_edp": "controls/hyd/yellow_edp", "blue_epump": "controls/hyd/blue_epump",
	"yellow_epump": "controls/hyd/yellow_epump", "ptu": "controls/hyd/ptu",
	"fuel_l1": "controls/fuel/pump_left", "fuel_l2": "controls/fuel/pump_left", "fuel_c1": "controls/fuel/pump_centre",
	"fuel_c2": "controls/fuel/pump_centre", "fuel_r1": "controls/fuel/pump_right", "fuel_r2": "controls/fuel/pump_right",
	"xfeed": "controls/fuel/crossfeed", "bleed1": "controls/bleed/eng1", "bleed2": "controls/bleed/eng2",
	"apu_bleed": "controls/bleed/apu", "pack1": "controls/bleed/pack1", "pack2": "controls/bleed/pack2",
	"seatbelt_sw": "controls/signs/seatbelts", "no_smoking_sw": "controls/signs/no_smoking"}

var _saved := {}


func teardown() -> void:
	for p in _saved:
		if _saved[p] == null:
			Props._p.erase(p)
		else:
			Props.set_v(p, _saved[p])
	_saved.clear()


func _keep(p: String) -> void:
	if not _saved.has(p):
		_saved[p] = Props.get_v(p, null)


func _levers() -> Dictionary:
	return AircraftDef.load_def("a320").data.cockpit.levers


func test_every_overhead_system_control_is_a_cockpit_lever() -> String:
	var lv := _levers()
	for pivot in NEW:
		if not lv.has(pivot):
			return "aircraft.json cockpit.levers has no %s" % pivot
		if str(lv[pivot].drive) != NEW[pivot]:
			return "%s drives %s, want %s" % [pivot, lv[pivot].drive, NEW[pivot]]
	return ""


func test_a_click_toggles_each_overhead_switch() -> String:
	var lv := _levers()
	for pivot in NEW:
		var p: String = NEW[pivot]
		_keep(p)
		Props.set_v(p, true)
		CockpitPick.commit(lv[pivot])
		if Props.get_v(p) != false:
			return "a click on %s should switch %s off, got %s" % [pivot, p, Props.get_v(p)]
		CockpitPick.commit(lv[pivot])
		if Props.get_v(p) != true:
			return "a second click on %s should switch %s on again" % [pivot, p]
	_keep("controls/signs/seatbelts")
	Props._p.erase("controls/signs/seatbelts")  # never set yet: reads 0.0, must still toggle
	CockpitPick.commit(lv.seatbelt_sw)
	if Props.get_v("controls/signs/seatbelts") != true:
		return "a sign switch never set should toggle on, not slide: got %s" % Props.get_v("controls/signs/seatbelts")
	return ""


func test_captions_light_off_or_on_like_the_real_panel() -> String:
	for c in [["lamp_bat1", "controls/electrical/bat1", false], ["lamp_pack2", "controls/bleed/pack2", false],
			["lamp_fuel_c2", "controls/fuel/pump_centre", false], ["lamp_ext_pwr", "controls/electrical/ext_pwr", true],
			["lamp_xfeed", "controls/fuel/crossfeed", true], ["lamp_apu_bleed", "controls/bleed/apu", true]]:
		_keep(c[1])
		Props.set_v(c[1], c[2])
		if not CockpitLamps.lit(c[0]):
			return "%s should light when %s is %s" % c
		Props.set_v(c[1], not c[2])
		if CockpitLamps.lit(c[0]):
			return "%s should be dark when %s is %s" % [c[0], c[1], not c[2]]
	return ""


func test_each_overhead_switch_has_a_key_action_on_the_a320() -> String:
	var ctl := AircraftControls.for_def(AircraftDef.load_def("a320"))
	var c172 := AircraftControls.for_def(AircraftDef.load_def("c172"))
	var props := {}
	for a in ctl.key_actions():
		if ControlActions.TOGGLES.has(a):
			props[ControlActions.TOGGLES[a]] = a
	for pivot in NEW:
		if not props.has(NEW[pivot]):
			return "no A320 key action switches %s" % NEW[pivot]
		var a: String = props[NEW[pivot]]
		if not a in ctl.buttons():
			return "%s is not on the A320 joystick list" % a
		if c172.offers(a):
			return "%s belongs to the A320 only" % a
		if KeyBindings.LABELS.get(a, "") == "" or InputBindings.LABELS.get(a, "") == "":
			return "%s has no label on the Controls page" % a
	_keep("controls/hyd/ptu")
	Props.set_v("controls/hyd/ptu", true)
	var joypad := JoystickControls.new()
	joypad._press("hyd_ptu")
	var off: bool = not Props.get_b("controls/hyd/ptu")
	joypad.free()
	return "" if off else "the PTU button action should switch the PTU off"
