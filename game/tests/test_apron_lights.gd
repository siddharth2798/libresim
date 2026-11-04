extends RefCounted
## Apron floodlights (world/apron_light_layout.gd, apron_floodlights.gd, apron_lamps.gd, stand_boards.gd):
## masts along airliner stand rows, poles on GA aprons, facade floods at contact stands, never in a runway
## strip, a stand or a taxiway corridor; the real-lamp budget per preset and the real / fake cross-fade.
## The real-data check (every lit airport with stands gets lights) is skipped without data/processed.

const GROUP := "corridor:TESTAPRON"


## n stands in a row along east, spacing sp, noses north; GA refs when ga.
func _row(n: int, sp: float, ga := false, y := 0.0, jet := false) -> Array:
	var out := []
	for i in n:
		out.append({"ref": ("GA%d" if ga else "%d") % (i + 1), "x": i * sp, "y": y, "heading_deg": 0.0,
			"kind": "gate" if jet else "remote", "jetbridge": jet, "src": "test"})
	return out


## A runway along east, its near edge `edge` m south of the stand row.
func _runway(edge: float) -> Dictionary:
	var c := -edge - 22.5
	return {"airport": "TESTAPRON", "width": 45.0, "length": 3000.0, "ends": [
		{"ident": "09", "x": -1000.0, "y": c, "h": 0.0}, {"ident": "27", "x": 2000.0, "y": c, "h": 0.0}]}


func _with_corridors(stands: Array, runways: Array, body: Callable) -> String:
	OpsCorridors.register("TESTAPRON", {"stands": stands, "taxi": {}}, runways, AircraftDef.load_def("c172"))
	var r: String = body.call()
	OpsCorridors.unregister("TESTAPRON")
	return r


## Every stand has a light within reach; no light in any stand's box, corridor or too tall for a runway.
func _check(lights: Array, stands: Array, runways: Array) -> String:
	if lights.is_empty():
		return "no lights"
	var sp := ApronLightLayout.spacings(stands)
	for m in lights:
		if m.kind != "facade":
			if not ApronLightLayout.clear(m.p, stands, sp, []):
				return "%s at %s stands in a stand / corridor" % [m.kind, m.p]
			if m.h > ApronLightLayout.max_height(m.p, runways) + 0.01 or m.h < ApronLightLayout.MIN_H:
				return "%s at %s is %.1f m tall (allowed %.1f)" % [m.kind, m.p, m.h, ApronLightLayout.max_height(m.p, runways)]
		if m.banks.is_empty():
			return "light without banks"
	for s in stands:
		var lit := lights.any(func(m): return m.p.distance_to(Vector2(s.x, s.y)) < ApronLightLayout.KIND[m.kind][0] * 1.2)
		if not lit:
			return "stand %s is not lit" % s.ref
	return ""


func test_masts_along_a_row_of_airliner_stands() -> String:
	var stands := _row(24, 45.0)
	var rws := [_runway(400.0)]
	return _with_corridors(stands, rws, func():
		var lights := ApronLightLayout.build(stands, rws, {}, "TESTAPRON")
		var err := _check(lights, stands, rws)
		if err != "":
			return err
		var masts := lights.filter(func(m): return m.kind == "mast")
		if masts.size() < 8 or masts.size() > 14:  # one mast per ~2 stands
			return "%d masts for 24 stands" % masts.size()
		if masts.any(func(m): return m.h < 25.0):
			return "a big apron gets 25-30 m masts"
		return "")


func test_small_airport_still_gets_a_mast() -> String:
	var stands := _row(2, 40.0)
	var rws := [_runway(300.0)]
	return _with_corridors(stands, rws, func():
		var lights := ApronLightLayout.build(stands, rws, {}, "TESTSMALL")
		var err := _check(lights, stands, rws)
		if err != "":
			return err
		return "" if lights.size() == 1 and lights[0].h <= 15.0 else "2 stands: %d lights, %.0f m" % [lights.size(), lights[0].h])


