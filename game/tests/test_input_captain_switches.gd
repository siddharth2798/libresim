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
	j._buttons(c)  # first seen pressed = UP (the pack's lever reads inverted): the sim follows the hardware
	var first := int(Props.get_v("controls/gear"))
	j.fake_buttons = FX.held(c, [])
	j._buttons(c)
	var up := int(Props.get_v("controls/gear"))
	j.fake_buttons = FX.held(c, ["gear_switch"])
	j._buttons(c)
	var down := int(Props.get_v("controls/gear"))
	j.fake_buttons = FX.held(c, [])
	j.resync()  # a restart: seen again, released = DOWN
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
	if [first, up, down, again] != [0, 1, 0, 1]:
		return "gear lever: start %d, released %d, pressed %d, restart %d, want 0 1 0 1" % [first, up, down, again]
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


## `invert` swaps pressed and released for a switch binding (the gear lever of the pack reads inverted by default),
## and the Invert toggle of a switch row on the Controls page sets it; a momentary button row has no such toggle.
func test_switch_invert_and_its_toggle() -> String:
	var c := FX.a320()
	var t := FX.table()
	if not bool(t["gear_switch"].get("invert", false)) or bool(t["parking_brake_switch"].get("invert", false)):
		return "default: gear must be inverted and the park brake not"
	var j := FX.joystick(c, ["parking_brake_switch"])
	if not j.button_down("parking_brake_switch"):
		return "an ordinary switch must read pressed = on"
	j.table["parking_brake_switch"]["invert"] = true
	var inverted := j.button_down("parking_brake_switch")
	j.fake_buttons = FX.held(c, [])
	var released := j.button_down("parking_brake_switch")
	j.free()
	if inverted or not released:
		return "invert did not swap pressed and released (%s, %s)" % [inverted, released]
	var b := {"button": 20, "device": 0, "guid": "", "name": "q-eng"}
	var row := VBoxContainer.new()
	row.set_script(load("res://ui/menu/controls_row.gd"))
	row.setup("gear_switch", b)
	var tog: Button = _find_button(row, "Invert")
	var plain := VBoxContainer.new()
	plain.set_script(load("res://ui/menu/controls_row.gd"))
	plain.setup("view_next", {"button": 19, "device": 0, "guid": "", "name": "sidestick"})
	var none := _find_button(plain, "Invert") == null
	if tog == null:
		return "no Invert toggle on the gear switch row"
	tog.button_pressed = true
	tog.pressed.emit()
	var set := bool(b.get("invert", false))
	row._clear()
	var cleared := not b.has("invert")
	row.free()
	plain.free()
	return "" if set and none and cleared else "toggle sets invert %s, momentary row has none %s, clear drops it %s" % [set, none, cleared]


func _find_button(n: Node, text: String) -> Button:
	if n is Button and (n as Button).text == text:
		return n
	for ch in n.get_children():
		var f := _find_button(ch, text)
		if f != null:
			return f
	return null


## The state a switch row's bar shows (and the game acts on) is the one after invert.
func test_logical_state_follows_invert() -> String:
	var plain := {"button": 20}
	var inv := {"button": 20, "invert": true}
	if InputBindings.logical(true, plain) != true or InputBindings.logical(false, plain) != false:
		return "a plain switch must read as pressed"
	if InputBindings.logical(true, inv) != false or InputBindings.logical(false, inv) != true:
		return "an inverted switch must read the other way round"
	var t := FX.table()  # the pack's gear lever: lever up = pressed, which is gear NOT down
	return "" if not InputBindings.logical(true, t["gear_switch"]) and InputBindings.logical(false, t["gear_switch"]) else "gear lever polarity in the profile"
