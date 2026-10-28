class_name FailureCatalog
extends RefCounted
## Every failure an aircraft can simulate. CATEGORIES is the full list (C172); categories() is the
## list for the aircraft being flown: its aircraft.json "failures": {"disabled": [ids]} removes
## entries (and categories left empty), and each engine beyond the first adds "engine_<n>" and
## "engine_partial_<n>" (FdmNode reads failures/engine_<n> and failures/engine_partial_<n>). Each id is a Props flag "failures/<id>" that the
## owning module reads (engine_piston/fdm_node, systems/*, instruments/gyros, avionics/*).
## Used by the flight-setup failures page, the in-flight failures panel (F9) and the
## random-failure scheduler (systems/failure_manager.gd).

const CATEGORIES := [
	["Engine", [
		["engine", "Engine failure (total)"],
		["engine_partial", "Partial power loss / rough running"],
		["mag_left", "Left magneto"],
		["mag_right", "Right magneto"],
	]],
	["Fuel", [
		["fuel_leak_left", "Left tank leak"],
		["fuel_leak_right", "Right tank leak"],
	]],
	["Electrical", [
		["alternator", "Alternator"],
		["battery", "Battery (dead)"],
	]],
	["Vacuum & gyros", [
		["vacuum_pump", "Vacuum pump"],
		["ai", "Attitude indicator gyro"],
		["hi", "Heading indicator gyro"],
		["tc", "Turn coordinator"],
	]],
	["Pitot-static", [
		["pitot_blocked", "Pitot tube blocked"],
		["static_blocked", "Static port blocked"],
	]],
	["Flight controls", [
		["flaps", "Flaps jammed"],
		["trim", "Elevator trim jammed"],
		["brake_left", "Left brake"],
		["brake_right", "Right brake"],
	]],
	["Avionics", [
		["com1", "COM1 radio"],
		["com2", "COM2 radio"],
		["nav1", "NAV1 receiver"],
		["nav2", "NAV2 receiver (ILS)"],
		["adf", "ADF receiver"],
		["dme", "DME"],
		["xpdr", "Transponder"],
		["gps", "GPS"],
	]],
]

## Scheduled-failure trigger modes (flight setup).
const MODES := ["Off", "At start", "After time", "Above altitude", "Above airspeed"]
const MODE_UNITS := ["", "", "min", "ft AGL", "kt"]


static var _cache := {}  # aircraft id -> categories()


## CATEGORIES adapted to the current aircraft (see the header). Same structure as CATEGORIES.
static func categories() -> Array:
	var def := AircraftDef.current()
	var n := def.engine_count()
	var key := "%s/%d" % [def.id, n]
	if _cache.has(key):
		return _cache[key]
	var off: Array = def.section("failures").get("disabled", [])
	var out := []
	for c in CATEGORIES:
		var items := []
		for f in c[1]:
			if not (f[0] in off):
				items.append(f)
		if c[0] == "Engine" and n > 1:
			var first := []
			var more := []
			for f in items:
				if f[0] == "engine":
					first.append(["engine", "Engine 1 failure (total)"])
				elif f[0] == "engine_partial":
					first.append(["engine_partial", "Engine 1 partial power loss / rough running"])
				else:
					more.append(f)
			for e in range(2, n + 1):
				if not ("engine" in off):
					first.append(["engine_%d" % e, "Engine %d failure (total)" % e])
				if not ("engine_partial" in off):
					first.append(["engine_partial_%d" % e, "Engine %d partial power loss / rough running" % e])
			items = first + more
		if not items.is_empty():
			out.append([c[0], items])
	_cache[key] = out
	return out


static func all_ids() -> Array:
	var out := []
	for c in categories():
		for f in c[1]:
			out.append(f[0])
	return out


static func label(id: String) -> String:
	for c in categories():
		for f in c[1]:
			if f[0] == id:
				return f[1]
	return id


static func ids_in(cats: Array) -> Array:
	var out := []
	for c in categories():
		if c[0] in cats:
			for f in c[1]:
				out.append(f[0])
	return out


static func category_names() -> Array:
	return categories().map(func(c): return c[0])


## Clear every failure flag (repair all).
static func clear_all() -> void:
	for id in all_ids():
		Props.set_v("failures/" + id, false)
