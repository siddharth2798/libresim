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
##   controls/pedal_disc bool (held: PEDALS DISC on the tiller, the pedals stop steering the nose wheel)
##   controls/reverse_<n> 0..1           (per engine n >= 1; reverse thrust selected, fraction of REV MAX)
##   controls/throttle, throttle_<n>     see engine_levers.gd (n = 1 mirrors the shared one)
##   controls/anti_ice/{wing, eng_<n>} bool (probe heat, controls/anti_ice/probe, stays on: systems/icing.gd)
##   controls/fcu/ap1, ap2, athr, loc, appr (bool toggles); ap_disc, athr_disc (pulses the autoflight consumes);
##   controls/ewd/master_ack (MASTER WARN / CAUT press: a pulse systems/airliner_warnings.gd consumes);
##   spd_mach, trk_fpa, metric_alt (FCU window / PFD display only), alt_inc_1000 (ALT knob detent 1000 ft)
##   controls/fcu/vert_select "VS" (V/S knob pulled: fly the V/S set) / "LEVEL" (pushed: V/S 0), consumed by systems/autoflight.gd
##   controls/fcu/fd, controls/efis/ls, controls/baro/{std, hpa}, controls/nd/{mode, range_nm},
##   controls/efis/nd_filter 0 none, 1 CSTR, 2 WPT, 3 VOR.D, 4 NDB, 5 ARPT (the EFIS control panel)
##   controls/fcu/spd_kt, hdg_deg, alt_ft, vs_fpm (set-points in pilot units, like adf/freq_khz)
##   controls/ground/jetway_stowed bool (the jetway stays retracted at a gate)  controls/ground/crew_away bool (ground vehicles sent away)
##   controls/ground/taxi_req, push_req int (counters: each press asks world/ground_ops.gd for a taxi route / pushback)
##   controls/door_open bool (cabin door L1; eases systems/door_pos 0..1, world/cabin_door.gd)
##   controls/doors/<id> bool (the other doors of aircraft.json ground.doors: R1 L2 R2 CF CA; eases systems/doors/<id>)
##   controls/doors/passenger_all_req, cargo_all_req int (bumped: open every passenger / cargo door, or shut them all when all are open)
##   controls/lights/{takeoff, rwy_turnoff, wing, logo} bool (an airliner's extra exterior lights, aircraft_lights.gd)
##   controls/electrical/{bat1, bat2, gen1, gen2, apu_gen, ext_pwr}, controls/hyd/{green_edp, yellow_edp, blue_epump,
##     yellow_epump, ptu}, controls/fuel/{pump_left, pump_centre, pump_right, crossfeed}, controls/bleed/{eng1, eng2, apu,
##     pack1, pack2}, controls/signs/{seatbelts, no_smoking} bool (airliner overhead; systems/airliner_*.gd)

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
	"tiller": ["tiller", "tiller_left", "tiller_right", "pedal_disc"],
	"doors": ["passenger_doors_all", "cargo_doors_all", "door_r1_toggle", "door_l2_toggle", "door_r2_toggle",
		"door_cargo_fwd_toggle", "door_cargo_aft_toggle"],  # the doors after L1 (door_toggle, every aircraft)
	"anti_ice": ["anti_ice_wing", "anti_ice_eng_1", "anti_ice_eng_2"],
	"fcu": ["fcu_ap1", "fcu_ap2", "fcu_athr", "fcu_loc", "fcu_appr", "fcu_spd_up", "fcu_spd_down",
		"fcu_hdg_right", "fcu_hdg_left", "fcu_alt_up", "fcu_alt_down", "fcu_vs_up", "fcu_vs_down", "fcu_ap_disc", "fcu_athr_disc",
		"master_warn", "fcu_spd_mach", "fcu_trk_fpa", "fcu_metric_alt", "fcu_alt_1000", "fcu_vs_pull", "fcu_vs_push",
		"fcu_spd_pull", "fcu_spd_push", "fcu_hdg_pull", "fcu_hdg_push", "fcu_alt_pull", "fcu_alt_push"],
	"efis": ["efis_fd", "efis_ls", "baro_std", "baro_up", "baro_down", "nd_mode_next", "nd_range_up", "nd_range_down", "nd_filter_next"],
	"ext_lights": ["takeoff_light", "turnoff_lights", "wing_lights", "logo_lights"],
	"elec": ["elec_bat1", "elec_bat2", "elec_gen1", "elec_gen2", "elec_apu_gen", "elec_ext_pwr"],
	"hyd": ["hyd_green_edp", "hyd_yellow_edp", "hyd_blue_epump", "hyd_yellow_epump", "hyd_ptu"],
	"fuel_pumps": ["fuel_pump_left", "fuel_pump_centre", "fuel_pump_right", "fuel_crossfeed"],
	"bleed": ["bleed_eng1", "bleed_eng2", "bleed_apu", "pack1", "pack2"],
	"signs": ["seatbelt_signs", "no_smoking_signs"],
}

