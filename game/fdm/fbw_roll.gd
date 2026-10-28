class_name FbwRoll
extends RefCounted
## Roll law (flight mode): the sidestick commands a roll RATE (full stick = `rate_dps`), released it holds the
## bank angle (wings level below `level_deg`; above `hold_deg` it rolls back to `hold_deg`). The bank limit is
## `limit_deg` (`limit_prot_deg` while the high angle of attack or high speed protection acts): the rate demand
## tapers to zero toward it. Autopilot: the demand is Props ap/cmd/roll_rate_dps and nothing else (no bank hold).
## Aileron-l command in degrees (+ = roll right); the right aileron is its mirror. Roll spoilers follow the
## aileron demand: panels 2-5 of the wing that goes down, on top of the speedbrake / ground spoilers.

var phi_ref := 0.0
var hold := false
var i_deg := 0.0
var p_demand := 0.0
var taper := 1.0


func reset() -> void:
	hold = false
	i_deg = 0.0
	p_demand = 0.0


## Roll rate demand (rad/s). `stick` -1..1 (+ right) or, with `ap`, `ap_rate` rad/s.
func demand(s: FbwSense, par: FbwParams, stick: float, ap: bool, ap_rate: float, bank_lim_deg: float) -> float:
	var rp: Dictionary = par.d.roll
	var rate := deg_to_rad(float(rp.rate_dps))
	var lim := deg_to_rad(bank_lim_deg)
	var c := 0.0
	if ap:
		c = ap_rate
		hold = false
	elif absf(stick) > 0.0:
		c = stick * rate
		hold = false
	else:
		if not hold and absf(s.p) < deg_to_rad(1.5):  # rolled out: remember this bank
			var lvl := deg_to_rad(float(rp.level_deg))
			phi_ref = 0.0 if absf(s.phi) < lvl else clampf(s.phi, -deg_to_rad(float(rp.hold_deg)), deg_to_rad(float(rp.hold_deg)))
			hold = true
		if hold:
			c = clampf(float(rp.k_bank) * (phi_ref - s.phi), -rate, rate)
	var tp := deg_to_rad(float(rp.taper_deg))
	taper = 1.0
	if c * s.phi > 0.0:  # rolling further into the bank
		taper = clampf((lim - absf(s.phi)) / tp, 0.0, 1.0)
		c *= taper
	elif absf(s.phi) > lim:
		c = -signf(s.phi) * minf(rate, float(rp.k_bank) * (absf(s.phi) - lim))
	p_demand = c
	return c


## Aileron-l command (deg).
func aileron(s: FbwSense, par: FbwParams) -> float:
	var rp: Dictionary = par.d.roll
	var err := p_demand - s.p
	var raw := s.sched * (float(rp.kp) * err + float(rp.kff) * p_demand) + i_deg
	if absf(raw) < 24.0:
		i_deg += s.sched * float(rp.ki) * err * s.dt
	return s.sched * (float(rp.kp) * err + float(rp.kff) * p_demand) + i_deg


## Roll spoilers on top of the commands `_direct()` computed (speedbrake / ground spoilers).
func spoilers(c: AirlinerControls, ail_deg: float, par: FbwParams) -> void:
	var rp: Dictionary = par.d.roll
	var n: int = c._n_panels
	var full: float = c._sp.get("max_deg", 50.0)
	if c.spoiler_cmd[1] >= full - 0.1 and c.spoiler_cmd[n + 1] >= full - 0.1:
		return  # ground spoilers out
	var frac := clampf((absf(ail_deg) / maxf(c._max("aileron-l"), 1.0) - float(rp.spoiler_start)) / (1.0 - float(rp.spoiler_start)), 0.0, 1.0)
	var sp := frac * float(rp.spoiler_max_deg)
	var down := 0 if ail_deg < 0.0 else n  # roll right: the right wing's panels rise (indices n..2n-1)
	var up := n if ail_deg < 0.0 else 0
	for i in range(1, n):
		c.spoiler_cmd[down + i] = maxf(c.spoiler_cmd[down + i], sp)
		c.spoiler_cmd[up + i] = maxf(c.spoiler_cmd[up + i] - sp, 0.0)
