extends RefCounted
## Apron ground flatness from the real terrain cache (tools/apron_flatten.py, pipeline step 17):
## the DSM's terminal walls, roofs and parked aircraft must not show up as mounds around the
## stands, and the landmark terminal models (step 16) must sit on that ground. Before the fix
## 54 % of VABB's stands had a mound taller than 1.5 m within 45 m (median 2.0 m, p90 12.4 m).
## Needs data/processed (like test_flight); skipped (passes) without terrain data.

const DISC := 45.0  # m around a stand
const STEP := 15.0  # m between samples (bilinear on the 30 m DEM)


func _ops() -> Dictionary:
	var d = Paths.load_json("airport_ops.json")
	return d if d is Dictionary else {}


## Peak-to-peak terrain height (m) within DISC of every stand of an airport.
func _stand_ptps(cache: TerrainTileCache, a: Dictionary) -> Array[float]:
	var out: Array[float] = []
	for s in a.stands:
		var lo := INF
		var hi := -INF
		var n := 0
		var d := -DISC
		while d <= DISC:
			var e := -DISC
			while e <= DISC:
				if d * d + e * e <= DISC * DISC:
					var h := cache.height_at(float(s.x) + e, float(s.y) + d)
					lo = minf(lo, h)
					hi = maxf(hi, h)
					n += 1
				e += STEP
			d += STEP
		if n >= 3:
			out.append(hi - lo)
	out.sort()
	return out


func _q(a: Array[float], f: float) -> float:
	return a[mini(int(f * a.size()), a.size() - 1)] if not a.is_empty() else 0.0


func _check(icao: String, med_max: float, p90_max: float, share_max: float) -> String:
	var ops := _ops()
	if not ops.has(icao) or not FileAccess.file_exists(Paths.data("terrain/meta.json")):
		return ""
	var cache := TerrainTileCache.new()
	var p := _stand_ptps(cache, ops[icao])
	if p.size() < 20:
		return "%s: only %d stands" % [icao, p.size()]
	var bumpy := 0
	for v in p:
		if v > 3.0:
			bumpy += 1
	var share := float(bumpy) / p.size()
	print("    %s: %d stands, ground peak-to-peak within %.0f m: median %.2f, p90 %.2f, max %.2f m; %.0f %% above 3 m" % [
		icao, p.size(), DISC, _q(p, 0.5), _q(p, 0.9), p[-1], share * 100.0])
	if _q(p, 0.5) > med_max:
		return "%s: median stand-area relief %.2f m (> %.2f)" % [icao, _q(p, 0.5), med_max]
	if _q(p, 0.9) > p90_max:
		return "%s: p90 stand-area relief %.2f m (> %.2f): DSM clutter is back on the apron" % [icao, _q(p, 0.9), p90_max]
	if share > share_max:
		return "%s: %.0f %% of the stands have a mound over 3 m (> %.0f %%)" % [icao, share * 100.0, share_max * 100.0]
	return ""


func test_apron_flat_vabb() -> String:
	return _check("VABB", 1.0, 2.0, 0.05)


func test_apron_flat_vanm() -> String:
	return _check("VANM", 0.3, 0.6, 0.0)


## The landmark terminal models' origin height is the ground under their footprints (16 raises every
## vertex by terrain minus origin, so each landmark sits on its own ground) and agrees with the
## stand ground beside them (before: VABB 14.8 m, a mound of terminal roofs, against 7 to 9 m).
func test_terminal_base_on_ground() -> String:
	var ops := _ops()
	if ops.is_empty() or not FileAccess.file_exists(Paths.data("terrain/meta.json")):
		return ""
	var cache := TerrainTileCache.new()
	for icao in ["VABB", "VAPO", "VOCI"]:
		var m = Paths.load_json("terminals/%s_model.json" % icao)
		if not m is Dictionary or not ops.has(icao):
			continue
		var base := float(m.origin[2])
		var cents: Array[Vector2] = []
		var under := 0.0
		for f in m.focus:
			var p := Vector2(float(m.origin[0]) + float(f[0]), float(m.origin[1]) + float(f[1]))
			cents.append(p)
			under += cache.height_at(p.x, p.y) / m.focus.size()
		if absf(base - under) > 1.5:
			return "%s: terminal base %.1f m but the terrain under the landmarks averages %.1f m (re-run step 16 after 17)" % [icao, base, under]
		var hs: Array[float] = []
		for s in ops[icao].stands:
			for p in cents:
				if Vector2(s.x, s.y).distance_to(p) < 700.0:
					hs.append(cache.height_at(s.x, s.y))
					break
		hs.sort()
		if hs.size() < 5:
			continue
		var apron: float = hs[hs.size() >> 1]
		print("    %s: terminal base %.1f m, terrain under the landmarks %.1f m, stand ground median %.1f m (%d stands within 700 m)" % [icao, base, under, apron, hs.size()])
		if absf(base - apron) > 2.0:
			return "%s: terminal base %.1f m is %.1f m from the apron ground %.1f m" % [icao, base, absf(base - apron), apron]
	return ""
