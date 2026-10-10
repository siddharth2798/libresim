extends RefCounted
## Core/world tests (M2).


func test_geo_roundtrip() -> String:
	# Reference values from tools/05 (GDAL/PROJ) for VAPO and VAJJ.
	for c in [[18.5821, 73.919701, 54856.12, -18505.25], [19.098100662231445, 72.83419799804688, -59540.2, 38627.86]]:
		var p := Geo.to_enu(c[0], c[1])
		if p.distance_to(Vector2(c[2], c[3])) > 0.05:
			return "to_enu %s -> %s, expected (%s, %s)" % [c, p, c[2], c[3]]
		var ll := Geo.to_latlon(p.x, p.y)
		if absf(ll.x - c[0]) > 2e-5 or absf(ll.y - c[1]) > 2e-5:  # Vector2 is float32 (~1 m in degrees)
			return "to_latlon mismatch %s" % ll
	return ""


func test_floating_origin() -> String:
	var fo = load("res://core/floating_origin.gd").new()
	var hits := []
	fo.shifted.connect(func(d): hits.append(d))
	var p := Vector3(54856.12, -18505.25, 600.0)
	fo.update_focus(p)
	if hits.size() != 1:
		return "expected a shift"
	var r: Vector3 = fo.to_render(p)
	if absf(r.x) > 5000.0 or absf(r.z) > 5000.0 or absf(r.y - 600.0) > 1e-3:
		return "render pos not near origin: %s" % r
	if (fo.to_world(r) - p).length() > 1e-2:
		return "to_world(to_render(p)) != p"
	fo.free()
	return ""


func test_terrain_heights() -> String:
	var cache := TerrainTileCache.new()
	var vapo := cache.height_at(54856.0, -18505.0)  # Pune airport, 592 m published
	if absf(vapo - 588.0) > 15.0:
		return "VAPO height %.1f" % vapo
	var sea := cache.height_at(-66000.0, 30000.0)  # Arabian Sea
	if absf(sea) > 3.0:
		return "sea height %.1f" % sea
	# Flattened runway: VABB 09/27 must be smooth (< 1 m between samples 100 m apart)
	var prev := cache.height_at(-58000.0, 37570.0)
	for x in range(-57900, -54700, 100):
		var h := cache.height_at(float(x), 37570.0)
		if absf(h - prev) > 1.0:
			return "VABB runway bump %.2f m at x=%d" % [h - prev, x]
		prev = h
	return ""
