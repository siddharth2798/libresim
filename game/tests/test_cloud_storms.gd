extends RefCounted
## Cloud-coupled weather physics, part 2: world/cloud_storm.gd (microbursts), world/cloud_physics.gd (Props
## published at the aircraft, their effect on wind_ned through weather.gd) and a hands-off C172 in a thermal.

const Part1 := preload("res://tests/test_cloud_weather.gd")
const DT := 1.0 / 120.0
const KT := 0.514444


func _first_cell(storms: float) -> Vector2i:
	for i in range(-5, 6):
		for j in range(-5, 6):
			if CloudStorm.cell(i, j, storms, 7).on:
				return Vector2i(i, j)
	return Vector2i(99, 99)


func test_storm_cell_shape() -> String:
	var ij := _first_cell(0.9)
	var cl := CloudStorm.cell(ij.x, ij.y, 0.9, 7)
	if ij.x == 99 or cl.radius < 1000.0 or cl.radius > 3000.0:
		return "no storm cell / radius %.0f m outside 1-3 km" % float(cl.get("radius", 0.0))
	var base := 1200.0 * 0.3048
	var ctr: Vector2 = CloudStorm.center_at(cl, 0.0, Vector2.ZERO)
	var core := CloudStorm.sample(Vector3(ctr.x, ctr.y, 300.0), 300.0, 0.0, Vector2.ZERO, 0.9, base)
	var far := CloudStorm.sample(Vector3(ctr.x + 9000.0, ctr.y, 300.0), 300.0, 0.0, Vector2.ZERO, 0.9, base)
	print("    core downdraft %.1f m/s (intensity %.2f, core %s); 9 km away shear %.2f" % [core.wind.z, core.intensity, core.core, far.shear])
	if core.wind.z < 4.0 or core.wind.z > 10.5 or not core.core or core.intensity < 0.4:
		return "core downdraft %.1f m/s, intensity %.2f" % [core.wind.z, core.intensity]
	var rad: float = cl.radius
	var best_out := 0.0
	for a in range(0, 360, 45):
		var dir := Vector2(cos(deg_to_rad(a)), sin(deg_to_rad(a)))  # east, north
		var p := Vector3(ctr.x + dir.x * rad * 0.55, ctr.y + dir.y * rad * 0.55, 60.0)
		var s := CloudStorm.sample(p, 60.0, 0.0, Vector2.ZERO, 0.9, base)
		var out := Vector2(s.wind.y, s.wind.x)  # NED (n, e, d) -> (east, north)
		if out.dot(dir) <= 0.0 or absf(out.normalized().dot(dir)) < 0.98:
			return "outflow at %d deg is not pointing away from the core: %s" % [a, out]
		best_out = maxf(best_out, out.length())
	if best_out < 8.0 or best_out > 16.0:
		return "surface outflow %.1f m/s not in 8-16 m/s" % best_out
	if CloudStorm.sample(Vector3(ctr.x, ctr.y, 300.0), 300.0, 0.0, Vector2.ZERO, 0.0, base).shear != 0.0:
		return "no storms setting, no shear"
	var high := CloudStorm.sample(Vector3(ctr.x, ctr.y, base + 4000.0), 4000.0, 0.0, Vector2.ZERO, 0.9, base)
	if high.wind.length() > 0.5:
		return "storm wind far above the tops: %.1f" % high.wind.length()
	var ground := CloudStorm.sample(Vector3(ctr.x, ctr.y, 0.0), 0.0, 0.0, Vector2.ZERO, 0.9, base)
	return "" if absf(ground.wind.z) < 0.01 else "downdraft %.2f at the ground (must turn to outflow)" % ground.wind.z


func test_storm_determinism_density_and_drift() -> String:
	var on := 0
	for i in range(0, 10):
		for j in range(0, 10):
			var a := CloudStorm.cell(i, j, 0.7, 7)
			var b := CloudStorm.cell(i, j, 0.7, 7)
			if a != b:
				return "storm cells are not deterministic"
			on += 1 if a.on else 0
	print("    storm cells present: %d of 100 ten-km cells at storms 0.7" % on)
	if on < 60 or on > 100:
		return "%d storm cells per 100 cells: want roughly one per 10 x 10 km" % on
	var cl := CloudStorm.cell(_first_cell(0.7).x, _first_cell(0.7).y, 0.7, 7)
	var c0 := CloudStorm.center_at(cl, 0.0, Vector2(10.0, 0.0))
	var c1 := CloudStorm.center_at(cl, 600.0, Vector2(10.0, 0.0))
	if c1.x <= c0.x + 1000.0 or absf(c1.y - c0.y) > 1.0:
		return "cell should drift with the wind (%.0f -> %.0f)" % [c0.x, c1.x]
	var p := Vector3(c1.x, c1.y, 300.0)
	var s := CloudStorm.sample(p, 300.0, 600.0, Vector2(10.0, 0.0), 0.7, 300.0)
	return "" if s.wind.z > 3.0 else "the moved cell has no downdraft at its new centre (%.1f)" % s.wind.z


