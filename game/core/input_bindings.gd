class_name InputBindings
extends RefCounted
## Joystick / gamepad binding table: action -> binding dictionary, plus the axis
## shaping maths (invert, deadzone, expo) and load/save (user://input_bindings.json).
## Button binding: {button, device, guid, name, invert}: invert swaps pressed and released (a switch wired the other way round).
## Axis binding:   {axis, device, guid, name, invert, deadzone, expo, range, lo, hi}
##   range "full" -1..1 -> -1..1 (stick), "half" -1..1 -> 0..1 (throttle lever),
##   "trigger" 0..1 -> 0..1 (gamepad trigger at rest = 0).
##   lo / hi (optional) calibrate the lever: the raw values at the low end (idle, closed)
##   and the high end (full) of its travel (lo may be above hi: a lever that reads falling when pushed
##   forward). Raw beyond lo or hi clamps, so a reverse zone behind idle reads as idle. Absent = the
##   range's natural ends (-1..1, trigger 0..1).
##   rev / clicks (thrust levers on an aircraft with detents and a reverse range): rev = raw at full
##   reverse, clicks = [{raw, detent (a sim detent name), play}] the lever's physical clicks (lever_detents.gd).
##   detents + values (speed brake lever): the raw value of each stop and the control value it gives.
## "flaps_lever" is a notched lever: its binding also has detents, the raw value of each notch
##   in order (0, 1, 2, ...); the nearest notch picks the flap setting (input/joystick_controls.gd).
## Buttons in ControlActions.LEVELS follow the held state of a latching switch (on / off).
## Button binding: {button, device, guid, name}. axis / button == -1 means unbound.
## A binding finds its pad by guid, else by name (case-insensitive substring of the pad's
## name, set by profiles for pads that are not plugged in yet), else by device index.

const PATH := "user://input_bindings.json"
const VERSION := 1

## Axis actions -> the Props they drive.
const AXES := {
	"pitch": "controls/pitch", "roll": "controls/roll", "yaw": "controls/yaw",
	"throttle": "controls/throttle", "mixture": "controls/mixture",
	"brake_left": "controls/brake_left", "brake_right": "controls/brake_right",
	"pitch_trim_axis": "controls/pitch_trim", "flaps_lever": "controls/flaps",
	# airliner axes (offered per aircraft, input/control_actions.gd)
	"throttle_2": "controls/throttle_2", "speedbrake": "controls/speedbrake",
	"rudder_trim_axis": "controls/rudder_trim", "tiller": "controls/tiller",
}
const BUTTONS := ["flaps_up", "flaps_down", "brakes", "parking_brake", "trim_up", "trim_down",
	"view_next", "view_cockpit", "starter", "magnetos_next", "toggle_map", "pause",
	"gear_toggle", "autobrake_next", "reverse", "speedbrake_out", "speedbrake_in", "throttle_detent_up",
	"throttle_detent_down", "engine_master_1", "engine_master_2", "engine_mode_next", "apu_master", "apu_start",
	"fcu_ap1", "fcu_ap2", "fcu_athr", "fcu_loc", "fcu_appr",
	"parking_brake_switch", "magnetos_switch", "engine_master_1_switch", "engine_master_2_switch",
	"gear_switch", "engine_mode_crank", "engine_mode_ign", "autobrake_btv", "autobrake_low", "autobrake_2",
	"autobrake_3", "autobrake_hi"]
