class_name WeightBalance
extends RefCounted
## Weight & balance against the POH CG envelope (aircraft.json "cg_envelope").
## Masses and stations come from the aircraft config (the same point masses and tanks
## the FDM's MassBalance uses); CG is reported in POH inches aft of datum:
##   cg_in = structural x (m) / 0.0254 + datum_offset_in
## Payload keys are those of Session.setup: fuel_gal (per tank) and one kg value per station of the
## aircraft's aircraft.json "payload.stations" (C172: copilot_kg, rear_kg, baggage_kg).

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


## One loading state: total weight and CG for given per-tank fuel.
## Returns {kg, lb, cg_in, normal, utility, over_max}.
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
	for t in cfg.tanks:
		var f := minf(fuel_gal_per_tank * kg_per_gal(ac), float(t.capacity_kg))
		kg += f
		moment += f * float(t.pos_m[0])
	var cg_in := moment / kg * IN_PER_M + float(env.get("datum_offset_in", 0.0))
	var lb := kg * LB_PER_KG
	var pt := Vector2(cg_in, lb)
	return {
		"kg": kg, "lb": lb, "cg_in": cg_in,
		"normal": inside(env.normal, pt),
		"utility": env.has("utility") and inside(env.utility, pt),
		"over_max": lb > float(env.max_lb) + 0.5,
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
	var land_gal := minf(gal, float(ac.cg_envelope.get("landing_fuel_gal_per_tank", 5.0)))
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
