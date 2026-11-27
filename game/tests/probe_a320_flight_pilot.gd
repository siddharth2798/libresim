extends RefCounted
## Probe helper of probe_a320_flight.gd: the crew of a whole A320 flight on the autopilot. It hand-flies only the takeoff (levers to
## TOGA, rudder on the runway, rotation and the first 100 ft by the side stick); from there it does what an Airbus crew does with the
## autoflight flying: AP1 + AP2 on, gear and flaps by the speeds, levers back to CL at LVR CLB, APPR pressed near the destination,
## gear down and flaps to FULL on the approach, autobrake MED, then hands off to the stop. It never touches the stick, rudder or
## levers after the AP is on (a stick input would disconnect it), and it never sets the FCU speed, altitude or heading: the route,
## the managed modes and the FMS do. Reads one dictionary per tick (`s`, built by the probe), writes the Props the cockpit writes.

const KT := 0.514444
const VFE := [999.0, 230.0, 215.0, 200.0, 185.0, 177.0]  # lever 0..5 (UP, 1, 1+F, 2, 3, FULL), kt
const APPR_RA_FT := 6000.0  # APPR is pressed in the approach phase (DECEL) or below this in the descent

var phase := "takeoff"
var rwy_hdg := 0.0  # rad, true
var log: Array = []
var _rotated := false
var _flaps := 2
var _gear := 1


func say(t: float, msg: String) -> void:
	log.append("FLIGHT %7.1f %s" % [t, msg])
	print(log.back())


func decide(s: Dictionary) -> void:
	match phase:
		"final": _final(s)
		"takeoff": _takeoff(s)
		"climb", "cruise", "descent", "approach": _airborne(s)
		"rollout": _rollout(s)


## --final: the air start on final (gear down, CONF 2): levers to CL, A/THR, managed speed, the FCU altitude where the aircraft is
## (ALT), AP1 + AP2, APPR; then the approach as in a whole flight.
func _final(s: Dictionary) -> void:
	_gear = 1
	_flaps = int(Props.get_v("controls/flaps", 3))
	for k in ["controls/throttle", "controls/throttle_1", "controls/throttle_2"]:
		Props.set_v(k, AfThrust.CL)
	Props.set_v("controls/fcu/alt_ft", roundf(s.alt_ft / 100.0) * 100.0)
	Props.set_v("controls/fcu/athr", true)
	Props.set_v("controls/fcu/spd_managed", true)
	Props.set_v("controls/fcu/ap1", true)
	Props.set_v("controls/fcu/ap2", true)
	Props.set_v("controls/fcu/appr", true)
	Props.set_v("controls/autobrake", 2)
	phase = "approach"
	say(s.t, "on final %.1f nm out, %.0f ft, %.0f kt, flaps %d: A/THR, AP1 + AP2, APPR" % [s.dest_nm, s.alt_ft, s.ias, _flaps])


func _takeoff(s: Dictionary) -> void:
	if s.t < 0.2:
		_set_flaps(2)
		Props.set_v("controls/pitch_trim", 0.15)
		Props.set_v("controls/parking_brake", false)
		Props.set_v("controls/brake_left", 0.0)
		Props.set_v("controls/brake_right", 0.0)
		Props.set_v("controls/autobrake", 0)
	var lever := minf(s.t / 3.0, 1.0)
	Props.set_v("controls/throttle", lever)
	Props.set_v("controls/throttle_1", lever)
	Props.set_v("controls/throttle_2", lever)
	var he := wrapf(deg_to_rad(s.hdg) - rwy_hdg, -PI, PI)
	Props.set_v("controls/yaw", clampf(-2.0 * he - deg_to_rad(s.r), -0.3 if s.ias < 60.0 else -1.0, 0.3 if s.ias < 60.0 else 1.0))
	if s.ias > 142.0:
		if not _rotated:
			_rotated = true
			say(s.t, "rotate at %.0f kt" % s.ias)
		Props.set_v("controls/pitch", clampf(0.30 + 0.12 * (12.0 - s.pitch) - 0.10 * s.q, -0.3, 0.8))
	if not s.wow and s.ra > 130.0:
		Props.set_v("controls/pitch", 0.0)
		Props.set_v("controls/yaw", 0.0)
		Props.set_v("controls/fcu/ap1", true)
		Props.set_v("controls/fcu/ap2", true)
		phase = "climb"
		say(s.t, "AP1 + AP2 pressed at %.0f ft RA, %.0f kt; FMA %s" % [s.ra, s.ias, s.fma])


