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
		var gates: int = int(_rows.VABB[0].get("gates_docked", 0))
		if gates < 45:
			return "only %d VABB jet-bridge gates dock an A320 (want 45+)" % gates
	if _rows.has("VOCL") and int(_rows.VOCL[0].get("gates_docked", 0)) < 4:
		return "only %d VOCL gates dock an A320 (want 4+)" % int(_rows.VOCL[0].get("gates_docked", 0))
	if _rows.has("VOGA") and int(_rows.VOGA[0].get("gates_docked", 0)) < 6:
		return "only %d VOGA gates dock an A320 (want 6)" % int(_rows.VOGA[0].get("gates_docked", 0))
	return ""


## Landmark terminal lines (mullions, panel joints, roof seams, tiles, soffit ribs) are box-filtered by the pixel
## footprint. Hard step() lines of 1-7 cm aliased into moire that crawled and waved as the camera moved.
func test_terminal_lines_are_filtered() -> String:
	var src := FileAccess.get_file_as_string("res://world/terminal.gdshader")
	if not src.contains("float line_cov(float x, float w)") or not src.contains("fwidth(x)"):
		return "the terminal shader should filter its lines by the pixel footprint"
	for bad in ["step(f.x", "step(f.y", "step(0.9, s)", "step(0.93, joint)"]:
		if src.contains(bad):
			return "a hard line is left: " + bad
	var inc := FileAccess.get_file_as_string("res://world/building_terminal.gdshaderinc")
	if not inc.contains("gl *= mix(1.0, 0.9 + 0.2 * hash(vec2(floor(u / TERM_MULL), floor(sto)) + id), detail)"):
		return "the generic terminal's per-panel glass tone should fade with the pixel footprint"
	return ""
