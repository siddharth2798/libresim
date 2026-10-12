class_name AtcMonitor
extends RefCounted
## Watches the world snapshot (atc_world.gd) and does what a controller does without being
## asked: follows the flight through the state machine, hands the pilot over to the next
## frequency, asks for "report final", clears to take off / land when the runway is free,
## tells the pilot to vacate; and gives advisories (never blocking): taking off or landing
## without clearance, entering a runway without clearance, COM1 failure, wrong frequency.
## Each advisory is shown once per flight (per departure after a landing) and is worded as a note,
## not a command. In a training lesson (silent = true) the monitor says nothing at all: the state
## still follows the flight and clearances count as given (/atc/cleared_takeoff, cleared_land
## true), so a lesson is never interrupted by ATC. Called a few times a second with sim time `now`.

const ROLL_MPS := 15.0    # ~30 kt: the take-off roll
const GO_AGL_M := 61.0    # ~200 ft: below this without a landing clearance = go around
const VACATE_MPS := 14.0  # ~27 kt
const JUMP_M := 400.0     # a bigger jump between looks = F5 reset or a loaded flight
const CALL_GAP := 0.3     # s before an unprompted call goes out

var c: AtcController
var silent := false  # training lesson: no unprompted calls or advisories, clearances implied
var _inited := false
var _last_pos := Vector2.ZERO
var _was_air := false
var _t_air := -1.0
var _t_td := -1.0
var _t_lined := -1.0
var _on_rwy := false
var _com_failed := false


func _init(ctl: AtcController) -> void:
	c = ctl


## Take the world as it is now as the starting point (also after a flight was loaded).
func rebase(w: Dictionary) -> void:
	_inited = true
	_last_pos = w.pos
	_was_air = not bool(w.wow)
	_t_air = -1.0
	_t_td = -1.0
	_t_lined = -1.0
	_on_rwy = bool(w.on_runway)


func step(w: Dictionary, now: float) -> void:
	if not _inited or (w.pos as Vector2).distance_to(_last_pos) > JUMP_M:
		c.reset(w)
		rebase(w)
	_last_pos = w.pos
	c.refresh_info(w)
	var failed := not bool(w.com1_ok) and str(w.get("com1_why", "failed")) != "unpowered"  # a switched-off radio is no event
	if failed and not _com_failed and not silent:
		c.system("com_failed", w, now)
	_com_failed = failed
	_follow_airport(w)
	if bool(w.wow):
		_ground(w, now)
	else:
		_air(w, now)
	_handoff_watch(w, now)
	if silent:  # lesson: clearances are implicit, nothing is ever pending
		for k in ["cleared", "lineup_ok", "cleared_takeoff", "cleared_land"]:
			c.s[k] = true
		c.s.handoff = ""


func _controlled(w: Dictionary) -> bool:
	return str(w.get("ctl", "")) in ["published", "any"]


## An unprompted call from the unit that answers `service`, if COM1 is tuned to it (else nobody
## hears it). The pilot reads it back if there is a readback phrase for it.
func _tell(service: String, key: String, w: Dictionary, now: float, extra := {}, then := Callable()) -> bool:
	if silent or not _controlled(w) or not bool(w.com1_ok) or not AtcFacilities.handles(w, service):
		return false
	var role := AtcFacilities.role_for(w, service)
	var x := extra.duplicate()
	x.fac = AtcFacilities.name_of(w, role)
	var sl := c.slots(w, x)
	var at := now + CALL_GAP
	c.say("controller", key, role, sl, at, then, true)
	if c.phr.has("readback", key):
		c.say("readback", key, "*", sl, at + c.readback_gap)
	return true


## The unit COM1 is tuned to hands the pilot over to another unit of the airport.
func _handoff_to(w: Dictionary, now: float, to_role: String) -> bool:
	var t := AtcFacilities.tuned(w)
	if silent or t.role == "" or not AtcFacilities.has_role(w, to_role):
		return false
	var x := {"fac": t.name, "fac2": AtcFacilities.name_of(w, to_role), "freq": AtcFacilities.freq_of(w, to_role)}
	var sl := c.slots(w, x)
	var then := func():
		c.s.handoff = to_role
		c.s.handoff_at = now
	c.say("controller", "handoff", t.role, sl, now + CALL_GAP, then, true)
	c.say("readback", "handoff", "*", sl, now + CALL_GAP + c.readback_gap)
	return true


