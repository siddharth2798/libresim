class_name RouteFuel
extends RefCounted
## Fuel for the planned route (the Route step's nav log footer and RouteChecks). Still air, at the aircraft's cruise
## true airspeed (cruise_kt: the "Cruise" line of aircraft.json specs) and cruise burn (aircraft.json payload):
##   gal aircraft (C172)  cruise_gph, reserve_gal
##   kg aircraft (A320, payload.fuel_unit "kg")  cruise_kgh, reserve_kg (default RESERVE_H at cruise burn)
## trip = distance / TAS x burn; need = trip + reserve; on board = WeightBalance.fuel_total (all tanks).
## level: "bad" when on board < need, "warn" when it lands with less than twice the reserve, else "ok".

const NM := 1852.0
const FALLBACK_KT := 100.0  # cruise speed when the aircraft names none
const RESERVE_H := 0.5  # reserve when the aircraft names none: 30 min at cruise burn
const DEFAULT_GPH := 9.0

static var _kt := {}  # aircraft id -> cruise KTAS


## Cruise true airspeed (kt): the "Cruise" line of aircraft.json specs ("124 KTAS", "about 450 KTAS"), else FALLBACK_KT.
static func cruise_kt(aircraft: String) -> float:
	if _kt.has(aircraft):
		return _kt[aircraft]
	var kt := FALLBACK_KT
	var def := AircraftDef.load_def(aircraft) if aircraft != "" else null
	if def != null:
		kt = cruise_kt_of(def.data)
	_kt[aircraft] = kt
	return kt


static func cruise_kt_of(ac: Dictionary) -> float:
	var re := RegEx.create_from_string("(\\d+)\\s*KTAS")
	for row in ac.get("specs", []):
		if row is Array and row.size() >= 2 and str(row[0]).begins_with("Cruise"):
			var m := re.search(str(row[1]))
			if m != null:
				return float(m.get_string(1))
	return FALLBACK_KT


## {unit ("gal" | "kg"), burn (per hour), trip, reserve, need, on_board, landing (on board - trip), hours, level} for
## `dist_m` flown at `tas_kt` with `on_board` fuel (in the aircraft's unit).
static func estimate(ac: Dictionary, dist_m: float, tas_kt: float, on_board: float) -> Dictionary:
	var pl: Dictionary = ac.get("payload", {})
	var kg := WeightBalance.fuel_in_kg(ac)
	var burn := float(pl.get("cruise_kgh" if kg else "cruise_gph", 0.0 if kg else DEFAULT_GPH))
	if burn <= 0.0:
		burn = 2500.0 if kg else DEFAULT_GPH
	var reserve := float(pl.get("reserve_kg" if kg else "reserve_gal", burn * RESERVE_H))
	var hours := dist_m / NM / maxf(tas_kt, 1.0)
	var trip := hours * burn
	var out := {"unit": "kg" if kg else "gal", "burn": burn, "trip": trip, "reserve": reserve, "need": trip + reserve,
		"on_board": on_board, "landing": on_board - trip, "hours": hours, "level": "ok"}
	if on_board < out.need:
		out.level = "bad"
	elif on_board - trip < 2.0 * reserve:
		out.level = "warn"
	return out


## The estimate for the setup's route (RouteTerrain.path distance; an "In the air" start on leg k counts from leg k on).
## {} without a route of at least one leg or without the aircraft.
static func for_setup(setup: Dictionary, d: NavDatabase) -> Dictionary:
	var p := RouteTerrain.path(setup, d)
	if p.pts.size() < 2:
		return {}
	var aircraft := str(setup.get("aircraft", AircraftDef.DEFAULT_ID))
	var def := AircraftDef.load_def(aircraft)
	if def == null:
		return {}
	var from := maxi(RouteSetup.air_leg(setup), 0)
	var dist := 0.0
	for k in range(from + 1, p.pts.size()):
		dist += (p.pts[k - 1] as Vector2).distance_to(p.pts[k])
	return estimate(def.data, dist, cruise_kt(aircraft), WeightBalance.fuel_total(def.data, setup))


## "Trip 18 gal + reserve 3 gal · on board 34 gal" (kg with thousands separators for an airliner).
static func text(f: Dictionary) -> String:
	if f.is_empty():
		return ""
	return "Trip %s + reserve %s · on board %s" % [amount(f.trip, f.unit), amount(f.reserve, f.unit), amount(f.on_board, f.unit, false)]


## A fuel amount, rounded up (`up`, what is needed) or to the nearest (what is on board).
static func amount(v: float, unit: String, up := true) -> String:
	var whole := ceili(v - 1e-6) if up else roundi(v)
	if unit == "kg":
		var n := str(whole)
		var s := ""
		while n.length() > 3:
			s = "," + n.right(3) + s
			n = n.left(n.length() - 3)
		return n + s + " kg"
	return "%d gal" % whole
