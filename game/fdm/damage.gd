class_name Damage
extends RefCounted
## Damage & crash model, evaluated every FDM step. Thresholds (C172S POH / FAR 23):
## - Landing gear: touchdown sink rate (at each wheel) > HARD -> hard landing (damage),
##   > COLLAPSE -> that gear collapses (it becomes a scraping structure point lowered
##   by COLLAPSE_DROP). Nose gear is weaker. Gear loads > N x static also collapse it.
## - Prop strike: lowest propeller tip below the ground while turning -> engine destroyed.
## - Structure contacts (tail, wingtips, nose skid, collapsed gear) hitting with a high
##   vertical speed, or the airframe sliding at speed -> crash.
## - Water contact (land class 255) -> ditching (crash). Trees/terrain impact -> crash.
## - Overspeed: IAS > VNE (structural damage after 2 s), > VD (failure, crash).
##   Flaps above VFE -> flap damage (jammed) after 2 s.
## - Flight load factor (aero + thrust) beyond +3.8 / -1.52 g -> overstress; beyond 1.5x
##   (ultimate) -> failure. Ground-contact loads are judged by the gear rules instead.
## Publishes via the arrays below; FdmNode copies them into Props "damage/*".

const KT := 0.514444
const HARD := 3.0  # m/s (~590 fpm) at the wheel
const COLLAPSE := 4.6  # m/s (~900 fpm)
const NOSE_COLLAPSE := 2.6  # m/s
const COLLAPSE_DROP := 0.35  # m the airframe sinks onto a failed leg
const MAIN_LOAD_W := 3.0  # main gear force limit, multiples of aircraft weight (backstop)
const NOSE_LOAD_W := 1.6  # nose gear force limit (weaker)
const VNE := 163.0 * KT
const VD := 185.0 * KT  # design dive speed: beyond this the structure fails
const VFE_10 := 110.0 * KT
const VFE_FULL := 85.0 * KT
const N_POS := 3.8
const N_NEG := -1.52
const PROP_RADIUS := 0.95
## Propeller hub (JSBSim structural m): spinner centre of the c172p 3D model, which gives
## the real C172's ~11 in (0.28 m) static prop clearance. (JSBSim's thruster point is not the hub.)
const PROP_HUB := Vector3(-0.88, 0.0, 0.926)

var crashed := false
var crash_reason := ""
var events: Array[String] = []  # human-readable log, newest last
var gear_failed := {}  # contact name -> true
var prop_destroyed := false
var flaps_jammed := false
var structure_damaged := false
var hard_landings := 0
var last_touchdown := {}  # stats of the latest touchdown (for the debrief)
var _was_touching := {}
var _overspeed_t := 0.0
var _flap_t := 0.0
var _air_time := 0.0


func reset() -> void:
	crashed = false
	crash_reason = ""
	events.clear()
	gear_failed.clear()
	prop_destroyed = false
	flaps_jammed = false
	structure_damaged = false
	hard_landings = 0
	last_touchdown = {}
	_was_touching.clear()


func _event(msg: String) -> void:
	events.append(msg)


func _crash(reason: String) -> void:
	if crashed:
		return
	crashed = true
	crash_reason = reason
	_event("CRASH: " + reason)


