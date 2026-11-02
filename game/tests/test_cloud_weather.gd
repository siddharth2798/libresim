extends RefCounted
## Cloud-coupled weather physics, part 1: world/cloud_field.gd (geometry, density, kind, turbulence
## scale) and world/cloud_convection.gd (thermals). Part 2: tests/test_cloud_storms.gd.


## Conditions as CloudPhysics.conditions() builds them, for a named preset at the given sun elevation.
static func cond(preset: String, sun_elev := 45.0, land := 1.0) -> Dictionary:
	var w: Dictionary = Session.WEATHER[preset]
	var cover: float = w.cloud_cover
	var conv: float = w.convection
	return {"cover": cover, "base_m": Units.ft_to_m(w.cloud_base_ft), "convection": conv, "storms": w.storms,
		"precip": w.precip, "land": land, "heat": CloudConvection.heating(sun_elev) * (1.0 - 0.7 * smoothstep(0.6, 1.0, cover)),
		"kind": CloudField.kind(cover, w.precip, conv, w.storms, sun_elev, w.turbulence), "drift": Vector2.ZERO,
		"wind_en": Vector2(8.0, 0.0)}


## Best (highest) and worst thermal over a 20 x 20 km grid at altitude alt (ground at 0).
static func extremes(c: Dictionary, alt: float) -> Vector2:
	var hi := -99.0
	var lo := 99.0
	for x in range(-10000, 10000, 250):
		for y in range(-10000, 10000, 250):
			var p := Vector3(x, y, alt)
			var w := CloudConvection.thermal(p, alt, c, CloudField.density(p, c.base_m, c.cover, c.drift))
			hi = maxf(hi, w)
			lo = minf(lo, w)
	return Vector2(hi, lo)


func test_cloud_geometry_and_density() -> String:
	var base := 1500.0
	var top := CloudField.top_m(base)
	if absf(top - base - WeatherFx.CLOUD_THICK) > 0.01:
		return "cloud top must be base + the shader thickness"
	var any := 0
	var prev_cover_sum := 0.0
	for cover in [0.0, 0.3, 0.6, 0.9, 1.0]:
		var sum := 0.0
		for x in range(-6000, 6000, 300):
			for y in range(-6000, 6000, 300):
				var z := base + 400.0
				var d := CloudField.density(Vector3(x, y, z), base, cover, Vector2(120.0, -40.0))
				var d_more := CloudField.density(Vector3(x, y, z), base, minf(cover + 0.1, 1.0), Vector2(120.0, -40.0))
				if d_more + 1e-6 < d:
					return "density fell when cover rose at (%d, %d): %.3f -> %.3f" % [x, y, d, d_more]
				if CloudField.density(Vector3(x, y, base - 1.0), base, cover, Vector2.ZERO) != 0.0 or CloudField.density(Vector3(x, y, top + 1.0), base, cover, Vector2.ZERO) != 0.0:
					return "density must be zero below the base and above the top"
				sum += d
				any += 1 if d > CloudField.IN_CLOUD else 0
		if sum + 1e-6 < prev_cover_sum:
			return "total cloud must grow with cover (%.1f after %.1f at cover %.1f)" % [sum, prev_cover_sum, cover]
		prev_cover_sum = sum
	if CloudField.density(Vector3(0, 0, base + 400.0), base, 0.0, Vector2.ZERO) != 0.0:
		return "no cover, no cloud"
	print("    %d of 5 x 1600 sample points inside a cloud over covers 0..1" % any)
	return "" if any > 200 else "almost no cloud found for covers up to 1"


func test_cloud_density_matches_cloud_layer_formula() -> String:
	# the CPU copy against CloudLayer.density_at's formula with the same images: bilinear vs nearest,
	# so agreement is statistical (same structure), not exact
	var layer := CloudLayer.new()
	layer._img_lo = CloudField._image(0.012, 4, 1)
	layer._img_hi = CloudField._image(0.03, 3, 2)
	layer.base = 1500.0
	layer.cover = 0.6
	layer.drift = Vector2(300.0, 100.0)
	var agree := 0
	var n := 0
	for x in range(-4000, 4000, 200):
		for y in range(-4000, 4000, 200):
			var p := Vector3(x, y, 1500.0 + 300.0)
			var a := layer.density_at(p)
			var b := CloudField.density(p, 1500.0, 0.6, Vector2(300.0, 100.0))
			n += 1
			if (a > 0.05) == (b > 0.05):
				agree += 1
	layer.free()
	print("    in-cloud agrees with CloudLayer at %d of %d points" % [agree, n])
	return "" if agree >= n * 0.9 else "CPU density disagrees with the visual layer (%d of %d)" % [agree, n]


func test_cloud_kind_for_presets() -> String:
	var want := {"Clear": "clear", "Fair": "cumulus", "Scattered": "cumulus", "Broken": "cumulus",
		"Overcast": "stratiform", "Winter haze": "clear", "Monsoon": "cumulonimbus"}
	for n in want:
		var c := cond(n)
		if c.kind != want[n]:
			return "%s by day: kind %s, want %s" % [n, c.kind, want[n]]
	if CloudField.kind(0.3, 0.0, 0.5, 0.0, -20.0) != "stratiform":
		return "scattered cloud at night is not cumulus"
	return ""


