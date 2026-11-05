class_name JoystickControls
extends Node
## Joystick / gamepad pilot input -> Props "controls/*", per core/input_bindings.gd.
## Coexists with KeyboardControls: while a bound axis (or a held brake/starter button)
## drives a control, Props "input/axis_owner/<name>" = "joy" and the keyboard skips it.
## Publishes "controls/joystick_active" (a bound axis on a connected pad).
## View / map / pause buttons inject the matching key press so existing handlers run.
## Reloads the table when Props "input/bindings_rev" changes (the controls page bumps it).
## A lever (half-range axis) is ignored until its pad has reported a non-zero value (macOS sends no
## initial position). The flaps lever acts only when it changes; latching switches (ControlActions.LEVELS) act
## when they change and, per their `sync`, once when first seen (flight start, pad plugged in); selector switches
## (ControlActions.SELECTORS: engine mode, auto brake) follow their position from first sight.
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
var _flap_idx := -1  # last notch of the flaps lever, -1 until it has been read
var fake_buttons := {}  # tests only: action -> held, stands in for a connected pad (empty = real hardware)
var fake_axes := {}  # tests only: axis action -> raw value, null = the pad has not reported that axis yet
var _sel := {}  # selector name -> last value written
var _live := {}  # "device:axis" -> true once a lever axis has reported a non-zero value

## Axes with their own handling in _process (levers, brakes, trim); the rest are written as they are.
const OWN_AXES := ["throttle", "throttle_2", "mixture", "brake_left", "brake_right", "pitch_trim_axis", "flaps_lever"]


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
	resync()
	_live.clear()


## Forget the switch and lever positions seen so far: the next frame treats them as first seen (flight start
## or restart, pad plugged in), so latching switches and selectors set the sim from the hardware. The flaps
## lever only records its notch again.
func resync() -> void:
	_prev.clear()
	_sel.clear()
	_flap_idx = -1


## Shaped value of an axis action, or null when unbound / its pad is missing.
func axis_value(action: String) -> Variant:
	var b: Dictionary = table.get(action, {})
	if int(b.get("axis", -1)) < 0:
		return null
	if fake_axes.has(action):
		return null if fake_axes[action] == null else InputBindings.shape(float(fake_axes[action]), b)
	var dev := InputBindings.resolve_device(b)
	if dev < 0:
		return null
	var raw := Input.get_joy_axis(dev, int(b.axis))
	if str(b.get("range", "full")) == "half" and not _reported(dev, int(b.axis), raw):
		return null
	return InputBindings.shape(raw, b)


## True when the lever-2 axis is bound to a connected pad: it is then a lever of its own even before it has reported.
func _lever2_bound(ctl: AircraftControls) -> bool:
	if not ctl.offers("throttle_2") or not ctl.levers.separate:
		return false
	var b: Dictionary = table.get("throttle_2", {})
	return int(b.get("axis", -1)) >= 0 and (fake_axes.has("throttle_2") or InputBindings.resolve_device(b) >= 0)


## A lever reads exactly 0.0 until it has moved once on some systems (macOS sends no initial
## report), which would be a phantom mid-travel throttle. Ignore it until then.
func _reported(dev: int, axis: int, raw: float) -> bool:
	var k := "%d:%d" % [dev, axis]
	if raw != 0.0:
		_live[k] = true
	return _live.has(k)


func button_down(action: String) -> bool:
	if not fake_buttons.is_empty():
		return fake_buttons.get(action, false)
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
	if ctl.offers("flaps_lever"):
		_flaps_lever()
	for a in ctl.axes():
		if a in OWN_AXES:
			continue
		var v = _notched(a, axis_value(a))
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
## no throttle_2 axis bound, the throttle axis moves all levers. A bound lever 2 that has not reported yet
## (macOS sends no initial report, so it reads 0.0 until it moves once) rests at idle: it must not copy lever 1.
func _levers(ctl: AircraftControls) -> bool:
	var lv := ctl.levers
	var v1 = axis_value("throttle") if ctl.offers("throttle") else null
	var bound2 := _lever2_bound(ctl)
	var v2 = axis_value("throttle_2") if bound2 else null
	_own("throttle", v1 != null)
	_own("throttle_2", bound2 or (v1 != null and lv.separate))
	if v1 != null:
		var p := LeverDetents.snap(_lever_pos("throttle", v1, lv), lv.detents)
		if lv.separate and not bound2:
			lv.write_pos_all(p)
		else:
			lv.write_pos(0, p)
	if bound2:
		lv.write_pos(1, LeverDetents.snap(_lever_pos("throttle_2", v2, lv), lv.detents) if v2 != null else 0.0)
	var m = axis_value("mixture") if ctl.offers("mixture") else null
	_own("mixture", m != null)
	if m != null:
		lv.write_all("mixture", m)
	return v1 != null or v2 != null or m != null


