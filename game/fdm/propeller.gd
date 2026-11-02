class_name Propeller
extends Thruster
## Fixed-pitch propeller from JSBSim tables C_THRUST(J), C_POWER(J) with tip-Mach
## corrections. Owns the engine/prop RPM state: I * dω/dt = Q_engine - Q_prop.

const ENGINE_INERTIA := 0.6  # kg*m^2 crankshaft + accessories

var inertia: float
var p_factor: float  # JSBSim p_factor (inches of thrust-line offset per radian)
var _ct: Dictionary
var _cp: Dictionary
var _ct_mach: Dictionary
var _cp_mach: Dictionary
var _cp_factor := 1.0
var _ct_factor: Dictionary = {"rows": [0.0], "cols": null, "data": [[1.0]]}


func _init(cfg: Dictionary, engine_cfg: Dictionary) -> void:
	diameter = cfg.diameter_m
	inertia = cfg.ixx_kgm2 + ENGINE_INERTIA
	sense = engine_cfg.sense
	p_factor = engine_cfg.p_factor
	_ct = cfg.C_THRUST
	_cp = cfg.C_POWER
	_ct_mach = cfg.CT_MACH
	_cp_mach = cfg.CP_MACH
	_cp_factor = cfg.get("cp_factor", 1.0)
	_ct_factor = cfg.get("ct_factor_vs_j", _ct_factor)


## v_axial: airspeed along the prop axis (m/s). Integrates RPM with engine torque.
func update(dt: float, engine_torque: float, v_axial: float, rho: float, sound_speed: float) -> void:
	var n := rpm / 60.0
	var d := diameter
	if n > 0.05:
		advance_ratio = maxf(v_axial, 0.0) / (n * d)
		var tip_mach := sqrt(pow(PI * d * n, 2.0) + v_axial * v_axial) / sound_speed
		var ct := Table.eval2(_ct, advance_ratio) * Table.eval2(_ct_mach, tip_mach) * Table.eval2(_ct_factor, advance_ratio)
		var cp := Table.eval2(_cp, advance_ratio) * Table.eval2(_cp_mach, tip_mach) * _cp_factor
		thrust = ct * rho * n * n * pow(d, 4.0)
		var power := cp * rho * n * n * n * pow(d, 5.0)
		torque = power / (TAU * n)
	else:
		advance_ratio = 0.0
		thrust = 0.0
		torque = 0.0
	# Windmilling drag when the engine is dead is captured by negative CT at high J.
	var area := PI * d * d / 4.0
	var vv := maxf(v_axial, 0.0)
	v_induced = 0.5 * (-vv + sqrt(maxf(vv * vv + 2.0 * maxf(thrust, 0.0) / (rho * area), 0.0)))
	var omega := rpm * TAU / 60.0
	omega = maxf(omega + (engine_torque - torque) / inertia * dt, 0.0)
	rpm = omega * 60.0 / TAU


## Angular momentum along body +x (for gyroscopic moments).
func angular_momentum() -> float:
	return sense * inertia * rpm * TAU / 60.0


## Lateral thrust-line offset (m) from P-factor, JSBSim style.
func p_factor_offset(u: float, v: float, w: float) -> Vector2:
	var tv := sqrt(v * v + w * w)
	if p_factor < 1e-4 or tv < 1e-4:
		return Vector2.ZERO
	var f := sense * p_factor * atan2(tv, u) / tv * 0.0254
	return Vector2(f * w, f * v)  # (y offset, z offset)
