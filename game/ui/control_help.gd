class_name ControlHelp
extends RefCounted
## The rows of the F1 key-help card (ui/hud.gd): the flight controls the aircraft offers
## (aircraft_controls.gd), with the keys as currently bound (core/key_bindings.gd), then the fixed hotkeys.
## A row is [keys text, what]; the card lays them out two per line.

## [group ("" = every aircraft), actions whose first key is shown, separator, what].
const FLIGHT := [
	["", ["pitch_down", "pitch_up", "roll_left", "roll_right"], " ", "pitch / roll"],
	["", ["yaw_left", "yaw_right"], " / ", "rudder"],
	["throttle", ["throttle_up", "throttle_down"], " / ", "throttle"],
	["thrust_levers", ["throttle_1_up", "throttle_1_down", "throttle_2_up", "throttle_2_down"], " ", "thrust lever 1 up dn · 2 up dn"],
	["thrust_levers", ["throttle_detent_up", "throttle_detent_down"], " / ", "thrust lever detents"],
	["reverse", ["reverse"], "", "thrust reverse (hold)"],
	["mixture", ["mixture_lean", "mixture_rich"], " / ", "mixture"],
	["trim", ["trim_down", "trim_up"], " / ", "trim"],
	["rudder_trim", ["rudder_trim_left", "rudder_trim_right"], " / ", "rudder trim"],
	["flaps", ["flaps_up", "flaps_down"], " / ", "flaps"],
	["speedbrake", ["speedbrake_in", "speedbrake_out"], " / ", "speedbrake in / out"],
	["gear", ["gear_toggle"], "", "landing gear"],
	["brakes", ["brakes", "brake_left", "brake_right"], " · ", "brakes"],
	["parking_brake", ["parking_brake"], "", "parking brake"],
	["autobrake", ["autobrake_next"], "", "autobrake"],
	["magnetos", ["magnetos_next"], "", "magnetos"],
	["starter", ["starter"], "", "starter"],
	["engine_master", ["engine_master_1", "engine_master_2"], " / ", "engine 1 / 2 master"],
	["engine_mode", ["engine_mode_next"], "", "engine mode"],
	["apu", ["apu_master", "apu_start"], " · ", "APU master · start"],
	["fcu", ["fcu_ap1", "fcu_ap2", "fcu_athr", "fcu_loc", "fcu_appr"], " ", "AP1 AP2 A/THR LOC APPR"],
	["fcu", ["fcu_spd_down", "fcu_spd_up"], " / ", "FCU speed"],
	["fcu", ["fcu_hdg_left", "fcu_hdg_right"], " / ", "FCU heading"],
	["fcu", ["fcu_alt_down", "fcu_alt_up"], " / ", "FCU altitude"],
	["fcu", ["fcu_vs_down", "fcu_vs_up"], " / ", "FCU vertical speed"],
	["", ["mouse_yoke"], "", "mouse yoke"],
	["", ["master", "avionics"], " · ", "master · avionics"],
	["fuel_selector", ["fuel_selector"], "", "fuel selector"],
	["fuel_shutoff", ["fuel_shutoff"], "", "fuel shutoff"],
	["", ["beacon", "nav_lights", "strobes", "landing_light", "taxi_light"], " ", "beacon nav strobe land taxi"],
	["", ["pitot_heat"], "", "pitot heat"],
]
const FIXED := [
	["C · 1–8", "views"], ["Tab", "panel layout"], ["N", "map"], ["`", "radio / ATC"],
	["T · P", "taxi route · pushback"], ["F2", "checklists"], ["F9 · F10", "failures · settings"],
	["R · F8", "replay · record"], ["F11", "quick-save"], ["J", "controls"], ["H", "flight-data bar"],
	["Esc", "pause menu"], ["L · Shift+L", "panel lights + / −"], ["F1", "this help"],
	["Ctrl+click", "zoom on cockpit item"], ["wheel", "zoom to cursor"], ["K", "training callouts on / off"],
	["Backspace", "dismiss taxi message"],
]


static func rows(ctl: AircraftControls, table: Dictionary) -> Array:
	var out := []
	for r in FLIGHT:
		if r[0] != "" and not ctl.has_group(r[0]):
			continue
		var parts := []
		for a in r[1]:
			var slots: Array = table.get(a, [])
			if not slots.is_empty():
				parts.append(KeyBindings.describe(slots[0]))
		if not parts.is_empty():
			out.append([str(r[2]).join(parts), r[3]])
	return out + FIXED
