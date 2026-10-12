class_name EnginePiston
extends RefCounted
## Normally aspirated, fuel-injected piston engine (Lycoming IO-360, 180 hp).
## Power scales with air mass flow (MAP, RPM, manifold temperature) times a
## mixture-efficiency curve, minus friction. Calibrated so full throttle at
## 2700 RPM, sea level ISA, best-power mixture gives max_hp.
## Inputs: throttle, mixture (0..1), magnetos (0 off,1 L,2 R,3 both), starter, fuel_ok.

const HP := 745.7
const INHG := 3386.389
const STOICH := 0.0667
const R_AIR := 287.053
const VOL_EFF := 0.85
const FRICTION_FRAC := 0.10  # friction power at max RPM as a fraction of max power
const STARTER_TORQUE := 120.0  # N*m at the crankshaft
const STARTER_RPM := 220.0
## The engine fires (and keeps running) above this crank speed. The starter alone turns the
## engine at only ~75-130 RPM (it works against friction and pumping), so a threshold above that
## (it was 150) made a cold start impossible. Real engines fire at cranking speed (impulse-coupled
## magnetos, fuel injected), well below idle (550).
const FIRE_RPM := 60.0
const FIRE_DELAY_S := 1.0  # it turns over this long before it catches (a windmilling engine, above WINDMILL_RPM, restarts at once)
const WINDMILL_RPM := 300.0
const MAP_ZERO := 4.0 * 3386.389  # IMEP ~ k * (MAP - MAP_ZERO): low-MAP inefficiency

var max_power: float
var max_rpm: float
var idle_rpm: float
var displacement: float  # m^3
var _k_power: float  # W per (kg/s air) at best power
var spark_drop: float
var _fire_t := 0.0  # s the engine has been turning above FIRE_RPM with spark, fuel and mixture

# inputs
var throttle := 0.0
var mixture := 1.0
var magnetos := 3
var starter := false
var fuel_ok := true
var failed := false  # catastrophic engine failure
var partial := false  # partial power loss: rough running at ~55 % power
# outputs
var running := false
var map_pa := 101325.0
var fuel_flow_kgs := 0.0
var power_w := 0.0
var egt_k := 288.0
var cht_k := 288.0
var oil_temp_k := 288.0
var oil_press_pa := 0.0
var torque := 0.0  # N*m on the crankshaft


func _init(cfg: Dictionary) -> void:
	max_power = cfg.maxhp * HP
	max_rpm = cfg.max_rpm
	idle_rpm = cfg.idle_rpm
	displacement = cfg.displacement_in3 * 1.6387064e-5
	spark_drop = cfg.spark_fail_drop
	var mdot := _air_flow(29.0 * INHG, max_rpm, 288.15 + 10.0)
	var p_fric := FRICTION_FRAC * max_power
	_k_power = (max_power + p_fric) / (mdot * (1.0 - MAP_ZERO / (29.0 * INHG)))


func _air_flow(map: float, rpm: float, t_k: float) -> float:
	return VOL_EFF * displacement * (rpm / 120.0) * map / (R_AIR * t_k)


## Pumping loss (W): drawing air through a part-closed throttle.
func _pumping(map: float, p_amb: float, rpm: float) -> float:
	return maxf(p_amb - map, 0.0) * displacement * rpm / 120.0


## Power factor vs equivalence ratio (1.0 at best power, phi ~ 1.15-1.2).
static func _mixture_factor(phi: float) -> float:
	if phi < 0.55 or phi > 2.0:
		return 0.0
	return clampf(1.0 - 1.2 * pow(phi - 1.18, 2.0) - (0.5 * (0.8 - phi) if phi < 0.8 else 0.0), 0.0, 1.0)


