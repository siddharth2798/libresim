extends RefCounted
## Joystick bindings (core/input_bindings.gd) and JoystickControls / keyboard coexistence.

const TMP := "user://test_input_bindings.json"


func _near(a: float, b: float, tol := 1e-4) -> bool:
	return absf(a - b) <= tol


func test_input_deadzone_invert() -> String:
	var b := {"range": "full", "deadzone": 0.1, "expo": 0.0, "invert": false}
	if InputBindings.shape(0.05, b) != 0.0 or InputBindings.shape(-0.1, b) != 0.0:
		return "inside deadzone not zero"
	if not _near(InputBindings.shape(0.55, b), 0.5) or not _near(InputBindings.shape(-0.55, b), -0.5):
		return "deadzone rescale wrong: %f" % InputBindings.shape(0.55, b)
	if not _near(InputBindings.shape(1.0, b), 1.0) or not _near(InputBindings.shape(-1.0, b), -1.0):
		return "full travel not reaching ±1"
	b.invert = true
	if not _near(InputBindings.shape(0.55, b), -0.5):
		return "invert wrong"
	if not _near(InputBindings.shape(3.0, b), -1.0):
		return "out-of-range raw not clamped"
	return ""


func test_input_expo() -> String:
	var b := {"range": "full", "deadzone": 0.0, "expo": 1.0}
	if not _near(InputBindings.shape(0.5, b), 0.125) or not _near(InputBindings.shape(-0.5, b), -0.125):
		return "expo 1 should be cubic: %f" % InputBindings.shape(0.5, b)
	b.expo = 0.5
	if not _near(InputBindings.shape(0.5, b), 0.3125):
		return "expo 0.5 blend wrong: %f" % InputBindings.shape(0.5, b)
	if not _near(InputBindings.shape(1.0, b), 1.0):
		return "expo changes full travel"
	var prev := -1.0
	for i in 21:  # monotonic over the whole travel
		var v := InputBindings.shape(-1.0 + i * 0.1, {"range": "full", "deadzone": 0.1, "expo": 0.4})
		if v < prev:
			return "shape not monotonic"
		prev = v
	return ""


func test_input_half_and_trigger() -> String:
	var h := {"range": "half", "deadzone": 0.0, "expo": 0.0, "invert": false}
	for p in [[-1.0, 0.0], [0.0, 0.5], [1.0, 1.0]]:
		if not _near(InputBindings.shape(p[0], h), p[1]):
			return "half %f -> %f, want %f" % [p[0], InputBindings.shape(p[0], h), p[1]]
	h.invert = true  # throttle lever: forward = -1 = full power
	if not _near(InputBindings.shape(-1.0, h), 1.0) or not _near(InputBindings.shape(1.0, h), 0.0):
		return "inverted half wrong"
	h.invert = false
	h.deadzone = 0.1
	if InputBindings.shape(-0.85, h) != 0.0:
		return "half deadzone should hold idle near the stop"
	var t := {"range": "trigger", "deadzone": 0.0, "expo": 0.0}
	if InputBindings.shape(0.0, t) != 0.0 or not _near(InputBindings.shape(0.6, t), 0.6) or InputBindings.shape(-0.5, t) != 0.0:
		return "trigger range wrong"
	t.invert = true
	if not _near(InputBindings.shape(0.0, t), 1.0):
		return "inverted trigger wrong"
	return ""


func test_input_defaults_complete() -> String:
	for prof in ["gamepad", "joystick"]:
		var d := InputBindings.defaults(prof)
		for a in InputBindings.AXES.keys() + InputBindings.BUTTONS:
			if not d.has(a):
				return "%s defaults missing %s" % [prof, a]
		if d.pitch.axis < 0 or d.roll.axis < 0 or d.flaps_up.button < 0 or d.brakes.button < 0:
			return "%s defaults leave primary controls unbound" % prof
		if d.pitch.get("invert", false):
			return "%s: pitch must not be inverted (stick forward = -1 = nose down)" % prof
	var g := InputBindings.defaults("gamepad")
	if g.brake_left.range != "trigger" or g.throttle.range != "half":
		return "gamepad ranges wrong"
	return ""


