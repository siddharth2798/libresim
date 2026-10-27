class_name KeyboardControls
extends Node
## Keyboard (and optional mouse-yoke) pilot input -> Props "controls/*".
## Primary controls are rate-based: holding a key moves the surface; on release it
## springs back to centre (UserOptions keyboard_mode "spring", default) or stays put
## ("sticky", FlightGear style: tap the opposite key to come back, it stops at centre).
## Throttle/mixture/trim move while held and stay put. FdmNode low-passes the result.
## Keys come from core/key_bindings.gd (defaults: docs/USAGE.md key map).

const RATE := 1.6          # stick travel per second while held
const SPRING := 2.5        # return-to-centre per second
const LEVER_RATE := 0.5    # throttle / mixture per second
const TRIM_RATE := 0.15

var pitch := 0.0
var roll := 0.0
var yaw := 0.0
var mouse_yoke := false
var parking_brake := false
var keys := {}  # KeyBindings table (core/key_bindings.gd), reloaded on input/bindings_rev
var _shifted := {}
var _keys_rev := -1
var _detent := {}  # sticky mode: axis -> true while held at the centre detent


func _ready() -> void:
	Props.set_v("controls/parking_brake", false)
	_load_keys()


func _load_keys() -> void:
	keys = KeyBindings.load_from()
	_shifted = KeyBindings.shifted_keys(keys)
	_keys_rev = int(Props.get_v("input/bindings_rev", 0))


func _unhandled_key_input(e: InputEvent) -> void:
	if not e.pressed or e.echo:
		return
	var flaps: int = Props.get_v("controls/flaps", 0)
	if _on(e, "flaps_down"):
		Props.set_v("controls/flaps", mini(flaps + 1, 3))
	if _on(e, "flaps_up"):
		Props.set_v("controls/flaps", maxi(flaps - 1, 0))
	if _on(e, "mouse_yoke"):
		mouse_yoke = not mouse_yoke
		Props.set_v("controls/mouse_yoke", mouse_yoke)
	if _on(e, "magnetos_next"):
		Props.set_v("controls/magnetos", (int(Props.get_v("controls/magnetos", 3)) + 1) % 4)
	if e.keycode == KEY_L and not e.ctrl_pressed and not e.alt_pressed:  # PANEL light dimmer (fixed hotkey)
		Props.set_v("controls/lights/panel", LightLogic.step_panel(Props.get_f("controls/lights/panel"), -1 if e.shift_pressed else 1))
	if _on(e, "master"):  # BAT and ALT together, as pilots usually switch them
		var on := not Props.get_b("controls/electrical/master_bat")
		Props.set_v("controls/electrical/master_bat", on)
		Props.set_v("controls/electrical/master_alt", on)
	if _on(e, "fuel_selector"):  # OFF, LEFT, RIGHT, BOTH
		Props.set_v("controls/fuel/selector", (int(Props.get_v("controls/fuel/selector", 3)) + 1) % 4)
	for a in KeyBindings.SWITCHES:
		if _on(e, a):
			Props.set_v(KeyBindings.SWITCHES[a], not Props.get_b(KeyBindings.SWITCHES[a]))
	if _on(e, "parking_brake"):
		parking_brake = not Props.get_b("controls/parking_brake")
		Props.set_v("controls/parking_brake", parking_brake)


func _on(e: InputEventKey, action: String) -> bool:
	return KeyBindings.matches(keys, action, e, _shifted)


## Held keys count for nothing while the pause screen is open: its arrow keys navigate it.
func _k(action: String) -> bool:
	return not Props.get_b("ui/pause_open") and KeyBindings.held(keys, action, _shifted)


## -1 / 0 / +1 from a pair of held actions.
func _axis(neg: String, pos: String) -> float:
	return (1.0 if _k(pos) else 0.0) - (1.0 if _k(neg) else 0.0)


static func _rate(cur: float, input: float, dt: float) -> float:
	if input != 0.0:
		# pressing against the current deflection moves faster (centre then deflect)
		var r := RATE * (2.0 if signf(input) != signf(cur) and cur != 0.0 else 1.0)
		return clampf(cur + input * r * dt, -1.0, 1.0)
	return move_toward(cur, 0.0, SPRING * dt)


## Sticky (FlightGear) keys: move while held, stay on release; crossing centre stops
## there until the key is pressed again, so a tap on the opposite key re-centres.
func _sticky(axis: String, cur: float, input: float, dt: float) -> float:
	if input == 0.0:
		_detent.erase(axis)
		return cur
	if _detent.has(axis):
		return 0.0
	var v := clampf(cur + input * RATE * dt, -1.0, 1.0)
	if cur != 0.0 and signf(v) != signf(cur):
		_detent[axis] = true
		return 0.0
	return v


func _move(axis: String, cur: float, input: float, dt: float) -> float:
	return _sticky(axis, cur, input, dt) if UserOptions.get_v("keyboard_mode") == "sticky" else _rate(cur, input, dt)


func _process(dt: float) -> void:
	if int(Props.get_v("input/bindings_rev", 0)) != _keys_rev:
		_load_keys()
	if mouse_yoke and Props.get_b("ui/pause_open"):
		pass  # the mouse is a pointer in the pause screen: the yoke stays where it was
	elif mouse_yoke:
		var vp := get_viewport()
		var m := vp.get_mouse_position() / vp.get_visible_rect().size * 2.0 - Vector2.ONE
		roll = clampf(m.x * 1.3, -1.0, 1.0)
		pitch = clampf(m.y * 1.3, -1.0, 1.0)  # mouse down = pull back
	else:
		var pitch_in := 0.0 if Props.get_b("ui/radio_open") else _axis("pitch_down", "pitch_up")  # the open radio's Up/Down choose a call
		pitch = _move("pitch", pitch, pitch_in, dt)
		roll = _move("roll", roll, _axis("roll_left", "roll_right"), dt)
	yaw = _move("yaw", yaw, _axis("yaw_left", "yaw_right"), dt)
	_put("pitch", pitch)
	_put("roll", roll)
	_put("yaw", yaw)

	var thr := Props.get_f("controls/throttle")
	thr += _axis("throttle_down", "throttle_up") * LEVER_RATE * dt  # Ctrl+PgUp/PgDn (checklists) don't match
	_put("throttle", clampf(thr, 0.0, 1.0))
	var mix := Props.get_f("controls/mixture", 1.0) + _axis("mixture_lean", "mixture_rich") * LEVER_RATE * dt
	_put("mixture", clampf(mix, 0.0, 1.0))
	var trim := Props.get_f("controls/pitch_trim") + _axis("trim_down", "trim_up") * TRIM_RATE * dt
	_put("pitch_trim", clampf(trim, -1.0, 1.0))

	var both := _k("brakes")
	var pb := 1.0 if Props.get_b("controls/parking_brake") else 0.0
	_put("brake_left", maxf(pb, 1.0 if both or _k("brake_left") else 0.0))
	_put("brake_right", maxf(pb, 1.0 if both or _k("brake_right") else 0.0))
	_put("starter", _k("starter") and not Props.get_b("view/free_cam"))


## Write controls/<name> unless a joystick axis/button owns it (JoystickControls).
func _put(name: String, v: Variant) -> void:
	if Props.get_v("input/axis_owner/" + name, "") != "joy":
		Props.set_v("controls/" + name, v)