func update(dt: float, rpm: float, p_amb: float, t_amb: float, airspeed: float) -> void:
	# Manifold pressure: throttle plate vs. engine suction (more RPM -> more vacuum at part throttle)
	var open := pow(clampf(throttle, 0.0, 1.0), 0.75)
	var suction := clampf(rpm / max_rpm, 0.0, 1.2)
	var closed_frac := clampf(0.36 - 0.2 * suction, 0.2, 1.0)
	var target_map := p_amb * lerpf(closed_frac, 0.975, open)
	if rpm < 50.0:
		target_map = p_amb
	map_pa = lerpf(map_pa, target_map, clampf(dt * 10.0, 0.0, 1.0))

	var t_man := t_amb + 10.0
	var mdot_air := _air_flow(map_pa, rpm, t_man)
	# Mixture lever meters fuel for sea-level density; altitude makes full rich richer.
	var far := mixture * 0.0834 * sqrt(101325.0 / p_amb)  # full rich = phi 1.25 at sea level
	var phi := far / STOICH
	var spark := 0.0
	match magnetos:
		1, 2: spark = 1.0 - spark_drop * 0.9  # single mag: slower burn, ~4 % RPM drop
		3: spark = 1.0
	var mf := _mixture_factor(phi)
	var can_fire := spark > 0.0 and fuel_ok and not failed and mf > 0.0 and rpm > FIRE_RPM
	_fire_t = _fire_t + dt if can_fire else 0.0
	running = can_fire and (rpm > WINDMILL_RPM or _fire_t >= FIRE_DELAY_S)
	var p_ind := _k_power * mdot_air * mf * spark * maxf(1.0 - MAP_ZERO / map_pa, 0.0) if running else 0.0
	if partial:
		p_ind *= lerpf(0.9, 0.55, throttle) * (1.0 + randf_range(-0.12, 0.12))  # misfiring: power drops (most at high power) and shakes
	fuel_flow_kgs = mdot_air * far if running else 0.0
	var omega := maxf(rpm, 1.0) * TAU / 60.0
	var p_fric := FRICTION_FRAC * max_power * rpm / max_rpm  # ~constant friction torque
	power_w = p_ind - p_fric - _pumping(map_pa, p_amb, rpm)
	torque = power_w / omega
	if rpm < 5.0:
		torque = 0.0  # no stiction model; starter breaks away instantly
	if starter:
		torque += STARTER_TORQUE * clampf(1.0 - rpm / STARTER_RPM, 0.0, 1.0)
	_update_temps(dt, p_ind, phi, rpm, t_amb, airspeed)


func _update_temps(dt: float, p_ind: float, phi: float, rpm: float, t_amb: float, v: float) -> void:
	var egt_target := t_amb
	if running:
		var peak := 1060.0 - 140.0 * absf(phi - 1.0) - (40.0 if phi < 1.0 else 0.0) * (1.0 - phi) * 4.0
		egt_target = lerpf(600.0, peak, clampf(p_ind / max_power + 0.3, 0.0, 1.0))
	egt_k = lerpf(egt_k, egt_target, clampf(dt * 0.8, 0.0, 1.0))
	var heat := p_ind / max_power
	var cooling := 0.4 + clampf(v / 50.0, 0.0, 1.5)
	var cht_target := t_amb + 260.0 * heat / cooling * (1.1 if phi < 1.1 else 1.0)
	cht_k = lerpf(cht_k, cht_target, clampf(dt * 0.02, 0.0, 1.0))
	var oil_target := t_amb + 100.0 * clampf(heat + 0.25 * float(running), 0.0, 1.0) / sqrt(cooling)
	oil_temp_k = lerpf(oil_temp_k, oil_target, clampf(dt * 0.008, 0.0, 1.0))
	var press_target := clampf(rpm / 1200.0, 0.0, 1.0) * 4.8e5 * clampf(1.15 - (oil_temp_k - 350.0) / 400.0, 0.8, 1.35)  # ~70-80 psi warm
	oil_press_pa = lerpf(oil_press_pa, press_target, clampf(dt * 3.0, 0.0, 1.0))
