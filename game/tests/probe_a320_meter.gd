extends RefCounted
## Measurements of probe_a320_landing.gd: approach gates (1,000 / 500 / 50 ft), the flare, the first touchdown, the
## rollout (spoilers, reverse, nose wheel, autobrake, deceleration, distances), bounces, damage, runway excursion.
## sample(s) is called every tick with the state dictionary of probe_a320_state.gd; verdict() gives PASS / FAIL.

const GATES := [1000.0, 500.0, 50.0]
const KT := 0.514444

var gates := {}  # ra ft -> state copy
var start := {}  # state at the first tick and after the hands-off seconds
var start_end := {}
var flare := {}
var td := {}
var td_dmg := {}
var rev_t := -1.0
var spoil_t := -1.0
var spoil_full_t := -1.0
var ab_t := -1.0
var nose_t := -1.0
var rev_max := 0.0
var bounces := 0
var bounce_max_ft := 0.0
var peak_decel := 0.0
var peak_nz := 0.0
var stop := {}
var s60 := {}
var gs80 := {}
var gs20 := {}
var final_n1: Array = []  # n1 / lever / thrust samples between 900 and 150 ft
var final_lever: Array = []
var final_thrust: Array = []
var final_gamma: Array = []
var max_cross := 0.0
var max_bank_roll := 0.0
var _last_ra := 1e9
var _air_t := 0.0
var _bounce_ra := 0.0
var _was_wow := false
var _nz_until := 0.0
var _prev: Dictionary = {}


func sample(s: Dictionary) -> void:
	if start.is_empty():
		start = s.duplicate()
	if s.t >= 8.0 and start_end.is_empty():
		start_end = s.duplicate()
	if not s.wow and s.ra < 900.0 and s.ra > 150.0 and td.is_empty():
		final_n1.append(s.n1)
		final_lever.append(s.lever)
		final_thrust.append(s.thrust_kn)
		final_gamma.append(s.gamma)
	for g in GATES:
		if not gates.has(g) and s.ra <= g and _last_ra > g and td.is_empty():
			gates[g] = s.duplicate()
	_last_ra = s.ra
	if flare.is_empty() and s.ra < 30.0 and not s.wow and not gates.is_empty():
		flare = s.duplicate()
	if s.wow and not _was_wow:
		if td.is_empty():
			td = s.duplicate()
			td_dmg = Props.get_v("damage/last_touchdown", {}).duplicate()
			_nz_until = s.t + 1.0
		elif _air_t > 0.3:
			bounces += 1
	if not s.wow and not td.is_empty():
		_air_t += s.dt
		_bounce_ra = maxf(_bounce_ra, s.ra)
		bounce_max_ft = maxf(bounce_max_ft, _bounce_ra)
	elif s.wow:
		_air_t = 0.0
		_bounce_ra = 0.0
	_was_wow = s.wow
	if td.is_empty():
		return
	if s.t < _nz_until:
		peak_nz = maxf(peak_nz, s.nz)
	var d: float = s.t - td.t
	if nose_t < 0.0 and s.nose:
		nose_t = d
	if spoil_t < 0.0 and s.spoil > 10.0:
		spoil_t = d
	if spoil_full_t < 0.0 and s.spoil > 45.0:
		spoil_full_t = d
	if ab_t < 0.0 and s.ab_on:
		ab_t = d
	if rev_t < 0.0 and s.rev > 0.5:
		rev_t = d
	rev_max = maxf(rev_max, s.rev)
	max_cross = maxf(max_cross, absf(s.cross))
	max_bank_roll = maxf(max_bank_roll, absf(s.bank))
	if d > 3.0 and s.nose and s.wow:
		peak_decel = maxf(peak_decel, s.decel)
	if s60.is_empty() and s.gs < 60.0:
		s60 = s.duplicate()
	if gs80.is_empty() and s.gs < 80.0:
		gs80 = s.duplicate()
	if gs20.is_empty() and s.gs < 20.0:
		gs20 = s.duplicate()
	if stop.is_empty() and s.gs < 0.5 and d > 3.0:
		stop = s.duplicate()
	_prev = s


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var x := 0.0
	for v in a:
		x += float(v)
	return x / a.size()


func _g(key: float, k: String, def := 0.0) -> float:
	return float(gates[key].get(k, def)) if gates.has(key) else def


