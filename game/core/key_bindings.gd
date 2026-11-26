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
## File version 2: the autopilot / autothrust disconnect actions got default keys. A version 1 file saved them empty (no key
## was the default then, not a choice), so an empty slot list of these in an older file takes the new default.
const VERSION := 2
const DEFAULT_SINCE_V2 := ["fcu_ap_disc", "fcu_athr_disc"]

const HELD := ["pitch_down", "pitch_up", "roll_left", "roll_right", "yaw_left", "yaw_right",
	"throttle_up", "throttle_down", "mixture_rich", "mixture_lean", "trim_down", "trim_up",
	"brakes", "brake_left", "brake_right", "starter",
	# twin-jet / airliner actions (offered per aircraft: input/control_actions.gd)
	"throttle_1_up", "throttle_1_down", "throttle_2_up", "throttle_2_down", "reverse", "apu_start",
	"rudder_trim_left", "rudder_trim_right", "fcu_spd_up", "fcu_spd_down", "fcu_hdg_right", "fcu_hdg_left",
	"fcu_alt_up", "fcu_alt_down", "fcu_vs_up", "fcu_vs_down", "tiller_left", "tiller_right", "baro_up", "baro_down"]
const PRESS := ["flaps_down", "flaps_up", "parking_brake", "magnetos_next", "mouse_yoke",
	"master", "avionics", "fuel_selector", "fuel_shutoff", "beacon", "nav_lights", "strobes",
	"landing_light", "taxi_light", "pitot_heat",
	"throttle_detent_up", "throttle_detent_down", "speedbrake_out", "speedbrake_in", "gear_toggle",
	"autobrake_next", "engine_master_1", "engine_master_2", "engine_mode_next", "apu_master",
	"fcu_ap1", "fcu_ap2", "fcu_athr", "fcu_loc", "fcu_appr", "fcu_ap_disc", "fcu_athr_disc", "fcu_spd_mach", "fcu_trk_fpa",
	"master_warn", "fcu_metric_alt", "fcu_alt_1000", "efis_fd", "efis_ls", "baro_std", "nd_mode_next", "nd_range_up", "nd_range_down", "nd_filter_next", "anti_ice_wing", "anti_ice_eng_1", "anti_ice_eng_2",
	"takeoff_light", "turnoff_lights", "wing_lights", "logo_lights", "alternate_static",
	"elec_bat1", "elec_bat2", "elec_gen1", "elec_gen2", "elec_apu_gen", "elec_ext_pwr", "hyd_green_edp", "hyd_yellow_edp", "hyd_blue_epump", "hyd_yellow_epump", "hyd_ptu", "fuel_pump_left", "fuel_pump_centre", "fuel_pump_right", "fuel_crossfeed", "bleed_eng1", "bleed_eng2", "bleed_apu", "pack1", "pack2", "seatbelt_signs", "no_smoking_signs",
	"jetway_toggle", "door_toggle", "passenger_doors_all", "cargo_doors_all", "door_r1_toggle", "door_l2_toggle", "door_r2_toggle", "door_cargo_fwd_toggle",
	"door_cargo_aft_toggle", "ground_crew_toggle", "taxi_route", "pushback", "fcu_vs_pull", "fcu_vs_push", "map_edit_route",
	"fcu_spd_pull", "fcu_spd_push", "fcu_hdg_pull", "fcu_hdg_push", "fcu_alt_pull", "fcu_alt_push"]
## Switch-row toggles: action -> Props path (fuel_selector cycles OFF/L/R/BOTH instead).
const SWITCHES := {"avionics": "controls/electrical/avionics", "fuel_shutoff": "controls/fuel/shutoff",
	"beacon": "controls/lights/beacon", "nav_lights": "controls/lights/nav", "strobes": "controls/lights/strobe",
	"landing_light": "controls/lights/landing", "taxi_light": "controls/lights/taxi",
	"pitot_heat": "controls/electrical/pitot_heat", "alternate_static": "systems/alternate_static"}
