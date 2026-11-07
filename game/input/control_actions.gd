class_name ControlActions
extends RefCounted
## Catalogue of the pilot actions an aircraft can offer (aircraft.json "controls", aircraft_controls.gd) and what
## they do to the property tree. Key / button / axis action names share one name space (core/key_bindings.gd,
## core/input_bindings.gd). An action in no group is offered by every aircraft; an action in a group only when the
## aircraft lists that group.
##
## Props published (written by input/*, consumed by fdm/ and systems/):
##   controls/speedbrake 0..1            controls/gear 0 (up) / 1 (down)
##   controls/flaps 0..fdm/flap_detents-1 (a notched flaps lever sets it, joystick_controls.gd)
##   controls/autobrake 0..3 (off, LO, MED, MAX)
##   controls/engine_master_<n> bool     controls/engine_mode 0 NORM / 1 CRANK / 2 IGN-START
##   controls/apu_master bool            controls/apu_start bool (held)
##   controls/rudder_trim -1..1          controls/tiller -1..1 (nosewheel, + = right)
##   controls/reverse_<n> 0..1           (per engine n >= 1; reverse thrust selected, fraction of REV MAX)
##   controls/throttle, throttle_<n>     see engine_levers.gd (n = 1 mirrors the shared one)
##   controls/anti_ice/{wing, eng_<n>} bool (probe heat, controls/anti_ice/probe, stays on: systems/icing.gd)
##   controls/fcu/ap1, ap2, athr, loc, appr (bool toggles)
##   controls/fcu/spd_kt, hdg_deg, alt_ft, vs_fpm (set-points in pilot units, like adf/freq_khz)
##   controls/lights/{takeoff, rwy_turnoff, wing, logo} bool (an airliner's extra exterior lights, aircraft_lights.gd)

const DEFAULT_GROUPS := ["throttle", "mixture", "trim", "flaps", "brakes", "parking_brake",
	"magnetos", "starter", "fuel_selector", "fuel_shutoff", "alternate_static"]

const GROUPS := {
	"throttle": ["throttle_up", "throttle_down", "throttle"],
	"mixture": ["mixture_rich", "mixture_lean", "mixture"],
	"trim": ["trim_up", "trim_down", "pitch_trim_axis"],
	"flaps": ["flaps_up", "flaps_down", "flaps_lever"],
	"brakes": ["brakes", "brake_left", "brake_right"],
	"parking_brake": ["parking_brake", "parking_brake_switch"],
	"magnetos": ["magnetos_next", "magnetos_switch"],
	"starter": ["starter"],
	"fuel_selector": ["fuel_selector"],
	"fuel_shutoff": ["fuel_shutoff"],
	"alternate_static": ["alternate_static"],
	"thrust_levers": ["throttle_1_up", "throttle_1_down", "throttle_2_up", "throttle_2_down",
		"throttle_detent_up", "throttle_detent_down", "throttle", "throttle_2"],  # lever 1 axis = "throttle" (also in group throttle)
	"reverse": ["reverse"],
	"speedbrake": ["speedbrake_out", "speedbrake_in", "speedbrake"],
	"gear": ["gear_toggle", "gear_switch"],
	"autobrake": ["autobrake_next", "autobrake_btv", "autobrake_low", "autobrake_2", "autobrake_3", "autobrake_hi"],
	"engine_master": ["engine_master_1", "engine_master_2", "engine_master_1_switch", "engine_master_2_switch"],
	"engine_mode": ["engine_mode_next", "engine_mode_crank", "engine_mode_ign"],
	"apu": ["apu_master", "apu_start"],
	"rudder_trim": ["rudder_trim_left", "rudder_trim_right", "rudder_trim_axis"],
	"tiller": ["tiller", "tiller_left", "tiller_right"],
	"anti_ice": ["anti_ice_wing", "anti_ice_eng_1", "anti_ice_eng_2"],
	"fcu": ["fcu_ap1", "fcu_ap2", "fcu_athr", "fcu_loc", "fcu_appr", "fcu_spd_up", "fcu_spd_down",
		"fcu_hdg_right", "fcu_hdg_left", "fcu_alt_up", "fcu_alt_down", "fcu_vs_up", "fcu_vs_down"],
	"ext_lights": ["takeoff_light", "turnoff_lights", "wing_lights", "logo_lights"],
}

## Press actions that flip a bool prop.
const TOGGLES := {
	"parking_brake": "controls/parking_brake",
	"engine_master_1": "controls/engine_master_1", "engine_master_2": "controls/engine_master_2",
	"apu_master": "controls/apu_master",
	"anti_ice_wing": "controls/anti_ice/wing", "anti_ice_eng_1": "controls/anti_ice/eng_1", "anti_ice_eng_2": "controls/anti_ice/eng_2",
	"fcu_ap1": "controls/fcu/ap1", "fcu_ap2": "controls/fcu/ap2", "fcu_athr": "controls/fcu/athr",
	"fcu_loc": "controls/fcu/loc", "fcu_appr": "controls/fcu/appr",
	"takeoff_light": "controls/lights/takeoff", "turnoff_lights": "controls/lights/rwy_turnoff",
	"wing_lights": "controls/lights/wing", "logo_lights": "controls/lights/logo",
}
## Press actions that cycle an int prop: action -> [prop, states, value when the prop was never set].
const CYCLES := {
	"magnetos_next": ["controls/magnetos", 4, 3], "fuel_selector": ["controls/fuel/selector", 4, 3],
	"autobrake_next": ["controls/autobrake", 4, 0], "engine_mode_next": ["controls/engine_mode", 3, 0],
	"gear_toggle": ["controls/gear", 2, 1],
}
## Press actions that move a 0..1 prop by a fixed step: action -> [prop, step].
const STEPS := {"speedbrake_out": ["controls/speedbrake", 0.25], "speedbrake_in": ["controls/speedbrake", -0.25]}