## Stats as a flat dictionary (units in the keys) for the result line and the table.
func stats(rwy_len: float, rwy_w: float) -> Dictionary:
	var r := {}
	for g in GATES:
		var k := "%d" % int(g)
		r["ias_" + k] = _g(g, "ias")
		r["gs_" + k] = _g(g, "gs")
		r["vs_" + k] = _g(g, "vs")
		r["fpa_" + k] = _g(g, "gamma")
		r["pitch_" + k] = _g(g, "pitch")
		r["alpha_" + k] = _g(g, "alpha")
		r["n1_" + k] = _g(g, "n1")
		r["thrust_" + k] = _g(g, "thrust_kn")
		r["aprot_" + k] = _g(g, "alpha_prot")
		r["amax_" + k] = _g(g, "alpha_max")
		r["vls_" + k] = _g(g, "vls")
	r["n1_final"] = _mean(final_n1)
	r["lever_final"] = _mean(final_lever)
	r["thrust_final_kn"] = _mean(final_thrust)
	r["fpa_final"] = _mean(final_gamma)
	r["flare_ra"] = flare.get("ra", 0.0)
	r["flare_t_s"] = (td.t - flare.t) if (not td.is_empty() and not flare.is_empty()) else 0.0
	r["flare_pitch0"] = flare.get("pitch", 0.0)
	r["td_ias"] = td.get("ias", 0.0)
	r["td_gs"] = td.get("gs", 0.0)
	r["td_pitch"] = td.get("pitch", 0.0)
	r["td_alpha"] = td.get("alpha", 0.0)
	r["td_bank"] = td.get("bank", 0.0)
	r["td_along"] = td.get("along", 0.0)
	r["td_cross"] = td.get("cross", 0.0)
	r["td_vs_fpm"] = td.get("vs", 0.0)
	r["td_sink_fpm"] = float(td_dmg.get("sink_fpm", 0.0))
	r["td_g"] = float(td_dmg.get("g", 0.0))
	r["peak_nz"] = peak_nz
	r["td_n1"] = td.get("n1", 0.0)
	r["td_mass"] = td.get("mass", 0.0)
	r["nose_s"] = nose_t
	r["spoil_s"] = spoil_t
	r["spoil_full_s"] = spoil_full_t
	r["autobrake_s"] = ab_t
	r["rev_s"] = rev_t
	r["bounces"] = bounces
	r["bounce_ft"] = bounce_max_ft
	r["peak_decel"] = peak_decel
	if not td.is_empty() and not stop.is_empty():
		var roll: float = stop.along - td.along
		r["roll_m"] = roll
		r["roll_s"] = stop.t - td.t
		r["mean_decel"] = td.gs * KT / maxf(stop.t - td.t, 1.0)
		r["ld_m"] = stop.along - (float(gates[50.0].along) if gates.has(50.0) else td.along)
		r["stop_along"] = stop.along
		r["stop_cross"] = stop.cross
	if not td.is_empty() and not s60.is_empty():
		r["roll60_m"] = s60.along - td.along
	if not gs80.is_empty() and not gs20.is_empty():
		r["decel_80_20"] = (gs80.gs - gs20.gs) * KT / maxf(gs20.t - gs80.t, 0.1)
	r["max_cross"] = max_cross
	r["rwy_len"] = rwy_len
	r["rwy_w"] = rwy_w
	return r


## "" when the landing is fine, else the first reason it is not.
func verdict(rwy_len: float, rwy_w: float, crashed: bool, damage_events: Array, structure: bool) -> String:
	if crashed:
		return "crashed"
	if td.is_empty():
		return "no_touchdown"
	if td.along < 150.0 or td.along > 1500.0:
		return "touchdown_zone(%.0f m)" % td.along
	if absf(td.cross) > rwy_w * 0.5:
		return "touchdown_off_runway"
	if stop.is_empty():
		return "did_not_stop"
	if stop.along > rwy_len - 20.0 or max_cross > rwy_w * 0.5:
		return "runway_excursion"
	if bounces > 1:
		return "bounces(%d)" % bounces
	if structure or not damage_events.is_empty():
		return "damage(%s)" % ", ".join(PackedStringArray(damage_events))
	if float(td_dmg.get("sink_fpm", 0.0)) > 600.0:
		return "hard_landing"
	return ""
