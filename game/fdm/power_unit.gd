class_name PowerUnit
extends RefCounted
## One engine with what turns its output into thrust, and where it sits on the airframe.
## Built from config.json: "engines": [{type: piston | turbine, pos_m, ..., propeller: {...}}], or the
## older single-engine form {engine: {...}, propeller: {...}} (a piston engine and its propeller).
## FDM.units holds them in order; FDM.engine / FDM.prop are unit 0 (engine 1).

var engine: Powerplant
var thruster: Thruster
var pos := Vector3.ZERO  # thrust point, structural metres (x aft, y right, z up)
var hub := Vector3.ZERO  # propeller hub (strike check), structural metres
var cruise_rpm := 0.0  # thruster rpm of a trimmed airborne start
var start_rpm := 0.0  # thruster rpm of a running engine at a ground start


## Every unit of a config. hubs: aircraft.json damage.prop_hubs_m (one per engine, optional).
static func from_config(cfg: Dictionary, hubs: Array = []) -> Array[PowerUnit]:
	var out: Array[PowerUnit] = []
	var list: Array = cfg.engines if cfg.has("engines") else [cfg.engine.merged({"propeller": cfg.propeller})]
	for i in list.size():
		var ec: Dictionary = list[i]
		var u := PowerUnit.new()
		match str(ec.get("type", "piston")):
			"turbine":
				var t := EngineTurbine.new(ec)
				u.engine = t
				u.thruster = TurbineThruster.new(t)
			_:
				u.engine = EnginePiston.new(ec)
				u.thruster = Propeller.new(ec.propeller, ec)
		u.cruise_rpm = ec.get("cruise_rpm", 0.85 * u.engine.max_rpm)
		u.start_rpm = ec.get("start_rpm", 1.45 * u.engine.idle_rpm)
		var a: Array = ec.pos_m
		u.pos = Vector3(a[0], a[1], a[2])
		var h: Array = hubs[i] if i < hubs.size() else a
		u.hub = Vector3(h[0], h[1], h[2])
		out.append(u)
	return out


## Engine then thruster, as the FDM steps them. v_axial: airspeed along the thrust axis,
## airspeed: true airspeed (both m/s).
func update(dt: float, atmo: AtmosphereISA, v_axial: float, airspeed: float) -> void:
	engine.update(dt, thruster.rpm, atmo.pressure, atmo.temperature, airspeed)
	thruster.update(dt, engine.torque, v_axial, atmo.density, atmo.sound_speed)


## Running state for a start: airborne (cruise speed) or on the ground (idle speed).
func warm_start(airborne: bool) -> void:
	var rpm := cruise_rpm if airborne else start_rpm
	thruster.rpm = rpm
	engine.warm_start(rpm / engine.max_rpm)