func _airborne(s: Dictionary) -> void:
	if _gear == 1 and s.vs > 300.0 and s.ra > 50.0 and phase == "climb":
		_set_gear(0, s)
	if (phase == "climb" or phase == "cruise") and _flaps > 0 and s.ra > 1000.0 and s.vert_fma != "SRS" \
			and s.ias >= s.spd_tgt_kt - 3.0:
		_set_flaps(_flaps - 1, s)  # at F, then at S: the managed target with the flaps out
	if s.thr_fma == "LVR CLB" and Props.get_f("controls/throttle_1") > AfThrust.CL + 0.01:
		for k in ["controls/throttle", "controls/throttle_1", "controls/throttle_2"]:
			Props.set_v(k, AfThrust.CL)
		say(s.t, "LVR CLB: levers to CL")
	if phase == "climb" and (s.vert_fma == "ALT" or s.vert_fma == "ALT CRZ") and s.alt_ft > 9000.0:
		phase = "cruise"
		say(s.t, "level at %.0f ft, FMA %s" % [s.alt_ft, s.fma])
	if phase == "cruise" and s.fms_phase == "DES":
		phase = "descent"
		say(s.t, "top of descent: FCU alt %.0f, FMA %s" % [s.fcu_alt, s.fma])
	if phase == "descent" and (s.fms_phase == "APPR" or (s.ra < APPR_RA_FT and s.dest_nm < 12.0)):
		Props.set_v("controls/fcu/appr", true)
		phase = "approach"
		say(s.t, "APPR pressed %.1f nm out, %.0f ft, %.0f kt; NAV2 %s; FMA %s" % [s.dest_nm, s.alt_ft, s.ias, s.ils_auto, s.fma])
	if phase == "approach":
		_configure(s)
	if s.thr_fma == "RETARD" and Props.get_f("controls/throttle_1") > 0.0:  # the crew pulls the levers to idle at RETARD
		for k in ["controls/throttle", "controls/throttle_1", "controls/throttle_2"]:
			Props.set_v(k, 0.0)
		say(s.t, "RETARD: levers to idle at %.0f ft RA" % s.ra)
	if s.wow:
		phase = "rollout"
		say(s.t, "touchdown %.0f kt, %.0f fpm; FMA %s" % [s.ias, s.vs, s.fma])


## Flaps one step at a time once the speed is below the next VFE, gear down with the glide slope near (or CONF 2).
func _configure(s: Dictionary) -> void:
	var gs_near: bool = s.vert_fma.begins_with("G/S") or s.vert_fma == "LAND"
	if _gear == 0 and (gs_near or _flaps >= 3):
		_set_gear(1, s)
		Props.set_v("controls/autobrake", 2)
	var next := _flaps + 1 if _flaps < 5 else 5
	if _flaps == 0:
		next = 1
	if next != _flaps and s.ias < VFE[next] - 8.0 and (next <= 3 or _gear == 1):
		_set_flaps(next, s)


func _rollout(s: Dictionary) -> void:
	if s.gs < 1.0 and phase == "rollout":
		phase = "stopped"
		say(s.t, "stopped")


func _set_flaps(n: int, s := {}) -> void:
	_flaps = n
	Props.set_v("controls/flaps", n)
	if not s.is_empty():
		say(s.t, "flaps %d at %.0f kt" % [n, s.ias])


func _set_gear(n: int, s: Dictionary) -> void:
	_gear = n
	Props.set_v("controls/gear", n)
	say(s.t, "gear %s at %.0f ft RA" % ["down" if n == 1 else "up", s.ra])