## Called by FDM.step after forces are computed. contacts: per-contact info from GearGround.
func update(f: FDM, dt: float, contact_info: Dictionary, surface: Callable) -> void:
	if crashed:
		return
	var weight := f.mb.mass * FDM.G
	var any_touch := false
	for c in f.gear.contacts:
		var info: Dictionary = contact_info.get(c.name, {})
		var touching: bool = info.get("depth", 0.0) > 0.0
		if touching:
			any_touch = true
		var vz: float = info.get("vz", 0.0)  # contact point vertical speed, NED (+ = down)
		var force: float = info.get("force", 0.0)
		var first: bool = touching and not _was_touching.get(c.name, false)
		_was_touching[c.name] = touching
		if not touching:
			continue
		if surface.call(info.get("n", 0.0), info.get("e", 0.0)) == 255:
			_crash("ditched in water")
			return
		if c.wheel and not gear_failed.has(c.name):
			var is_nose: bool = c.name == "NOSE"
			var limit_v := NOSE_COLLAPSE if is_nose else COLLAPSE
			var limit_f := weight * (NOSE_LOAD_W if is_nose else MAIN_LOAD_W)
			if first:
				_touchdown(f, c.name, vz)
				if vz > limit_v:
					_fail_gear(c, "%s gear collapsed (%.0f fpm at touchdown)" % [c.name.to_lower().replace("_", " "), vz * 196.85])
				elif vz > HARD and not is_nose:
					hard_landings += 1
					structure_damaged = true
					_event("Hard landing: %.0f fpm — gear inspection required" % (vz * 196.85))
			elif force > limit_f:
				_fail_gear(c, "%s gear overloaded (%.1f x aircraft weight)" % [c.name.to_lower().replace("_", " "), force / weight])
		elif not c.wheel or gear_failed.has(c.name):
			# airframe touching the ground
			var gs := Vector2(f.velocity_ned().x, f.velocity_ned().y).length()
			if vz > 3.0:
				_crash("%s struck the ground at %.0f fpm" % [c.name.to_lower().replace("_", " "), vz * 196.85])
				return
			if c.name.ends_with("TIP") and gs > 10.0 * KT:
				_crash("wingtip strike at %.0f kt — ground loop" % (gs / KT))
				return
			if c.name == "TAIL_SKID" and first:
				_event("Tail strike — check the tail skid")
				structure_damaged = true
	if not any_touch:
		_air_time += dt
	# propeller strike: lowest blade tip vs ground
	if not prop_destroyed and f.prop.rpm > 80.0:
		var r_bn := Basis(f.q)
		var hub := r_bn * f.mb.body_of(PROP_HUB)
		var down_b := r_bn.transposed() * Vector3(0, 0, 1)
		var tip_dir := (down_b - Vector3(1, 0, 0) * down_b.x).normalized()  # prop disc plane
		var tip := hub + r_bn * (tip_dir * PROP_RADIUS)
		var tn := f.pos_n + tip.x
		var te := f.pos_e + tip.y
		var td := f.pos_d + tip.z
		if td > -f.ground_height.call(tn, te):
			prop_destroyed = true
			f.engine.failed = true
			f.prop.rpm = 0.0
			_event("PROP STRIKE — engine destroyed")
			if Vector2(f.velocity_ned().x, f.velocity_ned().y).length() > 25.0 * KT:
				_crash("prop strike at speed — nose-over")
				return
	_check_air_limits(f, dt)


func _touchdown(f: FDM, name: String, vz: float) -> void:
	if name == "NOSE" and not last_touchdown.is_empty() and last_touchdown.get("fresh", false):
		return
	var e := f.euler()
	last_touchdown = {"sink_fpm": vz * 196.85, "kias": f.cas / KT, "pitch_deg": rad_to_deg(e.y),
		"bank_deg": rad_to_deg(e.x), "g": f.load_factor, "first_wheel": name, "fresh": true,
		"n": f.pos_n, "e": f.pos_e, "track": atan2(f.velocity_ned().y, f.velocity_ned().x),
		"heading": e.z, "air_time": _air_time}
	var flew := _air_time > 2.0  # ignore settling at spawn
	_air_time = 0.0
	if name == "NOSE" and flew:
		_event("Landed nose wheel first — risk of nose gear collapse / porpoising")


func _fail_gear(c: Dictionary, msg: String) -> void:
	gear_failed[c.name] = true
	c.wheel = false  # now scrapes like structure
	c.mu_d = 0.6
	c.pos.z += COLLAPSE_DROP
	structure_damaged = true
	_event(msg)


func _check_air_limits(f: FDM, dt: float) -> void:
	var ias := f.cas
	if ias > VD:
		_crash("in-flight structural failure at %.0f KIAS (VNE %d)" % [ias / KT, int(VNE / KT)])
		return
	_overspeed_t = _overspeed_t + dt if ias > VNE else 0.0
	if _overspeed_t > 2.0 and not structure_damaged:
		structure_damaged = true
		_event("Exceeded VNE (%.0f kt) — airframe damaged" % (ias / KT))
	var vfe := VFE_10 if f.fcs.flap_deg <= 10.5 else VFE_FULL
	_flap_t = _flap_t + dt if f.fcs.flap_deg > 1.0 and ias > vfe else 0.0
	if _flap_t > 2.0 and not flaps_jammed:
		flaps_jammed = true
		_event("Flaps over-sped above VFE (%d kt) — flaps damaged and jammed" % int(vfe / KT))
	var n := f.flight_load_factor  # gear loads are judged by the gear rules
	if n > N_POS * 1.5 or n < N_NEG * 1.5:
		_crash("structural failure: %.1f g (ultimate load exceeded)" % n)
	elif (n > N_POS or n < N_NEG) and not structure_damaged:
		structure_damaged = true
		_event("Overstress: %.1f g (limits +3.8 / -1.52 g) — airframe damaged" % n)
