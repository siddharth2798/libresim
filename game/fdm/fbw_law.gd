class_name FbwLaw
extends RefCounted
## Simplified Airbus-style fly-by-wire control law, installed as FlightControls.law of an AirlinerControls when
## aircraft.json "fcs" has {"law": "airbus_fbw"} (FbwLaw.for_def; absent = direct control, the C172). It is hand
## written and tuned against the JSBSim A320's own responses (tools/a320_reference.json); JSBSim's FBW is never
## interpreted at runtime. Each tick, after FDM.step set the pilot inputs and before the actuators move:
##   1. AirlinerControls._direct() gives the direct mapping and the speedbrake / ground spoiler commands,
##   2. the active law (FbwReversion: NORMAL / ALTERNATE / DIRECT) overwrites the surface commands:
##      FbwPitch (load factor + auto-trim via FbwTrim), FbwRoll (rate + bank hold, roll spoilers), FbwYaw
##      (pedals, damper, coordination), limits and warnings from FbwProtection,
##   3. on the ground (weight on wheels) the direct mapping takes over, blended over `ground_blend_s`.
## Pilot inputs: fcs.pitch (+1 = stick aft), roll (+1 right), yaw (+1 right pedal), pitch_trim (wheel).
## Autopilot: Props ap/cmd/active, ap/cmd/nz_g (g increment), ap/cmd/roll_rate_dps (+ right) replace the stick;
## ap/cmd/takeover is published true when the stick is moved past `takeover` (the autoflight then disengages).
## Publishes: fcs/law ("NORMAL" ...), fcs/law_id (0..2), fcs/law_reason, fcs/ground_mode, fcs/flare, plus the
## protection props (FbwProtection). Parameters: FbwParams. Law state is rebuilt from the surfaces on
## restart() (after trim, load, reset), so it is never part of a saved flight.

var par: FbwParams
var s := FbwSense.new()
var prot := FbwProtection.new()
var pitch := FbwPitch.new()
var roll := FbwRoll.new()
var yaw := FbwYaw.new()
var trim := FbwTrim.new()
var law := FbwReversion.NORMAL
var reason := ""
var wg := 1.0  # ground weight: 1 = direct (on the wheels), 0 = flight law
var _ready := false


static func for_def(def: AircraftDef) -> FbwLaw:
	if str(def.section("fcs").get("law", "")) != "airbus_fbw":
		return null
	var l := FbwLaw.new()
	l.par = FbwParams.from_def(def)
	return l


## Forget the law's internal state: the next update continues from the current surface positions.
func restart() -> void:
	_ready = false


func update(dt: float, f: FDM) -> void:
	var c: AirlinerControls = f.fcs
	if not _ready:
		s.find_gear_height(f)
		_ready = true
		wg = 1.0 if f.gear.wow else 0.0
		_rebuild(c)
	s.update(f, par, dt)
	prot.update_limits(s, par)
	var rv := FbwReversion.evaluate(s.gear_pos)
	if rv[0] != law:
		law = rv[0]
		_rebuild(c)
	reason = rv[1]
	var ap_on := law != FbwReversion.DIRECT and Props.get_b("ap/cmd/active")
	var thr := par.f("takeover")
	var grabbed := ap_on and (absf(c.pitch) > thr or absf(c.roll) > thr)
	Props.set_v("ap/cmd/takeover", grabbed)
	ap_on = ap_on and not grabbed
	wg = move_toward(wg, 1.0 if s.wow else 0.0, dt / maxf(par.f("ground_blend_s"), 1e-3))
	c._direct()
	if law == FbwReversion.DIRECT:
		c.cmd["stabilizer"] = trim.manual(c)
		pitch.track(c.cmd["elevator-l"])
		roll.reset()
	else:
		_flight_laws(c, ap_on)
	prot.update_flags(s, law == FbwReversion.NORMAL)
	_publish()


func _rebuild(c: AirlinerControls) -> void:
	pitch.reset((c.surface("elevator-l") + c.surface("elevator-r")) * 0.5)
	roll.reset()
	trim.rebase(c)


func _flight_laws(c: AirlinerControls, ap_on: bool) -> void:
	var normal := law == FbwReversion.NORMAL
	var dz := par.f("stick_deadzone")
	var sp := _dz(c.pitch, dz)
	var sr := _dz(c.roll, dz)
	var e_dir := pitch.ground(s, par, sp, c)
	# pitch
	var lim := prot.nz_limits(s, par)
	var inc := Props.get_f("ap/cmd/nz_g") if ap_on else (sp * (lim.y - 1.0) if sp > 0.0 else sp * (1.0 - lim.x) * prot.forward_authority(par))
	var nz_c := pitch.demand(s, par, prot, inc)
	var e := e_dir
	if wg >= 0.999:
		pitch.track(e_dir)
	else:
		e = lerpf(pitch.flight(s, par, prot, nz_c, maxf(sp, 0.0) if not ap_on else 0.0, normal), e_dir, wg)
	c.cmd["elevator-l"] = e
	c.cmd["elevator-r"] = e
	# THS: auto-trim in flight, the wheel on the ground; inhibited in the alpha protection
	if wg < 0.5:
		c.cmd["stabilizer"] = c.surface("stabilizer") if (normal and prot.alpha_active) else trim.auto(c, pitch.i_deg, par.d.pitch.trim_k, par.d.pitch.trim_dead_deg)
	else:
		c.cmd["stabilizer"] = trim.manual(c)
	# roll: rate law in normal law, the direct stick (already in cmd) otherwise
	var a: float = c.cmd["aileron-l"]
	if normal:
		var rp: Dictionary = par.d.roll
		var lim_deg := float(rp.limit_prot_deg) if (prot.alpha_active or prot.speed_active) else float(rp.limit_deg)
		roll.demand(s, par, sr, ap_on, deg_to_rad(Props.get_f("ap/cmd/roll_rate_dps")), lim_deg)
		prot.bank_active = roll.taper < 1.0 or (roll.hold and absf(roll.phi_ref) > 0.0 and absf(s.phi) > deg_to_rad(float(rp.hold_deg)))
		if wg >= 0.999:
			roll.reset()
		else:
			a = lerpf(roll.aileron(s, par), a, wg)
		c.cmd["aileron-l"] = a
		c.cmd["aileron-r"] = -a
	roll.spoilers(c, a, par)
	# yaw
	var ground_yaw := c.yaw * yaw.travel_deg(par, s.cas_kt, not Props.get_b("failures/fac"))
	var damper := not Props.get_b("failures/fac") and wg < 0.999
	c.cmd["rudder"] = lerpf(yaw.rudder(s, par, c.yaw, damper, not Props.get_b("failures/fac")), ground_yaw, wg)


static func _dz(x: float, dz: float) -> float:
	return 0.0 if absf(x) <= dz else signf(x) * (absf(x) - dz) / (1.0 - dz)


func _publish() -> void:
	Props.set_v("fcs/law", FbwReversion.NAMES[law])
	Props.set_v("fcs/law_id", law)
	Props.set_v("fcs/law_reason", reason)
	Props.set_v("fcs/ground_mode", wg > 0.5)
	Props.set_v("fcs/flare", pitch.flare)
