class_name Icing
extends Node
## Airframe, pitot / static and engine inlet ice, and the protection against it. One node for every
## aircraft (world/flight.tscn, Systems); what the ice does is applied by fdm/environment_effects.gd (drag,
## CLmax, engine power) and systems/pitot_static.gd (blocked probes).
## Accretion (IcingRates): in cloud (environment/ac_cloud_density > 0.05) with static air temperature between
## +2 and -20 C, at a rate from cloud density x airspeed x liquid water (cloud kind: stratiform < cumulus <
## storm) x availability (weather/icing, plus the storm cells' share); freezing rain below 0 C adds fast. Out of
## conditions the ice sublimates slowly, and melts above +5 C.
## Protection (aircraft.json "icing"): "protection" is "none", "pitot_only" (pitot / static heat and the engine
## "alt air" lever; the C172) or "wing_and_engine" (also wing anti-ice and engine anti-ice, bleed air from running
## engines: the A320). Probe heat needs the electrical bus. Bleed-powered anti-ice costs thrust (icing/bleed_penalty).
## Reads: atmosphere/temperature_k (static, ISA + weather), fdm/tas_mps, environment/{ac_cloud_density, cloud_kind,
##   storm_intensity, precip}, weather/icing, systems/electrical/powered, engines/<n>/running, the switch Props named
##   in the section (default controls/electrical/pitot_heat; airliner: controls/anti_ice/{probe, wing, eng_<n>}).
## Publishes icing/{airframe, pitot, static, engine_<n>, rate, conditions, ice_detected, pitot_blocked, static_blocked,
##   bleed_penalty, bleed_penalty_<n>} (levels 0..1). Saved with a flight (group "saveable").

const DEFAULTS := {
	"protection": "pitot_only",
	"drag_k": 0.011,  # CD added on the wing area at full airframe ice (about +35 % of the C172's CD0)
	"clmax_k": 0.22,  # CLmax lost at full ice (plus the stall alpha: see EnvironmentEffects)
	"power_loss_k": 0.25,  # power (piston) or thrust (turbine) lost at full inlet ice
	"egt_k": 0.0,  # EGT rise at full inlet ice, K (turbines)
	"pitot_heat_prop": "controls/electrical/pitot_heat",
	"wing_anti_ice_prop": "controls/anti_ice/wing",  # only with protection "wing_and_engine"
	"engine_anti_ice_prop": "controls/alt_air",  # "%d" = engine number (bleed anti-ice); else the piston alt-air lever
	"bleed_wing": 0.015, "bleed_engine": 0.02,  # thrust lost to bleed air by wing / engine anti-ice
	"rain_cl_k": 0.03, "rain_cd_k": 0.0012, "rain_n1_k": 0.01,  # heavy rain (EnvironmentEffects)
}
const PITOT_K := 6.0  # probes ice faster than the airframe
const STATIC_K := 0.5  # static ports slower than the pitot
const HEAT_CLEAR_S := 20.0  # heated probe clears in this time
const PROTECT_CLEAR_S := 40.0  # wing anti-ice clears the airframe, engine protection the inlet (30 s)
const PITOT_BLOCK := [0.7, 0.4]  # blocked above [0], free again below [1]
const STATIC_BLOCK := [0.9, 0.6]
const DETECT_RATE := 1.0 / 1500.0  # ice detector trips above this accretion rate (per s)
const DETECT_HOLD_S := 60.0

var def: AircraftDef  # tests set it; otherwise the current aircraft
var airframe := 0.0
var pitot := 0.0
var static_ice := 0.0
var engines: Array = []  # inlet ice per engine
var _p := DEFAULTS.duplicate(true)
var _n := 1
var _detect_t := 0.0
var _pitot_blocked := false
var _static_blocked := false


## The aircraft's icing numbers: aircraft.json "icing" over DEFAULTS.
static func params(d: AircraftDef) -> Dictionary:
	return d.section_or("icing", DEFAULTS)


func _ready() -> void:
	add_to_group(SituationSystems.GROUP)
	if def == null:
		def = AircraftDef.current()
	_p = params(def)
	_n = maxi(def.engine_count(), 1)
	reset()
	if str(_p.pitot_heat_prop).begins_with("controls/anti_ice/") and not Props.has(_p.pitot_heat_prop):
		Props.set_v(_p.pitot_heat_prop, true)  # probe heat is automatic: on until switched off


## Clean aircraft (a new flight).
func reset() -> void:
	airframe = 0.0
	pitot = 0.0
	static_ice = 0.0
	engines = []
	engines.resize(_n)
	engines.fill(0.0)
	_detect_t = 0.0
	_pitot_blocked = false
	_static_blocked = false
	_publish(0.0, [])


func save_key() -> String:
	return "icing"


func save_state() -> Dictionary:
	return {"airframe": airframe, "pitot": pitot, "static": static_ice, "engines": engines.duplicate(),
		"detect_t": _detect_t, "pitot_blocked": _pitot_blocked, "static_blocked": _static_blocked}


