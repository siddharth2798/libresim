class_name InputProfiles
extends RefCounted
## Hardware profiles for core/input_bindings.gd. Each device is matched by name (a
## case-insensitive substring of the pad's name), so the profile applies before the
## hardware is plugged in and survives joypad index changes on Linux and macOS.
##
## Thrustmaster TCA Captain Pack X, Airbus Edition: two separate USB pads,
##   sidestick  roll / pitch / twist (rudder) + buttons
##   quadrant   lever 1 -> throttle, lever 2 -> mixture (the C172 has one throttle)
##
## PROVISIONAL: axis and button numbers are the usual HID order, not read from the
## hardware. Linux (evdev) and macOS (IOKit) can number the same pad differently:
## record any difference in OS_OVERRIDES, keyed by Godot's OS.get_name(). Until
## then, Controls -> Bind captures the real numbers, and the quadrant levers need
## their Lo / Hi calibration (idle detent and full), which depends on the unit.

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
			"buttons": {"brakes": 0, "view_next": 1, "flaps_up": 2, "flaps_down": 3,
				"view_cockpit": 4, "toggle_map": 5},
		},
		"quadrant": {
			"name": "quadrant",
			"axes": {
				"throttle": {"axis": 0, "deadzone": 0.02},
				"mixture": {"axis": 1, "deadzone": 0.02},
			},
			"buttons": {},
		},
	},
}

## OS name -> profile -> device -> "axes" / "buttons" -> action -> values merged over PROFILES.
## Empty until each OS's numbering is checked against real hardware. Example:
##   "macOS": {"captain_pack": {"sidestick": {"axes": {"yaw": {"axis": 5}}}}}
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
