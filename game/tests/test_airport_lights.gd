extends RefCounted
## Aerodrome lighting layouts (world/runway_light_layout.gd, approach_lights.gd, papi.gd,
## taxiway_lights.gd) on a synthetic flat runway: PAPI colour logic, light counts and
## spacing, centreline/edge colour sequences, threshold/end beams, stop bars.

const L := 3000.0
const W := 45.0


static func _flat(_e: float, _n: float) -> float:
	return 10.0


## Runway along +north from (0,0) to (0,L); ILS on end 0 (runway 36, landing northward).
func _rwy(ils0 := true, length := L) -> Dictionary:
	var rw := {"airport": "TEST", "width": W, "length": length, "ends": [
		{"ident": "36", "x": 0.0, "y": 0.0, "h": 10.0}, {"ident": "18", "x": 0.0, "y": length, "h": 10.0}]}
	return AirportLights.describe(rw, ["36"] if ils0 else [])


func test_papi_readings() -> String:
	var r := _rwy()
	var units := Papi.units(r, 0, _flat)
	if units.size() != 4:
		return "expected 4 PAPI units, got %d" % units.size()
	var u0: Vector3 = units[0].pos
	if u0.x >= 0.0 or absf(u0.y - 300.0) > 0.1:
		return "PAPI should be left of the runway, 300 m in: %s" % u0
	var want := {2.0: "RRRR", 3.0: "WWRR", 4.0: "WWWW", 2.7: "WRRR", 3.3: "WWWR"}
	for deg in want:
		var d := 3000.0
		var eye := Vector3(u0.x, u0.y - d, u0.z + d * tan(deg_to_rad(deg)))
		var got := Papi.reading(units, eye)
		if got != want[deg]:
			return "at %.1f deg: %s, want %s" % [deg, got, want[deg]]
	if Papi.unit_color(3.0, 3.5) != RunwayLightLayout.RED or Papi.unit_color(3.0, 2.5) != RunwayLightLayout.WHITE:
		return "unit_color"
	return ""


func test_edge_light_count_and_spacing() -> String:
	var r := _rwy()
	var s := LightSet.new()
	RunwayLightLayout.edges(r, _flat, s)
	var n := ceili(L / RunwayLightLayout.EDGE_SPACING) + 1
	if s.count != n * 2 * 2:  # 2 sides x 2 beams (instrument runway)
		return "edge count %d, want %d" % [s.count, n * 4]
	# same side, same beam: every 4th instance
	var gap := s.pos(4).distance_to(s.pos(0))
	if gap > 60.01 or gap < 50.0:
		return "edge spacing %.1f" % gap
	if absf(absf(s.pos(0).x) - (W * 0.5 + 1.5)) > 0.01:
		return "edge offset %.2f" % s.pos(0).x
	return ""


func test_edge_caution_zone() -> String:
	var r := _rwy()
	var s := LightSet.new()
	RunwayLightLayout.edges(r, _flat, s)
	for i in s.count:
		var p := s.pos(i)
		var toward_b := s.beam(i).y < 0.0  # beam back toward end a: seen landing toward b
		var to_end := L - p.y if toward_b else p.y
		var want := RunwayLightLayout.YELLOW if to_end < 600.0 else RunwayLightLayout.WHITE
		if s.color(i) != want:
			return "edge light at %.0f m (to end %.0f) is %s" % [p.y, to_end, s.color(i)]
	var r2 := _rwy(false, 1000.0)  # visual runway: all white, bidirectional
	if r2.instrument:
		return "1000 m non-ILS runway should not be instrument"
	return ""


func test_centreline_sequence() -> String:
	var r := _rwy()
	var s := LightSet.new()
	RunwayLightLayout.centreline(r, _flat, s)
	var reds := 0
	var whites := 0
	var last_mid := Color()
	for i in s.count:
		if s.beam(i).y > 0.0:
			continue  # only the beam seen rolling toward end b
		var to_end := L - s.pos(i).y
		var c := s.color(i)
		if to_end < 300.0 and c != RunwayLightLayout.RED:
			return "last 300 m must be red (%.0f m)" % to_end
		if to_end > 900.0 and c != RunwayLightLayout.WHITE:
			return "white before 900 m from the end (%.0f m)" % to_end
		if to_end >= 300.0 and to_end < 900.0:
			if c == last_mid:
				return "900-300 m must alternate (%.0f m)" % to_end
			last_mid = c
			reds += int(c == RunwayLightLayout.RED)
			whites += int(c == RunwayLightLayout.WHITE)
	if reds < 15 or whites < 15:
		return "alternating zone reds %d whites %d" % [reds, whites]
	if s.count < 2 * int(L / 15.0) - 2:
		return "centreline count %d" % s.count
	return ""