func _reset_weather(preset := "Clear") -> void:
	var w: Dictionary = Session.WEATHER[preset]
	for k in w:
		Props.set_v("weather/" + k, float(w[k]))
	Props.set_v("weather/gust_kt", 0.0)
	Props.set_v("weather/turbulence", 0.0)
	Props.set_v("weather/wind_kt", 8.0)
	Props.set_v("weather/aloft_kt", 12.0)
	Props.set_v("weather/temp_c", 30.0)
	Props.set_v("environment/sun_elev_deg", 45.0)
	Props.set_v("environment/cloud_drift", Vector2.ZERO)
	Props.set_v("environment/storm_intensity", 0.0)


## The Props the tests below change are put back afterwards (later suites share them).
func _snapshot() -> Dictionary:
	var d := Props.dump("weather/")
	d.merge(Props.dump("environment/"), true)
	d.merge(Props.dump("fdm/"), true)
	return d


func test_cloud_props_and_wind() -> String:
	var snap := _snapshot()
	var r := _props_and_wind()
	Props.restore(snap)
	return r


func _props_and_wind() -> String:
	_reset_weather("Clear")
	Props.set_v("weather/convection", 0.0)
	var w := Weather.new()
	w._ready()
	Props.set_v("fdm/position_enu", Vector3(1000.0, 500.0, 500.0))
	Props.set_v("fdm/agl_m", 500.0)
	Props.set_v("fdm/tas_mps", 50.0)
	w._physics_process(DT)
	for k in ["ac_cloud_density", "ac_in_cloud", "cloud_base_m", "cloud_top_m", "cloud_kind", "turbulence_scale", "thermal_mps", "storm_intensity", "storm_core", "storm_shear_mps"]:
		if not Props.has("environment/" + k):
			return "environment/%s not published" % k
	var ws: Vector3 = Props.get_v("environment/wind_ned")
	if Props.get_f("environment/turbulence_scale") != 1.0 or Props.get_f("environment/thermal_mps") != 0.0 or Props.get_b("environment/ac_in_cloud") or Props.get_v("environment/cloud_kind") != "clear":
		return "clear air publishes scale %.2f thermal %.2f kind %s" % [Props.get_f("environment/turbulence_scale"), Props.get_f("environment/thermal_mps"), Props.get_v("environment/cloud_kind")]
	if absf(Props.get_f("environment/cloud_base_m") - Units.ft_to_m(6000.0)) > 0.1 or absf(Props.get_f("environment/cloud_top_m") - Units.ft_to_m(6000.0) - 900.0) > 0.1:
		return "cloud base/top Props wrong"
	if absf(ws.z) > 0.01:  # turbulence 0, no thermals, no lift (no terrain): the vertical wind is exactly zero
		return "clear air with turbulence 0 should have no vertical wind, got %.3f" % ws.z
	# in cloud: Scattered, put the aircraft inside the densest spot of a scan
	_reset_weather("Scattered")
	var best := Vector3.ZERO
	var best_d := 0.0
	var base := Units.ft_to_m(3000.0)
	for x in range(-8000, 8000, 200):
		for y in range(-8000, 8000, 200):
			var d := CloudField.density(Vector3(x, y, base + 300.0), base, 0.5, Vector2.ZERO)
			if d > best_d:
				best_d = d
				best = Vector3(x, y, base + 300.0)
	Props.set_v("fdm/position_enu", best)
	Props.set_v("fdm/agl_m", best.z)
	Props.set_v("weather/turbulence", 0.3)
	w._physics_process(DT)
	var in_scale := Props.get_f("environment/turbulence_scale")
	print("    in cloud (density %.2f): kind %s, turbulence scale %.2f" % [Props.get_f("environment/ac_cloud_density"), Props.get_v("environment/cloud_kind"), in_scale])
	if not Props.get_b("environment/ac_in_cloud") or Props.get_f("environment/ac_cloud_density") < 0.3 or in_scale < 1.9 or Props.get_v("environment/cloud_kind") != "cumulus":
		return "inside the densest cloud: density %.2f scale %.2f kind %s" % [Props.get_f("environment/ac_cloud_density"), in_scale, Props.get_v("environment/cloud_kind")]
	# thermal reaches wind_ned.z
	_reset_weather("Scattered")
	var ex := Vector3.ZERO
	var hi := 0.0
	var c := CloudPhysics.conditions()
	for x in range(-8000, 8000, 250):
		for y in range(-4000, 4000, 250):
			var t := CloudConvection.thermal(Vector3(x, y, 500.0), 500.0, c, 0.0)
			if t > hi:
				hi = t
				ex = Vector3(x, y, 500.0)
	Props.set_v("fdm/position_enu", ex)
	Props.set_v("fdm/agl_m", 500.0)
	Props.set_v("weather/turbulence", 0.0)
	w.free()
	w = Weather.new()  # fresh turbulence state: the in-cloud step above left some
	w._ready()
	w._physics_process(DT)
	ws = Props.get_v("environment/wind_ned")
	w.free()
	Props.set_v("weather/convection", 0.0)
	Props.set_v("weather/storms", 0.0)
	if Props.get_f("environment/thermal_mps") < 1.0 or absf(ws.z + Props.get_f("environment/thermal_mps")) > 0.01:
		return "thermal %.2f m/s should be wind_ned.z %.2f (up = negative)" % [Props.get_f("environment/thermal_mps"), ws.z]
	return ""