func test_turbulence_scale_values() -> String:
	if CloudField.turbulence_scale("cumulus", 0.0, 0.0, 0.0) != 1.0:
		return "clear air must keep the Dryden sigma"
	var strat := CloudField.turbulence_scale("stratiform", 0.6, 0.0, 0.0)
	var cu := CloudField.turbulence_scale("cumulus", 0.6, 0.0, 0.0)
	var cb := CloudField.turbulence_scale("cumulonimbus", 0.6, 0.0, 0.0)
	if not (strat >= 1.4 and strat <= 1.6 and cu > strat and cb > cu and cb <= 2.6):
		return "in-cloud scales stratiform %.2f cumulus %.2f cumulonimbus %.2f" % [strat, cu, cb]
	var prev := 1.0
	for near in [0.0, 0.2, 0.4, 0.7, 1.0]:
		var s := CloudField.turbulence_scale("cumulus", 0.0, near, 0.0)
		if s + 1e-6 < prev or s > cu:
			return "edge ramp not monotonic / above in-cloud at near %.1f: %.2f" % [near, s]
		prev = s
	if CloudField.turbulence_scale("stratiform", 0.0, 0.7, 0.0) >= CloudField.turbulence_scale("cumulus", 0.0, 0.7, 0.0):
		return "stratiform edges should be milder than cumulus"
	if CloudField.under_base(1300.0, 1500.0, "cumulus", 0.5) <= 0.0 or CloudField.under_base(1300.0, 1500.0, "stratiform", 0.5) != 0.0 or CloudField.under_base(0.0, 1500.0, "cumulus", 0.5) != 0.0:
		return "convective base turbulence only just under a cumulus base"
	# proximity: a point in clear air next to a cloud sees a ramp, far from clouds none
	var c := cond("Scattered")
	var near_n := 0
	for x in range(-8000, 8000, 100):
		var p := Vector3(x, 0.0, c.base_m + 200.0)
		if CloudField.density(p, c.base_m, c.cover, c.drift) < 0.01:
			var pr := CloudField.proximity(p, c.base_m, c.cover, c.drift)
			near_n += 1 if pr > 0.1 else 0
	print("    %d clear-air points within 300 m of a cloud on one 16 km line" % near_n)
	return "" if near_n > 0 else "no cloud-edge proximity found"


func test_thermal_profile_and_structure() -> String:
	var c := cond("Scattered")  # cumulus, convection 0.7, cover 0.5, base 3000 ft = 914 m AMSL
	var night := cond("Scattered", -20.0)
	var alt := 500.0
	var day_ex := extremes(c, alt)
	var night_ex := extremes(night, alt)
	print("    Scattered thermals at 500 m: best %.1f m/s, worst %.1f m/s; night best %.2f worst %.2f" % [day_ex.x, day_ex.y, night_ex.x, night_ex.y])
	if night_ex.x != 0.0 or night_ex.y != 0.0:
		return "thermals at night must be zero"
	if day_ex.x < 1.0 or day_ex.x > CloudConvection.MAX_UP:
		return "best thermal %.1f m/s not in 1-5 m/s" % day_ex.x
	if day_ex.y > -0.2 or day_ex.y < -1.5:
		return "sink between thermals %.2f m/s not weak (0.3-1)" % day_ex.y
	# above the top and above 4000 m AGL
	var top := CloudField.top_m(c.base_m)
	var above := extremes(c, top + 900.0)
	if above.x > 0.05:
		return "thermal %.2f m/s well above the cloud top" % above.x
	var high_c := c.duplicate()
	high_c.base_m = 5200.0
	var ceiling := extremes(high_c, 4200.0)
	if ceiling.x > 0.0 or ceiling.y < 0.0:
		return "thermals above 4000 m AGL: %s" % ceiling
	# vertical profile: mid boundary layer beats near-ground and above-the-layer values
	var p_mid := CloudConvection.profile_up(450.0, 900.0, 1800.0, true)
	if not (p_mid >= CloudConvection.profile_up(60.0, 900.0, 1800.0, true) and p_mid >= CloudConvection.profile_up(900.0, 900.0, 1800.0, true) and p_mid > CloudConvection.profile_up(2600.0, 900.0, 1800.0, true)):
		return "updraft profile does not peak mid boundary layer"
	# water is weak, forest cooler than bare land
	var water := c.duplicate()
	water.land = CloudConvection.land_factor(255)
	var wex := extremes(water, alt)
	if not (wex.x < day_ex.x * 0.4):
		return "water thermals %.2f vs land %.2f m/s" % [wex.x, day_ex.x]
	if CloudConvection.land_factor(150) >= CloudConvection.land_factor(0) or CloudConvection.land_factor(255) >= CloudConvection.land_factor(150):
		return "land factor order: bare > forest > water"
	# no convection setting, no thermals; thermals sit under the cloud: best lift where the cloud is
	var off := c.duplicate()
	off.convection = 0.0
	if extremes(off, alt) != Vector2.ZERO:
		return "convection 0 must switch thermals off"
	var under_cloud := 0.0
	var n_cloud := 0
	for x in range(-8000, 8000, 200):
		for y in range(-8000, 8000, 200):
			if CloudField.density(Vector3(x, y, c.base_m + 300.0), c.base_m, c.cover, c.drift) > 0.2:
				under_cloud += CloudConvection.thermal(Vector3(x, y, alt), alt, c, 0.0)
				n_cloud += 1
	if n_cloud == 0 or under_cloud / n_cloud < 0.8:
		return "mean lift under cloud %.2f m/s (%d points), want > 0.8" % [under_cloud / maxf(n_cloud, 1), n_cloud]
	return ""


func test_thermal_preset_strength_order() -> String:
	var clear := extremes(cond("Clear"), 500.0).x
	var fair := extremes(cond("Fair"), 500.0).x
	var scat := extremes(cond("Scattered"), 500.0).x
	var over := extremes(cond("Overcast"), 500.0).x
	print("    best thermal Clear %.1f Fair %.1f Scattered %.1f Overcast %.1f m/s" % [clear, fair, scat, over])
	return "" if clear < fair and fair <= scat and over < fair and over < 0.6 else "thermal strength order is off"
