class_name ReplayLayout
extends RefCounted
## Which Props a replay frame records for one aircraft (used by ReplayChannels). The BASE_* lists
## are the C172 / engine-1 set (derived by grepping what aircraft/, ui/gauges, ui/hud.gd,
## instruments/ and avionics/ read) and never change, so the C172 recording layout stays the same.
## Everything else comes from the aircraft's aircraft.json "replay" section (all keys optional):
##   lerp / rad / deg / bool / int  extra prop keys per interpolation kind (deg and rad = angles)
##   enums   {"ap/fma/lateral": ["", "HDG", "NAV", ...]}  string props recorded as an index into the list
##   units   true / false: per-engine channels engines/<n>/* and controls/throttle_<n> (default: on
##           when the aircraft has more than one engine)
##   fcs     true (ReplayChannels.EXTRA_FCS_FIELDS) or a list of FlightControls fields to record
##           (a missing field is skipped; an Array field gets one channel per element)
## Tanks beyond the two the C172's fuel/left_kg + fuel/right_kg cover are recorded as fuel/tank_kg#<i>
## (element i of the fuel/tank_kg array prop).

const BASE_LERP := [
	"fdm/tas_mps", "fdm/cas_mps", "fdm/groundspeed_mps", "fdm/vs_mps", "fdm/alt_m", "fdm/agl_m",
	"fdm/alpha_rad", "fdm/beta_rad", "fdm/load_factor", "fdm/flap_deg", "fdm/mass_kg",
	"engine/rpm", "engine/map_pa", "engine/fuel_flow_kgs", "engine/egt_k", "engine/cht_k",
	"engine/oil_temp_k", "engine/oil_press_pa", "engine/power_w", "engine/thrust_n",
	"fuel/total_kg", "fuel/left_kg", "fuel/right_kg",
	"controls/pitch", "controls/roll", "controls/yaw", "controls/throttle", "controls/mixture",
	"controls/pitch_trim", "controls/brake_left", "controls/brake_right",
	"instruments/asi_kt", "instruments/altimeter_ft", "instruments/vsi_fpm",
	"instruments/ai/pitch_rad", "instruments/tc_rate", "instruments/tc_ball",
	"instruments/tach_rpm", "instruments/oil_temp_f", "instruments/oil_press_psi", "instruments/egt_f",
	"instruments/fuel_flow_gph", "instruments/fuel_left_gal", "instruments/fuel_right_gal",
	"instruments/suction_inhg", "instruments/ammeter_a", "instruments/altimeter/kollsman_inhg",
	"systems/vacuum/suction_inhg", "systems/electrical/battery_amps", "systems/electrical/bus_volts",
	"systems/pitot_static/pitot_pa", "systems/pitot_static/static_pa",
	"avionics/nav1/cdi", "avionics/nav1/gs", "avionics/nav1/dme_nm", "avionics/nav2/cdi", "avionics/nav2/gs",
	"avionics/gps/dist_nm", "avionics/gps/ete",
]
const BASE_ANG_RAD := ["fdm/roll_rad", "fdm/pitch_rad", "fdm/heading_rad", "fdm/track_rad", "instruments/ai/roll_rad"]
const BASE_ANG_DEG := ["instruments/hi_deg", "instruments/compass_deg", "avionics/adf/bearing_deg", "avionics/gps/brg_mag"]
const BASE_BOOL := [
	"fdm/wow", "fdm/stall_warning", "engine/running", "controls/starter", "controls/parking_brake",
	"controls/lights/beacon", "controls/lights/nav", "controls/lights/strobe", "controls/lights/taxi", "controls/lights/landing",
	"controls/electrical/master_bat", "controls/electrical/master_alt", "controls/electrical/avionics",
	"systems/electrical/powered", "systems/electrical/avionics_powered", "systems/electrical/gauges_powered",
	"systems/electrical/tc_powered", "systems/electrical/low_volts", "systems/electrical/flap_motor_running",
	"instruments/ai/flag", "instruments/tc_flag",
	"avionics/nav1/valid", "avionics/nav1/gs_valid", "avionics/nav2/valid", "avionics/nav2/gs_valid", "avionics/adf/valid",
]
const BASE_INT := ["controls/flaps", "controls/magnetos", "avionics/nav1/to_from", "avionics/nav2/to_from"]

## Per-engine props (engines/<n>/<name>, published by FdmNode) and levers (controls/<name>_<n>).
const ENGINE_PROPS := ["rpm", "thrust_n", "fuel_flow_kgs", "egt_k", "oil_press_pa", "oil_temp_k"]
const ENGINE_LEVERS := ["throttle", "mixture"]


## {"lerp", "rad", "deg", "bool", "int": Array of keys, "enums": {key: Array of strings},
## "fcs": Array of FlightControls field names wanted}. `extra_fcs` = the default for "fcs": true.
static func build(def: AircraftDef, n_tanks: int, extra_fcs: Array) -> Dictionary:
	var out := {"lerp": BASE_LERP.duplicate(), "rad": BASE_ANG_RAD.duplicate(), "deg": BASE_ANG_DEG.duplicate(),
		"bool": BASE_BOOL.duplicate(), "int": BASE_INT.duplicate(), "enums": {}, "fcs": []}
	var sec: Dictionary = def.section("replay") if def else {}
	var n := def.engine_count() if def else 1
	if bool(sec.get("units", n > 1)):
		for i in range(1, n + 1):
			for p in ENGINE_PROPS:
				out.lerp.append("engines/%d/%s" % [i, p])
			out.bool.append("engines/%d/running" % i)
			for l in ENGINE_LEVERS:
				out.lerp.append("controls/%s_%d" % [l, i])
			out.bool.append("controls/starter_%d" % i)
	if n_tanks > 2:
		for i in n_tanks:
			out.lerp.append("fuel/tank_kg#%d" % i)
	for kind in ["lerp", "rad", "deg", "bool", "int"]:
		for k in sec.get(kind, []):
			if not out[kind].has(k):
				out[kind].append(str(k))
	var enums: Dictionary = sec.get("enums", {})
	for k in enums:
		out.enums[str(k)] = (enums[k] as Array).map(func(s): return str(s))
	var want = sec.get("fcs", false)
	out.fcs = extra_fcs.duplicate() if want is bool and want else (want.map(func(s): return str(s)) if want is Array else [])
	return out
