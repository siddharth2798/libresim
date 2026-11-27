class_name Damage
extends RefCounted
## Damage & crash model, evaluated every FDM step. Thresholds come from aircraft.json ("limits": speeds and load factors,
## "damage": touchdown and gear thresholds, propeller hubs); DEFAULTS are the C172S's (POH / FAR 23).
## - Landing gear: touchdown sink rate (per wheel) > HARD -> hard landing (damage), > COLLAPSE -> that gear collapses (a
##   scraping structure point lowered by COLLAPSE_DROP). Nose gear is weaker. Gear loads > N x static also collapse it.
## - Prop strike: lowest propeller tip below the ground while turning -> engine destroyed.
## - Structure contacts (tail, wingtips, nose skid, collapsed gear) with high vertical speed, or sliding at speed -> crash.
## - Water contact (land class 255) -> ditching (crash). Trees / terrain impact -> crash.
## - Overspeed (limits: vne_kias, vd_kias, vd_fail_k): over VNE / VMO for OVER_S -> "inspection due" note, no damage
##   (the structure is designed and flight-tested to VD, CS/FAR 23/25.335, .629); over VD for OVER_S -> airframe damaged;
##   over VD x vd_fail_k (flutter margin: 1.15 VD for part 25, 1.2 VD for part 23, .629) -> structural failure (crash).
## - Flaps (limits: vfe_kias, vfe_by, flap_damage_k): over VFE for OVER_S -> "inspection due" note, no damage; over
##   VFE x flap_damage_k for OVER_S -> flaps damaged and jammed. vfe_by "flap" keys vfe_kias by flap deg (C172: steps,
##   the first row whose angle is not exceeded); "slat_flap" by slat + flap deg, one row per lever detent, blended
##   between detents (A320: CONF 1 = slats 18 / flaps 0 has its own VFE, and a retracting surface's limit rises as it
##   moves, the same Vmax the PFD shows: instruments/airliner_air_data.gd).
##   Why 1.2: the flaps are designed for limit load at VF with a 2 g pull-up and a 25 ft/s gust (FAR 23.345, CS 25.345),
##   and must not yield below limit load (25.305): in steady 1 g flight they take ~1.2 VF before they deform; they fail
##   near the 1.5 ultimate factor (25.303), ~1.4 VF. VFE is the placard VF.
## - Load factor (aero + thrust) beyond +3.8 / -1.52 g -> overstress; beyond 1.5x -> failure. Ground loads are judged by
##   the gear rules.
## Publishes via the arrays below; FdmNode copies them into Props "damage/*".

const KT := 0.514444
const OVER_S := 2.0  # s over a speed limit before it counts (a gust or a slat / flap transition is not an exceedance)
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
	"vd_kias": 185.0,  # design dive speed: sustained flight beyond it damages the airframe
	"vd_fail_k": 1.2,  # structural failure at VD x this (flutter-free margin the structure is shown to, part 23 .629)
	"vfe_kias": [[10.5, 110.0], [1000.0, 85.0]],  # [max flap deg, KIAS]: flap speed for the current setting
	"vfe_by": "flap",  # "flap": vfe_kias rows keyed by flap deg; "slat_flap": by slat + flap deg
	"flap_damage_k": 1.2,  # flaps damaged at VFE x this (flap load ~ IAS^2: 1.44x the load at VFE; see the header)
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
var _overspeed_t := 0.0  # s over VD
var _flap_t := 0.0  # s over the flap damage speed
var _vne_t := 0.0  # s over VNE
var _vfe_t := 0.0  # s over VFE
var vne_noted := false  # an over-VNE inspection note was logged
var vfe_noted := false  # an over-VFE inspection note was logged
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
	vne_noted = false
	vfe_noted = false
	_overspeed_t = 0.0
	_flap_t = 0.0
	_vne_t = 0.0
	_vfe_t = 0.0
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
	_check_speed(f, dt)
	if crashed:
		return
	_check_flaps(f, dt)
	var n := f.flight_load_factor  # gear loads are judged by the gear rules
	var n_pos: float = lim.g_pos
	var n_neg: float = lim.g_neg
	if n > n_pos * 1.5 or n < n_neg * 1.5:
		_crash("structural failure: %.1f g (ultimate load exceeded)" % n)
	elif (n > n_pos or n < n_neg) and not structure_damaged:
		structure_damaged = true
		_event("Overstress: %.1f g (limits %+.1f / %+.2f g) — airframe damaged" % [n, n_pos, n_neg])


## VNE: a note; VD: damage; VD x vd_fail_k: failure.
func _check_speed(f: FDM, dt: float) -> void:
	var kias := f.cas / KT
	var vne := float(lim.vne_kias)
	var vd := float(lim.vd_kias)
	if kias > vd * float(lim.vd_fail_k):
		_crash("in-flight structural failure at %.0f KIAS (VD %d)" % [kias, int(vd)])
		return
	_overspeed_t = _overspeed_t + dt if kias > vd else 0.0
	if _overspeed_t > OVER_S and not structure_damaged:
		structure_damaged = true
		_event("Exceeded dive speed VD (%.0f kt, VD %d) — airframe damaged" % [kias, int(vd)])
	_vne_t = _vne_t + dt if kias > vne else 0.0
	if _vne_t > OVER_S and not vne_noted and not structure_damaged:
		vne_noted = true
		_event("Over the speed limit: %.0f kt (VNE / VMO %d) — airframe inspection due, no damage" % [kias, int(vne)])


## VFE: a note; VFE x flap_damage_k: flaps damaged and jammed.
func _check_flaps(f: FDM, dt: float) -> void:
	var ext := high_lift_deg(f)
	var kias := f.cas / KT
	var vfe := vfe_at(ext)
	var out := ext > 1.0
	var v_dmg := vfe * float(lim.flap_damage_k)
	_flap_t = _flap_t + dt if out and kias > v_dmg else 0.0
	if _flap_t > OVER_S and not flaps_jammed:
		flaps_jammed = true
		_event("Flaps over-sped far above VFE (%.0f kt, VFE %d) — flaps damaged and jammed" % [kias, int(vfe)])
	_vfe_t = _vfe_t + dt if out and kias > vfe else 0.0
	if _vfe_t > OVER_S and not vfe_noted and not flaps_jammed:
		vfe_noted = true
		_event("Flaps over-sped: %.0f kt (VFE %d) — inspection due, no damage" % [kias, int(vfe)])


## The angle vfe_kias is keyed by: flap deg, or slat + flap deg with limits.vfe_by "slat_flap".
func high_lift_deg(f: FDM) -> float:
	var ext: float = f.fcs.flap_deg
	if str(lim.vfe_by) == "slat_flap" and "slat_deg" in f.fcs:
		ext += float(f.fcs.get("slat_deg"))
	return ext


## Flap limit speed VFE (KIAS) at high-lift angle `ext` (see high_lift_deg; rules in instruments/flap_speeds.gd).
func vfe_at(ext: float) -> float:
	return FlapSpeeds.vfe(lim, ext)
