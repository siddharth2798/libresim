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
		or ControlActions.CYCLES.has(action) or ControlActions.STEPS.has(action)


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
	elif ControlActions.STEPS.has(action):
		var s: Array = ControlActions.STEPS[action]
		Props.set_v(s[0], clampf(Props.get_f(s[0]) + float(s[1]), 0.0, 1.0))
	else:
		return false
	return true


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
