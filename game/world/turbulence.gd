class_name Turbulence
extends RefCounted
## Continuous turbulence after MIL-F-8785C (the Dryden form JSBSim's FGWinds "Milspec" model uses), one first-order
## filter per axis on white noise, sampled exactly (x' = a x + sigma sqrt(1 - a^2) n, a = exp(-dt / tau)), so the
## statistics do not depend on the tick rate.
## Axes: u along the mean wind (horizontal), v across it, w vertical. Heights in feet inside scales() (as the
## standard), clamped at 10 ft:
##   below 1000 ft  L_w = h, L_u = L_v = h / (0.177 + 0.000823 h)^1.2, sigma_u = sigma_v = sigma_w / (0.177 + 0.000823 h)^0.4
##   1000-2000 ft   L_u = L_v = L_w from 1000 ft to 1750 ft linearly, sigma equal
##   above 2000 ft  L = 1750 ft on every axis
## (At 1000 ft the low-altitude formulas give exactly L = 1000 ft and equal sigmas, so the bands join without a step.)
## tau = L / V with V the airspeed through the mean air mass (without the turbulence itself, as JSBSim).
## Level (the Turbulence setting, 0..1; sigma_w()): 1/3 light, 2/3 moderate, 1 severe. Below 1000 ft sigma_w = 0.1 W20
## with W20 = 45 kt x level (the standard's 15 / 30 / 45 kt); above 2000 ft the probability-of-exceedance curves of
## MIL-F-8785C Fig. 7 (light 1e-2, moderate 1e-3, severe 1e-5; about 2.1 / 2.9 / 5.4 m/s at 1750 ft); linear between.
## Rotary gusts (JSBSim Milspec eqs 33-35, span b): p_g first-order with sigma_p = 1.9 sigma_w / sqrt(L_w b),
## L_p = sqrt(L_w b) / 2.6; q_g = -(dw_g/dt) / V low-passed with tau 4b / (pi V), r_g = (dv_g/dt) / V with 3b / (pi V)
## (v_g, w_g in body axes, w down). The FDM's aerodynamics see body rate - gust rate. Signs from the kinematics: an
## updraft reached first by the nose (dw_g/dt < 0) lifts the wing before the tail, a nose-up q_g.

const FT := 0.3048
const H_MIN_FT := 10.0
const CALM := 0.5  # m/s: below this mean wind the axes keep their last direction
const W20_SEVERE := 45.0 * 0.514444  # m/s: the 20 ft wind of severe turbulence (light 15 kt, moderate 30 kt)
const POE_H := [500.0, 1750.0, 3750.0, 7500.0, 15000.0, 25000.0, 35000.0, 45000.0, 55000.0, 65000.0, 75000.0, 80000.0]
const POE := [  # sigma, ft/s, at POE_H: light (1e-2), moderate (1e-3), severe (1e-5); MIL-F-8785C Fig. 7 as in JSBSim
	[6.6, 6.9, 7.4, 6.7, 4.6, 2.7, 0.4, 0.0, 0.0, 0.0, 0.0, 0.0],
	[8.6, 9.6, 10.6, 10.1, 8.0, 6.6, 5.0, 4.2, 2.7, 0.0, 0.0, 0.0],
	[15.6, 17.6, 23.0, 23.6, 22.1, 20.0, 16.0, 15.1, 12.1, 7.9, 6.2, 5.1],
]

var u := 0.0  # m/s along the mean wind
var v := 0.0  # m/s across it (to the right of downwind)
var w := 0.0  # m/s, + down (NED)
var pqr := Vector3.ZERO  # rotary gusts, body rad/s (p_g, q_g, r_g)
var _dir := Vector2(1.0, 0.0)  # (north, east) unit vector the mean wind blows toward
var _wb_prev := Vector2(INF, 0.0)  # last body (v_g, w_g)
var rng := RandomNumberGenerator.new()  # Weather shares its own; tests seed it


## {lu, lv, lw (m), ratio = sigma_u / sigma_w} at agl metres above the ground.
static func scales(agl_m: float) -> Dictionary:
	var h := maxf(agl_m / FT, H_MIN_FT)
	var lu: float
	var lw: float
	var ratio := 1.0
	if h <= 1000.0:
		var k := 0.177 + 0.000823 * h
		lw = h
		lu = h / pow(k, 1.2)
		ratio = 1.0 / pow(k, 0.4)
	elif h <= 2000.0:
		lu = 1000.0 + (h - 1000.0) / 1000.0 * 750.0
		lw = lu
	else:
		lu = 1750.0
		lw = lu
	return {"lu": lu * FT, "lv": lu * FT, "lw": lw * FT, "ratio": ratio}


