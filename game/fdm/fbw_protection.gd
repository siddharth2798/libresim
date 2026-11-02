class_name FbwProtection
extends RefCounted
## Normal-law protections as limits on the pitch law's demands, and the Props the displays and the
## auto-thrust read. Publishes (every tick):
##   fcs/alpha_prot_deg fcs/alpha_max_deg fcs/alpha_floor_deg fcs/alpha_stall_deg  limits for this configuration
##   fcs/alpha_floor (bool: auto-thrust goes to TOGA)   fcs/stall_warning (bool, every law)
##   fcs/prot/{alpha, speed, bank, pitch, nz} (bool: that protection is acting)
## High angle of attack: stick aft maps to an alpha demand between alpha_prot (stick neutral) and
## alpha_max (full aft); the pitch rate demand is capped by it, so the nz law runs below alpha_prot.

var a_prot := 0.15  # rad, lagged limits of the current configuration
var a_max := 0.2
var a_stall := 0.24
var a_floor := 0.17
var a_warn := 0.21
var speed_excess_kt := 0.0
var alpha_active := false
var speed_active := false
var pitch_active := false
var nz_active := false
var bank_active := false
var floor_latch := false
var _init_done := false


## Limits of the current slat / flap position: nearest configuration row, then a lag (no steps).
func update_limits(s: FbwSense, par: FbwParams) -> void:
	var al: Dictionary = par.d.alpha_deg
	var best: Array = al.rows[0]
	var bd := INF
	for r in al.rows:
		var dist := absf(float(r[0]) - s.slat_deg) / 27.0 + absf(float(r[1]) - s.flap_deg) / 35.0
		if dist < bd:
			bd = dist
			best = r
	var tgt := [deg_to_rad(best[2]), deg_to_rad(best[3]), deg_to_rad(best[4])]
	var k := 1.0 if not _init_done else 1.0 - exp(-s.dt / maxf(float(al.lag_s), 1e-3))
	_init_done = true
	a_prot = lerpf(a_prot, tgt[0], k)
	a_max = lerpf(a_max, tgt[1], k)
	a_stall = lerpf(a_stall, tgt[2], k)
	a_floor = a_prot + float(al.floor_frac) * (a_max - a_prot)
	a_warn = a_max + float(al.warn_frac) * (a_stall - a_max)
	var sp: Dictionary = par.d.speed_prot
	speed_excess_kt = maxf(s.cas_kt - (par.f("vmo_kt") + float(sp.above_vmo_kt)), (s.mach - (par.f("mmo") + float(sp.above_mmo))) * float(sp.mach_kt))


func nz_limits(s: FbwSense, par: FbwParams) -> Vector2:
	var flaps := s.slat_deg > 1.0 or s.flap_deg > 1.0
	return Vector2(par.f("nz_min_flaps" if flaps else "nz_min"), par.f("nz_max_flaps" if flaps else "nz_max"))


## Nose-up g bias of the high speed protection (0 below VMO + 6 / MMO + 0.01).
func speed_bias_g(par: FbwParams) -> float:
	var sp: Dictionary = par.d.speed_prot
	speed_active = speed_excess_kt > 0.0
	return clampf(speed_excess_kt * float(sp.bias_g_per_kt), 0.0, float(sp.bias_max_g)) if speed_active else 0.0


## Forward stick loses authority as the speed protection takes over (fraction of the stick that remains).
func forward_authority(par: FbwParams) -> float:
	return 1.0 - clampf(speed_excess_kt / float(par.d.speed_prot.fade_kt), 0.0, 1.0)


## Caps the pitch rate demand (rad/s): alpha protection, pitch attitude limits. `aft` is the stick aft fraction 0..1.
func cap_rate(s: FbwSense, par: FbwParams, q_c: float, aft: float) -> float:
	var pp: Dictionary = par.d.pitch
	var a_c := a_prot + aft * (a_max - a_prot)
	var a_pred := s.alpha + float(pp.alpha_lead_s) * s.alpha_dot
	var q_a := float(pp.k_alpha) * (a_c - a_pred)
	alpha_active = s.alpha > a_prot - deg_to_rad(0.3) or q_a < q_c
	var out := minf(q_c, q_a)
	var lim: Array = par.d.pitch_limit_deg
	var th_hi := deg_to_rad(float(lim[1]))
	var th_lo := deg_to_rad(float(lim[0]))
	var kt := float(pp.k_theta)
	var q_hi := kt * (th_hi - s.theta)
	var q_lo := kt * (th_lo - s.theta)
	pitch_active = out > q_hi or out < q_lo
	return clampf(out, q_lo, q_hi)


## Alpha floor (auto-thrust to TOGA) latches above alpha_floor, releases below alpha_prot - 1 deg.
func update_flags(s: FbwSense, normal: bool) -> void:
	if normal:
		if s.alpha > a_floor:
			floor_latch = true
		elif s.alpha < a_prot - deg_to_rad(1.0):
			floor_latch = false
	else:
		floor_latch = false
		alpha_active = false
		speed_active = false
		pitch_active = false
		nz_active = false
		bank_active = false
	Props.set_v("fcs/alpha_prot_deg", rad_to_deg(a_prot))
	Props.set_v("fcs/alpha_max_deg", rad_to_deg(a_max))
	Props.set_v("fcs/alpha_floor_deg", rad_to_deg(a_floor))
	Props.set_v("fcs/alpha_stall_deg", rad_to_deg(a_stall))
	Props.set_v("fcs/alpha_floor", floor_latch)
	Props.set_v("fcs/stall_warning", s.alpha > a_warn and not s.wow)
	Props.set_v("fcs/prot/alpha", alpha_active and normal)
	Props.set_v("fcs/prot/speed", speed_active)
	Props.set_v("fcs/prot/bank", bank_active)
	Props.set_v("fcs/prot/pitch", pitch_active)
	Props.set_v("fcs/prot/nz", nz_active)