func test_threshold_and_end_beams() -> String:
	var r := _rwy()
	var s := LightSet.new()
	RunwayLightLayout.threshold_bar(r, 0, _flat, s)
	var greens := 0
	for i in s.count:
		var c := s.color(i)
		var b := s.beam(i)
		if c == RunwayLightLayout.GREEN:
			greens += 1
			if b.y >= 0.0:
				return "green threshold light must beam outward (south)"
		elif c == RunwayLightLayout.RED and b.y <= 0.0:
			return "red end light must beam inward (north)"
	if greens < int(W / 3.0) + 10:  # full width + wing bars
		return "threshold greens %d" % greens
	return ""


func test_approach_systems() -> String:
	var r := _rwy()
	var s := LightSet.new()
	var f := LightSet.new()
	ApproachLights.build(r, 0, _flat, s, f)
	var far := 0.0
	for i in s.count:
		far = maxf(far, -s.pos(i).y)
	if absf(far - 900.0) > 3.0:
		return "ILS approach length %.0f" % far
	if f.count != 20:
		return "flashers %d" % f.count
	for i in range(1, f.count):  # built outward; the farthest fires first (rabbit runs in)
		if f.pos(i).y >= f.pos(i - 1).y or fmod(f.mode(i), 1.0) >= fmod(f.mode(i - 1), 1.0):
			return "flasher sequence order"
	var s2 := LightSet.new()
	var f2 := LightSet.new()
	ApproachLights.build(r, 1, _flat, s2, f2)  # no ILS on end 1, 3000 m: simple 420 m
	var far2 := 0.0
	for i in s2.count:
		far2 = maxf(far2, s2.pos(i).y - L)
	if absf(far2 - 420.0) > 1.0 or f2.count != 0:
		return "simple approach %.0f m, %d flashers" % [far2, f2.count]
	var s3 := LightSet.new()
	ApproachLights.build(_rwy(false, 1000.0), 0, _flat, s3, f2)
	return "" if s3.count == 0 else "short strip should have no approach lights"


func test_stop_bar() -> String:
	var r := _rwy()
	# taxiway from the runway edge eastward; hold point 90 m from the centreline
	var tw := {"width": 18.0, "pts": [[0.0, 1000.0, 10.0], [400.0, 1000.0, 10.0]]}
	var tl := TaxiwayLights.new([tw], [r], [])
	var s := LightSet.new()
	var n := tl.hold(Vector2(90.0, 1000.0), _flat, s)
	var bars := 0
	var wig := 0
	for i in s.count:
		var p := s.pos(i)
		if s.mode(i) >= 2.0:
			wig += 1
			continue
		bars += 1
		if absf(p.x - 90.0) > 0.01 or absf(p.y - 1000.0) > 9.01:
			return "stop-bar light off the hold line: %s" % p
		if s.color(i) != RunwayLightLayout.RED or s.beam(i).x <= 0.0:
			return "stop bar must be red and beam away from the runway"
	if bars != 7 or n != 7 or wig != 2:  # 18 m wide, 3 m spacing
		return "stop bar %d lights, %d guard lights" % [bars, wig]
	return ""


func test_taxiway_edges_skip_runway() -> String:
	var r := _rwy()
	var tw := {"width": 18.0, "pts": [[0.0, 1000.0, 10.0], [400.0, 1000.0, 10.0]]}
	var tl := TaxiwayLights.new([tw], [r], [])
	var s := LightSet.new()
	tl.taxiway([tw], 0, true, _flat, s)
	var blue := 0
	var lead := 0
	for i in s.count:
		var p := s.pos(i)
		if s.color(i) == RunwayLightLayout.BLUE:
			blue += 1
			if p.x < W * 0.5 + 12.0:
				return "blue edge light on the runway at %s" % p
			if absf(absf(p.y - 1000.0) - 10.0) > 0.01:
				return "edge offset %s" % p
		elif s.color(i) == TaxiwayLights.YELLOW:
			lead += 1
			if p.x > TaxiwayLights.STRIP:
				return "yellow lead-on light outside the strip"
	if blue < 20 or lead < 1:
		return "blue %d lead-on yellow %d" % [blue, lead]
	return ""


func test_levels() -> String:
	var night := RunwayLights.levels(-20.0, 20000.0)
	var day := RunwayLights.levels(40.0, 20000.0)
	var fog := RunwayLights.levels(40.0, 1500.0)
	if night.taxi < 0.99 or day.taxi > 0.01 or fog.stop < 0.99:
		return "taxi/stop levels"
	if day.papi < 0.99 or day.flash < 0.99 or day.rwy > 0.2:
		return "day levels"
	return ""
