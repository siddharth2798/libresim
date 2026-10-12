class_name LessonPilots
extends RefCounted
## Scripted pilots for tests/landing_probe.gd: they fly the training lessons through the
## property tree like the keyboard would (controls/*, +1 pitch = pull = nose up) on top of the
## attitude loops of tests/e2e/e2e_pilot.gd (`pl`: pitch_tgt, roll_tgt, hdg_tgt, active).
## `p` is the probe (ts = TrainingSession, pl = the attitude pilot, args, t, st = pilot state).
## Pilot kinds (--pilot=): good, plus faults that should end a lesson gracefully.


static func tick(p: Node, dt: float) -> void:
	if p.ts.run.is_empty():
		return
	match Session.training:
		"landing": landing(p, dt)
		"takeoff": takeoff(p, dt)
		"cruise": cruise(p, dt)


## Landing: pitch holds the speed, throttle holds the glide path (what the lesson teaches).
## good | fast | short | late_flaps | noflaps | nobrake | dive; --vbias=kt --gpbias=deg --react=s
static func landing(p: Node, dt: float) -> void:
	var s: Dictionary = p.ts._snapshot()
	var st: Dictionary = p.st
	var pl: Node = p.pl
	var pilot := str(p.args.get("pilot", "good"))
	var rwy_hdg: float = float(p.ts._rw.hdg)
	Props.set_v("controls/mixture", 1.0)
	pl.active = true
	if s.wow > 0.5 or st.get("td_t", -1.0) >= 0.0:
		if st.get("td_t", -1.0) < 0.0:
			st.td_t = p.t
		var since: float = p.t - st.td_t
		Props.set_v("controls/throttle", 0.0)
		pl.pitch_tgt = clampf(4.0 - since * 1.5, 0.0, 4.0)  # let the nose down gently
		pl.roll_tgt = 0.0
		pl.hdg_tgt = rwy_hdg
		var b := 1.0 if (since > 2.5 and pilot != "nobrake") else 0.0
		Props.set_v("controls/brake_left", b)
		Props.set_v("controls/brake_right", b)
		return
	pl.roll_tgt = pl.bank_for_track(rwy_hdg - clampf(s.cross * 0.15, -25.0, 25.0), 15.0)
	var react := float(p.args.get("react", 4.0))
	var ias: float = s.ias
	var flaps: int = int(Props.get_v("controls/flaps", 0))
	var v_tgt := 80.0 if p.t < react else 70.0
	if p.t > react and pilot != "noflaps" and ias < (82.0 if pilot != "late_flaps" else 66.0) and flaps < 2:
		if st.get("flaps_t", -1.0) < 0.0:
			st.flaps_t = p.t
		if p.t - st.flaps_t > 1.0:
			Props.set_v("controls/flaps", 2)
	if flaps >= 2:
		v_tgt = 65.0
	if s.along > -400.0:
		v_tgt = 62.0
	if pilot == "fast":
		v_tgt = 95.0
	if p.t > react:
		v_tgt += float(p.args.get("vbias", 0.0))
	if pilot == "dive" and p.t > react:
		pl.pitch_tgt = -14.0
		Props.set_v("controls/throttle", 0.6)
		return
	# pitch holds the speed (too fast -> pull up), slowly: the speed loop is the slow one
	var err := ias - v_tgt
	st.ip = clampf(st.get("ip", 0.0) + 0.05 * err * dt, -5.0, 5.0)
	pl.pitch_tgt = clampf(-2.0 + 0.25 * err + st.ip, -9.0, 8.0)
	# throttle holds the glide path from the height error and the sink-rate error
	var dist := maxf(-float(s.along), 1.0)
	var h_err: float = (s.pos.z - float(p.ts._rw.elev) - TrainingMarkers.TCH) - dist * tan(deg_to_rad(3.0))
	if pilot == "short":
		h_err -= 60.0
	h_err += float(p.args.get("hbias", 0.0)) + dist * tan(deg_to_rad(float(p.args.get("gpbias", 0.0))))
	var vs_want := -Props.get_f("fdm/groundspeed_mps") * tan(deg_to_rad(3.0))
	var vs_err := Props.get_f("fdm/vs_mps") - vs_want
	var thr := clampf(0.28 - (0.004 * h_err + 0.06 * vs_err), 0.0, 1.0)
	if p.t < react:
		thr = Props.get_f("controls/throttle")
	elif (flaps < 2 and pilot != "noflaps") or ias > v_tgt + 8.0:
		thr = minf(thr, 0.1)  # slowing down: power back
	Props.set_v("controls/throttle", thr)
	if s.agl < 25.0 and pilot != "fast":  # flare: idle, raise the nose to hold a small sink
		Props.set_v("controls/throttle", 0.0)
		pl.pitch_tgt = clampf(4.0 + 0.012 * (-150.0 - float(s.vs)), 2.0, 8.0)