## Vertical sigma (m/s) for a turbulence level 0..1 at agl metres.
static func sigma_w(level: float, agl_m: float) -> float:
	level = clampf(level, 0.0, 1.0)
	var h := maxf(agl_m / FT, H_MIN_FT)
	var low := 0.1 * W20_SEVERE * level
	if h <= 1000.0:
		return low
	var high := _poe(level, h)
	return lerpf(low, high, (h - 1000.0) / 1000.0) if h <= 2000.0 else high


## The exceedance curves at h ft, the level's place between them (0 none, 1/3 light, 2/3 moderate, 1 severe), m/s.
static func _poe(level: float, h: float) -> float:
	var x := level * 3.0  # 0..3: none, light, moderate, severe
	var i := mini(int(x), 2)
	var lo := 0.0 if i == 0 else _row(i - 1, h)
	return lerpf(lo, _row(i, h), x - i) * FT


static func _row(r: int, h: float) -> float:
	var row: Array = POE[r]
	if h <= POE_H[0]:
		return row[0]
	for k in range(1, POE_H.size()):
		if h <= POE_H[k]:
			return lerpf(row[k - 1], row[k], (h - POE_H[k - 1]) / (POE_H[k] - POE_H[k - 1]))
	return row[-1]


## Name of a level for the menus.
static func level_name(level: float) -> String:
	if level < 0.04:
		return "None"
	if level < 0.5:
		return "Light"
	return "Moderate" if level < 0.84 else "Severe"


## Advance by dt (s) at agl (m) with airspeed v_air (m/s, through the mean air mass), vertical sigma sig_w (m/s),
## the mean wind (NED m/s, sets the u / v axes), the aircraft heading (rad) and wing span (m; 0 = no rotary gusts).
## Returns the turbulence velocity, NED; the rotary gusts are in pqr.
func step(dt: float, agl: float, v_air: float, sig_w: float, mean_wind: Vector3, heading := 0.0, span := 0.0) -> Vector3:
	var sc := scales(agl)
	var sig_h: float = sig_w * float(sc.ratio)
	var vv := maxf(v_air, 5.0)
	u = _ou(u, dt, float(sc.lu) / vv, sig_h, rng.randfn())
	v = _ou(v, dt, float(sc.lv) / vv, sig_h, rng.randfn())
	w = _ou(w, dt, float(sc.lw) / vv, sig_w, rng.randfn())
	var hw := Vector2(mean_wind.x, mean_wind.y)
	if hw.length() > CALM:
		_dir = hw.normalized()
	var across := Vector2(-_dir.y, _dir.x)  # 90 deg right of downwind (NED: north, east)
	var g := Vector3(_dir.x * u + across.x * v, _dir.y * u + across.y * v, w)
	_rotary(dt, g, float(sc.lw), sig_w, vv, heading, span)
	return g


func _rotary(dt: float, g: Vector3, lw: float, sig_w: float, vv: float, heading: float, span: float) -> void:
	var wb := Vector2(-sin(heading) * g.x + cos(heading) * g.y, g.z)  # body-lateral and vertical gust
	if span <= 0.0:
		pqr = Vector3.ZERO
		_wb_prev = wb
		return
	var first := _wb_prev.x == INF
	var d := Vector2.ZERO if first else (wb - _wb_prev) / dt
	_wb_prev = wb
	var lb := sqrt(lw * span)
	var p := _ou(pqr.x, dt, lb / 2.6 / vv, 1.9 / lb * sig_w, rng.randfn())
	var aq := exp(-dt * PI * vv / (4.0 * span))
	var ar := exp(-dt * PI * vv / (3.0 * span))
	pqr = Vector3(p, aq * pqr.y + (1.0 - aq) * (-d.y / vv), ar * pqr.z + (1.0 - ar) * (d.x / vv))


static func _ou(x: float, dt: float, tau: float, sigma: float, n: float) -> float:
	var a := exp(-dt / maxf(tau, 1e-3))
	return a * x + sigma * sqrt(1.0 - a * a) * n
