class_name CockpitTipText
extends RefCounted
## Words on the cockpit hover note: the control's name, the key that moves it, and where it sits.
## Keys come from KeyBindings (so a rebind shows up). A path with no key says how it actually moves.

const Row = preload("res://ui/gauges/switch_row.gd")

const NAMES := {
	"thr_l": "Thrust lever 1", "thr_r": "Thrust lever 2", "rev_l": "Reverser 1", "rev_r": "Reverser 2",
	"athr_disc_l": "Autothrust disconnect", "athr_disc_r": "Autothrust disconnect",
	"speedbrake": "Speedbrake", "flaps_lever": "Flaps", "gear_lever": "Landing gear",
	"parking_brake": "Parking brake", "engine_master_1": "Engine 1 master", "engine_master_2": "Engine 2 master",
	"engine_mode": "Engine mode", "pitch_trim": "Pitch trim", "rudder_trim": "Rudder trim",
	"tiller_cpt": "Captain tiller", "tiller_fo": "First officer tiller",
	"hdg_sel": "Heading", "spd_sel": "Speed", "alt_sel": "Altitude", "vs_sel": "Vertical speed",
	"ap1": "Autopilot 1", "ap2": "Autopilot 2", "athr": "Autothrust", "loc": "Localiser", "appr": "Approach",
	"beacon_lt": "Beacon", "strobe_lt": "Strobes", "wing_lt": "Wing lights",
	"landing_lt": "Landing light", "landing_lt_r": "Landing light", "nose_lt": "Taxi light",
	"turnoff_lt": "Runway turnoff lights", "nav_logo_lt": "Nav and logo lights",
	"apu_master": "APU master", "apu_start": "APU start",
	"wing_anti_ice": "Wing anti-ice", "eng1_anti_ice": "Engine 1 anti-ice", "eng2_anti_ice": "Engine 2 anti-ice",
	"autobrake_lo": "Autobrake LO", "autobrake_med": "Autobrake MED", "autobrake_max": "Autobrake MAX",
}
const SWITCH_NAMES := {
	"BAT": "Battery", "ALT": "Alternator", "AVN": "Avionics", "BCN": "Beacon", "LAND": "Landing light",
	"TAXI": "Taxi light", "NAV": "Nav lights", "STRB": "Strobes", "PANEL": "Panel lights", "PITOT HT": "Pitot heat",
	"MAGS": "Magnetos", "FUEL": "Fuel selector", "SHUTOFF": "Fuel shutoff", "ALT STAT": "Alternate static",
}
## First property of a lever drive -> the actions whose first binding is the control line.
const KEYS := {
	"controls/throttle_1": ["throttle_1_up", "throttle_1_down", "throttle_detent_up", "reverse"],
	"controls/throttle_2": ["throttle_2_up", "throttle_2_down", "throttle_detent_up", "reverse"],
	"controls/pitch": ["pitch_down", "pitch_up"], "controls/roll": ["roll_left", "roll_right"],
	"controls/yaw": ["yaw_left", "yaw_right"], "controls/flaps": ["flaps_down", "flaps_up"],
	"controls/speedbrake": ["speedbrake_out", "speedbrake_in"], "controls/gear": ["gear_toggle"],
	"controls/parking_brake": ["parking_brake"], "controls/engine_mode": ["engine_mode_next"],
	"controls/engine_master_1": ["engine_master_1"], "controls/engine_master_2": ["engine_master_2"],
	"controls/brake_left": ["brake_left"], "controls/brake_right": ["brake_right"],
	"controls/tiller": ["tiller_left", "tiller_right"],
	"fdm/stabilizer_deg": ["trim_down", "trim_up"], "controls/rudder_trim": ["rudder_trim_left", "rudder_trim_right"],
	"controls/fcu/hdg_deg": ["fcu_hdg_left", "fcu_hdg_right"], "controls/fcu/spd_kt": ["fcu_spd_down", "fcu_spd_up"],
	"controls/fcu/alt_ft": ["fcu_alt_down", "fcu_alt_up"], "controls/fcu/vs_fpm": ["fcu_vs_down", "fcu_vs_up"],
	"controls/fcu/ap1": ["fcu_ap1"], "controls/fcu/ap2": ["fcu_ap2"], "controls/fcu/athr": ["fcu_athr"],
	"controls/fcu/loc": ["fcu_loc"], "controls/fcu/appr": ["fcu_appr"],
	"controls/lights/beacon": ["beacon"], "controls/lights/strobe": ["strobes"], "controls/lights/wing": ["wing_lights"],
	"controls/lights/landing": ["landing_light"], "controls/lights/taxi": ["taxi_light"],
	"controls/lights/rwy_turnoff": ["turnoff_lights"], "controls/lights/nav": ["nav_lights"], "controls/lights/logo": ["logo_lights"],
	"controls/apu_master": ["apu_master"], "controls/apu_start": ["apu_start"],
	"controls/anti_ice/wing": ["anti_ice_wing"], "controls/anti_ice/eng_1": ["anti_ice_eng_1"], "controls/anti_ice/eng_2": ["anti_ice_eng_2"],
	"controls/autobrake": ["autobrake_next"], "controls/electrical/master_bat": ["master"], "controls/electrical/master_alt": ["master"],
	"controls/electrical/avionics": ["avionics"], "controls/electrical/pitot_heat": ["pitot_heat"],
	"controls/magnetos": ["magnetos_next"], "controls/fuel/selector": ["fuel_selector"], "controls/fuel/shutoff": ["fuel_shutoff"],
}
const THRUST := [[-1.0, "REV MAX"], [-0.1, "REV IDLE"], [0.0, "IDLE"], [0.556, "CL"], [0.778, "FLX/MCT"], [1.0, "TOGA"]]