func load_state(d: Dictionary) -> void:
	airframe = clampf(float(d.get("airframe", airframe)), 0.0, 1.0)
	pitot = clampf(float(d.get("pitot", pitot)), 0.0, 1.0)
	static_ice = clampf(float(d.get("static", static_ice)), 0.0, 1.0)
	var e = d.get("engines", null)
	if e is Array:
		for i in mini(e.size(), engines.size()):
			engines[i] = clampf(float(e[i]), 0.0, 1.0)
	_detect_t = float(d.get("detect_t", _detect_t))
	_pitot_blocked = bool(d.get("pitot_blocked", _pitot_blocked))
	_static_blocked = bool(d.get("static_blocked", _static_blocked))
	_publish(0.0, [])


func _physics_process(dt: float) -> void:
	var t_c := Props.get_f("atmosphere/temperature_k", 288.15) - 273.15
	var tas := Props.get_f("fdm/tas_mps")
	var storm := Props.get_f("environment/storm_intensity")
	var avail := clampf(Props.get_f("weather/icing") + 0.6 * storm, 0.0, 1.0)
	var kind := str(Props.get_v("environment/cloud_kind", "stratiform"))
	var rate := IcingRates.cloud_rate(Props.get_f("environment/ac_cloud_density"), kind, avail, t_c, tas) \
		+ IcingRates.freezing_rate(Props.get_f("environment/precip"), t_c, tas)
	var acc := rate > 0.0
	var melt := IcingRates.melt_rate(t_c, acc)
	var running := _running()
	# airframe: wing anti-ice (bleed air) holds it clean and clears it; otherwise accretion against melting
	if _wing_protected(running):
		airframe = maxf(airframe - dt / PROTECT_CLEAR_S, 0.0)
	else:
		airframe = clampf(airframe + (rate - melt) * dt, 0.0, 1.0)
	# probes: heated (switch on and powered) clear in seconds, otherwise ice faster than the airframe and melt faster
	if _pitot_heated():
		pitot = maxf(pitot - dt / HEAT_CLEAR_S, 0.0)
		static_ice = maxf(static_ice - dt / HEAT_CLEAR_S, 0.0)
	else:
		pitot = clampf(pitot + (rate * PITOT_K - melt * 3.0) * dt, 0.0, 1.0)
		static_ice = clampf(static_ice + (rate * PITOT_K * STATIC_K - melt * 3.0) * dt, 0.0, 1.0)
	_pitot_blocked = _latch(_pitot_blocked, pitot, PITOT_BLOCK)
	_static_blocked = _latch(_static_blocked, static_ice, STATIC_BLOCK)
	var bleed := []
	for i in _n:
		if _engine_protected(i, running):
			engines[i] = maxf(engines[i] - dt / (PROTECT_CLEAR_S * 0.75), 0.0)
		else:
			engines[i] = clampf(engines[i] + (rate - melt) * dt, 0.0, 1.0)
		bleed.append(_bleed(i, running))
	_detect_t = DETECT_HOLD_S if rate > DETECT_RATE else maxf(_detect_t - dt, 0.0)
	_publish(rate, bleed)


func _latch(on: bool, level: float, th: Array) -> bool:
	return level > th[0] if not on else level > th[1]


func _publish(rate: float, bleed: Array) -> void:
	Props.set_v("icing/airframe", airframe)
	Props.set_v("icing/pitot", pitot)
	Props.set_v("icing/static", static_ice)
	Props.set_v("icing/rate", rate)
	Props.set_v("icing/conditions", rate > 0.0)
	Props.set_v("icing/ice_detected", _detect_t > 0.0)
	Props.set_v("icing/pitot_blocked", _pitot_blocked)
	Props.set_v("icing/static_blocked", _static_blocked)
	var worst := 0.0
	for i in _n:
		Props.set_v("icing/engine_%d" % (i + 1), engines[i])
		var b: float = bleed[i] if i < bleed.size() else 0.0
		Props.set_v("icing/bleed_penalty_%d" % (i + 1), b)
		worst = maxf(worst, b)
	Props.set_v("icing/bleed_penalty", worst)


## Any engine running (bleed air for the anti-ice systems).
func _running() -> bool:
	for i in _n:
		if Props.get_b("engines/%d/running" % (i + 1)):
			return true
	return _n == 1 and Props.get_b("engine/running")


func _pitot_heated() -> bool:
	return _p.protection != "none" and Props.get_b(_p.pitot_heat_prop) and Props.get_b("systems/electrical/powered", true)


func _wing_protected(running: bool) -> bool:
	return _p.protection == "wing_and_engine" and running and Props.get_b(_p.wing_anti_ice_prop)


## Engine i's inlet is protected: the alt-air lever (piston), or its anti-ice switch with the engine running.
func _engine_protected(i: int, running: bool) -> bool:
	if _p.protection == "none" or str(_p.engine_anti_ice_prop) == "":
		return false
	var prop := str(_p.engine_anti_ice_prop)
	if not "%d" in prop:
		return Props.get_b(prop)
	return _p.protection == "wing_and_engine" and Props.get_b(prop % (i + 1)) and Props.get_b("engines/%d/running" % (i + 1))


## Thrust fraction engine i gives up to bleed air: its own anti-ice plus the wing's.
func _bleed(i: int, running: bool) -> float:
	var b := 0.0
	var prop := str(_p.engine_anti_ice_prop)
	if "%d" in prop and _engine_protected(i, running):
		b += _p.bleed_engine
	if _wing_protected(running):
		b += _p.bleed_wing
	return b