const LABELS := KeyLabels.LABELS  ## Controls page names (core/key_labels.gd)
## Other in-flight hotkeys (not rebindable here): a binding on one of these is a conflict.
const RESERVED := {
	KEY_C: "camera", KEY_1: "view 1", KEY_2: "view 2", KEY_3: "view 3", KEY_4: "view 4",
	KEY_5: "view 5", KEY_6: "view 6", KEY_7: "view 7", KEY_8: "view 8", KEY_V: "re-centre view",
	KEY_N: "moving map", KEY_H: "HUD", KEY_J: "controls panel",
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
	t.alternate_static = []  # cockpit switch; bind a key on the Controls page
	t.map_edit_route = [spec(KEY_E)]  # only while the N map is open (ui/moving_map.gd); E alone is free in flight
	_add_airliner_defaults(t)
	return t


## Airliner overhead switches (ELEC, HYD, FUEL, AIR, SIGNS; input/control_actions.gd) and some FCU / EFIS extras: no default key.
const OVERHEAD := ["elec_bat1", "elec_bat2", "elec_gen1", "elec_gen2", "elec_apu_gen", "elec_ext_pwr", "hyd_green_edp",
	"hyd_yellow_edp", "hyd_blue_epump", "hyd_yellow_epump", "hyd_ptu", "fuel_pump_left", "fuel_pump_centre", "fuel_pump_right",
	"fuel_crossfeed", "bleed_eng1", "bleed_eng2", "bleed_apu", "pack1", "pack2", "seatbelt_signs", "no_smoking_signs",
	"fcu_spd_mach", "fcu_trk_fpa", "fcu_metric_alt", "fcu_alt_1000", "efis_fd", "efis_ls", "baro_std",
	"baro_up", "baro_down", "nd_mode_next", "nd_range_up", "nd_range_down", "nd_filter_next"]  # and the FCU / EFIS extras


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
	t.master_warn = [spec(KEY_M, false, true)]  # Ctrl+M: MASTER WARN / CAUT (M = magnetos, Shift+M = master switch)
	t.apu_start = [spec(KEY_U, false, false, true)]
	t.anti_ice_wing = [spec(KEY_W, false, true)]
	t.anti_ice_eng_1 = [spec(KEY_E, false, false, true)]
	t.anti_ice_eng_2 = [spec(KEY_D, false, false, true)]
	t.takeoff_light = [spec(KEY_T, false, false, true)]
	t.turnoff_lights = [spec(KEY_R, false, false, true)]
	t.wing_lights = [spec(KEY_W, false, false, true)]
	t.logo_lights = [spec(KEY_O, false, false, true)]
	t.rudder_trim_left = [spec(KEY_Z, false, false, true)]
	t.rudder_trim_right = [spec(KEY_X, false, false, true)]
	for i in 5:  # Ctrl+1..5 (the view keys ignore Ctrl)
		t[["fcu_ap1", "fcu_ap2", "fcu_athr", "fcu_loc", "fcu_appr"][i]] = [spec(KEY_1 + i, false, true)]
	# the sidestick takeover button and the thrust levers' instinctive disconnect: Ctrl+Backspace / Ctrl+Shift+Backspace
	# (Backspace alone dismisses the taxi message; the N map's clear key ignores Ctrl)
	t.fcu_ap_disc = [spec(KEY_BACKSPACE, false, true)]
	t.fcu_athr_disc = [spec(KEY_BACKSPACE, true, true)]
	t.fcu_spd_up = [spec(KEY_BRACKETRIGHT, false, false, true)]
	t.fcu_spd_down = [spec(KEY_BRACKETLEFT, false, false, true)]
	t.fcu_hdg_right = [spec(KEY_RIGHT, false, false, true)]
	t.fcu_hdg_left = [spec(KEY_LEFT, false, false, true)]
	t.fcu_alt_up = [spec(KEY_UP, false, false, true)]
	t.fcu_alt_down = [spec(KEY_DOWN, false, false, true)]
	t.fcu_vs_up = [spec(KEY_APOSTROPHE, false, false, true)]
	t.fcu_vs_down = [spec(KEY_SEMICOLON, false, false, true)]
	t.fcu_vs_pull = [spec(KEY_APOSTROPHE, true, false, true)]  # Shift = pull, as Shift+click on the knob
	t.fcu_vs_push = [spec(KEY_SEMICOLON, true, false, true)]
	t.fcu_spd_pull = [spec(KEY_BRACKETRIGHT, true, false, true)]  # Shift+Alt + the turn key: pull; the opposite key: push
	t.fcu_spd_push = [spec(KEY_BRACKETLEFT, true, false, true)]
	t.fcu_hdg_pull = [spec(KEY_RIGHT, true, false, true)]
	t.fcu_hdg_push = [spec(KEY_LEFT, true, false, true)]
	t.fcu_alt_pull = [spec(KEY_UP, true, false, true)]
	t.fcu_alt_push = [spec(KEY_DOWN, true, false, true)]
	t.tiller_left = []  # nosewheel tiller; bind keys or a joystick axis
	t.tiller_right = []
	t.jetway_toggle = [spec(KEY_J, true)]
	t.door_toggle = [spec(KEY_O)]
	t.passenger_doors_all = [spec(KEY_O, true)]
	t.cargo_doors_all = [spec(KEY_O, false, true)]
	for a in ["door_r1_toggle", "door_l2_toggle", "door_r2_toggle", "door_cargo_fwd_toggle", "door_cargo_aft_toggle"]:
		t[a] = []  # listed under Ground operations; bind a key there
	t.ground_crew_toggle = [spec(KEY_U)]
	t.taxi_route = [spec(KEY_T)]
	t.pushback = [spec(KEY_P)]
	for o in OVERHEAD:
		t[o] = []  # airliner overhead switches: click them in the cockpit, or bind a key on the Controls page


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


## The first key bound to `action` as text ("Shift+J"), for messages; `t` defaults to the saved bindings.
static func key_text(action: String, t := {}) -> String:
	var slots: Array = (t if not t.is_empty() else load_from()).get(action, [])
	return describe(slots[0]) if not slots.is_empty() else "set a key on the Controls page"


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
	f.store_string(JSON.stringify({"version": VERSION, "keys": t}, "  "))
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
			if l.is_empty() and a in DEFAULT_SINCE_V2 and int(d.get("version", 1)) < 2:
				continue
			t[a] = l.slice(0, SLOTS)
	return t
