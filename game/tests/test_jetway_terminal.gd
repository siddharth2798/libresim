extends Node
## Jet bridges meet their terminal (tools/jetway_net.py + world/jetway_build.gd, measured by tests/jetway_audit.gd on
## the real data): every movable bridge's rotunda is joined by its fixed stub or a fixed link to a building wall
## (no gap in the air, rotunda column not inside the building), its wheels stand on the apron in the rest and docked
## poses, and a docked hood is on the A320's door. Before: one bridge per OSM way, hinged at the way's terminal end
## and scaled at most 1.8 x, so at VABB the 25-45 m second bridges of the T2 piers started in the air 30-65 m from
## the pier (24 of 66 connected), the hood of a 90 m way stopped 50 m short of its cab, and the wheels of a
## pitched bridge left the ground. Needs data/processed (skipped, passing, without it).

const Audit := preload("res://tests/jetway_audit.gd")
const Report := preload("res://tests/debug_jetway_audit.gd")
const AIRPORTS := ["VABB", "VAPO", "VOCI", "VOML", "VOGA", "VOCL", "VOKN"]
const MAX_GAP := 1.0  # a root end may stop at most this far out of the wall
const MAX_WHEEL := 0.25  # wheels within this of the apron
const MAX_DOOR := 0.15  # docked hood face to the door tip

var _rows := {}


func _measure() -> Dictionary:
	if not _rows.is_empty():
		return _rows
	var ops = Paths.load_json("airport_ops.json")
	if not ops is Dictionary or not FileAccess.file_exists(Paths.data("terrain/meta.json")):
		return {}
	var audit := Audit.new(TerrainTileCache.new())
	for icao in AIRPORTS:
		if ops.has(icao) and not ops[icao].jetbridges.is_empty():
			_rows[icao] = audit.measure(icao, ops[icao], self)
	return _rows


func test_jetway_roots_meet_the_terminal_wall() -> String:
	var bad := []
	for icao in _measure():
		for r in _rows[icao]:
			if not Report.connected(r):
				bad.append("%s #%d at (%.0f, %.0f): root ends %s m from the wall%s" % [icao, r.k, r.rot.x, r.rot.y,
					r.ends.map(func(e): return "%.1f" % e.d), ", rotunda inside the building" if r.buried else ""])
	return "" if bad.is_empty() else "%d jet bridges not joined to their terminal: %s" % [bad.size(), "; ".join(bad.slice(0, 6))]


func test_jetway_wheels_on_the_apron() -> String:
	var bad := []
	for icao in _measure():
		for r in _rows[icao]:
			if Report.worst_wheel(r) > MAX_WHEEL:
				bad.append("%s #%d: wheels %s m off the ground (rest, docked...)" % [icao, r.k, r.wheel.map(func(v): return "%.2f" % v)])
	return "" if bad.is_empty() else "; ".join(bad.slice(0, 6))


func test_jetway_docked_hood_on_the_door_and_bridges_dock() -> String:
	var docks := 0
	for icao in _measure():
		for r in _rows[icao]:
			docks += int(r.docks > 0)
			if r.dock_err > MAX_DOOR:
				return "%s #%d: docked hood %.2f m from the door tip" % [icao, r.k, r.dock_err]
	if _rows.has("VABB"):
		var vabb: int = _rows.VABB.filter(func(r): return r.docks > 0).size()
		if vabb < 28:
			return "only %d VABB jet bridges dock an A320 (want 28+; 19 gates before)" % vabb
	return ""
