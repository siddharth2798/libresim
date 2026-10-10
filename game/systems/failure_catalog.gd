class_name FailureCatalog
extends RefCounted
## Every failure the C172 can simulate. Each id is a Props flag "failures/<id>" that the
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


static func all_ids() -> Array:
	var out := []
	for c in CATEGORIES:
		for f in c[1]:
			out.append(f[0])
	return out


static func label(id: String) -> String:
	for c in CATEGORIES:
		for f in c[1]:
			if f[0] == id:
				return f[1]
	return id


static func ids_in(categories: Array) -> Array:
	var out := []
	for c in CATEGORIES:
		if c[0] in categories:
			for f in c[1]:
				out.append(f[0])
	return out


static func category_names() -> Array:
	return CATEGORIES.map(func(c): return c[0])


## Clear every failure flag (repair all).
static func clear_all() -> void:
	for id in all_ids():
		Props.set_v("failures/" + id, false)
