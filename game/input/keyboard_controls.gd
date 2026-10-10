class_name KeyboardControls
extends Node
## Keyboard (and optional mouse-yoke) pilot input -> Props "controls/*".
## Primary controls are rate-based: holding a key moves the surface, releasing
## springs it back to centre. Throttle/mixture/trim move while held and stay put.
## See docs/USAGE.md for the key map.

const RATE := 1.6          # stick travel per second while held
const SPRING := 2.5        # return-to-centre per second
const LEVER_RATE := 0.5    # throttle / mixture per second
const TRIM_RATE := 0.15

var pitch := 0.0
var roll := 0.0
var yaw := 0.0
var mouse_yoke := false
var parking_brake := false


func _ready() -> void:
	Props.set_v("controls/parking_brake", false)


func _unhandled_key_input(e: InputEvent) -> void:
	if not e.pressed or e.echo:
		return
	var flaps: int = Props.get_v("controls/flaps", 0)
	match e.keycode:
		KEY_F7, KEY_BRACKETRIGHT:
			Props.set_v("controls/flaps", mini(flaps + 1, 3))
		KEY_F6, KEY_BRACKETLEFT:
			Props.set_v("controls/flaps", maxi(flaps - 1, 0))
		KEY_Y:
			mouse_yoke = not mouse_yoke
			Props.set_v("controls/mouse_yoke", mouse_yoke)
		KEY_M:
			Props.set_v("controls/magnetos", (int(Props.get_v("controls/magnetos", 3)) + 1) % 4)
		KEY_B:
			if e.shift_pressed:
				parking_brake = not parking_brake
				Props.set_v("controls/parking_brake", parking_brake)


func _axis(neg: Array, pos: Array) -> float:
	var v := 0.0
	for k in neg:
		if Input.is_physical_key_pressed(k):
			v -= 1.0
	for k in pos:
		if Input.is_physical_key_pressed(k):
			v += 1.0
	return v


static func _rate(cur: float, input: float, dt: float) -> float:
	if input != 0.0:
		# pressing against the current deflection moves faster (centre then deflect)
		var r := RATE * (2.0 if signf(input) != signf(cur) and cur != 0.0 else 1.0)
		return clampf(cur + input * r * dt, -1.0, 1.0)
	return move_toward(cur, 0.0, SPRING * dt)


func _process(dt: float) -> void:
	if mouse_yoke:
		var vp := get_viewport()
		var m := vp.get_mouse_position() / vp.get_visible_rect().size * 2.0 - Vector2.ONE
		roll = clampf(m.x * 1.3, -1.0, 1.0)
		pitch = clampf(m.y * 1.3, -1.0, 1.0)  # mouse down = pull back
	else:
		pitch = _rate(pitch, _axis([KEY_UP, KEY_KP_8], [KEY_DOWN, KEY_KP_2]), dt)
		roll = _rate(roll, _axis([KEY_LEFT, KEY_KP_4], [KEY_RIGHT, KEY_KP_6]), dt)
	yaw = _rate(yaw, _axis([KEY_Z, KEY_KP_0], [KEY_X, KEY_KP_ENTER]), dt)
	Props.set_v("controls/pitch", pitch)
	Props.set_v("controls/roll", roll)
	Props.set_v("controls/yaw", yaw)

	var thr := Props.get_f("controls/throttle") + _axis([KEY_PAGEDOWN, KEY_MINUS, KEY_KP_SUBTRACT],
		[KEY_PAGEUP, KEY_EQUAL, KEY_KP_ADD]) * LEVER_RATE * dt
	Props.set_v("controls/throttle", clampf(thr, 0.0, 1.0))
	var mix := Props.get_f("controls/mixture", 1.0) + _axis([KEY_SEMICOLON], [KEY_APOSTROPHE]) * LEVER_RATE * dt
	Props.set_v("controls/mixture", clampf(mix, 0.0, 1.0))
	var trim := Props.get_f("controls/pitch_trim") + _axis([KEY_HOME, KEY_KP_7], [KEY_END, KEY_KP_1]) * TRIM_RATE * dt
	Props.set_v("controls/pitch_trim", clampf(trim, -1.0, 1.0))

	var both := Input.is_physical_key_pressed(KEY_B) and not Input.is_key_pressed(KEY_SHIFT)
	var pb := 1.0 if parking_brake else 0.0
	Props.set_v("controls/brake_left", maxf(pb, 1.0 if both or Input.is_physical_key_pressed(KEY_COMMA) else 0.0))
	Props.set_v("controls/brake_right", maxf(pb, 1.0 if both or Input.is_physical_key_pressed(KEY_PERIOD) else 0.0))
	Props.set_v("controls/starter", Input.is_physical_key_pressed(KEY_S) and not Props.get_b("view/free_cam"))
