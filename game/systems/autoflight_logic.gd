class_name AfLogic
extends RefCounted
## The autoflight state machine (pure logic: AfInputs in, commands and FMA text out; the Props side is
## systems/autoflight.gd). Holds the lateral / vertical / thrust mode objects and decides:
##  - AP1 / AP2 / A/THR engagement from the FCU requests (level vs state: the node writes the state back
##    to controls/fcu/{ap1, ap2, athr}, so a difference means the pilot pressed the button); the AP needs
##    power, the air and 100 ft of radio altitude; it drops on touchdown
##  - disconnects: button / instinctive disconnect (voluntary: 1.5 s warning), sidestick takeover, power or
##    AP failure, the landing auto-disconnect at 50 ft in LAND (limits.autoflight.land_disconnect_ft; 0 = off);
##    `disc_pulse` is true for 0.5 s, `disconnect_count` counts them, `warning` stays on after an
##    involuntary one until the disconnect button is pressed again
##  - the vertical mode the FCU selects: a changed vs_fpm selects V/S, a changed alt_ft in ALT hold selects
##    OP CLB / OP DES (CLB / DES when vs_managed), vs_managed toggles managed / V/S, or
##    controls/fcu/vert_select = "OPEN" | "MANAGED" | "VS" (consumed) for a knob pull / push
##  - takeoff: on the ground with the flight director on and the levers at FLX or TOGA, SRS + RWY; SRS ends
##    at the acceleration altitude (1500 ft above the field) into OP CLB; TOGA with flaps out on the glide
##    slope is a go-around (SRS, heading hold)
##  - defaults when guidance starts in flight: HDG on the present heading (FCU written) and ALT (within
##    100 ft of the FCU altitude) or V/S at the present vertical speed (FCU written)
## Outputs: nz_g, roll_rate (rad/s), fd_pitch / fd_roll (rad), lever_cmd, athr_active, FMA strings,
## `writes` = FCU set-points in SI to give back to the FCU ({hdg (true rad), vs (m/s)}).

const WARN_VOLUNTARY_S := 1.5
const PULSE_S := 0.5
const ENGAGE_RA_M := 30.0  # 100 ft
const FD_TAKEOFF_PITCH := deg_to_rad(10.0)

var speeds: AfSpeeds
var lat := AfLateral.new()
var vert := AfVertical.new()
var thr := AfThrust.new()
var ap1 := false
var ap2 := false
var fd := false
var takeoff := false
var disc_pulse := false
var disconnect_count := 0
var warning := false
var nz_g := 0.0
var roll_rate := 0.0
var fd_pitch := 0.0
var fd_roll := 0.0
var spd_target := 0.0
var fma := {"thrust": "", "vertical": "", "lateral": "", "approach": "", "misc": ""}
var thrust_limit := ""
var writes := {}
var _pulse := 0.0
var _warn_t := 0.0
var _last := {}  # FCU values of the previous tick
var _srs_end_alt := 0.0


func _init(limits := {}) -> void:
	speeds = AfSpeeds.new(limits)


func engaged() -> bool:
	return ap1 or ap2