func test_ga_apron_gets_pole_lights() -> String:
	var stands := _row(12, 15.0, true)
	var rws := [_runway(250.0)]
	return _with_corridors(stands, rws, func():
		var lights := ApronLightLayout.build(stands, rws, {}, "TESTGA")
		var err := _check(lights, stands, rws)
		if err != "":
			return err
		if lights.any(func(m): return m.kind != "pole" or m.h > ApronLightLayout.POLE_H):
			return "GA tie-downs get 10 m poles, not masts"
		return "" if lights.size() >= 3 and lights.size() <= 8 else "%d poles for 12 tie-downs" % lights.size())


func test_never_near_a_runway() -> String:
	var stands := _row(8, 45.0)
	var rws := [_runway(70.0)]  # a cramped apron right beside the runway: no room for tall masts ahead... or none
	return _with_corridors(stands, rws, func():
		var lights := ApronLightLayout.build(stands, rws, {}, "TESTRWY")
		for m in lights:
			var side: float = absf(m.p.y - rws[0].ends[0].y) - 22.5
			if side < 30.0 + 4.0 * m.h - 0.01:
				return "%.0f m light only %.0f m from the runway edge" % [m.h, side]
		var back := ApronLightLayout.build(stands, [_runway(-200.0)], {}, "TESTRWY")  # runway right through the apron
		return "" if back.all(func(m): return ApronLightLayout.max_height(m.p, [_runway(-200.0)]) >= m.h) else "mast in a runway strip")


func test_facade_floods_and_boards_at_contact_stands() -> String:
	var stands := _row(6, 40.0, false, 0.0, true)
	var gates := []
	for s in stands:
		gates.append({"ref": "", "x": s.x - 15.0, "y": 36.0})
	var ops := {"gates": gates}
	var lights := ApronLightLayout.build(stands, [], ops, "TESTGATE")
	var fac := lights.filter(func(m): return m.kind == "facade")
	if fac.size() != 6:
		return "%d facade floods for 6 contact stands" % fac.size()
	for m in fac:
		if absf(m.p.y - 39.0) > 0.5 or m.banks[0].aim.y > 0.0:
			return "facade flood at %s should be on the facade, aimed back at the stand (%s)" % [m.p, m.banks[0].aim]
	var boards := StandBoards.boards(stands, ops)
	if boards.size() != 6 or StandBoards.label("Bay V20") != "V20":
		return "%d stand boards" % boards.size()
	return ""


func test_lamp_type_per_airport() -> String:
	if ApronLightLayout.lamp_type("VABB", {"apron_lamps": "hps"}, 100) != "hps":
		return "data override (airport_ops apron_lamps) ignored"
	var seen := {}
	for icao in ["VABB", "VAPO", "VOCI", "VOCL", "VAJJ", "VOGO", "VOML", "VOKN", "VOCC", "VANM"]:
		var t := ApronLightLayout.lamp_type(icao, {}, 50)
		if t != ApronLightLayout.lamp_type(icao, {}, 50):
			return "lamp type must be stable"
		seen[t] = true
	return "" if seen.size() >= 2 else "every airport got the same lamps: %s" % seen.keys()


func test_light_budget_per_preset() -> String:
	var last := -1
	for p in Graphics.ORDER:
		var s: Dictionary = Graphics.PRESETS[p]
		var mobile := Graphics.preset_renderer(p) == "mobile"
		if mobile and (s.real_lights > 4 or s.apron_shadows > 0):
			return "%s (Mobile): at most 4 real apron lamps, no shadows" % p
		if not mobile and s.real_lights < 8:
			return "%s (Forward+): more real apron lamps" % p
		if s.real_lights < last:
			return "%s: fewer lamps than the preset below" % p
		last = s.real_lights
	return "" if Graphics.PRESETS.ultra.apron_shadows == 1 and Graphics.PRESETS.max.apron_shadows == 2 and Graphics.PRESETS.high.apron_shadows == 0 else "shadows: Ultra 1, Max 2"