const LABELS := {
	"pitch": "Pitch (elevator)", "roll": "Roll (ailerons)", "yaw": "Yaw (rudder)",
	"throttle": "Throttle", "mixture": "Mixture", "brake_left": "Left toe brake",
	"brake_right": "Right toe brake", "pitch_trim_axis": "Pitch trim (axis)",
	"flaps_up": "Flaps up (retract)", "flaps_down": "Flaps down (extend)", "brakes": "Brakes (hold)",
	"parking_brake": "Parking brake toggle", "trim_up": "Trim nose up", "trim_down": "Trim nose down",
	"view_next": "Next camera (C)", "view_cockpit": "Cockpit camera (1)", "starter": "Starter (hold)",
	"magnetos_next": "Magnetos cycle", "toggle_map": "Moving map (N)", "pause": "Pause (Esc)",
	"throttle_2": "Thrust lever 2 (lever 1 = Throttle)", "speedbrake": "Speedbrake", "rudder_trim_axis": "Rudder trim (axis)",
	"tiller": "Nosewheel tiller", "gear_toggle": "Landing gear up / down", "autobrake_next": "Autobrake cycle",
	"reverse": "Thrust reverse (hold)", "speedbrake_out": "Speedbrake out", "speedbrake_in": "Speedbrake in",
	"throttle_detent_up": "Thrust levers: next detent up", "throttle_detent_down": "Thrust levers: next detent down",
	"engine_master_1": "Engine 1 master", "engine_master_2": "Engine 2 master", "engine_mode_next": "Engine mode cycle",
	"apu_master": "APU master", "apu_start": "APU start (hold)", "fcu_ap1": "Autopilot 1", "fcu_ap2": "Autopilot 2",
	"fcu_athr": "Autothrust", "fcu_loc": "FCU LOC", "fcu_appr": "FCU APPR",
	"flaps_lever": "Flaps lever (notches)", "parking_brake_switch": "Parking brake (switch)",
	"magnetos_switch": "Magnetos OFF / BOTH (switch)", "engine_master_1_switch": "Engine 1 master (switch)",
	"engine_master_2_switch": "Engine 2 master (switch)", "gear_switch": "Landing gear lever (switch, pressed = down)",
	"engine_mode_crank": "Engine mode CRANK (held)", "engine_mode_ign": "Engine mode IGN/START (held)",
	"autobrake_btv": "Auto brake BTV", "autobrake_low": "Auto brake LOW", "autobrake_2": "Auto brake 2",
	"autobrake_3": "Auto brake 3", "autobrake_hi": "Auto brake HI",
}
## Binding keys that belong to one physical axis (calibration, notches): dropped when the axis is rebound.
const CAL_KEYS := ["lo", "hi", "rev", "clicks", "detents", "values"]
const RANGES := ["full", "half", "trigger"]
## Actions whose output is 0..1 (default range "half").
const HALF := ["throttle", "mixture", "brake_left", "brake_right", "throttle_2", "speedbrake"]


## Is a button binding "on", given whether the hardware button is pressed? `invert` swaps it. The game and the live bar
## on the Controls page both use this, so they always agree.
static func logical(pressed: bool, b: Dictionary) -> bool:
	return pressed != bool(b.get("invert", false))


static func is_axis(action: String) -> bool:
	return AXES.has(action)


static func unbound(action: String) -> Dictionary:
	if is_axis(action):
		return {"axis": -1, "device": 0, "guid": "", "invert": false, "deadzone": 0.05,
			"expo": 0.0, "range": "half" if action in HALF else "full"}
	return {"button": -1, "device": 0, "guid": ""}


static func _ax(t: Dictionary, action: String, axis: int, opts := {}) -> void:
	var b := unbound(action)
	b.axis = axis
	b.merge(opts, true)
	t[action] = b


static func _bt(t: Dictionary, action: String, button: int) -> void:
	var b := unbound(action)
	b.button = button
	t[action] = b