## Lever position of a shaped axis value v (lever_detents.gd from_binding, which has the rules).
func _lever_pos(action: String, v: float, lv: EngineLevers) -> float:
	var b: Dictionary = table.get(action, {})
	var raw = fake_axes[action] if fake_axes.has(action) else InputBindings.raw_value(b)
	return LeverDetents.axis_to_pos(v, lv.reverse_frac) if raw == null \
		else LeverDetents.from_binding(b, float(raw), v, lv.detents, lv.reverse_frac)


## An axis with notches (speed brake lever) gives its nearest notch's value instead of the shaped one.
func _notched(action: String, v: Variant) -> Variant:
	var b: Dictionary = table.get(action, {})
	var raw = InputBindings.raw_value(b)
	return v if v == null or raw == null else InputBindings.notched(b, float(raw), float(v))


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
		if ControlActions.in_selector(a):
			continue
		var down := button_down(a)
		if ControlActions.LEVELS.has(a):
			_level(a, down)
			continue
		if down and not _prev.get(a, false):
			_press(a)
		_prev[a] = down
	_selectors(ctl)


## Is the button bound and its pad connected (a missing pad reads "released", which is not a position)?
func _seen(a: String) -> bool:
	if not fake_buttons.is_empty():
		return fake_buttons.has(a)
	var b: Dictionary = table.get(a, {})
	return int(b.get("button", -1)) >= 0 and InputBindings.resolve_device(b) >= 0


## A latching switch: acts when it changes; when first seen it sets the sim per the switch's `sync`.
func _level(a: String, down: bool) -> void:
	if not _seen(a):
		_prev.erase(a)
		return
	if _prev.has(a):
		if _prev[a] != down:
			ControlSteps.level(a, down)
	else:
		var sync: String = ControlActions.LEVELS[a][3]
		if sync == "both" or (sync == "on" and down):
			ControlSteps.level(a, down)
	_prev[a] = down


## Selector switches of the aircraft: the prop takes the position's value when first seen and on every change.
func _selectors(ctl: AircraftControls) -> void:
	for name in ControlActions.SELECTORS:
		var spec: Dictionary = ControlActions.SELECTORS[name]
		var value: int = spec.rest
		var any := false
		for a in spec.positions.keys().filter(func(k): return ctl.offers(k) and _seen(k)):
			any = true
			value = maxi(value, int(spec.positions[a]) if button_down(a) else value)
		if not any:
			_sel.erase(name)
		elif _sel.get(name, -1) != value:
			_sel[name] = value
			Props.set_v(spec.prop, value)


## The flaps lever's nearest notch sets the flaps (notches beyond the aircraft's last flap detent
## stay on it). Only a change of notch acts, so the keyboard and buttons still work between moves.
func _flaps_lever() -> void:
	var b: Dictionary = table.get("flaps_lever", {})
	var raw = InputBindings.raw_value(b)
	if raw != null and not _reported(InputBindings.resolve_device(b), int(b.axis), float(raw)):
		raw = null  # not moved yet: the pad has sent no real position
	if raw == null or not b.get("detents") is Array or b.detents.is_empty():
		_flap_idx = -1
		return
	flap_notch(InputBindings.detent_index(float(raw), b.detents))


## `ctl` is the aircraft's controls (its notch -> setting table); default the current aircraft's.
func flap_notch(i: int, ctl: AircraftControls = null) -> void:
	if _flap_idx >= 0 and i != _flap_idx:
		Props.set_v("controls/flaps", ControlSteps.flap_setting(i, ctl if ctl != null else controls()))
	_flap_idx = i


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