## Held keys that move a prop at a rate while down: prop (without "controls/"), minus, plus, per s, lo, hi.
const RATE_PROPS := [
	{"prop": "pitch_trim", "neg": "trim_down", "pos": "trim_up", "rate": 0.15, "lo": -1.0, "hi": 1.0},
	{"prop": "rudder_trim", "neg": "rudder_trim_left", "pos": "rudder_trim_right", "rate": 0.1, "lo": -1.0, "hi": 1.0},
]
## FCU knobs (held, repeating): action -> [prop, step, lo, hi, wraps].
const KNOBS := {
	"fcu_spd_up": ["controls/fcu/spd_kt", 1.0, 100.0, 399.0, false], "fcu_spd_down": ["controls/fcu/spd_kt", -1.0, 100.0, 399.0, false],
	"fcu_hdg_right": ["controls/fcu/hdg_deg", 1.0, 0.0, 359.0, true], "fcu_hdg_left": ["controls/fcu/hdg_deg", -1.0, 0.0, 359.0, true],
	"fcu_alt_up": ["controls/fcu/alt_ft", 100.0, 100.0, 39000.0, false], "fcu_alt_down": ["controls/fcu/alt_ft", -100.0, 100.0, 39000.0, false],
	"fcu_vs_up": ["controls/fcu/vs_fpm", 100.0, -6000.0, 6000.0, false], "fcu_vs_down": ["controls/fcu/vs_fpm", -100.0, -6000.0, 6000.0, false],
}
## Latching switches (a joystick button that stays down): action -> [prop, value when off, value when on, sync].
## They act on both edges. `sync` is what the hardware position does when first seen (flight start, pad plugged in):
## "both" sets the prop from it, "on" only when on, "" nothing (a magneto switch must not stop a running engine).
const LEVELS := {
	"parking_brake_switch": ["controls/parking_brake", false, true, "both"],
	"magnetos_switch": ["controls/magnetos", 0, 3, ""],  # OFF / BOTH
	"engine_master_1_switch": ["controls/engine_master_1", false, true, "on"],
	"engine_master_2_switch": ["controls/engine_master_2", false, true, "on"],
	"gear_switch": ["controls/gear", 0, 1, "both"],  # on = DOWN (the pack's lever is inverted in its profile)
}
## Selector switches, one button per position (held while the selector is there); no button held = `rest`.
## The prop follows the position at first sight and on change: name -> {prop, rest, positions}.
## Engine mode: NORM = rest 0, CRANK 1, IGN/START 2. Auto brake dial (DISARM BTV LOW 2 3 HI) -> sim 0 off / 1 LO /
## 2 MED / 3 MAX: BTV and LOW = LO, 2 and 3 = MED, HI = MAX (no brake-to-vacate in the sim).
const SELECTORS := {
	"engine_mode": {"prop": "controls/engine_mode", "rest": 0, "positions": {"engine_mode_crank": 1, "engine_mode_ign": 2}},
	"autobrake": {"prop": "controls/autobrake", "rest": 0, "positions": {"autobrake_btv": 1, "autobrake_low": 1,
		"autobrake_2": 2, "autobrake_3": 2, "autobrake_hi": 3}},
}
## Initial Props of a group (only set when the prop does not exist yet); aircraft.json "defaults" wins.
const SEEDS := {
	"speedbrake": {"controls/speedbrake": 0.0}, "gear": {"controls/gear": 1}, "autobrake": {"controls/autobrake": 0},
	"engine_mode": {"controls/engine_mode": 0}, "apu": {"controls/apu_master": false, "controls/apu_start": false},
	"rudder_trim": {"controls/rudder_trim": 0.0}, "tiller": {"controls/tiller": 0.0},
	"anti_ice": {"controls/anti_ice/wing": false, "controls/anti_ice/eng_1": false, "controls/anti_ice/eng_2": false, "controls/anti_ice/probe": true},
	"fcu": {"controls/fcu/ap1": false, "controls/fcu/ap2": false, "controls/fcu/athr": false, "controls/fcu/loc": false,
		"controls/fcu/appr": false, "controls/fcu/spd_kt": 250.0, "controls/fcu/hdg_deg": 0.0,
		"controls/fcu/alt_ft": 10000.0, "controls/fcu/vs_fpm": 0.0},
	"ext_lights": {"controls/lights/takeoff": false, "controls/lights/rwy_turnoff": false, "controls/lights/wing": false,
		"controls/lights/logo": false},
}
## Held buttons (a joystick button is down or not; no press edge).
const HELD_BUTTONS := ["reverse", "apu_start"]

static var _owner := {}


## Group an action belongs to, "" when every aircraft offers it.
static func group_of(action: String) -> String:
	if _owner.is_empty():
		for g in GROUPS:
			for a in GROUPS[g]:
				_owner[a] = g
	return _owner.get(action, "")


## Is this button action one position of a selector switch (SELECTORS)?
static func in_selector(action: String) -> bool:
	return SELECTORS.values().any(func(s): return s.positions.has(action))
