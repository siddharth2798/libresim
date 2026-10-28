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
		if down and not _prev.get(a, false):
			_press(a)
		_prev[a] = down


func _press(a: String) -> void:
	var flaps: int = Props.get_v("controls/flaps", 0)
	match a:
		"flaps_up":
			Props.set_v("controls/flaps", maxi(flaps - 1, 0))
		"flaps_down":
			Props.set_v("controls/flaps", mini(flaps + 1, int(Props.get_v("fdm/flap_detents", 4)) - 1))
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
