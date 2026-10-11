class_name KeyBindings
extends RefCounted
## Rebindable flight-control keys: action -> up to SLOTS key specs
## {key: physical keycode, shift, ctrl, alt}. Saved to user://key_bindings.json.
## Held actions (pitch, throttle, brakes…) are polled every frame; press actions
## (flaps, magnetos…) fire on key-down. Defaults are the original hard-coded keys.
## Modifier rule: ctrl / alt must match exactly; shift must match only when the same
## key is also bound with Shift somewhere (B = brakes vs Shift+B = parking brake).

const PATH := "user://key_bindings.json"
const SLOTS := 3

const HELD := ["pitch_down", "pitch_up", "roll_left", "roll_right", "yaw_left", "yaw_right",
	"throttle_up", "throttle_down", "mixture_rich", "mixture_lean", "trim_down", "trim_up",
	"brakes", "brake_left", "brake_right", "starter"]
const PRESS := ["flaps_down", "flaps_up", "parking_brake", "magnetos_next", "mouse_yoke"]
const LABELS := {
	"pitch_down": "Pitch: push (nose down)", "pitch_up": "Pitch: pull (nose up)",
	"roll_left": "Roll left", "roll_right": "Roll right", "yaw_left": "Rudder left", "yaw_right": "Rudder right",
	"throttle_up": "Throttle up", "throttle_down": "Throttle down", "mixture_rich": "Mixture richer",
	"mixture_lean": "Mixture leaner", "trim_down": "Trim nose down", "trim_up": "Trim nose up",
	"brakes": "Both brakes (hold)", "brake_left": "Left brake (hold)", "brake_right": "Right brake (hold)",
	"starter": "Starter (hold)", "flaps_down": "Flaps down one notch", "flaps_up": "Flaps up one notch",
	"parking_brake": "Parking brake toggle", "magnetos_next": "Magnetos cycle", "mouse_yoke": "Mouse yoke toggle",
}
## Other in-flight hotkeys (not rebindable here): a binding on one of these is a conflict.
const RESERVED := {
	KEY_C: "camera", KEY_1: "view 1", KEY_2: "view 2", KEY_3: "view 3", KEY_4: "view 4",
	KEY_5: "view 5", KEY_6: "view 6", KEY_7: "view 7", KEY_8: "view 8", KEY_V: "re-centre view",
	KEY_N: "moving map", KEY_T: "taxi route", KEY_P: "pushback", KEY_H: "HUD", KEY_J: "controls panel",
	KEY_TAB: "panel layout", KEY_QUOTELEFT: "radio menu", KEY_ESCAPE: "pause", KEY_F1: "key help",
	KEY_F2: "checklists", KEY_F3: "perf overlay", KEY_F5: "reset", KEY_F8: "recording",
	KEY_F9: "failures", KEY_F10: "settings", KEY_F11: "saved flights", KEY_F12: "credits",
	KEY_R: "instant replay", KEY_L: "panel light (Shift: dimmer)",
}


static func spec(key: int, shift := false, ctrl := false, alt := false) -> Dictionary:
	return {"key": key, "shift": shift, "ctrl": ctrl, "alt": alt}


static func defaults() -> Dictionary:
	var k := {
		"pitch_down": [KEY_UP, KEY_KP_8], "pitch_up": [KEY_DOWN, KEY_KP_2],
		"roll_left": [KEY_LEFT, KEY_KP_4], "roll_right": [KEY_RIGHT, KEY_KP_6],
		"yaw_left": [KEY_Z, KEY_KP_0], "yaw_right": [KEY_X, KEY_KP_ENTER],
		"throttle_up": [KEY_PAGEUP, KEY_EQUAL, KEY_KP_ADD],
		"throttle_down": [KEY_PAGEDOWN, KEY_MINUS, KEY_KP_SUBTRACT],
		"mixture_rich": [KEY_APOSTROPHE], "mixture_lean": [KEY_SEMICOLON],
		"trim_down": [KEY_HOME, KEY_KP_7], "trim_up": [KEY_END, KEY_KP_1],
		"brakes": [KEY_B], "brake_left": [KEY_COMMA], "brake_right": [KEY_PERIOD], "starter": [KEY_S],
		"flaps_down": [KEY_F7, KEY_BRACKETRIGHT], "flaps_up": [KEY_F6, KEY_BRACKETLEFT],
		"magnetos_next": [KEY_M], "mouse_yoke": [KEY_Y],
	}
	var t := {}
	for a in k:
		t[a] = k[a].map(func(c): return spec(c))
	t.parking_brake = [spec(KEY_B, true)]
	return t