## Takeoff: full power, rudder on the centreline, rotate at 55 kt, climb at 74 kt.
## good | norotate (stays on the ground to the end) | settle (lifts off, then pushes the nose down)
static func takeoff(p: Node, dt: float) -> void:
	var s: Dictionary = p.ts._snapshot()
	var st: Dictionary = p.st
	var pl: Node = p.pl
	var pilot := str(p.args.get("pilot", "good"))
	var rwy_hdg: float = float(p.ts._rw.hdg)
	Props.set_v("controls/mixture", 1.0)
	Props.set_v("controls/parking_brake", false)
	pl.active = true
	pl.hdg_tgt = rwy_hdg
	Props.set_v("controls/throttle", clampf((p.t - 1.0) / 3.0, 0.0, 1.0))
	var on_ground: bool = s.wow > 0.5
	pl.roll_tgt = 0.0 if on_ground else pl.bank_for_track(rwy_hdg - clampf(s.cross * 0.1, -8.0, 8.0), 8.0)
	if st.get("rot_t", -1.0) < 0.0 and s.ias >= 55.0 and pilot != "norotate":
		st.rot_t = p.t
	if st.get("rot_t", -1.0) >= 0.0:
		pl.pitch_tgt = minf((p.t - st.rot_t) * 3.0, 8.0)
		if s.agl > 60.0:
			pl.pitch_tgt = clampf(8.0 + 0.4 * (s.ias - 74.0), 2.0, 14.0)
	else:
		pl.pitch_tgt = 0.0
	if pilot == "settle" and s.wow < 0.5 and s.agl > 3.0:
		st.air_t = st.get("air_t", 0.0) + dt
		if st.air_t > 2.0:
			pl.pitch_tgt = -5.0
			Props.set_v("controls/throttle", 0.2)


## Cruise: hold altitude, set power, trim hands-off, turn left 90, climb 500, descend 500, level off.
## good | low (descends into the ground)
static func cruise(p: Node, dt: float) -> void:
	var s: Dictionary = p.ts._snapshot()
	var st: Dictionary = p.st
	var pl: Node = p.pl
	var run: Dictionary = p.ts.run
	var step: int = run.step
	var s0: Dictionary = run.s0
	if not st.has("alt0"):
		st.alt0 = s.alt
		st.trim = Props.get_f("controls/pitch_trim")
		st.calm = 0.0
	Props.set_v("controls/mixture", 1.0)
	pl.active = true
	pl.roll_tgt = 0.0
	if str(p.args.get("pilot", "good")) == "low" and p.t > 10.0:
		pl.pitch_tgt = -8.0
		return
	var thr := Props.get_f("controls/throttle")
	var target_alt: float = float(st.get("hold_alt", st.alt0))
	match step:
		0:
			_hold(pl, s, target_alt)
		1:  # cruise power: 2,300 rpm
			Props.set_v("controls/throttle", clampf(thr + (2300.0 - s.rpm) * 0.0008 * dt * 5.0, 0.0, 1.0))
			_hold(pl, s, target_alt)
		2:  # trim until the yoke is not needed, then hands off
			_hold(pl, s, target_alt)
			var held: float = Props.get_f("controls/pitch")
			if st.calm < 3.0:
				st.trim = clampf(st.trim + 0.6 * held * dt, -1.0, 1.0)
				Props.set_v("controls/pitch_trim", st.trim)
				st.calm = st.calm + dt if absf(held) < 0.03 else 0.0
			else:  # hands off; tap the trim a little while it still climbs or sinks
				pl.active = false  # no yoke input (pitch_in = 0), only a light touch on the ailerons
				var rates: Vector3 = Props.get_v("fdm/body_rates", Vector3.ZERO)
				Props.set_v("controls/pitch", 0.0)
				Props.set_v("controls/roll", clampf(-0.045 * rad_to_deg(Props.get_f("fdm/roll_rad")) - 0.012 * rad_to_deg(rates.x), -1.0, 1.0))
				Props.set_v("controls/yaw", 0.0)
				st.trim = clampf(st.trim - 0.00006 * float(s.vs) * dt, -1.0, 1.0)
				Props.set_v("controls/pitch_trim", st.trim)
		3:  # standard-rate-ish left turn of 90 degrees
			var d := wrapf(float(s.hdg) - float(s0.hdg), -180.0, 180.0)
			pl.roll_tgt = -20.0 if d > -75.0 else (-8.0 if d > -84.0 else 0.0)
			_hold(pl, s, target_alt, 1.0 if d > -84.0 else 0.0)
		4:  # climb at Vy
			Props.set_v("controls/throttle", 1.0)
			pl.pitch_tgt = clampf(8.0 + 0.4 * (s.ias - 74.0), 2.0, 14.0)
			st.hold_alt = s.alt
		5:  # descend at about 500 fpm
			Props.set_v("controls/throttle", clampf(thr + (1900.0 - s.rpm) * 0.0008 * dt * 5.0, 0.0, 1.0))
			pl.pitch_tgt = clampf(-1.0 + 0.004 * (-500.0 - s.vs), -6.0, 5.0)
			st.hold_alt = s.alt
		_:  # level off
			Props.set_v("controls/throttle", clampf(thr + (2300.0 - s.rpm) * 0.0008 * dt * 5.0, 0.0, 1.0))
			if not st.has("lvl"):
				st.lvl = float(st.hold_alt) - 30.0
			_hold(pl, s, float(st.lvl))
	st.last_step = step


## Pitch target that holds `alt_ft`, with extra pitch `bank_comp` (deg) for a banked turn.
static func _hold(pl: Node, s: Dictionary, alt_ft: float, bank_comp := 0.0) -> void:
	var err := alt_ft - float(s.alt)
	pl.pitch_tgt = clampf(1.5 + bank_comp + 0.02 * err - 0.004 * float(s.vs), -6.0, 9.0)