## profile "gamepad" (SDL standard layout), "joystick" (stick + twist + throttle lever) or
## "captain_pack" (Thrustmaster TCA sidestick + quadrant, see input_profiles.gd; os_name
## picks the per-OS axis numbering, default the running OS).
static func defaults(profile := "gamepad", os_name := "") -> Dictionary:
	var t := {}
	for a in AXES:
		t[a] = unbound(a)
	for a in BUTTONS:
		t[a] = unbound(a)
	if profile == InputProfiles.CAPTAIN_PACK:
		t.merge(InputProfiles.captain_pack(os_name if os_name != "" else OS.get_name()), true)
		return t
	if profile == "joystick":
		# Stick forward = -1 on axis 1 = push = nose down, matching controls/pitch (+1 = aft).
		_ax(t, "roll", 0, {"deadzone": 0.03, "expo": 0.2})
		_ax(t, "pitch", 1, {"deadzone": 0.03, "expo": 0.2})
		_ax(t, "yaw", 2, {"deadzone": 0.08, "expo": 0.2})
		_ax(t, "throttle", 3, {"invert": true, "deadzone": 0.02})  # lever forward = -1 = full
		_bt(t, "brakes", 0)
		_bt(t, "view_next", 1)
		_bt(t, "flaps_down", 2)
		_bt(t, "flaps_up", 3)
		_bt(t, "trim_down", 4)
		_bt(t, "trim_up", 5)
		_bt(t, "parking_brake", 6)
		_bt(t, "view_cockpit", 7)
		_bt(t, "toggle_map", 8)
		_bt(t, "magnetos_next", 9)
		_bt(t, "starter", 10)
		_bt(t, "pause", 11)
		_ax(t, "speedbrake", 4, {"deadzone": 0.02})
		_bt(t, "gear_toggle", 12)
		_bt(t, "autobrake_next", 13)
		_bt(t, "reverse", 14)
		return t
	_ax(t, "roll", JOY_AXIS_LEFT_X, {"deadzone": 0.1, "expo": 0.35})
	_ax(t, "pitch", JOY_AXIS_LEFT_Y, {"deadzone": 0.1, "expo": 0.35})
	_ax(t, "yaw", JOY_AXIS_RIGHT_X, {"deadzone": 0.12, "expo": 0.3})
	_ax(t, "brake_left", JOY_AXIS_TRIGGER_LEFT, {"range": "trigger", "deadzone": 0.05})
	_ax(t, "brake_right", JOY_AXIS_TRIGGER_RIGHT, {"range": "trigger", "deadzone": 0.05})
	_bt(t, "flaps_up", JOY_BUTTON_RIGHT_SHOULDER)
	_bt(t, "flaps_down", JOY_BUTTON_LEFT_SHOULDER)
	_bt(t, "brakes", JOY_BUTTON_A)
	_bt(t, "parking_brake", JOY_BUTTON_X)
	_bt(t, "view_next", JOY_BUTTON_Y)
	_bt(t, "view_cockpit", JOY_BUTTON_B)
	_bt(t, "trim_up", JOY_BUTTON_DPAD_DOWN)  # like pulling back
	_bt(t, "trim_down", JOY_BUTTON_DPAD_UP)
	_bt(t, "magnetos_next", JOY_BUTTON_DPAD_RIGHT)
	_bt(t, "starter", JOY_BUTTON_RIGHT_STICK)
	_bt(t, "toggle_map", JOY_BUTTON_BACK)
	_bt(t, "pause", JOY_BUTTON_START)
	_bt(t, "gear_toggle", JOY_BUTTON_DPAD_LEFT)
	_bt(t, "reverse", JOY_BUTTON_LEFT_STICK)
	return t


## Raw joypad axis value -> control value, per the binding's calibration, invert, deadzone,
## expo and range.
static func shape(raw: float, b: Dictionary) -> float:
	var dz := clampf(float(b.get("deadzone", 0.0)), 0.0, 0.95)
	var e := clampf(float(b.get("expo", 0.0)), 0.0, 1.0)
	var inv: bool = b.get("invert", false)
	var u := position(raw, b)  # 0..1 along the calibrated travel
	if str(b.get("range", "full")) == "full":
		var v := u * 2.0 - 1.0
		if inv:
			v = -v
		return signf(v) * _curve(_dead(absf(v), dz), e)
	return _curve(_dead(1.0 - u if inv else u, dz), e)


## Where the raw value sits along the binding's travel, 0 at lo and 1 at hi, clamped.
static func position(raw: float, b: Dictionary) -> float:
	var lo := float(b.get("lo", 0.0 if str(b.get("range", "full")) == "trigger" else -1.0))
	var hi := float(b.get("hi", 1.0))
	if absf(hi - lo) < 0.05:  # a collapsed calibration would divide by ~0: ignore it
		lo = 0.0 if str(b.get("range", "full")) == "trigger" else -1.0
		hi = 1.0
	return clampf((raw - lo) / (hi - lo), 0.0, 1.0)


