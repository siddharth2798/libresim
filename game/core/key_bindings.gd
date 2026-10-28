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
	"brakes", "brake_left", "brake_right", "starter",
	# twin-jet / airliner actions (offered per aircraft: input/control_actions.gd)
	"throttle_1_up", "throttle_1_down", "throttle_2_up", "throttle_2_down", "reverse", "apu_start",
	"rudder_trim_left", "rudder_trim_right", "fcu_spd_up", "fcu_spd_down", "fcu_hdg_right", "fcu_hdg_left",
	"fcu_alt_up", "fcu_alt_down", "fcu_vs_up", "fcu_vs_down"]
const PRESS := ["flaps_down", "flaps_up", "parking_brake", "magnetos_next", "mouse_yoke",
	"master", "avionics", "fuel_selector", "fuel_shutoff", "beacon", "nav_lights", "strobes",
	"landing_light", "taxi_light", "pitot_heat",
	"throttle_detent_up", "throttle_detent_down", "speedbrake_out", "speedbrake_in", "gear_toggle",
	"autobrake_next", "engine_master_1", "engine_master_2", "engine_mode_next", "apu_master",
	"fcu_ap1", "fcu_ap2", "fcu_athr", "fcu_loc", "fcu_appr", "anti_ice_wing", "anti_ice_eng_1", "anti_ice_eng_2"]
## Switch-row toggles: action -> Props path (fuel_selector cycles OFF/L/R/BOTH instead).
const SWITCHES := {"avionics": "controls/electrical/avionics", "fuel_shutoff": "controls/fuel/shutoff",
	"beacon": "controls/lights/beacon", "nav_lights": "controls/lights/nav", "strobes": "controls/lights/strobe",
	"landing_light": "controls/lights/landing", "taxi_light": "controls/lights/taxi",
	"pitot_heat": "controls/electrical/pitot_heat"}
