class_name Damage
extends RefCounted
## Damage & crash model, evaluated every FDM step. Thresholds come from the aircraft's aircraft.json
## ("limits": speeds and load factors, "damage": touchdown and gear thresholds, propeller hubs);
## the values in DEFAULTS are those of the C172S (POH / FAR 23):
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
const REARM_S := 0.5  # a contact must be off the ground this long before it counts as a new touch
                      # (debounces touchdown / tail-strike events while a skid or wheel chatters)
const DEFAULTS := {
	"hard_landing_ms": 3.0,  # m/s (~590 fpm) at the wheel
	"collapse_ms": 4.6,  # m/s (~900 fpm)
	"nose_collapse_ms": 2.6,  # m/s, nose or tail wheel
	"collapse_drop_m": 0.35,  # m the airframe sinks onto a failed leg
	"side_damage_ms": 3.0,  # m/s sideways drift of a main wheel at touchdown (~6 kt)
	"side_collapse_ms": 5.0,  # m/s (~10 kt): gear folds / ground loop
	"main_load_w": 3.0,  # main gear force limit, multiples of aircraft weight (backstop)
	"nose_load_w": 1.6,  # nose / tail wheel force limit (weaker)
}
const LIMIT_DEFAULTS := {
	"vne_kias": 163.0,
	"vd_kias": 185.0,  # design dive speed: beyond this the structure fails
	"vfe_kias": [[10.5, 110.0], [1000.0, 85.0]],  # [max flap deg, KIAS]: flap speed for the current setting
	"g_pos": 3.8,
	"g_neg": -1.52,
}

var p: Dictionary  # thresholds (DEFAULTS merged with aircraft.json "damage")
var lim: Dictionary  # limits (LIMIT_DEFAULTS merged with aircraft.json "limits")
var crashed := false
var crash_reason := ""
var events: Array[String] = []  # human-readable log, newest last
var gear_failed := {}  # contact name -> true
var prop_destroyed := false  # any propeller struck the ground
var struck := {}  # engine index -> true: that engine's propeller hit the ground (FdmNode keeps it failed)
var flaps_jammed := false
var structure_damaged := false
var hard_landings := 0
var last_touchdown := {}  # stats of the latest touchdown (for the debrief)
var _was_touching := {}
var _clear_t := {}  # contact name -> seconds off the ground (absent = never touched)
var _overspeed_t := 0.0
var _flap_t := 0.0
var _air_time := 0.0


func _init(def: AircraftDef = null) -> void:
	if def == null:
		def = AircraftDef.current()
	p = DEFAULTS.duplicate()
	p.merge(def.section("damage"), true)
	lim = LIMIT_DEFAULTS.duplicate(true)
	lim.merge(def.section("limits"), true)


func reset() -> void:
	crashed = false
	crash_reason = ""
	events.clear()
	gear_failed.clear()
	prop_destroyed = false
	struck.clear()
	flaps_jammed = false
	structure_damaged = false
	hard_landings = 0
	last_touchdown = {}
	_was_touching.clear()
	_clear_t.clear()


