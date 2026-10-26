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
##   quadrant   lever 1 throttle, speed brake lever = mixture (RET = rich, pull back to lean;
##              lever 2 is unbound: its idle detent would mean mixture cutoff and stop the
##              engine), flaps lever (notches 0-1-2-3-FULL; FULL stays at flaps 3), engine mode
##              switch IGN/START = starter, ENG 1 master = magnetos OFF / BOTH, park brake switch
## Numbers were read off real hardware on macOS (Godot 4.7, IOKit) with the mapper page.
## Linux (evdev) can number the same pad differently and is NOT yet checked: record any
## difference in OS_OVERRIDES, keyed by Godot's OS.get_name(). Unused here, by design:
## sidestick base wheel (axis 3), left base keys Y / unlabelled / B (buttons 11-14, the same
## numbers as the hat), throttle lever 2 (axis 1), gear lever (button 20), auto brake dial
## (21-25), ENG 2 master (3), pushbuttons (4, 5), rudder trim (16-18).
## Throttle lo = the idle detent just above the reverse zone, estimated from where the
## lever rested (-0.51) plus a little play: re-set it with Lo on the Controls page.

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
				"throttle": {"axis": 0, "deadzone": 0.02, "lo": -0.48, "hi": 1.0},
				"mixture": {"axis": 5, "invert": true, "deadzone": 0.02},  # speed brake lever, RET = -1 = rich
				"flaps_lever": {"axis": 2, "detents": [-1.0, -0.49, -0.06, 0.44, 1.0]},
			},
			"buttons": {"starter": 7, "parking_brake_switch": 19, "magnetos_switch": 2},
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