const LABELS := {
	"pitch_down": "Pitch: push (nose down)", "pitch_up": "Pitch: pull (nose up)",
	"roll_left": "Roll left", "roll_right": "Roll right", "yaw_left": "Rudder left", "yaw_right": "Rudder right",
	"throttle_up": "Throttle up", "throttle_down": "Throttle down", "mixture_rich": "Mixture richer",
	"mixture_lean": "Mixture leaner", "trim_down": "Trim nose down", "trim_up": "Trim nose up",
	"brakes": "Both brakes (hold)", "brake_left": "Left brake (hold)", "brake_right": "Right brake (hold)",
	"starter": "Starter (hold)", "flaps_down": "Flaps down one notch", "flaps_up": "Flaps up one notch",
	"parking_brake": "Parking brake toggle", "magnetos_next": "Magnetos cycle", "mouse_yoke": "Mouse yoke toggle",
	"master": "Master switch (BAT + ALT)", "avionics": "Avionics master", "fuel_selector": "Fuel selector cycle",
	"fuel_shutoff": "Fuel shutoff valve", "beacon": "Beacon", "nav_lights": "Nav lights", "strobes": "Strobes",
	"landing_light": "Landing light", "taxi_light": "Taxi light", "pitot_heat": "Pitot heat",
	"throttle_1_up": "Thrust lever 1 up", "throttle_1_down": "Thrust lever 1 down",
	"throttle_2_up": "Thrust lever 2 up", "throttle_2_down": "Thrust lever 2 down",
	"throttle_detent_up": "Thrust levers: next detent up", "throttle_detent_down": "Thrust levers: next detent down",
	"reverse": "Thrust reverse (hold)", "speedbrake_out": "Speedbrake out", "speedbrake_in": "Speedbrake in",
	"gear_toggle": "Landing gear up / down", "autobrake_next": "Autobrake cycle",
	"engine_master_1": "Engine 1 master", "engine_master_2": "Engine 2 master", "engine_mode_next": "Engine mode cycle",
	"apu_master": "APU master", "apu_start": "APU start (hold)",
	"anti_ice_wing": "Wing anti-ice", "anti_ice_eng_1": "Engine 1 anti-ice", "anti_ice_eng_2": "Engine 2 anti-ice",
	"rudder_trim_left": "Rudder trim left", "rudder_trim_right": "Rudder trim right",
	"fcu_ap1": "Autopilot 1", "fcu_ap2": "Autopilot 2", "fcu_athr": "Autothrust", "fcu_loc": "FCU LOC", "fcu_appr": "FCU APPR",
	"fcu_spd_up": "FCU speed up", "fcu_spd_down": "FCU speed down", "fcu_hdg_right": "FCU heading right",
	"fcu_hdg_left": "FCU heading left", "fcu_alt_up": "FCU altitude up", "fcu_alt_down": "FCU altitude down",
	"fcu_vs_up": "FCU vertical speed up", "fcu_vs_down": "FCU vertical speed down",
}
## Other in-flight hotkeys (not rebindable here): a binding on one of these is a conflict.
const RESERVED := {
	KEY_C: "camera", KEY_1: "view 1", KEY_2: "view 2", KEY_3: "view 3", KEY_4: "view 4",
	KEY_5: "view 5", KEY_6: "view 6", KEY_7: "view 7", KEY_8: "view 8", KEY_V: "re-centre view",
	KEY_N: "moving map", KEY_T: "taxi route", KEY_P: "pushback", KEY_H: "HUD", KEY_J: "controls panel",
	KEY_TAB: "panel layout", KEY_QUOTELEFT: "radio menu", KEY_ESCAPE: "pause", KEY_F1: "key help",
	KEY_F2: "checklists", KEY_F3: "perf overlay", KEY_F5: "reset", KEY_F8: "recording",
	KEY_F9: "failures", KEY_F10: "settings", KEY_F11: "saved flights", KEY_F12: "credits",
	KEY_R: "instant replay", KEY_L: "panel light (Shift: dimmer)", KEY_K: "training callouts", KEY_BACKSPACE: "dismiss taxi message",
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
	# switch row (cold & dark start-up without the mouse)
	t.master = [spec(KEY_M, true)]
	t.avionics = [spec(KEY_V, true)]
	t.fuel_selector = [spec(KEY_F, true)]
	t.fuel_shutoff = [spec(KEY_F, false, true)]
	t.beacon = [spec(KEY_B, false, true)]
	t.nav_lights = [spec(KEY_N, false, true)]
	t.strobes = [spec(KEY_S, false, true)]
	t.landing_light = [spec(KEY_L, false, true)]
	t.taxi_light = [spec(KEY_T, false, true)]
	t.pitot_heat = [spec(KEY_H, false, true)]
	_add_airliner_defaults(t)
	return t


## Defaults of the actions only some aircraft offer (Alt / Ctrl chords and keys the C172 set leaves free).
static func _add_airliner_defaults(t: Dictionary) -> void:
	t.throttle_1_up = [spec(KEY_PAGEUP, false, false, true)]
	t.throttle_1_down = [spec(KEY_PAGEDOWN, false, false, true)]
	t.throttle_2_up = [spec(KEY_HOME, false, false, true)]
	t.throttle_2_down = [spec(KEY_END, false, false, true)]
	t.throttle_detent_up = [spec(KEY_EQUAL, false, false, true)]
	t.throttle_detent_down = [spec(KEY_MINUS, false, false, true)]
	t.reverse = [spec(KEY_KP_MULTIPLY), spec(KEY_X, false, true)]
	t.speedbrake_out = [spec(KEY_BACKSLASH)]
	t.speedbrake_in = [spec(KEY_SLASH)]
	t.gear_toggle = [spec(KEY_G, false, true)]
	t.autobrake_next = [spec(KEY_A, false, true)]
	t.engine_master_1 = [spec(KEY_E, false, true)]
	t.engine_master_2 = [spec(KEY_D, false, true)]
	t.engine_mode_next = [spec(KEY_I, false, true)]
	t.apu_master = [spec(KEY_U, false, true)]
	t.apu_start = [spec(KEY_U, false, false, true)]
	t.anti_ice_wing = [spec(KEY_W, false, true)]
	t.anti_ice_eng_1 = [spec(KEY_E, false, false, true)]
	t.anti_ice_eng_2 = [spec(KEY_D, false, false, true)]
	t.rudder_trim_left = [spec(KEY_Z, false, false, true)]
	t.rudder_trim_right = [spec(KEY_X, false, false, true)]
	for i in 5:  # Ctrl+1..5 (the view keys ignore Ctrl)
		t[["fcu_ap1", "fcu_ap2", "fcu_athr", "fcu_loc", "fcu_appr"][i]] = [spec(KEY_1 + i, false, true)]
	t.fcu_spd_up = [spec(KEY_BRACKETRIGHT, false, false, true)]
	t.fcu_spd_down = [spec(KEY_BRACKETLEFT, false, false, true)]
	t.fcu_hdg_right = [spec(KEY_RIGHT, false, false, true)]
	t.fcu_hdg_left = [spec(KEY_LEFT, false, false, true)]
	t.fcu_alt_up = [spec(KEY_UP, false, false, true)]
	t.fcu_alt_down = [spec(KEY_DOWN, false, false, true)]
	t.fcu_vs_up = [spec(KEY_APOSTROPHE, false, false, true)]
	t.fcu_vs_down = [spec(KEY_SEMICOLON, false, false, true)]


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
## `only` (when not empty) limits the check to those actions (what the aircraft offers).
static func conflicts(t: Dictionary, only := []) -> Array:
	var out := []
	var acts := t.keys() if only.is_empty() else t.keys().filter(func(a): return a in only)
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
