class_name WeightBalance
extends RefCounted
## Weight & balance against the POH CG envelope (aircraft.json "cg_envelope").
## Masses and stations come from the aircraft config (the same point masses and tanks
## the FDM's MassBalance uses); CG is reported in POH inches aft of datum:
##   cg_in = structural x (m) / 0.0254 + datum_offset_in
## Payload keys are those of Session.setup: fuel_gal (per tank) and one kg value per station of the
## aircraft's aircraft.json "payload.stations" (C172: copilot_kg, rear_kg, baggage_kg).
## An aircraft with payload.fuel_unit "kg" (the A320) keeps the TOTAL fuel in kg in fuel_gal (the key name is
## historic); fuel_per_tank() spreads it: wing tanks first in proportion to their capacity, then the centre
## tank; the tiny pipe tanks stay empty. With cg_envelope.mac {lemac_x_m, mac_m} the CG is reported in % MAC
## instead of inches, and cg_envelope.weight_unit "kg" makes the envelope and the result's "w" kg (default lb).

const IN_PER_M := 1.0 / 0.0254
const LB_PER_KG := 1.0 / 0.45359237

const DEFAULT_KG_PER_GAL := 2.72  # avgas, 6.0 lb/US gal


## Config point mass name -> kg for the stations of aircraft.json "payload" ({} stations = none):
## each station's setup kg (Session.setup[key]) is split evenly over its "masses".
static func station_masses(payload: Dictionary, setup: Dictionary) -> Dictionary:
	var out := {}
	for st in payload.get("stations", []):
		var names: Array = st.masses
		for n in names:
			out[n] = float(setup.get(st.key, 0.0)) / names.size()
	return out


static func kg_per_gal(ac: Dictionary) -> float:
	return float(ac.get("payload", {}).get("fuel_kg_per_gal", ac.get("cg_envelope", {}).get("fuel_kg_per_gal", DEFAULT_KG_PER_GAL)))


## The aircraft config (flight-model config.json) named by the envelope, or {}.
static func load_config(ac: Dictionary) -> Dictionary:
	var def := AircraftDef.load_def(str(ac.get("id", AircraftDef.DEFAULT_ID)))
	var cfg_name = ac.get("cg_envelope", {}).get("config", "")
	if def == null:
		return {}
	if cfg_name == "" or cfg_name == def.path("config").get_file():
		return def.config()
	var path := def.dir + "/" + str(cfg_name)
	if not FileAccess.file_exists(path):
		return {}
	var j = JSON.parse_string(FileAccess.get_file_as_string(path))
	return j if j is Dictionary else {}


static func fuel_in_kg(ac: Dictionary) -> bool:
	return str(ac.get("payload", {}).get("fuel_unit", "gal")) == "kg"


## Fuel (kg) in each tank of cfg.tanks for the setup amount: gal per tank, or total kg (payload.fuel_unit "kg").
static func fuel_per_tank(ac: Dictionary, cfg: Dictionary, amount: float) -> Array:
	var tanks: Array = cfg.tanks
	var out := []
	if not fuel_in_kg(ac):
		for t in tanks:
			out.append(minf(amount * kg_per_gal(ac), float(t.capacity_kg)))
		return out
	var total := 0.0
	for t in tanks:
		total += float(t.capacity_kg)
	var wings := 0.0
	for t in tanks:
		if float(t.capacity_kg) >= 0.01 * total and absf(float(t.pos_m[1])) > 0.5:
			wings += float(t.capacity_kg)
	var left := amount
	var wing_kg := minf(left, wings)
	left -= wing_kg
	for t in tanks:
		var cap := float(t.capacity_kg)
		if cap < 0.01 * total:
			out.append(0.0)
		elif absf(float(t.pos_m[1])) > 0.5:
			out.append(wing_kg * cap / maxf(wings, 1.0))
		else:
			out.append(minf(left, cap))
	return out


## CG in the envelope's unit: % MAC when it has a "mac", else inches aft of the datum.
static func cg_value(env: Dictionary, x_m: float) -> float:
	if env.has("mac"):
		return (x_m - float(env.mac.lemac_x_m)) / float(env.mac.mac_m) * 100.0
	return x_m * IN_PER_M + float(env.get("datum_offset_in", 0.0))


## One loading state: total weight and CG for the fuel (per tank in gal, or total kg: see fuel_per_tank).
## Returns {kg, lb, w (envelope weight unit), cg_in (envelope CG unit), normal, utility, over_max}.
static func point(ac: Dictionary, cfg: Dictionary, setup: Dictionary, fuel_gal_per_tank: float) -> Dictionary:
	var env: Dictionary = ac.cg_envelope
	var m: Dictionary = cfg.mass
	var stations := station_masses(ac.get("payload", {}), setup)
	var kg: float = m.empty_kg
	var moment: float = float(m.empty_kg) * float(m.empty_cg_m[0])
	for p in m.point_masses:
		var w: float = stations.get(p.name, float(p.kg))  # pilot and anything not on the start screen: config default
		kg += w
		moment += w * float(p.pos_m[0])
	var fuel := fuel_per_tank(ac, cfg, fuel_gal_per_tank)
	for i in cfg.tanks.size():
		kg += fuel[i]
		moment += fuel[i] * float(cfg.tanks[i].pos_m[0])
	var cg_in := cg_value(env, moment / kg)
	var lb := kg * LB_PER_KG
	var in_kg := str(env.get("weight_unit", "lb")) == "kg"
	var w := kg if in_kg else lb
	var pt := Vector2(cg_in, w)
	return {
		"kg": kg, "lb": lb, "w": w, "cg_in": cg_in,
		"normal": inside(env.normal, pt),
		"utility": env.has("utility") and inside(env.utility, pt),
		"over_max": w > float(env.max_kg if in_kg else env.max_lb) + 0.5,
	}


## Takeoff (setup fuel) and landing (reserve fuel, never more than at takeoff).
## Returns {takeoff, landing, ok} where ok = both points inside the normal envelope.
static func compute(ac: Dictionary, setup: Dictionary, cfg: Dictionary = {}) -> Dictionary:
	if not ac.has("cg_envelope"):
		return {}
	if cfg.is_empty():
		cfg = load_config(ac)
	if cfg.is_empty():
		return {}
	var gal := float(setup.get("fuel_gal", 0.0))
	var land_gal := minf(gal, float(ac.cg_envelope.get("landing_fuel_kg" if fuel_in_kg(ac) else "landing_fuel_gal_per_tank", 5.0)))
	var to := point(ac, cfg, setup, gal)
	var ld := point(ac, cfg, setup, land_gal)
	return {"takeoff": to, "landing": ld, "ok": to.normal and ld.normal}


## Point-in-polygon (even-odd), points [[x, y], ...]; edges count as inside.
static func inside(poly: Array, pt: Vector2) -> bool:
	var n := poly.size()
	var c := false
	for i in n:
		var a := Vector2(poly[i][0], poly[i][1])
		var b := Vector2(poly[(i + 1) % n][0], poly[(i + 1) % n][1])
		if Geometry2D.get_closest_point_to_segment(pt, a, b).distance_to(pt) < 1e-3:
			return true
		if (a.y > pt.y) != (b.y > pt.y) and pt.x < (b.x - a.x) * (pt.y - a.y) / (b.y - a.y) + a.x:
			c = not c
	return c