var _last_hard_t := -INF  # sim time of the last hard-landing / side-load event
var _last_side_t := -INF

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
		var first: bool = touching and not _was_touching.get(c.name, false) and _clear_t.get(c.name, INF) >= REARM_S
		_was_touching[c.name] = touching
		if not touching:
			_clear_t[c.name] = _clear_t.get(c.name, INF) + dt
			continue
		_clear_t[c.name] = 0.0
		if surface.call(info.get("n", 0.0), info.get("e", 0.0)) == 255:
			_crash("ditched in water")
			return
		if c.wheel and not gear_failed.has(c.name):
			var is_nose: bool = c.role != "main"  # nose or tail wheel: the weaker leg
			var limit_v: float = p.nose_collapse_ms if is_nose else p.collapse_ms
			var limit_f: float = weight * (p.nose_load_w if is_nose else p.main_load_w)
			var drift: float = absf(info.get("vlat", 0.0))
			if first and not is_nose and drift > p.side_collapse_ms:
				_fail_gear(c, "%s gear folded: touched down drifting sideways at %.0f kt (side load)" % [c.name.to_lower().replace("_", " "), drift / KT])
				continue
			if first and not is_nose and drift > p.side_damage_ms and f.time - _last_side_t > 1.0:
				_last_side_t = f.time
				structure_damaged = true
				_event("Side-load landing: drifting %.0f kt at touchdown — gear damaged (use a crab/wing-low correction)" % (drift / KT))
			if first:
				_touchdown(f, c.name, c.role, vz)
				if vz > limit_v:
					_fail_gear(c, "%s gear collapsed (%.0f fpm at touchdown)" % [c.name.to_lower().replace("_", " "), vz * 196.85])
				elif vz > p.hard_landing_ms and not is_nose and f.time - _last_hard_t > 1.0:  # one per touchdown, not per wheel
					_last_hard_t = f.time
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
			if c.role == "wingtip" and gs > 10.0 * KT:
				_crash("wingtip strike at %.0f kt — ground loop" % (gs / KT))
				return
			if c.role == "tail_skid" and first:
				_event("Tail strike — check the tail skid")
				structure_damaged = true
	if not any_touch:
		_air_time += dt
	# propeller strike: lowest blade tip of each propeller vs ground
	for i in f.units.size():
		var u: PowerUnit = f.units[i]
		if u.thruster.diameter <= 0.0 or u.thruster.rpm <= 80.0 or struck.has(i):
			continue
		var r_bn := Basis(f.q)
		var hub := r_bn * f.mb.body_of(u.hub)
		var down_b := r_bn.transposed() * Vector3(0, 0, 1)
		var tip_dir := (down_b - Vector3(1, 0, 0) * down_b.x).normalized()  # prop disc plane
		var tip := hub + r_bn * (tip_dir * u.thruster.diameter * 0.5)
		var tn := f.pos_n + tip.x
		var te := f.pos_e + tip.y
		var td := f.pos_d + tip.z
		if td > -f.ground_height.call(tn, te):
			prop_destroyed = true
			struck[i] = true
			u.engine.failed = true
			u.thruster.rpm = 0.0
			_event("PROP STRIKE — engine destroyed")
			if Vector2(f.velocity_ned().x, f.velocity_ned().y).length() > 25.0 * KT:
				_crash("prop strike at speed — nose-over")
				return
	_check_air_limits(f, dt)


func _touchdown(f: FDM, name: String, role: String, vz: float) -> void:
	if role == "nose" and not last_touchdown.is_empty() and last_touchdown.get("fresh", false):
		return
	var e := f.euler()
	last_touchdown = {"sink_fpm": vz * 196.85, "kias": f.cas / KT, "pitch_deg": rad_to_deg(e.y),
		"bank_deg": rad_to_deg(e.x), "g": f.load_factor, "first_wheel": name, "fresh": true,
		"n": f.pos_n, "e": f.pos_e, "track": atan2(f.velocity_ned().y, f.velocity_ned().x),
		"heading": e.z, "air_time": _air_time}
	var flew := _air_time > 2.0  # ignore settling at spawn
	_air_time = 0.0
	if role == "nose" and flew:
		_event("Landed nose wheel first — risk of nose gear collapse / porpoising")


func _fail_gear(c: Dictionary, msg: String) -> void:
	gear_failed[c.name] = true
	c.wheel = false  # now scrapes like structure
	c.mu_d = 0.6
	c.pos.z += p.collapse_drop_m
	structure_damaged = true
	_event(msg)


func _check_air_limits(f: FDM, dt: float) -> void:
	var ias := f.cas
	var vne: float = lim.vne_kias * KT
	if ias > float(lim.vd_kias) * KT:
		_crash("in-flight structural failure at %.0f KIAS (VNE %d)" % [ias / KT, int(vne / KT)])
		return
	_overspeed_t = _overspeed_t + dt if ias > vne else 0.0
	if _overspeed_t > 2.0 and not structure_damaged:
		structure_damaged = true
		_event("Exceeded VNE (%.0f kt) — airframe damaged" % (ias / KT))
	var vfe := _vfe(f.fcs.flap_deg) * KT
	_flap_t = _flap_t + dt if f.fcs.flap_deg > 1.0 and ias > vfe else 0.0
	if _flap_t > 2.0 and not flaps_jammed:
		flaps_jammed = true
		_event("Flaps over-sped above VFE (%d kt) — flaps damaged and jammed" % int(vfe / KT))
	var n := f.flight_load_factor  # gear loads are judged by the gear rules
	var n_pos: float = lim.g_pos
	var n_neg: float = lim.g_neg
	if n > n_pos * 1.5 or n < n_neg * 1.5:
		_crash("structural failure: %.1f g (ultimate load exceeded)" % n)
	elif (n > n_pos or n < n_neg) and not structure_damaged:
		structure_damaged = true
		_event("Overstress: %.1f g (limits %+.1f / %+.2f g) — airframe damaged" % [n, n_pos, n_neg])


## Flap limit speed (KIAS) for the current flap angle: the first row of limits.vfe_kias whose flap
## angle is not exceeded.
func _vfe(flap_deg: float) -> float:
	for row in lim.vfe_kias:
		if flap_deg <= float(row[0]):
			return float(row[1])
	return float(lim.vfe_kias[-1][1])