## "none" shows the lever. "glass" shows nothing (a display is in front). "switches" is the switch row.
static func choice(kind: String, at: Vector2, rect: Rect2, count: int, lever_id: String) -> Dictionary:
	if kind == "switches":
		return {"switch": switch_index(at, rect, count), "lever": ""}
	if kind == "glass":
		return {"switch": -1, "lever": ""}
	return {"switch": -1, "lever": lever_id}


static func lever_id(item: Dictionary) -> String:
	if item.is_empty():
		return ""
	var node = item.get("node")
	if node is Node:
		return str((node as Node).name).trim_prefix("pivot_")
	return str(item.get("id", ""))


static func switch_index(at: Vector2, rect: Rect2, count: int) -> int:
	if count < 1 or rect.size.x <= 0.0:
		return -1
	if at.x < rect.position.x or at.y < rect.position.y or at.x >= rect.end.x or at.y >= rect.end.y:
		return -1
	var i := int((at.x - rect.position.x) / rect.size.x * count)
	return i if i < count else -1


static func compose(lever_id: String, drive: String, value: Variant, switch_i: int, switch_value: Variant, bindings: Dictionary) -> String:
	if switch_i >= 0:
		return switch_card(switch_i, switch_value, bindings)
	return card(lever_id, drive, value, bindings)


static func card(id: String, drive: String, value: Variant, bindings: Dictionary) -> String:
	if id == "" or drive == "":
		return ""
	return "%s\n%s\n%s" % [title(id), control_line(drive, bindings), state(drive, value)]


static func switch_card(index: int, value: Variant, bindings: Dictionary) -> String:
	var items: Array = Row.ITEMS
	if index < 0 or index >= items.size():
		return ""
	var it: Array = items[index]
	var drive := str(it[1])
	return "%s\n%s\n%s" % [str(SWITCH_NAMES.get(it[0], it[0])), control_line(drive, bindings), state(drive, value)]


static func title(id: String) -> String:
	if id.begins_with("sidestick_") or id.begins_with("boot"):
		return "%s sidestick" % _who(id)
	if id.begins_with("pedal_"):
		var side := "left" if "_l_" in id else "right"
		var part := "brake" if id.ends_with("_brake") else "pedal"
		return "%s %s %s" % [_who(id), side, part]
	return str(NAMES.get(id, id.replace("_", " ").capitalize()))


static func control_line(drive: String, bindings: Dictionary) -> String:
	var terms: Array = CockpitLevers.parse_drive(drive)
	var bits := []
	var seen := {}
	for t in terms:
		for action in KEYS.get(str(t[1]), []):
			var slots: Array = bindings.get(action, [])
			if slots.is_empty():
				continue
			var label := KeyBindings.describe(slots[0])
			if seen.has(label) or bits.size() >= 4:
				continue
			seen[label] = true
			bits.append(label)
	if not bits.is_empty():
		return " · ".join(bits)
	for t in terms:
		var path := str(t[1])
		if path == "controls/tiller":
			return "Tiller axis"
		if path == "controls/lights/panel":
			return "L · Shift+L"
	return "Click"


