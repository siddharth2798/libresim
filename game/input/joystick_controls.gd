class_name JoystickControls
extends Node
## Joystick / gamepad pilot input -> Props "controls/*", per core/input_bindings.gd.
## Coexists with KeyboardControls: while a bound axis (or a held brake/starter button)
## drives a control, Props "input/axis_owner/<name>" = "joy" and the keyboard skips it.
## Publishes "controls/joystick_active" (a bound axis on a connected pad).
## View / map / pause buttons inject the matching key press so existing handlers run.
## Reloads the table when Props "input/bindings_rev" changes (the controls page bumps it).
## Only the axes / buttons the aircraft offers (aircraft_controls.gd) act. Held buttons that have no
## prop of their own (reverse, APU start) publish "input/held/<action>" for the keyboard side to use.

const TRIM_RATE := 0.15  # same as KeyboardControls
const KEYS := {"view_next": KEY_C, "view_cockpit": KEY_1, "toggle_map": KEY_N, "pause": KEY_ESCAPE}

var table := {}
var _rev := -1
var _prev := {}  # button action -> was pressed
var _owned := {}  # control name -> true while we own it
var _ctl: AircraftControls
var _lever_keys: LeverKeys

## Axes with their own handling in _process (levers, brakes, trim); the rest are written as they are.
const OWN_AXES := ["throttle", "throttle_2", "mixture", "brake_left", "brake_right", "pitch_trim_axis"]


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection)
	_reload()


func controls() -> AircraftControls:
	_ctl = AircraftControls.refresh(_ctl)
	if _lever_keys == null:
		_lever_keys = LeverKeys.new(self)
	return _ctl


func _reload() -> void:
	table = InputBindings.load_from()
	_rev = int(Props.get_v("input/bindings_rev", 0))


func _on_joy_connection(device: int, connected: bool) -> void:
	print("joystick %d %s: %s" % [device, "connected" if connected else "disconnected", Input.get_joy_name(device)])
	Props.set_v("input/joy_event", "%s %s" % [Input.get_joy_name(device), "connected" if connected else "disconnected"])
	_prev.clear()


## Shaped value of an axis action, or null when unbound / its pad is missing.
func axis_value(action: String) -> Variant:
	var b: Dictionary = table.get(action, {})
	if int(b.get("axis", -1)) < 0:
		return null
	var dev := InputBindings.resolve_device(b)
	if dev < 0:
		return null
	return InputBindings.shape(Input.get_joy_axis(dev, int(b.axis)), b)


func button_down(action: String) -> bool:
	var b: Dictionary = table.get(action, {})
	if int(b.get("button", -1)) < 0:
		return false
	var dev := InputBindings.resolve_device(b)
	return dev >= 0 and Input.is_joy_button_pressed(dev, int(b.button))


func _own(name: String, on: bool) -> void:
	if on:
		_owned[name] = true
		Props.set_v("input/axis_owner/" + name, "joy")
	elif _owned.has(name):
		_owned.erase(name)
		Props.set_v("input/axis_owner/" + name, "")


func _write(name: String, v: Variant) -> void:
	_own(name, v != null)
	if v != null:
		Props.set_v("controls/" + name, v)


func _process(dt: float) -> void:
	if int(Props.get_v("input/bindings_rev", 0)) != _rev:
		_reload()
	var ctl := controls()
	var active := _levers(ctl)
	for a in ctl.axes():
		if a in OWN_AXES:
			continue
		var v = axis_value(a)
		active = active or v != null
		_write(str(InputBindings.AXES[a]).trim_prefix("controls/"), v)
	if ctl.offers("pitch_trim_axis"):
		var trim = axis_value("pitch_trim_axis")
		_write("pitch_trim", trim)
		if trim == null:  # trim buttons nudge the shared prop, like the keyboard
			var t := (1.0 if button_down("trim_up") else 0.0) - (1.0 if button_down("trim_down") else 0.0)
			if t != 0.0:
				Props.set_v("controls/pitch_trim", clampf(Props.get_f("controls/pitch_trim") + t * TRIM_RATE * dt, -1.0, 1.0))
	Props.set_v("controls/joystick_active", active)
	if ctl.offers("brakes"):
		_brakes()
	if ctl.offers("starter"):
		_write("starter", true if button_down("starter") else null)
	for a in ControlActions.HELD_BUTTONS:
		if ctl.offers(a):
			Props.set_v("input/held/" + a, button_down(a))
	_buttons(ctl)


## Throttle (lever 1), throttle_2 (lever 2, separate levers only) and mixture axes; true when one is bound.
## A lever axis maps through the reverse range and detents (lever_detents.gd). With separate levers and
## no throttle_2 axis bound, the throttle axis moves all levers.
func _levers(ctl: AircraftControls) -> bool:
	var lv := ctl.levers
	var v1 = axis_value("throttle") if ctl.offers("throttle") else null
	var v2 = axis_value("throttle_2") if ctl.offers("throttle_2") and lv.separate else null
	_own("throttle", v1 != null)
	_own("throttle_2", v2 != null or (v1 != null and lv.separate))
	if v1 != null:
		var p := LeverDetents.snap(LeverDetents.axis_to_pos(v1, lv.reverse_frac), lv.detents)
		if lv.separate and v2 == null:
			lv.write_pos_all(p)
		else:
			lv.write_pos(0, p)
	if v2 != null:
		lv.write_pos(1, LeverDetents.snap(LeverDetents.axis_to_pos(v2, lv.reverse_frac), lv.detents))
	var m = axis_value("mixture") if ctl.offers("mixture") else null
	_own("mixture", m != null)
	if m != null:
		lv.write_all("mixture", m)
	return v1 != null or v2 != null or m != null


func _brakes() -> void:
	var held := button_down("brakes")
	var pb := 1.0 if Props.get_b("controls/parking_brake") else 0.0
	for side in ["brake_left", "brake_right"]:
		var v = axis_value(side)
		if v == null and not held:
			_write(side, null)
			continue
		var x: float = 0.0 if v == null else v
		_write(side, maxf(pb, 1.0 if held else x))


func _buttons(ctl: AircraftControls) -> void:
	for a in ctl.buttons():
		var down := button_down(a)
		if down and not _prev.get(a, false):
			_press(a)
		_prev[a] = down


func _press(a: String) -> void:
	if ControlSteps.press(a):  # flaps, parking brake, magnetos, gear, autobrake, engine / APU / FCU toggles ...
		return
	controls()
	if not _lever_keys.detent_key(_ctl, a) and KEYS.has(a):
		tap_key(KEYS[a])


static func tap_key(k: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = down
		Input.parse_input_event(e)
