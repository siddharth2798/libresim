class_name GenericFixtures
extends RefCounted
## Aircraft built in code for tests/test_generic_aircraft.gd: variations of the c172's config.json
## (its aero.json is used as it is) as twin piston, taildragger and twin turbine.

const DT := 1.0 / 120.0


static func c172_config() -> Dictionary:
	return AircraftDef.load_def("c172").config().duplicate(true)


## An FDM for a config (a deep copy of the c172's, edited); aero.json is the c172's.
static func fdm(cfg: Dictionary, id := "test") -> FDM:
	return FDM.new(AircraftDef.make(id, {"name": id}, "res://aircraft/c172", cfg))


## Two piston engines at y = -1.6 / +1.6 (counter-rotating), tanks left / right / centre.
static func twin_config() -> Dictionary:
	var c := c172_config()
	var engines := []
	for side in [-1.0, 1.0]:
		var e: Dictionary = c.engine.duplicate(true)
		e.pos_m = [c.engine.pos_m[0], 1.6 * side, c.engine.pos_m[2]]
		e.sense = -side
		e.propeller = c.propeller.duplicate(true)
		engines.append(e)
	c.erase("engine")
	c.erase("propeller")
	c.engines = engines
	var t: Dictionary = c.tanks[0]
	var tanks := []
	for y in [-2.0, 2.0, 0.0]:
		var tk: Dictionary = t.duplicate(true)
		tk.pos_m = [t.pos_m[0], y, t.pos_m[2]]
		tk.capacity_kg = 60.0
		tk.contents_kg = 30.0
		tanks.append(tk)
	c.tanks = tanks
	return c


## The nose wheel replaced by a steerable tail wheel (the tail skid dropped), the mains moved ahead of
## the CG so the aircraft sits on its tail.
static func taildragger_config() -> Dictionary:
	var c := c172_config()
	var gear := []
	for g in c.gear:
		if g.name == "NOSE":
			g.name = "TAIL_WHEEL"
			g.pos_m = [4.6, 0.0, 0.2]
		elif g.name == "TAIL_SKID":
			continue
		elif g.name.ends_with("_MAIN"):
			g.pos_m[0] = 0.6
			g.pos_m[2] = -0.5
		gear.append(g)
	c.gear = gear
	return c


## Two turbine engines (12 kN each, no propeller) at the height of the CG, fast spool.
static func turbine_config() -> Dictionary:
	var c := c172_config()
	var engines := []
	for y in [-1.6, 1.6]:
		engines.append({"type": "turbine", "thrust_n": 12000.0, "max_rpm": 100.0, "idle_n1": 0.25,
			"spool_up_s": 1.0, "spool_down_s": 1.0, "tsfc_kg_per_n_s": 2.0e-5, "pos_m": [1.0, y, 0.93]})
	c.erase("engine")
	c.erase("propeller")
	c.engines = engines
	return c


static func run(f: FDM, seconds: float) -> void:
	for i in int(seconds / DT):
		f.step(DT)


## Airborne at 100 kt, running, trimmed (every engine started like FdmNode.place_airborne).
static func fly_trimmed(f: FDM, kcas := 51.4) -> void:
	f.set_airborne(0.0, 0.0, 900.0, 0.0, kcas)
	for u in f.units:
		u.warm_start(true)
	f.trim_level_cas(kcas)
