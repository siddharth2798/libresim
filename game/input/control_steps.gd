class_name ControlSteps
extends RefCounted
## What a key press or a joystick button press does to Props, shared by keyboard_controls.gd and
## joystick_controls.gd (tables in control_actions.gd). Gating by what the aircraft offers is done
## by the callers.

const KNOB_DELAY := 0.4   # s held before an FCU knob repeats
const KNOB_REPEAT := 0.08  # s between repeats


## True when `action` is one of the shared press actions (flaps, toggles, cycles, steps).
static func handles(action: String) -> bool:
	return action in ["flaps_up", "flaps_down"] or ControlActions.TOGGLES.has(action) \
		or ControlActions.CYCLES.has(action) or ControlActions.STEPS.has(action) or ControlActions.PULSES.has(action)


## Apply a press action; false when it is not one of ours.
static func press(action: String) -> bool:
	if action == "flaps_down" or action == "flaps_up":
		var flaps: int = Props.get_v("controls/flaps", 0)
		var top := int(Props.get_v("fdm/flap_detents", 4)) - 1
		Props.set_v("controls/flaps", mini(flaps + 1, top) if action == "flaps_down" else maxi(flaps - 1, 0))
	elif ControlActions.TOGGLES.has(action):
		var p: String = ControlActions.TOGGLES[action]
		Props.set_v(p, not Props.get_b(p))
	elif ControlActions.CYCLES.has(action):
		var c: Array = ControlActions.CYCLES[action]
		Props.set_v(c[0], (int(Props.get_v(c[0], c[2])) + 1) % int(c[1]))
	elif ControlActions.PULSES.has(action):
		var q: String = ControlActions.PULSES[action]
		Props.set_v(q, int(Props.get_v(q, 0)) + 1)
	elif ControlActions.STEPS.has(action):
		var s: Array = ControlActions.STEPS[action]
		Props.set_v(s[0], clampf(Props.get_f(s[0]) + float(s[1]), 0.0, 1.0))
	else:
		return false
	return true


## A latching switch changed: set its prop to the "on" or "off" value (ControlActions.LEVELS).
static func level(action: String, on: bool) -> void:
	var l: Array = ControlActions.LEVELS[action]
	Props.set_v(l[0], l[2] if on else l[1])


## The flap setting for a flaps-lever notch. With the aircraft's notch table (aircraft.json controls.flaps_lever
## "settings", AircraftControls.flap_notches) the notch picks that sim setting; "on_ground" {"<notch>": setting}
## overrides it while the aircraft is on its wheels (A320: lever 1 = CONF 1+F for take-off, CONF 1 in the air).
## Without a table the notch is the setting, and notches beyond the aircraft's last detent stay on it.
static func flap_setting(notch: int, ctl: AircraftControls = null) -> int:
	var top := int(Props.get_v("fdm/flap_detents", 4)) - 1
	if ctl != null and not ctl.flap_notches.is_empty():
		var s := int(ctl.flap_notches[clampi(notch, 0, ctl.flap_notches.size() - 1)])
		if Props.get_b("fdm/wow") and ctl.flap_ground.has(str(notch)):
			s = int(ctl.flap_ground[str(notch)])
		return clampi(s, 0, top)
	return clampi(notch, 0, top)


## One FCU knob step (the first press) or a repeat while held; `state` keeps the hold timer per
## action. Returns true when the set-point changed.
static func knob(action: String, down: bool, dt: float, state: Dictionary) -> bool:
	if not down:
		state.erase(action)
		return false
	var k: Array = ControlActions.KNOBS[action]
	var due := false
	if not state.has(action):
		state[action] = -KNOB_DELAY
		due = true
	else:
		state[action] += dt
		if state[action] >= 0.0:
			state[action] -= KNOB_REPEAT
			due = true
	if due:
		var v: float = Props.get_f(k[0]) + float(k[1])
		Props.set_v(k[0], wrapf(v, k[2], k[3] + 1.0) if k[4] else clampf(v, k[2], k[3]))
	return due