func _advisory(key: String, w: Dictionary, now: float) -> void:
	if not silent:
		c.say("advisory", key, "*", c.slots(w), now)


func _follow_airport(w: Dictionary) -> void:
	var apt := str(w.apt)
	if apt != str(c.s.airport) and c.s.state in ["parked", "clearance", "taxi", "hold_short", "lined_up", "enroute", "departed", "landed", "vacated"]:
		c.s.airport = apt
		c.s.runway = ""
		c.rev += 1


# ---- on the ground ----

func _ground(w: Dictionary, now: float) -> void:
	if _was_air:  # touchdown
		_was_air = false
		_t_td = now
		if str(w.apt) == "":
			c.set_state("parked")
		else:
			c.s.arrived = true
			c.s.cleared_land = false
			c.set_state("landed")
	_t_air = -1.0
	var st: String = c.s.state
	var gs := float(w.gs)
	if st in ["parked", "clearance", "taxi", "hold_short", "lined_up"]:
		_departure_side(w, now, st)
	elif st == "takeoff" and gs < 2.0:
		c.set_state("lined_up")  # rejected take-off
	elif st == "landed":
		_after_landing(w, now)
	if bool(c.s.arrived) and c.s.state in ["landed", "vacated", "taxi"] and gs < 0.5 and bool(w.at_stand):
		_park(w)
	_on_rwy = bool(w.on_runway)


func _departure_side(w: Dictionary, now: float, st_in: String) -> void:
	var st := st_in
	var s := c.s
	var gs := float(w.gs)
	var on := bool(w.on_runway)
	var moved := (w.pos as Vector2).distance_to(Vector2(s.park_e, s.park_n))
	if st in ["parked", "clearance"] and gs > 2.0 and moved > 15.0:  # taxiing, asked or not
		c.set_state("taxi")
		st = "taxi"
	if st in ["parked", "clearance", "taxi"] and not on and gs < 3.0 and moved > 50.0 \
			and (float(w.rwy_dist) < 90.0 or float(w.hold_dist) < 40.0):
		c.set_state("hold_short")
		st = "hold_short"
	if st == "hold_short":
		_tower_handover(w, now)
	if on and not _on_rwy and _controlled(w) and not s.lineup_ok and not s.cleared_takeoff and not c.flag("adv_hold"):
		c.set_flag("adv_hold")
		_advisory("hold_crossed", w, now)
	if on and bool(w.aligned) and gs < 3.0 and st != "lined_up":
		c.set_state("lined_up")
		st = "lined_up"
		_t_lined = now
	if st == "lined_up" and s.lineup_ok and not s.cleared_takeoff and _t_lined >= 0.0 and now - _t_lined > 3.0:
		_takeoff_clear(w, now)  # "line up and wait" was given; the runway is free
	if on and bool(w.aligned) and gs > ROLL_MPS:
		if _controlled(w) and not s.cleared_takeoff:
			if s.lineup_ok:
				_takeoff_clear(w, now)  # rolling start after line-up: cleared as it goes
			elif not c.flag("adv_takeoff"):
				c.set_flag("adv_takeoff")
				_advisory("takeoff_no_clr", w, now)
		c.set_state("takeoff")


func _takeoff_clear(w: Dictionary, now: float) -> void:
	if c.flag("st_tc"):
		return
	var then := func(): c.s.cleared_takeoff = true
	if _tell("tower", "takeoff_clear", w, now, {"rwy": c.runway_for(w)}, then):
		c.set_flag("st_tc")


## At the holding point: the unit COM1 is tuned to says "contact Tower", or the radio says what to tune.
func _tower_handover(w: Dictionary, now: float) -> void:
	if silent or c.flag("st_ho") or str(w.ctl) != "published" or AtcFacilities.role_for(w, "tower") == "":
		return
	c.set_flag("st_ho")
	if AtcFacilities.handles(w, "tower") or _handoff_to(w, now, "TWR"):
		return
	var f := AtcFacilities.facility_for(w, "tower")
	c.system("tune_hint", w, now, {"fac2": f.name, "freq2": f.mhz})


func _after_landing(w: Dictionary, now: float) -> void:
	if not c.flag("st_vacate") and (float(w.gs) < VACATE_MPS or now - _t_td > 6.0):
		var sep := AtcFacilities.separate(w, "GND")
		var x := {"fac2": AtcFacilities.name_of(w, "GND"), "freq": AtcFacilities.freq_of(w, "GND")} if sep else {}
		var then := func():
			c.s.handoff = "GND"
			c.s.handoff_at = now
		if _tell("tower", "vacate" if sep else "vacate_nofreq", w, now, x, then if sep else Callable()):
			c.set_flag("st_vacate")
	if not bool(w.on_runway) and float(w.gs) < 15.0:
		c.set_state("vacated")


