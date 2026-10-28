class_name TurbineThruster
extends Thruster
## The jet of an EngineTurbine: thrust straight from the engine, no rotating mass modelled.
## rpm is N1 (percent of max when scaled by the engine's max_rpm).

var _engine: EngineTurbine


func _init(engine: EngineTurbine) -> void:
	_engine = engine


func update(_dt: float, _engine_torque: float, _v_axial: float, _rho: float, _sound_speed: float) -> void:
	rpm = _engine.n1 * _engine.max_rpm
	thrust = _engine.thrust_n
