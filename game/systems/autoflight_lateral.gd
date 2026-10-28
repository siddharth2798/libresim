class_name AfLateral
extends RefCounted
## Lateral modes of the autoflight (pure logic, no Props). Output: bank_cmd (rad, + right) and the roll
## rate demand (rad/s) that the control law gets as `ap/cmd/roll_rate_dps`.
##   RWY   takeoff: hold the runway heading until 30 ft, then HDG (or NAV when managed)
##   HDG   selected heading (FCU), shortest turn
##   NAV   managed: GPS leg (avionics/gps: direct-to or the route), track intercept with cross-track
##   LOC*  localizer capture: the capture point is found from the closure rate (lead = turn radius x
##         (1 - cos of the intercept angle)); same guidance as LOC
##   LOC   localizer track: track = course - K x offset (clamped), so a crosswind is flown out
## Armed: "LOC" (LOC or APPR pressed, waiting for the signal and the capture point). LAND is the
## localizer / glide slope mode below 400 ft (shown by the FMA only).
## Bank is limited to 25 deg; the roll demand is K x (bank - roll), limited to 8 deg/s.

const BANK_MAX := deg_to_rad(25.0)
const K_HDG := 1.2  # bank per heading error
const K_TRK := 1.4  # bank per track error
const K_LOC := 0.0004  # rad of intercept angle per m of offset
const LOC_ANGLE_MAX := deg_to_rad(30.0)
const K_NAV_XTK := deg_to_rad(40.0) / 1852.0  # intercept angle per m of cross-track error
const NAV_ANGLE_MAX := deg_to_rad(40.0)
const K_ROLL := 0.8
const ROLL_RATE_MAX := deg_to_rad(8.0)
const BANK_RATE := deg_to_rad(5.0)  # bank command slew, rad/s
const CAPTURE_BANK := deg_to_rad(22.0)  # bank assumed for the capture lead
const AIRBORNE_RA_M := 9.0  # RWY ends (30 ft)

var mode := ""  # "", RWY, HDG, NAV, LOC*, LOC
var armed := ""  # "", LOC
var bank_cmd := 0.0
var roll_rate_cmd := 0.0
var rwy_heading := 0.0


func reset() -> void:
	mode = ""
	armed = ""
	bank_cmd = 0.0
	roll_rate_cmd = 0.0


func takeoff(heading: float) -> void:
	mode = "RWY"
	rwy_heading = heading


func captured() -> bool:
	return mode == "LOC*" or mode == "LOC"


## Default mode when guidance starts in flight: the heading the aircraft is on (the caller sets the FCU).
func start_hdg() -> void:
	mode = "HDG"


func update(i: AfInputs) -> void:
	if mode == "RWY" and not i.wow and i.ra_m > AIRBORNE_RA_M:
		mode = "HDG"
	if mode != "RWY":
		_select(i)
	var target := 0.0
	match mode:
		"RWY": target = clampf(0.6 * wrapf(rwy_heading - i.heading, -PI, PI), -0.1, 0.1)
		"HDG": target = K_HDG * wrapf(i.f.hdg - i.heading, -PI, PI)
		"NAV": target = K_TRK * wrapf(_nav_track(i) - i.track, -PI, PI)
		"LOC*", "LOC": target = K_TRK * wrapf(_loc_track(i) - i.track, -PI, PI)
	target = clampf(target, -BANK_MAX, BANK_MAX)
	bank_cmd += clampf(target - bank_cmd, -BANK_RATE * i.dt, BANK_RATE * i.dt)
	roll_rate_cmd = clampf(K_ROLL * (bank_cmd - i.roll), -ROLL_RATE_MAX, ROLL_RATE_MAX)


## Mode transitions: HDG <-> NAV (managed), LOC arming, capture, loss of the signal.
func _select(i: AfInputs) -> void:
	var want_loc: bool = i.f.loc or i.f.appr
	if captured() and (not want_loc or i.ils.is_empty()):
		mode = "HDG"
	if not captured():
		armed = "LOC" if want_loc else ""
		if armed != "" and not i.ils.is_empty() and _capture_point(i):
			mode = "LOC*"
			armed = ""
		elif mode == "" or mode == "HDG" or mode == "NAV":
			mode = "NAV" if i.f.hdg_mgd and not i.gps.is_empty() else "HDG"
	elif mode == "LOC*" and absf(i.loc_offset_m()) < 25.0 and absf(wrapf(i.track - i.ils.course, -PI, PI)) < deg_to_rad(4.0):
		mode = "LOC"


## True when the turn onto the localizer course should start now.
func _capture_point(i: AfInputs) -> bool:
	var y := i.loc_offset_m()
	var th := wrapf(i.track - i.ils.course, -PI, PI)
	if absf(th) > deg_to_rad(100.0):
		return false
	var v := maxf(i.gs_mps, 30.0)
	var lead := v * v / (AfInputs.G * tan(CAPTURE_BANK)) * (1.0 - cos(th)) * 1.3 + 20.0
	return absf(y) < 60.0 or (y * th < 0.0 and absf(y) <= lead)


## Track to fly towards the active GPS waypoint: the leg course corrected by the cross-track error.
func _nav_track(i: AfInputs) -> float:
	var g: Dictionary = i.gps
	if g.is_empty():
		return i.track
	if g.dist <= 2000.0:  # close to the waypoint: fly straight at it
		return g.brg
	var leg: float = g.brg + asin(clampf(g.xtk / g.dist, -1.0, 1.0))  # right of the leg: the leg lies to the left of the bearing
	return leg - clampf(K_NAV_XTK * g.xtk, -NAV_ANGLE_MAX, NAV_ANGLE_MAX)


func _loc_track(i: AfInputs) -> float:
	return i.ils.course - clampf(K_LOC * i.loc_offset_m(), -LOC_ANGLE_MAX, LOC_ANGLE_MAX)