func test_input_save_load_roundtrip() -> String:
	var t := InputBindings.defaults("joystick")
	t.yaw.invert = true
	t.yaw.deadzone = 0.17
	t.yaw.expo = 0.45
	t.yaw.guid = "abc123"
	t.mixture.axis = 5
	t.mixture.device = 2
	t.pause.button = -1
	if not InputBindings.save_to(t, TMP):
		return "save failed"
	var r := InputBindings.load_from(TMP)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	for a in t:
		for k in t[a]:
			if typeof(r[a][k]) != typeof(t[a][k]) or r[a][k] != t[a][k]:
				return "%s.%s: %s != %s" % [a, k, r[a][k], t[a][k]]
	if typeof(r.mixture.axis) != TYPE_INT:
		return "axis index not int after load"
	var miss := InputBindings.load_from("user://does_not_exist.json", "gamepad")
	return "" if miss.roll.axis == JOY_AXIS_LEFT_X else "missing file did not give defaults"


func test_input_keyboard_yields_to_joy() -> String:
	var k := KeyboardControls.new()
	Props.set_v("input/axis_owner/pitch", "joy")
	Props.set_v("controls/pitch", 0.42)
	k._process(0.1)
	var held := Props.get_f("controls/pitch")
	Props.set_v("input/axis_owner/pitch", "")
	k._process(0.1)
	var back := Props.get_f("controls/pitch")
	k.free()
	if not _near(held, 0.42):
		return "keyboard overwrote a joystick-owned axis"
	return "" if _near(back, 0.0) else "keyboard did not resume after release"


func test_input_joystick_unbound_releases() -> String:
	var j := JoystickControls.new()
	j.table = InputBindings.defaults("gamepad")
	for b in j.table.values():  # point every binding at a pad that is not there, whatever is plugged in
		b.device = 99
	j._rev = int(Props.get_v("input/bindings_rev", 0))
	j._own("pitch", true)
	j._process(0.016)  # bound pad missing -> nothing owned, joystick inactive
	var owner = Props.get_v("input/axis_owner/pitch", "")
	var active := Props.get_b("controls/joystick_active")
	j.free()
	if owner == "joy":
		return "axis still owned with no pad connected"
	return "" if not active else "joystick_active true with no pad"


func test_input_button_effects() -> String:
	var j := JoystickControls.new()
	Props.set_v("controls/flaps", 0)
	j._press("flaps_down")
	j._press("flaps_down")
	j._press("flaps_up")
	var flaps: int = Props.get_v("controls/flaps")
	Props.set_v("controls/parking_brake", false)
	j._press("parking_brake")
	var pb := Props.get_b("controls/parking_brake")
	Props.set_v("controls/magnetos", 3)
	j._press("magnetos_next")
	var mags: int = Props.get_v("controls/magnetos")
	Props.set_v("controls/parking_brake", false)
	j.free()
	if flaps != 1:
		return "flaps buttons: got %d, want 1" % flaps
	if not pb:
		return "parking brake button did not toggle"
	return "" if mags == 0 else "magnetos did not cycle BOTH -> OFF"


