class_name Thruster
extends RefCounted
## What turns engine output into force on the airframe: a Propeller (torque in, thrust out) or the
## jet of a TurbineThruster. rpm is the speed shown on the tachometer (propeller rpm, jet N1).

var rpm := 0.0
var thrust := 0.0  # N along +x body
var torque := 0.0  # N*m the thruster absorbs from the engine shaft
var v_induced := 0.0  # m/s induced through the disc (aero model input)
var advance_ratio := 0.0
var sense := 0.0  # +1 / -1 rotation sense about +x body, 0 = no rotating mass worth modelling
var diameter := 0.0  # m: the propeller disc for the strike check (0 = none)


func update(_dt: float, _engine_torque: float, _v_axial: float, _rho: float, _sound_speed: float) -> void:
	pass


## Angular momentum along body +x (for gyroscopic moments).
func angular_momentum() -> float:
	return 0.0


## Lateral thrust-line offset (m) from P-factor: (y offset, z offset).
func p_factor_offset(_u: float, _v: float, _w: float) -> Vector2:
	return Vector2.ZERO