## Press actions that flip a bool prop.
const TOGGLES := {
	"parking_brake": "controls/parking_brake",
	"engine_master_1": "controls/engine_master_1", "engine_master_2": "controls/engine_master_2",
	"apu_master": "controls/apu_master",
	"anti_ice_wing": "controls/anti_ice/wing", "anti_ice_eng_1": "controls/anti_ice/eng_1", "anti_ice_eng_2": "controls/anti_ice/eng_2",
	"fcu_ap1": "controls/fcu/ap1", "fcu_ap2": "controls/fcu/ap2", "fcu_athr": "controls/fcu/athr",
	"fcu_loc": "controls/fcu/loc", "fcu_appr": "controls/fcu/appr",
	"fcu_ap_disc": "controls/fcu/ap_disc", "fcu_athr_disc": "controls/fcu/athr_disc", "master_warn": "controls/ewd/master_ack", "fcu_spd_mach": "controls/fcu/spd_mach",
	"fcu_trk_fpa": "controls/fcu/trk_fpa", "fcu_metric_alt": "controls/fcu/metric_alt", "fcu_alt_1000": "controls/fcu/alt_inc_1000",
	"efis_fd": "controls/fcu/fd", "efis_ls": "controls/efis/ls", "baro_std": "controls/baro/std",
	"takeoff_light": "controls/lights/takeoff", "turnoff_lights": "controls/lights/rwy_turnoff",
	"wing_lights": "controls/lights/wing", "logo_lights": "controls/lights/logo",
	# every aircraft: the ramp (world/jetway_rig.gd, world/ramp_crew.gd, world/cabin_door.gd)
	"jetway_toggle": "controls/ground/jetway_stowed", "door_toggle": "controls/door_open",
	"door_r1_toggle": "controls/doors/R1", "door_l2_toggle": "controls/doors/L2", "door_r2_toggle": "controls/doors/R2",
	"door_cargo_fwd_toggle": "controls/doors/CF", "door_cargo_aft_toggle": "controls/doors/CA",
	"ground_crew_toggle": "controls/ground/crew_away",
	# airliner overhead ELEC / HYD / FUEL / AIR / SIGNS (systems/airliner_*.gd read them)
	"elec_bat1": "controls/electrical/bat1",
	"elec_bat2": "controls/electrical/bat2",
	"elec_gen1": "controls/electrical/gen1",
	"elec_gen2": "controls/electrical/gen2",
	"elec_apu_gen": "controls/electrical/apu_gen",
	"elec_ext_pwr": "controls/electrical/ext_pwr",
	"hyd_green_edp": "controls/hyd/green_edp",
	"hyd_yellow_edp": "controls/hyd/yellow_edp",
	"hyd_blue_epump": "controls/hyd/blue_epump",
	"hyd_yellow_epump": "controls/hyd/yellow_epump",
	"hyd_ptu": "controls/hyd/ptu",
	"fuel_pump_left": "controls/fuel/pump_left",
	"fuel_pump_centre": "controls/fuel/pump_centre",
	"fuel_pump_right": "controls/fuel/pump_right",
	"fuel_crossfeed": "controls/fuel/crossfeed",
	"bleed_eng1": "controls/bleed/eng1",
	"bleed_eng2": "controls/bleed/eng2",
	"bleed_apu": "controls/bleed/apu",
	"pack1": "controls/bleed/pack1",
	"pack2": "controls/bleed/pack2",
	"seatbelt_signs": "controls/signs/seatbelts",
	"no_smoking_signs": "controls/signs/no_smoking",
}
## Press actions that bump a counter prop: a request another module acts on (world/ground_ops.gd watches them).
const PULSES := {"taxi_route": "controls/ground/taxi_req", "pushback": "controls/ground/push_req",
	"passenger_doors_all": "controls/doors/passenger_all_req", "cargo_doors_all": "controls/doors/cargo_all_req"}
