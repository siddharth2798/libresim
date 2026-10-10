class_name Electrical
extends Node
## C172S 28 V system: 24 V battery (BAT master), 60 A alternator (ALT master,
## needs ~1000+ RPM), avionics master, loads from switches. Simplified bus model:
## bus voltage = alternator regulation (28.5 V) if it can carry the load, else
## battery voltage under load. Battery state of charge integrates current.
## Switches (Props controls/electrical/*): master_bat, master_alt, avionics,
##   pitot_heat; lights from controls/lights/*.
## Failures: failures/alternator, failures/battery (dead/flat).
## Publishes systems/electrical/{bus_volts, battery_amps, soc, low_volts,
##   powered, avionics_powered, gauges_powered, tc_powered, flaps_powered, starter_ok}

const BAT_CAPACITY_AH := 35.0
const ALT_MAX_A := 60.0
const LOADS := {  # amps at 28 V
	"base": 3.0, "avionics": 6.0, "pitot_heat": 10.0, "nav": 2.0, "beacon": 1.5,
	"strobe": 2.5, "taxi": 4.0, "landing": 7.0, "panel": 1.0,
}

var soc := 0.9  # battery state of charge 0..1


func _ready() -> void:
	for k in ["master_bat", "master_alt", "avionics"]:
		if not Props.has("controls/electrical/" + k):
			Props.set_v("controls/electrical/" + k, true)


func _physics_process(dt: float) -> void:
	var bat_on := Props.get_b("controls/electrical/master_bat") and not Props.get_b("failures/battery")
	var alt_on := Props.get_b("controls/electrical/master_alt") and bat_on and not Props.get_b("failures/alternator")
	var rpm := Props.get_f("engine/rpm")
	var load := 0.0
	if bat_on:
		load += LOADS.base
		if Props.get_b("controls/electrical/avionics"):
			load += LOADS.avionics
		if Props.get_b("controls/electrical/pitot_heat"):
			load += LOADS.pitot_heat
		for l in ["nav", "beacon", "strobe", "taxi", "landing", "panel"]:
			if Props.get_b("controls/lights/" + l):
				load += LOADS[l]
		if Props.get_b("controls/starter"):
			load += 150.0
		if Props.get_b("systems/electrical/flap_motor_running"):
			load += 15.0
	var alt_avail := ALT_MAX_A * clampf((rpm - 700.0) / 600.0, 0.0, 1.0) if alt_on else 0.0
	var bat_v := 23.2 + 2.4 * soc  # open-circuit 23.2..25.6 V
	var volts := 0.0
	var bat_amps := 0.0
	if bat_on:
		if alt_avail >= load:
			volts = 28.5
			bat_amps = minf((1.0 - soc) * 40.0 + 0.5, alt_avail - load)  # charging
		else:
			bat_amps = -(load - alt_avail)
			volts = bat_v - 0.05 * absf(bat_amps)  # internal resistance + wiring
		soc = clampf(soc + bat_amps * dt / 3600.0 / BAT_CAPACITY_AH, 0.0, 1.0)
		if soc <= 0.0:
			volts = 0.0
	var powered := volts > 20.0
	var avionics := powered and Props.get_b("controls/electrical/avionics")
	Props.set_v("systems/electrical/bus_volts", volts)
	Props.set_v("systems/electrical/battery_amps", bat_amps)
	Props.set_v("systems/electrical/soc", soc)
	Props.set_v("systems/electrical/low_volts", bat_on and volts < 24.5)
	Props.set_v("systems/electrical/powered", powered)
	Props.set_v("systems/electrical/avionics_powered", avionics)
	Props.set_v("systems/electrical/gauges_powered", powered)
	Props.set_v("systems/electrical/tc_powered", powered)
	Props.set_v("systems/electrical/flaps_powered", powered)
	Props.set_v("systems/electrical/starter_ok", bat_on and volts > 18.0)