func _key(k: Key, shift := false, ctrl := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.shift_pressed = shift
	e.ctrl_pressed = ctrl
	e.pressed = true
	return e


func test_input_keys_defaults_match_old() -> String:
	var old := {  # the hard-coded keys keyboard_controls.gd used before bindings
		"pitch_down": [KEY_UP, KEY_KP_8], "pitch_up": [KEY_DOWN, KEY_KP_2],
		"roll_left": [KEY_LEFT, KEY_KP_4], "roll_right": [KEY_RIGHT, KEY_KP_6],
		"yaw_left": [KEY_Z, KEY_KP_0], "yaw_right": [KEY_X, KEY_KP_ENTER],
		"throttle_up": [KEY_PAGEUP, KEY_EQUAL, KEY_KP_ADD], "throttle_down": [KEY_PAGEDOWN, KEY_MINUS, KEY_KP_SUBTRACT],
		"mixture_rich": [KEY_APOSTROPHE], "mixture_lean": [KEY_SEMICOLON],
		"trim_down": [KEY_HOME, KEY_KP_7], "trim_up": [KEY_END, KEY_KP_1],
		"brakes": [KEY_B], "brake_left": [KEY_COMMA], "brake_right": [KEY_PERIOD], "starter": [KEY_S],
		"flaps_down": [KEY_F7, KEY_BRACKETRIGHT], "flaps_up": [KEY_F6, KEY_BRACKETLEFT],
		"magnetos_next": [KEY_M], "mouse_yoke": [KEY_Y], "parking_brake": [KEY_B],
	}
	var d := KeyBindings.defaults()
	if d.size() != (KeyBindings.HELD + KeyBindings.PRESS).size() or not d.has_all(old.keys()):
		return "default action count %d, want %d incl. the %d original actions" % [d.size(), (KeyBindings.HELD + KeyBindings.PRESS).size(), old.size()]
	for a in old:
		var got: Array = d[a].map(func(s): return int(s.key))
		if got != old[a]:
			return "%s: %s != %s" % [a, got, old[a]]
	if not d.parking_brake[0].shift or d.brakes[0].shift:
		return "parking brake must be Shift+B and brakes plain B"
	if not KeyBindings.conflicts(d).is_empty():
		return "defaults have conflicts: %s" % KeyBindings.conflicts(d)
	return ""


func test_input_keys_roundtrip() -> String:
	var t := KeyBindings.defaults()
	t.pitch_up = [KeyBindings.spec(KEY_W), KeyBindings.spec(KEY_K, false, true, true)]
	t.starter = []
	if not KeyBindings.save_to(t, TMP):
		return "save failed"
	var r := KeyBindings.load_from(TMP)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	if r.size() != t.size():
		return "action count changed"
	for a in t:
		if r[a].size() != t[a].size():
			return "%s: %d keys after load, want %d" % [a, r[a].size(), t[a].size()]
		for i in t[a].size():
			if not KeyBindings.same(r[a][i], t[a][i]) or typeof(r[a][i].key) != TYPE_INT:
				return "%s[%d]: %s != %s" % [a, i, r[a][i], t[a][i]]
	return ""


func test_input_keys_conflicts() -> String:
	var t := KeyBindings.defaults()
	t.starter = [KeyBindings.spec(KEY_M)]  # clashes with magnetos
	t.mouse_yoke = [KeyBindings.spec(KEY_N)]  # clashes with the moving map hotkey
	t.brake_left = [KeyBindings.spec(KEY_N, true)]  # Shift+N is fine
	var c := KeyBindings.conflicts(t)
	if c.size() != 2:
		return "want 2 conflicts, got %s" % [c]
	return ""


func test_input_keys_modifiers() -> String:
	var t := KeyBindings.defaults()
	var sh := KeyBindings.shifted_keys(t)
	if not KeyBindings.matches(t, "parking_brake", _key(KEY_B, true), sh):
		return "Shift+B should toggle parking brake"
	if KeyBindings.matches(t, "parking_brake", _key(KEY_B), sh):
		return "plain B toggled parking brake"
	if not KeyBindings.matches(t, "flaps_down", _key(KEY_F7, true), sh):
		return "Shift should not matter for keys never bound with Shift"
	if KeyBindings.matches(t, "flaps_down", _key(KEY_F7, false, true), sh):
		return "Ctrl+F7 should not match plain F7"
	# rebinding is honoured by KeyboardControls (event path)
	var k := KeyboardControls.new()
	k.keys = t
	k.keys.flaps_down = [KeyBindings.spec(KEY_G)]
	k._shifted = KeyBindings.shifted_keys(k.keys)
	Props.set_v("controls/flaps", 0)
	k._unhandled_key_input(_key(KEY_F7))
	var f0: int = Props.get_v("controls/flaps")
	k._unhandled_key_input(_key(KEY_G))
	var f1: int = Props.get_v("controls/flaps")
	k.free()
	Props.set_v("controls/flaps", 0)
	return "" if f0 == 0 and f1 == 1 else "rebound flaps key: F7 -> %d, G -> %d" % [f0, f1]