func test_storm_in_weather_publishes_and_shears() -> String:
	var snap := _snapshot()
	var r := _storm_in_weather()
	Props.restore(snap)
	return r


func _storm_in_weather() -> String:
	_reset_weather("Monsoon")
	var base := Units.ft_to_m(1200.0)
	var cl := CloudStorm.cell(_first_cell(0.7).x, _first_cell(0.7).y, 0.7, 7)
	var w := Weather.new()
	w._ready()
	var ctr: Vector2 = CloudStorm.center_at(cl, 0.0, Vector2.ZERO)
	Props.set_v("fdm/position_enu", Vector3(ctr.x, ctr.y, 400.0))
	Props.set_v("fdm/agl_m", 400.0)
	Props.set_v("fdm/tas_mps", 50.0)
	w._physics_process(DT)
	var ws: Vector3 = Props.get_v("environment/wind_ned")
	print("    storm core: intensity %.2f, core %s, downdraft wind_ned.z %.1f, turbulence scale %.1f, shear %.1f" % [Props.get_f("environment/storm_intensity"), Props.get_b("environment/storm_core"), ws.z, Props.get_f("environment/turbulence_scale"), Props.get_f("environment/storm_shear_mps")])
	var kind: String = Props.get_v("environment/cloud_kind")
	var ok := kind == "cumulonimbus" and Props.get_b("environment/storm_core") and ws.z > 3.0 and Props.get_f("environment/turbulence_scale") > 2.0
	w.free()
	if not ok:
		return "Monsoon storm core: kind %s core %s wind z %.1f scale %.1f" % [kind, Props.get_b("environment/storm_core"), ws.z, Props.get_f("environment/turbulence_scale")]
	# storms 0: nothing
	_reset_weather("Monsoon")
	Props.set_v("weather/storms", 0.0)
	var w2 := Weather.new()
	w2._ready()
	w2._physics_process(DT)
	var calm: float = Props.get_f("environment/storm_intensity")
	w2.free()
	Props.set_v("weather/storms", 0.0)
	Props.set_v("weather/convection", 0.0)
	return "" if calm == 0.0 else "storms 0 still gives storm intensity %.2f" % calm


## Hands-off C172 east through a thermal vs the same flight in still air.
func _fly(c: Dictionary, y: float, use_thermal: bool, secs: float) -> float:
	var f := FDM.new()
	f.fcs.roll_stability = 0.0
	f.engine.mixture = 1.0
	var tas := 100.0 * KT
	for i in 3:
		f.set_airborne(y, -1000.0, 600.0, PI * 0.5, tas)  # n = y, e = -1000, heading east
		f.prop.rpm = 2300.0
		f.trim_level(tas)
		f.step(1e-4)
		tas *= 100.0 * KT / f.cas
	f.time = 0.0
	var alt0 := f.altitude()
	for i in int(secs / DT):
		var w := 0.0
		if use_thermal:
			var p := Vector3(f.pos_e, f.pos_n, f.altitude())
			w = CloudConvection.thermal(p, f.altitude(), c, CloudField.density(p, c.base_m, c.cover, c.drift))
		f.wind_ned = Vector3(0.0, 0.0, -w)
		f.step(DT * 0.5)
		f.step(DT * 0.5)
	return f.altitude() - alt0


func test_hands_off_c172_gains_altitude_in_a_thermal() -> String:
	var c := Part1.cond("Scattered")
	var best_y := 0.0
	var best_mean := -9.0
	for y in range(-8000, 8000, 250):  # the track (east, 2 km) with the best mean lift at 600 m
		var sum := 0.0
		for k in 41:
			var p := Vector3(-1000.0 + k * 50.0, y, 600.0)
			sum += CloudConvection.thermal(p, 600.0, c, CloudField.density(p, c.base_m, c.cover, c.drift))
		if sum / 41.0 > best_mean:
			best_mean = sum / 41.0
			best_y = y
	var gain := _fly(c, best_y, true, 40.0)
	var still := _fly(c, best_y, false, 40.0)
	print("    hands-off C172, 40 s east over a track averaging %.1f m/s lift: %+.0f m with the thermal, %+.0f m in still air" % [best_mean, gain, still])
	if best_mean < 1.0:
		return "no thermal track found (mean %.2f m/s)" % best_mean
	return "" if gain > still + 15.0 else "thermal gave %+.0f m vs %+.0f m in still air" % [gain, still]