func _park(w: Dictionary) -> void:
	var s := c.s
	c.set_state("parked")
	for k in ["arrived", "cleared", "cleared_takeoff", "cleared_land", "lineup_ok", "pushed"]:
		s[k] = false
	s.handoff = ""
	s.runway = ""
	for k in s.flags.keys():
		if str(k).begins_with("adv_") or str(k) == "land_wait":
			s.flags.erase(k)
	var p: Vector2 = w.pos
	s.park_e = p.x
	s.park_n = p.y
	c.rev += 1


# ---- in the air ----

func _air(w: Dictionary, now: float) -> void:
	var s := c.s
	if _t_air < 0.0:
		_t_air = now
	if not _was_air and now - _t_air >= 1.5:  # airborne for good (not a bounce)
		_was_air = true
		if s.state in ["parked", "clearance", "taxi", "hold_short", "lined_up", "takeoff", "landed", "vacated"]:
			c.set_state("departed")
			s.cleared_takeoff = false
			s.lineup_ok = false
			s.arrived = false
	if not _was_air:
		return
	var st: String = s.state
	var agl := float(w.agl)
	if st == "departed":
		if agl > 150.0 and not c.flag("st_dep_ho"):
			_departure_handoff(w, now, agl)
		if str(w.apt) == "" or float(w.apt_dist) > 15000.0:
			c.set_state("enroute")
	elif st == "inbound":
		if float(w.apt_dist_nm) <= 5.5 and not c.flag("st_rf"):
			if _tell("tower", "report_final", w, now, {"rwy": c.runway_for(w)}) or _handoff_to(w, now, "TWR"):
				c.set_flag("st_rf")
	elif st == "final" and c.flag("land_wait") and bool(w.rwy_free):
		var then := func():
			c.s.cleared_land = true
			c.clear_flag("land_wait")
		_tell("tower", "land_clear", w, now, {"rwy": c.runway_for(w)}, then)
	if st in ["inbound", "final"] and (str(w.apt) == "" or float(w.apt_dist) > 90000.0):
		c.set_state("enroute")
	if _controlled(w) and not s.cleared_land and agl < GO_AGL_M and float(w.vs) < -0.3 \
			and not (w.appr as Dictionary).is_empty() and not c.flag("adv_land"):
		c.set_flag("adv_land")
		_advisory("land_no_clr", w, now)
	if silent and st in ["enroute", "departed", "inbound"] and agl < 500.0 and float(w.vs) < -0.5 and not (w.appr as Dictionary).is_empty():
		c.set_state("final")  # lesson: the approach is followed without calls


func _departure_handoff(w: Dictionary, now: float, agl: float) -> void:
	if agl > 900.0 or not _controlled(w):
		c.set_flag("st_dep_ho")  # too late / nobody to hand over
		return
	if AtcFacilities.separate(w, "APP"):
		var x := {"fac2": AtcFacilities.name_of(w, "APP"), "freq": AtcFacilities.freq_of(w, "APP")}
		var then := func():
			c.s.handoff = "APP"
			c.s.handoff_at = now
		if _tell("tower", "handoff", w, now, x, then):
			c.set_flag("st_dep_ho")
	elif _tell("tower", "depart_vfr", w, now):
		c.set_flag("st_dep_ho")


# ---- handover follow-up ----

## A handover is pending until COM1 handles the next unit; after 25 s the radio says what to tune.
func _handoff_watch(w: Dictionary, now: float) -> void:
	var h := str(c.s.handoff)
	if h == "" or silent:
		return
	var svc: String = {"TWR": "tower", "GND": "ground", "APP": "approach"}.get(h, "")
	if svc == "" or AtcFacilities.handles(w, svc):
		c.s.handoff = ""
		c.rev += 1
	elif now - float(c.s.handoff_at) > 25.0 and not c.flag("st_hint_" + h) and bool(w.com1_ok):
		c.set_flag("st_hint_" + h)
		var f := AtcFacilities.facility_for(w, svc)
		if float(f.mhz) > 0.0:
			c.system("tune_hint", w, now, {"fac2": f.name, "freq2": f.mhz})
