extends RefCounted
## The Captain Pack's switches on the A320 through JoystickControls (input/joystick_controls.gd): engine mode selector,
## auto brake dial, gear lever, ENG masters and park brake switch, start-up sync, and the C172 magneto switch. No
## hardware needed: the pad is JoystickControls.fake_buttons (tests/captain_fixtures.gd).

const FX := preload("res://tests/captain_fixtures.gd")


func test_a320_engine_mode_selector() -> String:
	var c := FX.a320()
	var out := []
	var j := FX.joystick(c)
	Props.set_v("controls/engine_mode", 1)
	j._buttons(c)  # first seen: NORM (no button) sets the sim from the hardware
	out.append(int(Props.get_v("controls/engine_mode")))
	for on in [["engine_mode_crank"], ["engine_mode_ign"], [], ["engine_mode_ign"]]:
		j.fake_buttons = FX.held(c, on)
		j._buttons(c)
		out.append(int(Props.get_v("controls/engine_mode")))
	j.fake_buttons = FX.held(c, [])
	j._buttons(c)
	Props.set_v("controls/engine_mode", 1)  # the keyboard cycles it: an unchanged selector leaves it alone
	j._buttons(c)
	var kept := int(Props.get_v("controls/engine_mode"))
	j.free()
	Props.set_v("controls/engine_mode", 0)
	if out != [0, 1, 2, 0, 2]:
		return "NORM / CRANK / IGN / NORM / IGN gave %s, want [0,1,2,0,2]" % [out]
	return "" if kept == 1 else "an unchanged selector overwrote the keyboard's engine mode"


func test_a320_autobrake_dial() -> String:
	var c := FX.a320()
	var j := FX.joystick(c)
	var got := []
	for on in [[], ["autobrake_btv"], ["autobrake_low"], ["autobrake_2"], ["autobrake_3"], ["autobrake_hi"], []]:
		j.fake_buttons = FX.held(c, on)
		j._buttons(c)
		got.append(int(Props.get_v("controls/autobrake")))
	ControlSteps.press("autobrake_next")  # the keyboard cycles it between dial moves
	var cycled := int(Props.get_v("controls/autobrake"))
	j._buttons(c)
	var kept := int(Props.get_v("controls/autobrake"))
	j.free()
	Props.set_v("controls/autobrake", 0)
	if got != [0, 1, 1, 2, 2, 3, 0]:
		return "DISARM BTV LOW 2 3 HI DISARM gave %s, want [0,1,1,2,2,3,0] (sim off/LO/MED/MAX)" % [got]
	return "" if cycled == 1 and kept == 1 else "dial overwrote a keyboard change (%d, %d)" % [cycled, kept]


func test_a320_gear_lever_and_start_sync() -> String:
	var c := FX.a320()
	var j := FX.joystick(c, ["gear_switch"])
	Props.set_v("controls/gear", 0)
	j._buttons(c)  # first seen pressed = DOWN: the sim follows the hardware
	var first := int(Props.get_v("controls/gear"))
	j.fake_buttons = FX.held(c, [])
	j._buttons(c)
	var up := int(Props.get_v("controls/gear"))
	j.fake_buttons = FX.held(c, ["gear_switch"])
	j._buttons(c)
	var down := int(Props.get_v("controls/gear"))
	j.fake_buttons = FX.held(c, [])
	j.resync()  # a restart: seen again, released = UP
	Props.set_v("controls/gear", 1)
	j._buttons(c)
	var again := int(Props.get_v("controls/gear"))
	j.free()
	var absent := JoystickControls.new()  # an unbound lever must never act
	absent.table = FX.table()
	absent.table.gear_switch.button = -1
	Props.set_v("controls/gear", 0)
	absent._buttons(c)
	var untouched := int(Props.get_v("controls/gear"))
	absent.free()
	Props.set_v("controls/gear", 1)
	if [first, up, down, again] != [1, 0, 1, 0]:
		return "gear lever: start %d, released %d, pressed %d, restart %d, want 1 0 1 0" % [first, up, down, again]
	return "" if untouched == 0 else "an unbound gear lever changed the gear"


func test_a320_masters_and_parking_brake_sync() -> String:
	var c := FX.a320()
	Props.set_v("controls/engine_master_1", true)  # a running start
	Props.set_v("controls/engine_master_2", false)
	Props.set_v("controls/parking_brake", false)
	var j := FX.joystick(c, ["engine_master_2_switch", "parking_brake_switch"])
	j._buttons(c)
	var m1 := Props.get_b("controls/engine_master_1")  # switch released at start: a running engine is not shut down
	var m2 := Props.get_b("controls/engine_master_2")  # pressed at start = ON
	var pb := Props.get_b("controls/parking_brake")
	j.fake_buttons = FX.held(c, ["engine_master_2_switch"])
	j._buttons(c)
	var pb_off := not Props.get_b("controls/parking_brake")
	j.fake_buttons = FX.held(c, [])
	j._buttons(c)
	var m2_off := not Props.get_b("controls/engine_master_2")
	j.free()
	for k in ["controls/engine_master_1", "controls/engine_master_2", "controls/parking_brake"]:
		Props.set_v(k, false)
	if not m1 or not m2 or not pb:
		return "start sync: master 1 %s (keep on), master 2 %s (on), parking brake %s (on)" % [m1, m2, pb]
	return "" if pb_off and m2_off else "switch edges after start did not act"


func test_c172_magneto_switch_never_syncs_at_start() -> String:
	var c := AircraftControls.default_set()
	Props.set_v("controls/magnetos", 3)
	var j := JoystickControls.new()
	j.table = FX.table()
	j.fake_buttons = FX.held(c)  # ENG 1 master released at start
	j._buttons(c)
	var kept := int(Props.get_v("controls/magnetos"))
	j.fake_buttons = FX.held(c, ["magnetos_switch"])
	j._buttons(c)
	j.fake_buttons = FX.held(c)
	j._buttons(c)
	var off := int(Props.get_v("controls/magnetos"))
	j.free()
	Props.set_v("controls/magnetos", 3)
	return "" if kept == 3 and off == 0 else "magnetos: at start %d (want 3), after the flips %d (want 0)" % [kept, off]


func test_controls_page_macos_pad_hint() -> String:
	var page = load("res://ui/menu/controls_page.gd")
	var mac: String = page.no_pad_text("macOS")
	var lin: String = page.no_pad_text("Linux")
	if not mac.contains("./run.sh") or lin.contains("run.sh") or not mac.begins_with(lin):
		return "the no-pad hint should point to ./run.sh on macOS only: %s | %s" % [mac, lin]
	return ""
