class_name Electrical
extends Node
## 28 V system (C172S numbers by default: 24 V battery, 60 A alternator that needs ~1000+ RPM),
## master switches, avionics master, loads from switches. Simplified bus model:
## bus voltage = alternator regulation if it can carry the load, else
## battery voltage under load. Battery state of charge integrates current.
## The numbers are the aircraft's aircraft.json "systems.electrical" over DEFAULTS: battery_ah,
## alt_max_a, alt_rpm_min / alt_rpm_ramp (alternator output ramps up over that many RPM), bus_volts
## (regulated), bat_v_empty / bat_v_full (open circuit), bat_ohm (internal resistance + wiring),
## charge_gain / charge_min_a (charge current taper), starter_a, flap_motor_a, low_volts, powered_volts,
## starter_min_volts, loads (amps at 28 V, per consumer).
## Switches (Props controls/electrical/*): master_bat, master_alt, avionics,
##   pitot_heat; lights from controls/lights/*.
## Failures: failures/alternator, failures/battery (dead/flat).
## Publishes systems/electrical/{bus_volts, battery_amps, soc, low_volts,
##   powered, avionics_powered, gauges_powered, tc_powered, flaps_powered, starter_ok}

const DEFAULTS := {
	"battery_ah": 35.0,
	"alt_max_a": 60.0,
	"alt_rpm_min": 700.0,
	"alt_rpm_ramp": 600.0,
	"bus_volts": 28.5,
	"bat_v_empty": 23.2,  # open-circuit voltage at 0 / 100 % charge
	"bat_v_full": 25.6,
	"bat_ohm": 0.05,  # cranking ~150 A sags to ~17-18 V
	"charge_gain": 40.0,  # charge current = (1 - soc) * gain + min, capped by spare alternator output
	"charge_min_a": 0.5,
	"starter_a": 150.0,
	"flap_motor_a": 15.0,
	"low_volts": 24.5,
	"powered_volts": 20.0,
	"starter_min_volts": 15.0,  # starter contactor drops out below this (flat battery)
	"loads": {  # amps at 28 V
		"base": 3.0, "avionics": 6.0, "pitot_heat": 10.0, "nav": 2.0, "beacon": 1.5,
		"strobe": 2.5, "taxi": 4.0, "landing": 7.0, "panel": 1.0,
	},
}

var soc := 0.9  # battery state of charge 0..1
var _p := DEFAULTS.duplicate(true)


func _ready() -> void:
	add_to_group(SituationSystems.GROUP)
	var mine: Dictionary = AircraftDef.current().section("systems").get("electrical", {})
	_p = DEFAULTS.duplicate(true)
	_p.merge(mine, true)
	_p.loads = DEFAULTS.loads.duplicate()
	_p.loads.merge(mine.get("loads", {}), true)
	for k in ["master_bat", "master_alt", "avionics"]:
		if not Props.has("controls/electrical/" + k):
			Props.set_v("controls/electrical/" + k, true)


## Saved with a flight situation (core/situation_systems.gd).
func save_key() -> String:
	return "electrical"


func save_state() -> Dictionary:
	return {"soc": soc}


func load_state(d: Dictionary) -> void:
	soc = float(d.get("soc", soc))


func _physics_process(dt: float) -> void:
	var bat_on := Props.get_b("controls/electrical/master_bat") and not Props.get_b("failures/battery")
	var alt_on := Props.get_b("controls/electrical/master_alt") and bat_on and not Props.get_b("failures/alternator")
	var rpm := Props.get_f("engine/rpm")
	var load := 0.0
	if bat_on:
		load += _p.loads.base
		if Props.get_b("controls/electrical/avionics"):
			load += _p.loads.avionics
		if Props.get_b("controls/electrical/pitot_heat"):
			load += _p.loads.pitot_heat
		for l in ["nav", "beacon", "strobe", "taxi", "landing", "panel"]:
			if Props.get_b("controls/lights/" + l):
				load += _p.loads[l]
		if Props.get_b("controls/starter"):
			load += _p.starter_a
		if Props.get_b("systems/electrical/flap_motor_running"):
			load += _p.flap_motor_a
	var alt_avail: float = _p.alt_max_a * clampf((rpm - _p.alt_rpm_min) / _p.alt_rpm_ramp, 0.0, 1.0) if alt_on else 0.0
	var bat_v: float = lerpf(_p.bat_v_empty, _p.bat_v_full, soc)
	var volts := 0.0
	var bat_amps := 0.0
	if bat_on:
		if alt_avail >= load:
			volts = _p.bus_volts
			bat_amps = minf((1.0 - soc) * _p.charge_gain + _p.charge_min_a, alt_avail - load)  # charging
		else:
			bat_amps = -(load - alt_avail)
			volts = bat_v - _p.bat_ohm * absf(bat_amps)  # internal resistance + wiring
		soc = clampf(soc + bat_amps * dt / 3600.0 / _p.battery_ah, 0.0, 1.0)
		if soc <= 0.0:
			volts = 0.0
	var powered: bool = volts > _p.powered_volts
	var avionics := powered and Props.get_b("controls/electrical/avionics")
	Props.set_v("systems/electrical/bus_volts", volts)
	Props.set_v("systems/electrical/battery_amps", bat_amps)
	Props.set_v("systems/electrical/soc", soc)
	Props.set_v("systems/electrical/low_volts", bat_on and volts < _p.low_volts)
	Props.set_v("systems/electrical/powered", powered)
	Props.set_v("systems/electrical/avionics_powered", avionics)
	Props.set_v("systems/electrical/gauges_powered", powered)
	Props.set_v("systems/electrical/tc_powered", powered)
	Props.set_v("systems/electrical/flaps_powered", powered)
	Props.set_v("systems/electrical/starter_ok", bat_on and volts > _p.starter_min_volts)