static func state(drive: String, value: Variant) -> String:
	var terms: Array = CockpitLevers.parse_drive(drive)
	if terms.is_empty():
		return ""
	var path := str(terms[0][1])
	if terms.size() == 2 and float(terms[1][0]) < 0.0 and path.begins_with("controls/throttle_"):
		return _thrust(_num(value))
	if terms.size() == 2 and str(terms[1][1]) == "controls/lights/logo":
		return ["Off", "Nav", "Nav and logo"][clampi(int(round(_num(value))), 0, 2)]
	return _one(path, value)


static func _who(id: String) -> String:
	return "First officer" if "_fo" in id else "Captain"


static func _one(path: String, value: Variant) -> String:
	match path:
		"controls/parking_brake":
			return "Set" if _on(value) else "Off"
		"controls/gear":
			return "Down" if _on(value) else "Up"
		"controls/engine_mode":
			return ["NORM", "CRANK", "IGN/START"][clampi(int(round(_num(value))), 0, 2)]
		"controls/flaps":
			return ["0", "1", "1+F", "2", "3", "FULL"][clampi(int(round(_num(value))), 0, 5)]
		"controls/speedbrake":
			return _span(_num(value), "In", "Full")
		"controls/autobrake":
			return ["Off", "LO", "MED", "MAX"][clampi(int(round(_num(value))), 0, 3)]
		"controls/magnetos":
			return ["OFF", "L", "R", "BOTH"][clampi(int(round(_num(value))), 0, 3)]
		"controls/fuel/selector":
			return ["OFF", "LEFT", "RIGHT", "BOTH"][clampi(int(round(_num(value))), 0, 3)]
		"controls/fuel/shutoff":
			return "Closed" if _on(value) else "Open"
		"controls/lights/panel":
			return "%d%%" % roundi(clampf(_num(value), 0.0, 1.0) * 100.0)
		"fdm/stabilizer_deg":
			return _trim(_num(value))
		"controls/pitch":
			return _axis(_num(value), "Nose down", "Nose up")
		"controls/roll", "controls/yaw", "controls/tiller", "controls/rudder_trim":
			return _axis(_num(value), "Left", "Right")
		"controls/brake_left", "controls/brake_right":
			var b := _num(value)
			return "Off" if b < 0.02 else "%d%%" % roundi(clampf(b, 0.0, 1.0) * 100.0)
		"controls/fcu/hdg_deg":
			return "%d°" % clampi(int(round(_num(value))), 0, 360)
		"controls/fcu/spd_kt":
			return "%d kt" % int(round(_num(value)))
		"controls/fcu/alt_ft":
			return "%d ft" % int(round(_num(value)))
		"controls/fcu/vs_fpm":
			var vs := int(round(_num(value)))
			return "0" if abs(vs) < 50 else "%+d ft/min" % vs
	if _toggles(path):
		return "On" if _on(value) else "Off"
	if value is bool:
		return "On" if value else "Off"
	return "%s" % value


static func _toggles(path: String) -> bool:
	return path.begins_with("controls/lights/") or path.begins_with("controls/electrical/") \
		or path.begins_with("controls/fcu/") or path.begins_with("controls/anti_ice/") \
		or path.begins_with("controls/engine_master") or path.begins_with("controls/apu") \
		or path == "systems/alternate_static"


static func _thrust(v: float) -> String:
	var best := ""
	var dist := 0.045
	for d in THRUST:
		var gap := absf(v - float(d[0]))
		if gap < dist:
			dist = gap
			best = str(d[1])
	if best != "":
		return best
	if v < -0.02:
		return "Reverse %d%%" % roundi(clampf(-v, 0.0, 1.0) * 100.0)
	return "%d%%" % roundi(clampf(v, 0.0, 1.0) * 100.0)


static func _span(v: float, lo: String, hi: String) -> String:
	if v < 0.02:
		return lo
	if v > 0.98:
		return hi
	return "%d%%" % roundi(clampf(v, 0.0, 1.0) * 100.0)


static func _axis(v: float, neg: String, pos: String) -> String:
	if absf(v) < 0.05:
		return "Neutral"
	return "%s %d%%" % [pos if v > 0.0 else neg, roundi(absf(v) * 100.0)]


static func _trim(v: float) -> String:
	if absf(v) < 0.05:
		return "0°"
	if v < 0.0:
		return "%.1f° nose up" % absf(v)
	return "%.1f° nose down" % v


static func _on(value: Variant) -> bool:
	return value if value is bool else _num(value) >= 0.5


static func _num(value: Variant) -> float:
	if value == null:
		return 0.0
	return (1.0 if value else 0.0) if value is bool else float(value)
