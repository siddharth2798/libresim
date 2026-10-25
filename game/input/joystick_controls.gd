class_name JoystickControls
extends Node
## Joystick / gamepad pilot input -> Props "controls/*", per core/input_bindings.gd.
## Coexists with KeyboardControls: while a bound axis (or a held brake/starter button)
## drives a control, Props "input/axis_owner/<name>" = "joy" and the keyboard skips it.
## Publishes "controls/joystick_active" (a bound axis on a connected pad).
## View / map / pause buttons inject the matching key press so existing handlers run.
## Reloads the table when Props "input/bindings_rev" changes (the controls page bumps it).

const TRIM_RATE := 0.15  # same as KeyboardControls
const KEYS := {"view_next": KEY_C, "view_cockpit": KEY_1, "toggle_map": KEY_N, "pause": KEY_ESCAPE}

var table := {}
var _rev := -1
var _prev := {}  # button action -> was pressed
var _owned := {}  # control name -> true while we own it
var _flap_idx := -1  # last notch of the flaps lever, -1 until it has been read
var _live := {}  # "device:axis" -> true once a lever axis has reported a non-zero value


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection)
	_reload()


func _reload() -> void:
	table = InputBindings.load_from()
	_rev = int(Props.get_v("input/bindings_rev", 0))


func _on_joy_connection(device: int, connected: bool) -> void:
	print("joystick %d %s: %s" % [device, "connected" if connected else "disconnected", Input.get_joy_name(device)])
	Props.set_v("input/joy_event", "%s %s" % [Input.get_joy_name(device), "connected" if connected else "disconnected"])
	_prev.clear()
	_live.clear()


## Shaped value of an axis action, or null when unbound / its pad is missing.
func axis_value(action: String) -> Variant:
	var b: Dictionary = table.get(action, {})
	if int(b.get("axis", -1)) < 0:
		return null
	var dev := InputBindings.resolve_device(b)
	if dev < 0:
		return null
	var raw := Input.get_joy_axis(dev, int(b.axis))
	if str(b.get("range", "full")) == "half" and not _reported(dev, int(b.axis), raw):
		return null
	return InputBindings.shape(raw, b)


## A lever (half-range axis) reads exactly 0.0 until it has moved once on some systems (macOS
## sends no initial report), which would be a phantom mid-travel throttle. Ignore it until then.
func _reported(dev: int, axis: int, raw: float) -> bool:
	var k := "%d:%d" % [dev, axis]
	if raw != 0.0:
		_live[k] = true
	return _live.has(k)


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
	var active := false
	for a in ["pitch", "roll", "yaw", "throttle", "mixture"]:
		var v = axis_value(a)
		active = active or v != null
		_write(a, v)
	var trim = axis_value("pitch_trim_axis")
	_write("pitch_trim", trim)
	if trim == null:  # trim buttons nudge the shared prop, like the keyboard
		var t := (1.0 if button_down("trim_up") else 0.0) - (1.0 if button_down("trim_down") else 0.0)
		if t != 0.0:
			Props.set_v("controls/pitch_trim", clampf(Props.get_f("controls/pitch_trim") + t * TRIM_RATE * dt, -1.0, 1.0))
	Props.set_v("controls/joystick_active", active)
	_brakes()
	_flaps_lever()
	var start := button_down("starter")
	_write("starter", true if start else null)
	_buttons()


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


func _buttons() -> void:
	for a in InputBindings.BUTTONS:
		var down := button_down(a)
		if a in InputBindings.LEVEL:  # a switch: act when it changes, not when first seen
			if _prev.has(a) and _prev[a] != down:
				_level(a, down)
		elif down and not _prev.get(a, false):
			_press(a)
		_prev[a] = down


## A latching switch changed: parking brake on = held, magnetos BOTH = held / OFF = released.
func _level(a: String, down: bool) -> void:
	match a:
		"parking_brake_switch":
			Props.set_v("controls/parking_brake", down)
		"magnetos_switch":
			Props.set_v("controls/magnetos", 3 if down else 0)


## The flaps lever's nearest notch sets the flaps (C172: 0..3, notches beyond 3 stay at 3).
## Only a change of notch acts, so the keyboard and buttons still work between moves.
func _flaps_lever() -> void:
	var b: Dictionary = table.get("flaps_lever", {})
	var raw = InputBindings.raw_value(b)
	if raw != null and not _reported(InputBindings.resolve_device(b), int(b.axis), float(raw)):
		raw = null  # not moved yet: the pad has sent no real position
	if raw == null or not b.get("detents") is Array or b.detents.is_empty():
		_flap_idx = -1
		return
	flap_notch(clampi(InputBindings.detent_index(float(raw), b.detents), 0, 3))


func flap_notch(i: int) -> void:
	if _flap_idx >= 0 and i != _flap_idx:
		Props.set_v("controls/flaps", i)
	_flap_idx = i


func _press(a: String) -> void:
	var flaps: int = Props.get_v("controls/flaps", 0)
	match a:
		"flaps_up":
			Props.set_v("controls/flaps", maxi(flaps - 1, 0))
		"flaps_down":
			Props.set_v("controls/flaps", mini(flaps + 1, 3))
		"parking_brake":
			Props.set_v("controls/parking_brake", not Props.get_b("controls/parking_brake"))
		"magnetos_next":
			Props.set_v("controls/magnetos", (int(Props.get_v("controls/magnetos", 3)) + 1) % 4)
		_:
			if KEYS.has(a):
				tap_key(KEYS[a])


static func tap_key(k: Key) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = down
		Input.parse_input_event(e)
