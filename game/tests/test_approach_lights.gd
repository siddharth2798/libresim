extends RefCounted
## Approach lights (world/approach_lights.gd) stand on the ground under them. They used to be held
## at threshold height or above, so where the approach ground falls away (VAPO: 17 m below the
## threshold within 200 m, lights up to 18 m in the air; median 16 m on runway 28) the "blinking
## lights before the runway" floated. Real-data part needs data/processed (skipped without).

const MAX_ABOVE := 1.5  # m above the ground (LIFT 0.6, flashers 1.0)


## Ground that falls 20 m over the first 300 m of the approach to runway 36 (north), then stays low.
static func _dip(_e: float, n: float) -> float:
	return 10.0 - clampf(-n / 300.0, 0.0, 1.0) * 20.0


func _rwy() -> Dictionary:
	var rw := {"airport": "TEST", "width": 45.0, "length": 3000.0, "ends": [
		{"ident": "36", "x": 0.0, "y": 0.0}, {"ident": "18", "x": 0.0, "y": 3000.0}]}
	return AirportLights.describe(rw, ["36"])


## [min, max] of (light height - ground) over a set.
func _above(s: LightSet, hf: Callable) -> Vector2:
	var lo := INF
	var hi := -INF
	for i in s.count:
		var p := s.pos(i)
		var d: float = p.z - hf.call(p.x, p.y)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	return Vector2(lo, hi)


func test_approach_lights_follow_dip() -> String:
	var s := LightSet.new()
	var f := LightSet.new()
	ApproachLights.build(_rwy(), 0, _dip, s, f)
	for pair in [["steady", s], ["flash", f]]:
		var a := _above(pair[1], _dip)
		if a.x < 0.0 or a.y > MAX_ABOVE:
			return "%s lights %.2f to %.2f m above the ground (want 0 to %.1f)" % [pair[0], a.x, a.y, MAX_ABOVE]
	return ""


## Every approach light of the lit runways of VAPO (ground drops away before runway 28), VABB and
## VOCI sits on the real terrain (level-0 heights, the same function the gear and the lights use).
func test_approach_lights_on_real_ground() -> String:
	var rws = Paths.load_json("runways.json")
	var ilsd = Paths.load_json("ils.json")
	if not rws is Dictionary or not ilsd is Array or not FileAccess.file_exists(Paths.data("terrain/meta.json")):
		return ""
	var cache := TerrainTileCache.new()
	var hf := func(e: float, n: float) -> float: return cache.height_at(e, n)
	for icao in ["VAPO", "VABB", "VOCI"]:
		var ils_rwys := []
		for e in ilsd:
			if e.airport == icao:
				ils_rwys.append(str(e.runway))
		for rw in rws.runways:
			if rw.airport != icao or not AirportLights.is_lit(icao, rw):
				continue
			var r := AirportLights.describe(rw, ils_rwys)
			for i in 2:
				var s := LightSet.new()
				var f := LightSet.new()
				ApproachLights.build(r, i, hf, s, f)
				for ls in [s, f]:
					if ls.count == 0:
						continue
					var a := _above(ls, hf)
					if a.x < 0.0 or a.y > MAX_ABOVE:
						return "%s %s: lights %.2f to %.2f m above the ground (want 0 to %.1f)" % [icao, r.idents[i], a.x, a.y, MAX_ABOVE]
	return ""
