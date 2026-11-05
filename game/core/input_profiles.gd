class_name InputProfiles
extends RefCounted
## Hardware profiles for core/input_bindings.gd. Each device is matched by name (a
## case-insensitive substring of the pad's name), so the profile applies before the
## hardware is plugged in and survives joypad index changes on Linux and macOS.
##
## Thrustmaster TCA Captain Pack X, Airbus Edition, in PC mode (switch on the sidestick's
## back). Two pads: "TCA Sidestick X Copilot", and the quadrant plugged into the Mac or hub
## directly as "TCA Q-Eng 1&2" (it does not pass through the sidestick's USB-A ports).
##   sidestick  roll / pitch / twist (rudder), trigger = brakes, hat = trim, base keys
##   quadrant   C172: lever 1 = throttle (forward = more), speed brake lever = mixture (RET = rich),
##              flaps lever 0-1-2-3 (FULL stays at 3), IGN/START = starter, ENG 1 master = magnetos
##              BOTH / OFF, park brake switch.
##              A320: both thrust levers through the sim's detents (IDLE, CL, FLX/MCT, TOGA; behind
##              idle = reverse), speed brake lever in five notches, flaps lever 0-1-2-3-FULL (aircraft.json
##              controls.flaps_lever), gear lever, auto brake dial, engine mode selector, ENG 1 / 2 master,
##              park brake switch.
## An action only acts on an aircraft that offers it (input/aircraft_controls.gd), which is why
## one physical control can carry a different action per aircraft.
## MEASURED on the owner's hardware on macOS 27 (Godot 4.7.2 = SDL3, values equal the raw HID values),
## capture date 2026-11-04, with tools/hid_probe.swift (raw HID) and tests/probe_pads.gd (Godot's view).
## Godot numbers axes by ascending HID usage, so the quadrant's descriptor order 0,1,2,3 is Godot axis
## 0,1,2,5. Linux (evdev) can number the same pad differently and is NOT checked: record any
## difference in OS_OVERRIDES, keyed by Godot's OS.get_name().
##   thrust lever 1 / 2 (axis 0 / 1): forward = DECREASING. TOGA -1.0, FLX/MCT click -0.485 (lever 2 -0.48),
##     CLB click -0.01 (lever 2 -0.02), IDLE detent +0.48 (lever 2 +0.47), reverse = back towards +1.0
##     (one reverse position, full at +1.0). Binding fields: lo = raw at idle, hi = raw at TOGA, rev = raw at
##     full reverse, clicks = the physical clicks with the sim detent each one is (play = raw width that still
##     reads as the click), see input/lever_detents.gd. The C172 has no such detents: linear idle..TOGA.
##   flaps lever (axis 2): notches -1.0, -0.456, -0.051, +0.47, +1.0.
##   speed brake lever (axis 5): stops -1.0 (retracted), -0.523, -0.031, +0.465, +1.0 (no ARM position).
##   ENG 1 / 2 master = buttons 2 / 3 (latching, pressed = ON); engine mode CRANK = button 6 held, IGN/START =
##     button 7 held, NORM = none; gear lever = button 20 (pressed = DOWN); park brake switch = 19; auto brake
##     dial one-hot buttons 21 BTV, 22 LOW, 23 "2", 24 "3", 25 HI, DISARM = none.
## Unused by design: sidestick base wheel (axis 3), left base keys (buttons 11-14, the numbers of the hat),
## pushbuttons (4, 5), rudder trim (16-18), and the quadrant's virtual lever-zone buttons (lever 1: 8-11,
## lever 2: 12-15, speed brake: 26-30): they overlap, the axes are better.

const CAPTAIN_PACK := "captain_pack"

const PROFILES := {
	CAPTAIN_PACK: {
		"sidestick": {
			"name": "sidestick",
			"axes": {
				"roll": {"axis": 0, "deadzone": 0.03, "expo": 0.3},
				"pitch": {"axis": 1, "deadzone": 0.03, "expo": 0.3},
				"yaw": {"axis": 2, "deadzone": 0.1, "expo": 0.25},
			},
			"buttons": {"brakes": 0, "view_next": 2, "view_cockpit": 3, "flaps_up": 4,
				"toggle_map": 5, "flaps_down": 8, "parking_brake": 9, "pause": 21,
				"trim_down": 11, "trim_up": 12},  # hat up = nose down, hat down = nose up
		},
		"quadrant": {
			"name": "q-eng",
			"axes": {
				"throttle": {"axis": 0, "deadzone": 0.02, "lo": 0.48, "hi": -1.0, "rev": 1.0, "clicks": [
					{"raw": -0.485, "detent": "FLX/MCT", "play": 0.03}, {"raw": -0.01, "detent": "CL", "play": 0.03}]},
				"throttle_2": {"axis": 1, "deadzone": 0.02, "lo": 0.47, "hi": -1.0, "rev": 1.0, "clicks": [
					{"raw": -0.48, "detent": "FLX/MCT", "play": 0.03}, {"raw": -0.02, "detent": "CL", "play": 0.03}]},
				"mixture": {"axis": 5, "invert": true, "deadzone": 0.02},  # speed brake lever, RET = -1 = rich
				"speedbrake": {"axis": 5, "deadzone": 0.02,  # same lever: five stops -> 0, 0.25, 0.5, 0.75, 1
					"detents": [-1.0, -0.523, -0.031, 0.465, 1.0], "values": [0.0, 0.25, 0.5, 0.75, 1.0]},
				"flaps_lever": {"axis": 2, "detents": [-1.0, -0.456, -0.051, 0.47, 1.0]},
			},
			"buttons": {"starter": 7, "parking_brake_switch": 19, "magnetos_switch": 2,
				"engine_master_1_switch": 2, "engine_master_2_switch": 3, "gear_switch": 20,
				"engine_mode_crank": 6, "engine_mode_ign": 7, "autobrake_btv": 21, "autobrake_low": 22,
				"autobrake_2": 23, "autobrake_3": 24, "autobrake_hi": 25},
		},
	},
}

## OS name -> profile -> device -> "axes" / "buttons" -> action -> values merged over PROFILES.
## Empty: macOS is the numbering above; Linux still has to be checked. Example:
##   "Linux": {"captain_pack": {"sidestick": {"axes": {"yaw": {"axis": 5}}}}}
const OS_OVERRIDES := {"Linux": {}, "macOS": {}}


## action -> binding for the profile's actions on the given OS (Windows and other
## systems use the base numbering). Merge over InputBindings.defaults().
static func captain_pack(os_name: String, overrides := OS_OVERRIDES) -> Dictionary:
	var out := {}
	var over: Dictionary = overrides.get(os_name, {}).get(CAPTAIN_PACK, {})
	var devices: Dictionary = PROFILES[CAPTAIN_PACK]
	for dev in devices:
		var spec: Dictionary = devices[dev]
		var dev_over: Dictionary = over.get(dev, {})
		for a in spec.axes:
			var b := InputBindings.unbound(a)
			b.merge(spec.axes[a], true)
			b.merge(dev_over.get("axes", {}).get(a, {}), true)
			b.name = spec.name
			out[a] = b
		for a in spec.buttons:
			var b := InputBindings.unbound(a)
			b.button = dev_over.get("buttons", {}).get(a, spec.buttons[a])
			b.name = spec.name
			out[a] = b
	return out