## 0..1 magnitude with the bottom dz removed and the rest rescaled to 0..1.
static func _dead(m: float, dz: float) -> float:
	return 0.0 if m <= dz else clampf((m - dz) / (1.0 - dz), 0.0, 1.0)


## Expo: blend of linear and cubic, so small inputs are finer and full travel is still 1.
static func _curve(m: float, e: float) -> float:
	return (1.0 - e) * m + e * m * m * m


## Index of the detent nearest to raw (0 for an empty list).
static func detent_index(raw: float, detents: Array) -> int:
	var best := 0
	for i in detents.size():
		if absf(raw - float(detents[i])) < absf(raw - float(detents[best])):
			best = i
	return best


## Value of the nearest notch of an axis with "detents" (raw per notch) and "values" (output per notch);
## `shaped` when the binding has no such pair.
static func notched(b: Dictionary, raw: float, shaped: float) -> float:
	var d = b.get("detents")
	var v = b.get("values")
	if not (d is Array and v is Array) or d.is_empty() or d.size() != v.size():
		return shaped
	return float(v[detent_index(raw, d)])


## The raw axis value of a bound axis on a connected pad, else null.
static func raw_value(b: Dictionary) -> Variant:
	var dev := resolve_device(b)
	if dev < 0 or int(b.get("axis", -1)) < 0:
		return null
	return Input.get_joy_axis(dev, int(b.axis))


## The joypad index this binding reads from, or -1 if that pad is not connected.
static func resolve_device(b: Dictionary) -> int:
	return pick_device(b, JoyPads.connected())


## resolve_device over a list of {id, name, guid} pads (separate so tests need no hardware).
## guid wins, then name (no match = -1, never falls back to the index), then device index.
static func pick_device(b: Dictionary, pads: Array) -> int:
	var guid := str(b.get("guid", ""))
	if guid != "":
		for p in pads:
			if p.guid == guid:
				return p.id
	var want := str(b.get("name", "")).to_lower()
	if want != "":
		for p in pads:
			if str(p.name).to_lower().contains(want):
				return p.id
		return -1
	var dev := int(b.get("device", 0))
	for p in pads:
		if p.id == dev:
			return dev
	return -1


static func describe(b: Dictionary) -> String:
	if int(b.get("axis", -1)) >= 0:
		return "Pad %d · axis %d%s" % [int(b.device), int(b.axis), " (inv)" if b.get("invert", false) else ""]
	if int(b.get("button", -1)) >= 0:
		return "Pad %d · button %d" % [int(b.device), int(b.button)]
	return "—"


static func save_to(table: Dictionary, path := PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("InputBindings: cannot write %s" % path)
		return false
	f.store_string(JSON.stringify({"version": VERSION, "bindings": table}, "  "))
	return true


## save_to, then bump `input/bindings_rev` so a running JoystickControls reloads the table.
static func save_bump(table: Dictionary, path := PATH) -> bool:
	var ok := save_to(table, path)
	Props.set_v("input/bindings_rev", int(Props.get_v("input/bindings_rev", 0)) + 1)
	return ok


## Load a table; missing actions / keys are filled from the defaults, so old files keep working.
static func load_from(path := PATH, profile := "gamepad") -> Dictionary:
	var t := defaults(profile)
	if not FileAccess.file_exists(path):
		return t
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary or not d.get("bindings") is Dictionary:
		push_warning("InputBindings: bad file %s, using defaults" % path)
		return t
	for a in d.bindings:
		if t.has(a) and d.bindings[a] is Dictionary:
			var b := unbound(a)
			b.merge(d.bindings[a], true)
			for k in ["axis", "button", "device"]:  # JSON numbers come back as float
				if b.has(k):
					b[k] = int(b[k])
			t[a] = b
	return t