## Ground operations, offered by every aircraft: their own section on the Controls page (keyboard and joystick).
const GROUND := ["taxi_route", "pushback", "jetway_toggle", "door_toggle", "passenger_doors_all", "cargo_doors_all", "door_r1_toggle",
	"door_l2_toggle", "door_r2_toggle", "door_cargo_fwd_toggle", "door_cargo_aft_toggle", "ground_crew_toggle"]

## Press actions that write fixed values (the FCU V/S knob pulled / pushed, as its push / pull in aircraft.json
## cockpit.levers vs_sel): turning the knob (fcu_vs_up / fcu_vs_down) only presets controls/fcu/vs_fpm; the pull flies it.
const SETS := {
	"fcu_vs_pull": {"controls/fcu/vs_managed": false, "controls/fcu/vert_select": "VS"},
	"fcu_vs_push": {"controls/fcu/vs_fpm": 0.0, "controls/fcu/vs_managed": false, "controls/fcu/vert_select": "LEVEL"},
	# the other FCU knobs, the same writes as their cockpit.levers push / pull (tests/test_fcu_truth_table.gd compares them)
	"fcu_spd_pull": {"controls/fcu/spd_managed": false}, "fcu_spd_push": {"controls/fcu/spd_managed": true},
	"fcu_hdg_pull": {"controls/fcu/hdg_managed": false}, "fcu_hdg_push": {"controls/fcu/hdg_managed": true},
	"fcu_alt_pull": {"controls/fcu/vs_managed": false, "controls/fcu/vert_select": "OPEN"},
	"fcu_alt_push": {"controls/fcu/vs_managed": true, "controls/fcu/vert_select": "MANAGED"},
}

## Press actions that cycle an int prop: action -> [prop, states, value when the prop was never set].
const CYCLES := {
	"magnetos_next": ["controls/magnetos", 4, 3], "fuel_selector": ["controls/fuel/selector", 4, 3],
	"autobrake_next": ["controls/autobrake", 4, 0], "engine_mode_next": ["controls/engine_mode", 3, 0],
	"gear_toggle": ["controls/gear", 2, 1], "nd_mode_next": ["controls/nd/mode", 5, 0], "nd_filter_next": ["controls/efis/nd_filter", 6, 0],
}
## ND range steps (nm) for nd_range_up / nd_range_down (ControlSteps) and the EFIS range knob.
const ND_RANGES := [10.0, 20.0, 40.0, 80.0, 160.0, 320.0]
## Press actions that move a 0..1 prop by a fixed step: action -> [prop, step].
const STEPS := {"speedbrake_out": ["controls/speedbrake", 0.25], "speedbrake_in": ["controls/speedbrake", -0.25]}

