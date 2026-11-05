extends RefCounted
## Shared fixtures of the Captain Pack tests on the A320 (test_input_captain_a320.gd, test_input_captain_switches.gd).


static func a320() -> AircraftControls:
	return AircraftControls.for_def(AircraftDef.load_def("a320"))


static func table() -> Dictionary:
	return InputBindings.defaults(InputProfiles.CAPTAIN_PACK, "macOS")


## fake_buttons of a pad where only the actions in `on` are held (and every offered button is bound and connected).
static func held(ctl: AircraftControls, on := []) -> Dictionary:
	var d := {}
	for a in ctl.buttons():
		d[a] = a in on
	return d


static func joystick(ctl: AircraftControls, on := []) -> JoystickControls:
	var j := JoystickControls.new()
	j.table = table()
	j.fake_buttons = held(ctl, on)
	return j