static func describe(s: Dictionary) -> String:
	var parts := []
	for m in ["ctrl", "alt", "shift"]:
		if s.get(m, false):
			parts.append(m.capitalize())
	var n := OS.get_keycode_string(int(s.key))
	parts.append(SHORT.get(n, n.replace("Kp ", "Num ")))
	return "+".join(parts)


const SHORT := {"BracketLeft": "[", "BracketRight": "]", "Apostrophe": "'", "Semicolon": ";",
	"Comma": ",", "Period": ".", "Minus": "−", "Equal": "=", "Slash": "/", "Backslash": "\\",
	"QuoteLeft": "`", "Kp Add": "Num +", "Kp Subtract": "Num −", "Kp Multiply": "Num *",
	"Kp Divide": "Num /", "Kp Period": "Num .", "Up": "↑", "Down": "↓", "Left": "←", "Right": "→"}


static func from_event(e: InputEventKey) -> Dictionary:
	var k := int(e.physical_keycode) if e.physical_keycode != KEY_NONE else int(e.keycode)
	return spec(k, e.shift_pressed, e.ctrl_pressed or e.meta_pressed, e.alt_pressed)


static func same(a: Dictionary, b: Dictionary) -> bool:
	return int(a.key) == int(b.key) and bool(a.shift) == bool(b.shift) \
		and bool(a.ctrl) == bool(b.ctrl) and bool(a.alt) == bool(b.alt)


## Keys that are also bound with Shift (so their unshifted binding needs Shift up).
static func shifted_keys(t: Dictionary) -> Dictionary:
	var out := {}
	for a in t:
		for s in t[a]:
			if s.shift:
				out[int(s.key)] = true
	return out


static func _mods_ok(s: Dictionary, shift: bool, ctrl: bool, alt: bool, strict_shift: bool) -> bool:
	if bool(s.ctrl) != ctrl or bool(s.alt) != alt:
		return false
	return shift == bool(s.shift) if (s.shift or strict_shift) else true


## Is a held action active now (polls the keyboard)?
static func held(t: Dictionary, action: String, shifted: Dictionary) -> bool:
	var sh := Input.is_key_pressed(KEY_SHIFT)
	var ct := Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_META)
	var al := Input.is_key_pressed(KEY_ALT)
	for s in t.get(action, []):
		if Input.is_physical_key_pressed(int(s.key)) and _mods_ok(s, sh, ct, al, shifted.has(int(s.key))):
			return true
	return false


## Does a key-down event trigger this press action?
static func matches(t: Dictionary, action: String, e: InputEventKey, shifted: Dictionary) -> bool:
	var ev := from_event(e)
	for s in t.get(action, []):
		if int(s.key) == ev.key and _mods_ok(s, ev.shift, ev.ctrl, ev.alt, shifted.has(int(s.key))):
			return true
	return false


## Conflicts as readable strings: a key spec on two actions, or on a reserved hotkey.
static func conflicts(t: Dictionary) -> Array:
	var out := []
	var acts := t.keys()
	for i in acts.size():
		for s in t[acts[i]]:
			if not s.shift and not s.ctrl and not s.alt and RESERVED.has(int(s.key)):
				out.append("%s: %s is also %s" % [LABELS.get(acts[i], acts[i]), describe(s), RESERVED[int(s.key)]])
			for j in range(i + 1, acts.size()):
				for o in t[acts[j]]:
					if same(s, o):
						out.append("%s is bound to both %s and %s" % [describe(s),
							LABELS.get(acts[i], acts[i]), LABELS.get(acts[j], acts[j])])
	return out


static func save_to(t: Dictionary, path := PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("KeyBindings: cannot write %s" % path)
		return false
	f.store_string(JSON.stringify({"version": 1, "keys": t}, "  "))
	return true


## Missing actions fall back to defaults; unknown actions are dropped.
static func load_from(path := PATH) -> Dictionary:
	var t := defaults()
	if not FileAccess.file_exists(path):
		return t
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary or not d.get("keys") is Dictionary:
		push_warning("KeyBindings: bad file %s, using defaults" % path)
		return t
	for a in d.keys:
		if t.has(a) and d.keys[a] is Array:
			var l := []
			for s in d.keys[a]:
				if s is Dictionary and s.has("key"):
					l.append(spec(int(s.key), bool(s.get("shift", false)), bool(s.get("ctrl", false)), bool(s.get("alt", false))))
			t[a] = l.slice(0, SLOTS)
	return t