func update(i: AfInputs) -> void:
	writes = {}
	_pulse = maxf(_pulse - i.dt, 0.0)
	disc_pulse = _pulse > 0.0
	if _warn_t > 0.0:
		_warn_t -= i.dt
		warning = warning and _warn_t > 0.0
	_buttons(i)
	_protections(i)
	fd = i.f.fd and i.powered
	var guidance := engaged() or fd
	_takeoff(i, guidance)
	var mgd := {"cas": 0.0, "mach": false}
	if guidance and (not i.wow or takeoff):
		var prev := vert.mode
		var by_pilot := _modes(i)
		mgd = _speed_target(i)
		lat.update(i)
		vert.update(i, spd_target, lat.captured())
		if vert.mode == "V/S" and prev != "V/S" and prev != "" and by_pilot != "V/S":  # fell back to V/S (glide slope lost): hold the present rate
			writes["vs"] = i.vs_mps
	else:
		lat.reset()
		vert.reset()
		takeoff = false
	if engaged() and vert.land and speeds.cfg.land_disconnect_ft > 0.0 and Units.m_to_ft(i.ra_m) < speeds.cfg.land_disconnect_ft:
		_disconnect(false)
	if not guidance:
		spd_target = speeds.limited(i, i.f.spd) if not i.f.spd_mgd else speeds.managed(i, "")["cas"]
		mgd = {"cas": spd_target, "mach": false}
	thr.update(i, vert.mode, spd_target, mgd.mach, vert.land)
	_outputs(i, guidance)
	_last = {"alt": i.f.alt, "vs": i.f.vs, "vs_mgd": i.f.vs_mgd}


# --- engagement and disconnects ---------------------------------------------

func _buttons(i: AfInputs) -> void:
	var f := i.f
	var dropped := false  # the request props still say "on" until the node writes the state back
	if f.ap_disc:  # instinctive disconnect: drops the AP, or cancels the warning
		dropped = true
		if engaged():
			_disconnect(false)
		else:
			warning = false
	if f.athr_disc:
		thr.drop()
	for k in ["ap1", "ap2"]:
		var on: bool = ap1 if k == "ap1" else ap2
		if f[k] and not on and not dropped and _can_engage(i):
			if k == "ap1":
				ap1 = true
			else:
				ap2 = true
			warning = false
		elif not f[k] and on:
			if k == "ap1":
				ap1 = false
			else:
				ap2 = false
			if not engaged():
				_disconnect(false)
	if f.athr and not thr.armed and not f.athr_disc:
		thr.armed = true
	elif not f.athr and thr.armed:
		thr.drop()


func _can_engage(i: AfInputs) -> bool:
	return i.powered and not i.ap_failed and not i.wow and i.ra_m > ENGAGE_RA_M


func _protections(i: AfInputs) -> void:
	if not engaged():
		return
	if i.wow:  # touchdown: the AP drops quietly
		ap1 = false
		ap2 = false
	elif i.takeover or i.ap_failed or not i.powered:
		_disconnect(true)


func _disconnect(involuntary: bool) -> void:
	ap1 = false
	ap2 = false
	disconnect_count += 1
	_pulse = PULSE_S
	disc_pulse = true
	warning = true
	_warn_t = 1.0e9 if involuntary else WARN_VOLUNTARY_S


# --- takeoff, go-around, mode defaults ----------------------------------------

func _takeoff(i: AfInputs, guidance: bool) -> void:
	if i.wow:
		if guidance and not takeoff and i.lever >= 0.7:
			takeoff = true
			_srs_end_alt = i.alt_m + Units.ft_to_m(speeds.cfg.accel_agl_ft)
			lat.takeoff(i.heading)
			vert.set_mode("SRS")
		elif takeoff and i.lever < 0.3:  # rejected, or never applied
			takeoff = false
			lat.reset()
			vert.reset()
		return
	var ga: bool = guidance and i.lever >= AfThrust.TOGA - AfThrust.DETENT_TOL and i.flap_lever >= 1 \
		and (vert.mode == "G/S" or vert.mode == "G/S*")
	if ga:  # go-around: SRS, heading hold, A/THR to MAN TOGA by the lever
		takeoff = true
		_srs_end_alt = i.alt_m + Units.ft_to_m(speeds.cfg.accel_agl_ft)
		lat.start_hdg()
		writes["hdg"] = i.heading
		vert.set_mode("SRS")
	if takeoff and vert.mode == "SRS" and i.alt_m >= _srs_end_alt:
		takeoff = false
		vert.set_mode("CLB" if i.f.vs_mgd else "OP CLB")
	elif takeoff and vert.mode != "SRS":
		takeoff = false


