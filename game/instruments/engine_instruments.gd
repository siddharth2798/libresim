class_name EngineInstruments
extends Node
## Engine/fuel gauges with needle lag, in display units (steam panel; engine 1):
## tach (RPM), oil temp (F) & press (psi), EGT (F, relative scale), fuel flow (gph),
## fuel quantity L/R (gal), suction (inHg). Electric gauges read 0 without bus power.

var _v := {}
var _kg_gal := 0.0  # fuel density, kg per US gal (aircraft.json payload.fuel_kg_per_gal)


func _lag(key: String, target: float, rate: float, dt: float) -> float:
	var cur: float = _v.get(key, target)
	cur = lerpf(cur, target, clampf(rate * dt, 0.0, 1.0))
	_v[key] = cur
	Props.set_v("instruments/" + key, cur)
	return cur


func _physics_process(dt: float) -> void:
	if _kg_gal == 0.0:
		_kg_gal = float(AircraftDef.current().section("payload").get("fuel_kg_per_gal", 2.72))
	var elec := Props.get_b("systems/electrical/gauges_powered", true)
	_lag("tach_rpm", Props.get_f("engine/rpm"), 6.0, dt)  # mechanical cable drive
	_lag("oil_temp_f", (Units.k_to_c(Props.get_f("engine/oil_temp_k", 288.0)) * 1.8 + 32.0) if elec else 0.0, 1.0, dt)
	_lag("oil_press_psi", Props.get_f("engine/oil_press_pa") / 6894.76 if elec else 0.0, 3.0, dt)
	_lag("egt_f", (Units.k_to_c(Props.get_f("engine/egt_k", 288.0)) * 1.8 + 32.0) if elec else 0.0, 1.0, dt)
	_lag("fuel_flow_gph", Props.get_f("engine/fuel_flow_kgs") * 3600.0 / _kg_gal if elec else 0.0, 2.0, dt)
	var left: float = Props.get_v("fuel/left_kg", Props.get_f("fuel/total_kg") * 0.5)
	var right: float = Props.get_v("fuel/right_kg", Props.get_f("fuel/total_kg") * 0.5)
	_lag("fuel_left_gal", left / _kg_gal if elec else 0.0, 0.5, dt)
	_lag("fuel_right_gal", right / _kg_gal if elec else 0.0, 0.5, dt)
	_lag("suction_inhg", Props.get_f("systems/vacuum/suction_inhg"), 3.0, dt)
	_lag("ammeter_a", Props.get_f("systems/electrical/battery_amps"), 3.0, dt)