## Held keys that move a prop at a rate while down: prop (without "controls/"), minus, plus, per s, lo, hi.
const RATE_PROPS := [
	{"prop": "pitch_trim", "neg": "trim_down", "pos": "trim_up", "rate": 0.15, "lo": -1.0, "hi": 1.0},
	{"prop": "rudder_trim", "neg": "rudder_trim_left", "pos": "rudder_trim_right", "rate": 0.1, "lo": -1.0, "hi": 1.0},
]
## FCU knobs (held, repeating): action -> [prop, step, lo, hi, wraps, prop read while unset (optional)].
const KNOBS := {
	"fcu_spd_up": ["controls/fcu/spd_kt", 1.0, 100.0, 399.0, false], "fcu_spd_down": ["controls/fcu/spd_kt", -1.0, 100.0, 399.0, false],
	"fcu_hdg_right": ["controls/fcu/hdg_deg", 1.0, 0.0, 359.0, true], "fcu_hdg_left": ["controls/fcu/hdg_deg", -1.0, 0.0, 359.0, true],
	"fcu_alt_up": ["controls/fcu/alt_ft", 100.0, 100.0, 39000.0, false], "fcu_alt_down": ["controls/fcu/alt_ft", -100.0, 100.0, 39000.0, false],
	"fcu_vs_up": ["controls/fcu/vs_fpm", 100.0, -6000.0, 6000.0, false], "fcu_vs_down": ["controls/fcu/vs_fpm", -100.0, -6000.0, 6000.0, false],
	"baro_up": ["controls/baro/hpa", 1.0, 945.0, 1050.0, false, "weather/qnh_hpa"],
	"baro_down": ["controls/baro/hpa", -1.0, 945.0, 1050.0, false, "weather/qnh_hpa"],
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
## Ramp state every aircraft starts a flight with (and gets back on a restart): door shut, jetway and vehicles called.
const RAMP_SEEDS := {"controls/door_open": false, "systems/door_pos": 0.0, "controls/ground/jetway_stowed": false,
	"controls/doors/R1": false, "systems/doors/R1": 0.0, "controls/doors/L2": false, "systems/doors/L2": 0.0,
	"controls/doors/R2": false, "systems/doors/R2": 0.0, "controls/doors/CF": false, "systems/doors/CF": 0.0,
	"controls/doors/CA": false, "systems/doors/CA": 0.0,
	"controls/ground/crew_away": false}
## Initial Props of a group (only set when the prop does not exist yet); aircraft.json "defaults" wins.
const SEEDS := {
	"speedbrake": {"controls/speedbrake": 0.0}, "gear": {"controls/gear": 1}, "autobrake": {"controls/autobrake": 0},
	"engine_mode": {"controls/engine_mode": 0}, "apu": {"controls/apu_master": false, "controls/apu_start": false},
	"rudder_trim": {"controls/rudder_trim": 0.0}, "tiller": {"controls/tiller": 0.0, "controls/pedal_disc": false},
	"anti_ice": {"controls/anti_ice/wing": false, "controls/anti_ice/eng_1": false, "controls/anti_ice/eng_2": false, "controls/anti_ice/probe": true},
	"fcu": {"controls/fcu/ap1": false, "controls/fcu/ap2": false, "controls/fcu/athr": false, "controls/fcu/loc": false,
		"controls/fcu/appr": false, "controls/fcu/spd_kt": 250.0, "controls/fcu/hdg_deg": 0.0,
		"controls/fcu/alt_ft": 10000.0, "controls/fcu/vs_fpm": 0.0},
	"efis": {"controls/fcu/fd": true, "controls/efis/ls": true, "controls/baro/std": false, "controls/nd/mode": 0,
		"controls/nd/range_nm": 40.0, "controls/efis/nd_filter": 0},
	"ext_lights": {"controls/lights/takeoff": false, "controls/lights/rwy_turnoff": false, "controls/lights/wing": false,
		"controls/lights/logo": false},
	"elec": {"controls/electrical/bat1": true, "controls/electrical/bat2": true, "controls/electrical/gen1": true, "controls/electrical/gen2": true, "controls/electrical/apu_gen": true, "controls/electrical/ext_pwr": true},
	"hyd": {"controls/hyd/green_edp": true, "controls/hyd/yellow_edp": true, "controls/hyd/blue_epump": true, "controls/hyd/yellow_epump": false, "controls/hyd/ptu": true},
	"fuel_pumps": {"controls/fuel/pump_left": true, "controls/fuel/pump_centre": true, "controls/fuel/pump_right": true, "controls/fuel/crossfeed": false},
	"bleed": {"controls/bleed/eng1": true, "controls/bleed/eng2": true, "controls/bleed/apu": true, "controls/bleed/pack1": true, "controls/bleed/pack2": true},
	"signs": {"controls/signs/seatbelts": false, "controls/signs/no_smoking": false},
}
## Held buttons (a joystick button is down or not; no press edge).
const HELD_BUTTONS := ["reverse", "apu_start", "pedal_disc"]

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