## Banks on a line every 30 m, the camera walks along it: each bank's real share + pool share is 1 and
## changes smoothly (no pop when a lamp moves to another bank).
func test_real_lamps_cross_fade() -> String:
	var banks := []
	for i in 40:
		banks.append({"key": "b%d" % i, "lamp": Vector3(i * 30.0, 50.0, 25.0), "aim": Vector3(i * 30.0, 20.0, 0.0),
			"col": Color.WHITE, "half_deg": 50.0, "throw": 40.0, "kind": "mast"})
	var built := {"T": {"banks": banks}}
	var lamps := ApronLamps.new()
	lamps.set_budget(4)
	var prev := {}
	var x := 0.0
	while x < 900.0:
		lamps.update(1.0, built, Vector3(x, 0.0, 2.0), Vector3(x, 0.0, 0.0), 1.0, null)
		var real := {}
		for l in lamps.get_children():
			if l.visible:
				real[l.position] = l.light_energy / (ApronLamps.ENERGY * 40.0 * 40.0)
		for b in banks:
			var d: float = Vector3(x, 0.0, 2.0).distance_to(b.lamp)
			var fake := smoothstep(lamps.real_in, lamps.real_out, d) if lamps.real_out > 0.0 else 1.0
			var r: float = real.get(FloatingOrigin.to_render_d(b.lamp.x, b.lamp.y, b.lamp.z), 0.0)
			if absf(r + fake - 1.0) > 0.02:
				lamps.free()
				return "bank %s at %.0f m: real %.2f + pool %.2f != 1" % [b.key, d, r, fake]
			if prev.has(b.key) and absf(prev[b.key] - r) > 0.12:
				lamps.free()
				return "bank %s popped %.2f -> %.2f" % [b.key, prev[b.key], r]
			prev[b.key] = r
		x += 2.0
	lamps.free()
	return ""


## Real data: every lit airport with stands gets lights, every one clear of corridors and runways.
func test_real_airports() -> String:
	var ops = Paths.load_json("airport_ops.json")
	var rj = Paths.load_json("runways.json")
	if not ops is Dictionary or rj == null:
		return ""
	var rws := {}
	for r in (rj if rj is Array else rj.get("runways", [])):
		if not rws.has(r.airport):
			rws[r.airport] = []
		rws[r.airport].append(r)
	var line := []
	for icao in ops:
		var a: Dictionary = ops[icao]
		var lit: bool = rws.get(icao, []).any(func(rw): return AirportLights.is_lit(icao, rw))
		if a.stands.is_empty() or not lit:
			continue
		OpsCorridors.register(icao, a, rws[icao], AircraftDef.load_def("c172"))
		var lights := ApronLightLayout.build(a.stands, rws[icao], a, icao)
		var bad := lights.filter(func(m): return m.kind != "facade" and (ObstacleRegistry.overlaps_corridor(ObstacleShapes.box(m.p, 1.0, 1.0, 0.0, 0.0, 0.0, "")) or m.h > ApronLightLayout.max_height(m.p, rws[icao]) + 0.01))
		OpsCorridors.unregister(icao)
		var k := {"mast": 0, "pole": 0, "facade": 0}
		for m in lights:
			k[m.kind] += 1
		line.append("%s %d stands: %d masts, %d poles, %d facade" % [icao, a.stands.size(), k.mast, k.pole, k.facade])
		if lights.is_empty():
			return "%s (%d stands) has no apron lights" % [icao, a.stands.size()]
		if not bad.is_empty():
			return "%s: light at %s in a corridor / too tall for the runway" % [icao, bad[0].p]
	print("    apron lights: " + "; ".join(line))
	return ""



## The airside mask (no city-light speckle on aprons): 1 on stands, taxiways and runways, 0 well away.
func test_apron_mask_covers_airside() -> String:
	var stands := _row(6, 45.0)
	var ops := {"stands": stands, "taxi": {"nodes": {"a": [-100.0, -80.0], "b": [400.0, -80.0]}, "edges": [["a", "b", 0, 0, "taxiway"]]}}
	var m := ApronMask.paint(ops, [_runway(300.0)])
	for p in [Vector2(90.0, 0.0), Vector2(150.0, -80.0), Vector2(500.0, -345.0)]:
		if ApronMask.sample(m, p) < 0.99:
			return "airside point %s not masked" % p
	return "" if ApronMask.sample(m, Vector2(100.0, -190.0)) < 0.01 else "grass between taxiway and runway is masked"
