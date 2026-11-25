class_name AfLogic
extends RefCounted
## The autoflight state machine (pure logic: AfInputs in, commands and FMA text out; the Props side is
## systems/autoflight.gd). Holds the lateral / vertical / thrust mode objects and decides:
##  - AP1 / AP2 / A/THR engagement from the FCU requests (the node writes the state back to controls/fcu/{ap1, ap2, athr},
##    so a difference means the pilot pressed the button); the AP needs power, air and 100 ft radio altitude; drops on touchdown
##  - disconnects: button / instinctive (voluntary: 1.5 s warning), sidestick takeover, power or AP failure, landing
##    auto-disconnect at 50 ft in LAND (limits.autoflight.land_disconnect_ft; 0 = off); `disc_pulse` is true for 0.5 s,
##    `disconnect_count` counts them, `warning` stays on after an involuntary one until the button is pressed again
##  - vertical mode from the FCU: controls/fcu/vert_select = "OPEN" | "MANAGED" | "VS" (V/S knob pulled) | "LEVEL" (V/S knob
##    pushed: V/S 0) (consumed); a changed alt_ft selects OP CLB / OP DES (CLB / DES when vs_managed, including while the
##    mode is not yet ALT), vs_managed toggles managed / V/S. At the selected altitude, managed engages ALT.
##    Turning the V/S knob outside V/S only presets vs_fpm (`vs_preset` s left: the FCU window shows it, AfPreview); a pull
##    flies the preset, or the present vertical speed when the window shows dashes (no preset). In V/S a turn changes the target.
##    A turn of the ALT knob alone never changes the mode: ALT / ALT* keep holding, OP and managed climbs and descents keep
##    their mode while the new target is on their side; a target on the wrong side (or > 250 ft away in ALT*) reverts to V/S.
##    HDG pushed (managed) with no GPS route does not engage NAV: the request is withdrawn (writes.hdg_mgd), window and mode agree.
##  - takeoff: on the ground with FD on and levers at FLX or TOGA, SRS + RWY; SRS ends at the acceleration altitude (1500 ft
##    above the field) into OP CLB; TOGA with flaps out on the glide slope is a go-around (SRS, heading hold)
##  - defaults when guidance starts in flight: HDG on the present heading and ALT (within 100 ft of the FCU altitude),
##    managed CLB/DES when vs_managed, or V/S at the present vertical speed (FCU written)
## Outputs: nz_g, roll_rate (rad/s), fd_pitch / fd_roll (rad), lever_cmd, athr_active, FMA strings, `writes` = FCU set-points
## in SI to give back to the FCU ({hdg (true rad), vs (m/s)}).

const WARN_VOLUNTARY_S := 1.5
const PULSE_S := 0.5
const ENGAGE_RA_M := 30.0  # 100 ft
const FD_TAKEOFF_PITCH := deg_to_rad(10.0)
const VS_PRESET_S := AfPreview.VS_S  # a V/S preset shows in the FCU window this long without a pull (Airbus: 45 s)

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
var preview := AfPreview.new()
var vs_preset: float:  # s the FCU V/S window still shows a preset turned outside V/S
	get: return preview.vs
var hdg_preset: float:  # s the managed HDG window still shows a turned heading
	get: return preview.hdg
var spd_preset: float:  # s the managed SPD window still shows a turned speed
	get: return preview.spd
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
	preview.update(i, vert.mode == "V/S")
	_protections(i)
	fd = i.f.fd and i.powered
	var guidance := engaged() or fd
	_takeoff(i, guidance)
	var mgd := {"cas": 0.0, "mach": false}
	if guidance and (not i.wow or takeoff):
		var prev := vert.mode
		var by_pilot := AfSelect.modes(self, i)
		mgd = _speed_target(i)
		lat.update(i)
		if i.f.hdg_mgd and lat.mode == "HDG" and i.gps.is_empty():  # NAV needs a route: the push is refused, the window keeps the heading
			writes["hdg_mgd"] = false
		vert.update(i, spd_target, lat.captured())
		if vert.mode == "V/S" and prev != "V/S" and prev != "" and by_pilot != "V/S":  # fell back to V/S (glide slope lost): hold the present rate
			writes["vs"] = i.vs_mps
			writes["vs_mgd"] = false
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
	preview.reset()
