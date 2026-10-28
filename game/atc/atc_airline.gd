class_name AtcAirline
extends RefCounted
## What an airline-profile flight gets from the monitor on top of the shared state machine: after the
## handover to Approach a "radar contact, climb flight level 100" (a generic instruction: no real SID
## or STAR is modelled). The GA/VFR branches of atc_monitor.gd stay as they are; the airline wording of
## the shared calls is in the phrase file ("profiles" -> "airline").


## Called from AtcMonitor.step for airline aircraft.
static func step(m: AtcMonitor, w: Dictionary, now: float) -> void:
	var c := m.c
	if c.s.state != "departed" or not c.flag("st_dep_ho") or c.flag("st_dep_climb") or float(w.agl) < 300.0:
		return
	if AtcFacilities.separate(w, "APP") and m._tell("approach", "depart_climb", w, now):
		c.set_flag("st_dep_climb")


## The phrase key of the "frequency change approved" call after take-off when there is no separate Approach.
static func depart_key(profile: String) -> String:
	return "depart_ifr" if AtcProfile.is_airline(profile) else "depart_vfr"