## Vertical mode selection from the FCU, and the defaults when guidance starts. Returns the mode picked.
func _modes(i: AfInputs) -> String:
	var f := i.f
	var alt_err: float = f.alt - i.alt_m
	if lat.mode == "" and vert.mode == "":  # guidance has just started in flight
		lat.start_hdg()
		lat.bank_cmd = i.roll
		if not f.hdg_mgd:
			writes["hdg"] = i.heading
		if absf(alt_err) < 30.0:
			vert.set_mode("ALT")
		else:
			vert.set_mode("V/S")
			writes["vs"] = i.vs_mps
	if vert.mode == "SRS" or vert.mode == "G/S" or vert.mode == "G/S*" or _last.is_empty():
		return ""
	var up := alt_err > 0.0
	var pick := ""
	if f.select == "OPEN":
		pick = "OP CLB" if up else "OP DES"
	elif f.select == "MANAGED" or (f.vs_mgd and not _last.vs_mgd):
		pick = "CLB" if up else "DES"
	elif f.select == "VS" or (not f.vs_mgd and (absf(f.vs - _last.vs) > 0.01 or _last.vs_mgd)):
		pick = "V/S"
	elif absf(f.alt - _last.alt) > 1.0 and (vert.mode == "ALT" or vert.mode == "ALT*"):
		pick = ("CLB" if up else "DES") if f.vs_mgd else ("OP CLB" if up else "OP DES")
	if pick != "":
		vert.set_mode(pick)
	return pick


func _speed_target(i: AfInputs) -> Dictionary:
	var m := {"cas": 0.0, "mach": false}
	if vert.mode == "SRS":
		m.cas = speeds.srs_target(i)
	elif i.f.spd_mgd:
		m = speeds.managed(i, vert.mode)
	else:
		m.cas = speeds.limited(i, i.f.spd)
	spd_target = m.cas
	return m


# --- outputs ------------------------------------------------------------------

func _outputs(i: AfInputs, guidance: bool) -> void:
	nz_g = vert.nz(i) if engaged() else 0.0
	roll_rate = lat.roll_rate_cmd if engaged() else 0.0
	fd_roll = lat.bank_cmd if guidance else i.roll
	if not guidance:
		fd_pitch = i.pitch
	elif i.wow:
		fd_pitch = FD_TAKEOFF_PITCH
	else:
		fd_pitch = i.pitch + clampf(vert.gamma_cmd - i.gamma(), -0.15, 0.15)
	var armed_ground: bool = fd and i.wow and not takeoff
	var above: bool = (_srs_end_alt > 0.0 and i.alt_m >= _srs_end_alt) or Units.m_to_ft(i.ra_m) > speeds.cfg.accel_agl_ft
	fma = {"thrust": thr.fma(i, above), "vertical": AfFma.vertical(vert, armed_ground),
		"lateral": AfFma.lateral(lat, vert, armed_ground), "approach": AfFma.approach(lat, i.f.appr),
		"misc": AfFma.misc(ap1, ap2, fd, thr.armed)}
	thrust_limit = thr.limit_text(i)


# --- save / load ---------------------------------------------------------------

func save_state() -> Dictionary:
	return {"ap1": ap1, "ap2": ap2, "athr": thr.armed, "lat": lat.mode, "vert": vert.save_state(), "takeoff": takeoff,
		"srs_end_alt": _srs_end_alt, "warning": warning, "count": disconnect_count}


func load_state(d: Dictionary) -> void:
	ap1 = bool(d.get("ap1", false))
	ap2 = bool(d.get("ap2", false))
	thr.armed = bool(d.get("athr", false))
	lat.mode = str(d.get("lat", ""))
	vert.load_state(d.get("vert", {}))
	takeoff = bool(d.get("takeoff", false))
	_srs_end_alt = float(d.get("srs_end_alt", 0.0))
	warning = bool(d.get("warning", false))
	disconnect_count = int(d.get("count", 0))
	_last = {}
