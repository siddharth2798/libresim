extends Node
## Debug: jetway-to-terminal audit of every airport with jet bridges (tests/jetway_audit.gd), before (the old
## one-bridge-per-way layout) and now, with the worst offenders.
##   godot --headless --path game res://tests/debug_jetway_audit.tscn [-- --icao=VABB --all]

const Audit := preload("res://tests/jetway_audit.gd")
const OK_GAP := 1.0  # a root end at most this far out of the wall is connected
const OK_WHEEL := 0.25


static func connected(row: Dictionary) -> bool:
	if row.buried or row.ends.is_empty():
		return false
	for e in row.ends:
		if e.d > OK_GAP:
			return false
	return true


static func worst_gap(row: Dictionary) -> float:
	var g := -INF
	for e in row.ends:
		g = maxf(g, e.d)
	return g if not row.ends.is_empty() else INF


static func worst_wheel(row: Dictionary) -> float:
	var w := 0.0
	for v in row.wheel:
		w = maxf(w, absf(v))
	return w


func _ready() -> void:
	var only := ""
	var all := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--icao="):
			only = a.substr(7)
		elif a == "--all":
			all = true
	var ops = Paths.load_json("airport_ops.json")
	var audit := Audit.new(TerrainTileCache.new())
	for icao in ops:
		var a: Dictionary = ops[icao]
		if a.jetbridges.is_empty() or (only != "" and icao != only):
			continue
		var old := audit.legacy(icao, a)
		var now := audit.measure(icao, a, self)
		print("== %s: %d OSM jet-bridge ways, %d fixed links" % [icao, a.jetbridges.size(), a.get("jetlinks", []).size()])
		for pair in [["before", old], ["now", now]]:
			var rows: Array = pair[1]
			var ok := rows.filter(func(r): return connected(r)).size()
			var gaps := rows.map(func(r): return worst_gap(r))
			gaps.sort()
			var wh := rows.map(func(r): return worst_wheel(r))
			wh.sort()
			var buried := rows.filter(func(r): return r.buried).size()
			print("  %-6s bridges %2d  connected %2d  buried %d  worst gap %6.1f m  wheels off ground: max %.2f m, %d over %.2f" % [
				pair[0], rows.size(), ok, buried, gaps[-1] if not gaps.is_empty() else 0.0, wh[-1] if not wh.is_empty() else 0.0,
				wh.filter(func(v): return v > OK_WHEEL).size(), OK_WHEEL])
		var docks := now.filter(func(r): return r.docks > 0).size()
		var lane := now.filter(func(r): return r.rest_lane < 0.0).size()
		var flo := now.map(func(r): return r.floor_agl.min())
		var fhi := now.map(func(r): return r.floor_agl.max())
		var derr := now.map(func(r): return r.dock_err)
		var stub := now.map(func(r): return r.stub_err)
		print("  A320 gates docked: before %d, now %d of %d jet-bridge gates; drawn stub vs model max %.2f m" % [audit.legacy_gates_docked(a),
			now[0].get("gates_docked", 0) if not now.is_empty() else 0, a.stands.filter(func(s): return s.jetbridge).size(), stub.max() if not stub.is_empty() else 0.0])
		print("  now: %d bridges dock an A320 (max hood-to-door %.2f m), cab floor %.2f..%.2f m above the apron, %d rest hoods on a taxi lane" % [
			docks, derr.max() if not derr.is_empty() else 0.0, flo.min() if not flo.is_empty() else 0.0, fhi.max() if not fhi.is_empty() else 0.0, lane])
		var bad := now.filter(func(r): return all or not connected(r) or worst_wheel(r) > OK_WHEEL or r.rest_lane < 0.0)
		bad.sort_custom(func(x, y): return worst_gap(x) - minf(x.rest_lane, 0.0) > worst_gap(y) - minf(y.rest_lane, 0.0))
		for r in bad.slice(0, 12):
			print("    #%d rot (%.1f, %.1f): ends %s buried %s wheels %s floor %s lane %.1f docks %d" % [r.k, r.rot.x, r.rot.y,
				r.ends.map(func(e): return "%.1f" % e.d), r.buried, r.wheel.map(func(v): return "%.2f" % v),
				r.floor_agl.map(func(v): return "%.2f" % v), r.rest_lane, r.docks])
		for u in audit.undocked(a).slice(0, 14 if all else 6):
			print("    gate '%s' (%s) not docked: nearest cab end %.1f m from the door, tunnel %.1f m, cab twist %.0f deg" % [u.ref, u.src, u.cab_m, u.len, u.twist_deg])
		var obad := old.filter(func(r): return not connected(r))
		obad.sort_custom(func(x, y): return worst_gap(x) > worst_gap(y))
		print("  before, worst: %s" % ", ".join(obad.slice(0, 8).map(func(r): return "#%d %.1f m%s" % [r.k, worst_gap(r), " buried" if r.buried else ""])))
	get_tree().quit()
