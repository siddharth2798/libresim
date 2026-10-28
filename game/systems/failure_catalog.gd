class_name FailureCatalog
extends RefCounted
## Every failure an aircraft can simulate. CATEGORIES is the full list (C172); categories() is the
## list for the aircraft being flown: its aircraft.json "failures": {"disabled": [ids]} removes
## entries (and categories left empty), and each engine beyond the first adds "engine_<n>" and
## "engine_partial_<n>" (FdmNode reads failures/engine_<n> and failures/engine_partial_<n>). Each id is a Props flag "failures/<id>" that the
## owning module reads (engine_piston/fdm_node, systems/*, instruments/gyros, avionics/*).
## An aircraft whose aircraft.json "systems.profile" is "airliner" gets AIRLINER_EXTRA merged in (a category with the
## same name gets the entries added, others are appended; engine fires are made per engine); its own
## "failures.disabled" hides the piston ones (see AIRLINER_HIDDEN). CATEGORIES itself is the C172 list (a test pins it).
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

## Airliner failures (profile "airliner"), merged into CATEGORIES by categories(). Who reads them: failures/hyd_G|B|Y
## systems/airliner_hydraulics, gen1 / gen2 / apu_gen / battery airliner_electrical, fuel_pump_* airliner_fuel,
## engine_fire[_n] the FDM, apu (airliner_electrical for the generator; apu.gd should read it too), adr_* ADIRS,
## gear and spoilers the gear / flight-control code.
const AIRLINER_EXTRA := [
	["Electrical", [
		["gen1", "Generator 1"],
		["gen2", "Generator 2"],
		["apu_gen", "APU generator"],
	]],
	["Hydraulics", [
		["hyd_G", "Green hydraulic system"],
		["hyd_B", "Blue hydraulic system"],
		["hyd_Y", "Yellow hydraulic system"],
	]],
	["Fuel", [
		["fuel_pump_left", "Left tank pumps"],
		["fuel_pump_centre", "Centre tank pumps"],
		["fuel_pump_right", "Right tank pumps"],
	]],
	["Fire", []],  # "engine_fire" per engine, added by categories()
	["APU", [["apu", "APU failure"]]],
	["Air data", [
		["adr_1", "Air data reference 1"],
		["adr_2", "Air data reference 2"],
		["adr_3", "Air data reference 3"],
	]],
	["Landing gear & spoilers", [
		["gear", "Landing gear (will not retract / extend normally)"],
		["spoilers", "Spoilers"],
	]],
]
## Piston-only failures an airliner profile hides, to be listed in its aircraft.json "failures.disabled".
const AIRLINER_HIDDEN := ["mag_left", "mag_right", "vacuum_pump", "ai", "hi", "tc", "alternator"]

## Scheduled-failure trigger modes (flight setup).
const MODES := ["Off", "At start", "After time", "Above altitude", "Above airspeed"]
const MODE_UNITS := ["", "", "min", "ft AGL", "kt"]


static var _cache := {}  # aircraft id -> categories()


## CATEGORIES adapted to the current aircraft (see the header). Same structure as CATEGORIES.
static func categories() -> Array:
	var def := AircraftDef.current()
	var n := def.engine_count()
	var airliner: bool = str(def.section("systems").get("profile", "ga")) == "airliner"
	var key := "%s/%d/%s" % [def.id, n, "airliner" if airliner else "ga"]
	if _cache.has(key):
		return _cache[key]
	var off: Array = def.section("failures").get("disabled", [])
	var out := []
	for c in _base(airliner, n):
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


## CATEGORIES, with the airliner entries merged in for an airliner (see the header).
static func _base(airliner: bool, engines: int) -> Array:
	if not airliner:
		return CATEGORIES
	var out := CATEGORIES.duplicate(true)
	for x in AIRLINER_EXTRA:
		var items: Array = x[1].duplicate(true)
		if x[0] == "Fire":
			for e in range(1, engines + 1):
				items.append(["engine_fire" if e == 1 else "engine_fire_%d" % e, "Engine %d fire" % e])
		var found := false
		for c in out:
			if c[0] == x[0]:
				c[1].append_array(items)
				found = true
		if not found:
			out.append([x[0], items])
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
