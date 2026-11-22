extends RefCounted
## Wind and turbulence physics (world/weather.gd, world/turbulence.gd, world/cloud_storm.gd, world/cloud_convection.gd):
## MIL-F-8785C low-altitude scales and sigma ratio, tick-rate independence, the airspeed the filters use, zero-mean
## gusts that fade aloft, the vertical wind taper above the wheels, no step at a storm cell's edge, thermals that carry
## as much air down as up, and rain at the aircraft. Pause and save / load: tests/test_weather_hold.gd.

const KT := 0.514444
const FT := 0.3048
const Part1 := preload("res://tests/test_cloud_weather.gd")


## Runs f with every Prop put back afterwards (later suites share the tree); returns f's error text.
static func _guard(f: Callable) -> String:
	var snap: Dictionary = Props._p.duplicate(true)
	SimHold.publish(false, false)
	var err: String = f.call()
	Props._p = snap
	return err


## Calm, clear weather with the given wind, gust peak and turbulence slider; the aircraft at agl, flying at tas.
static func _weather(wind_kt: float, gust_kt: float, turb: float, agl: float, tas := 50.0) -> void:
	for k in Weather.DEFAULTS:
		Props.set_v("weather/" + k, Weather.DEFAULTS[k])
	Props.set_v("weather/wind_dir_deg", 270.0)
	Props.set_v("weather/aloft_dir_deg", 270.0)
	Props.set_v("weather/wind_kt", wind_kt)
	Props.set_v("weather/aloft_kt", wind_kt)
	Props.set_v("weather/gust_kt", gust_kt)
	Props.set_v("weather/turbulence", turb)
	Props.set_v("weather/cloud_cover", 0.0)
	Props.set_v("weather/wind_table", [])
	Props.set_v("fdm/position_enu", Vector3(0.0, 0.0, agl))
	Props.set_v("fdm/agl_m", agl)
	Props.set_v("fdm/tas_mps", tas)
	Props.set_v("fdm/wheel_depth_m", 0.0)
	for k in ["fdm/track_rad", "fdm/groundspeed_mps", "fdm/vs_mps", "environment/wind_ned"]:
		Props._p.erase(k)


static func _new_weather(seed := 11) -> Weather:
	var w := Weather.new()
	w._ready()
	w._rng.seed = seed
	return w


static func _std(a: PackedFloat64Array) -> float:
	var s := 0.0
	var s2 := 0.0
	for v in a:
		s += v
		s2 += v * v
	var m := s / a.size()
	return sqrt(maxf(s2 / a.size() - m * m, 0.0))


## Time constant (s) of a first-order process from its lag-one autocorrelation r: tau = -dt / ln(r) (low-noise estimate).
static func _lag1_tau(a: PackedFloat64Array, dt: float) -> float:
	var c0 := 0.0
	var c1 := 0.0
	for i in a.size() - 1:
		c0 += a[i] * a[i]
		c1 += a[i] * a[i + 1]
	return -dt / log(clampf(c1 / c0, 1e-6, 0.999999))


## Lag (s) where the autocorrelation first falls below 1/e: the filter's time constant.
static func _corr_time(a: PackedFloat64Array, dt: float) -> float:
	var v0 := 0.0
	for x in a:
		v0 += x * x
	for lag in range(1, a.size() / 4):
		var c := 0.0
		for i in range(0, a.size() - lag, 2):
			c += a[i] * a[i + lag]
		if 2.0 * c / v0 < exp(-1.0):
			return lag * dt
	return -1.0


func test_turbulence_low_altitude_scales_match_mil_f_8785c() -> String:
	for h_ft in [10.0, 100.0, 300.0, 700.0, 1000.0]:
		var k: float = 0.177 + 0.000823 * h_ft
		var sc := Turbulence.scales(h_ft * FT)
		var lu: float = h_ft / pow(k, 1.2) * FT
		if absf(sc.lu - lu) > 0.01 or absf(sc.lv - lu) > 0.01 or absf(sc.lw - h_ft * FT) > 0.01 or absf(sc.ratio - 1.0 / pow(k, 0.4)) > 1e-4:
			return "at %d ft: L_u %.1f L_v %.1f L_w %.1f m ratio %.3f, want %.1f / %.1f / %.1f / %.3f" % [h_ft, sc.lu, sc.lv, sc.lw, sc.ratio, lu, lu, h_ft * FT, 1.0 / pow(k, 0.4)]
	if Turbulence.scales(0.5).lw != Turbulence.scales(10.0 * FT).lw:
		return "height not clamped at 10 ft"
	var mid := Turbulence.scales(1500.0 * FT)
	var high := Turbulence.scales(3000.0 * FT)
	if absf(mid.lu - 1375.0 * FT) > 0.01 or mid.lw != mid.lu or mid.ratio != 1.0 or absf(high.lu - 1750.0 * FT) > 0.01 or high.lw != high.lu:
		return "1500 ft %s, 3000 ft %s: want 1375 ft then 1750 ft on every axis, equal sigma" % [mid, high]
	# the filters: at 98 ft (30 m) sigma_u / sigma_w and each time constant L / V, as the formulas say
	var t := Turbulence.new()
	t.rng.seed = 5
	var dt := 1.0 / 120.0
	var us := PackedFloat64Array()
	var ws := PackedFloat64Array()
	var east := Vector3(0.0, 5.0, 0.0)  # wind toward the east: u is the east component
	for i in int(900.0 / dt):
		var g := t.step(dt, 30.0, 50.0, 1.0, east)
		if i % 4 == 0:
			us.append(g.y)
			ws.append(g.z)
	var want := Turbulence.scales(30.0)
	var ratio := _std(us) / _std(ws)
	var tu := _corr_time(us, dt * 4.0)
	var tw := _corr_time(ws, dt * 4.0)
	print("    30 m AGL: sigma_u / sigma_w %.2f (want %.2f), tau_u %.2f s (want %.2f), tau_w %.2f s (want %.2f)" % [ratio, want.ratio, tu, want.lu / 50.0, tw, want.lw / 50.0])
	if absf(ratio / want.ratio - 1.0) > 0.12 or absf(tu / (want.lu / 50.0) - 1.0) > 0.25 or absf(tw / (want.lw / 50.0) - 1.0) > 0.2:
		return "filters at 30 m: ratio %.2f tau_u %.2f tau_w %.2f" % [ratio, tu, tw]
	return ""


func test_turbulence_is_tick_rate_independent() -> String:
	return _guard(func():
		var out := []
		for hz in [120.0, 30.0]:
			_weather(10.0, 0.0, 0.5, 30.0)
			var w := _new_weather(21)
			var zs := PackedFloat64Array()
			var hs := PackedFloat64Array()
			for i in int(400.0 * hz):
				w._physics_process(1.0 / hz)
				zs.append(w._turb.z)
				hs.append(w._turb.y)
			w.free()
			out.append([_std(zs), _std(hs), _lag1_tau(zs, 1.0 / hz)])
		print("    120 Hz: sigma_w %.3f sigma_h %.3f tau_w %.3f s | 30 Hz: %.3f %.3f %.3f s" % [out[0][0], out[0][1], out[0][2], out[1][0], out[1][1], out[1][2]])
		for j in 3:
			if absf(out[1][j] / out[0][j] - 1.0) > 0.08:
				return "120 Hz %s vs 30 Hz %s" % [out[0], out[1]]
		return "")


## The time constants use the airspeed through the mean air mass (ground velocity against wind minus turbulence),
## not fdm/tas_mps, which includes the turbulence.
func test_turbulence_time_constant_uses_air_mass_speed() -> String:
	return _guard(func():
		_weather(0.0, 0.0, 0.5, 30.0, 5.0)  # tas says 5 m/s ...
		Props.set_v("fdm/groundspeed_mps", 50.0)  # ... but the aircraft moves at 50 m/s through calm air
		Props.set_v("fdm/track_rad", 0.0)
		Props.set_v("fdm/vs_mps", 0.0)
		var w := _new_weather(4)
		var zs := PackedFloat64Array()
		var dt := 1.0 / 120.0
		for i in int(300.0 / dt):
			w._physics_process(dt)
			zs.append(w._turb.z)
		w.free()
		var tau := _corr_time(zs, dt)
		var want: float = Turbulence.scales(30.0).lw / 50.0
		return "" if absf(tau / want - 1.0) < 0.25 else "tau_w %.2f s, want %.2f s (L_w / 50 m/s)" % [tau, want])


func test_gusts_and_lulls_keep_the_set_mean_and_fade_aloft() -> String:
	return _guard(func():
		_weather(20.0, 30.0, 0.0, 10.0)
		var w := _new_weather(3)
		var dt := 0.05
		var sum := 0.0
		var lo := 99.0
		var hi := 0.0
		var n := int(3600.0 / dt)
		for i in n:
			w._physics_process(dt)
			var v: Vector3 = Props.get_v("environment/wind_ned")
			var kt := Vector2(v.x, v.y).length() / KT
			sum += kt
			lo = minf(lo, kt)
			hi = maxf(hi, kt)
		w.free()
		print("    20G30 kt at 10 m, 1 h: mean %.2f kt, min %.1f, max %.1f" % [sum / n, lo, hi])
		if absf(sum / n - 20.0) > 0.8 or hi < 27.0 or lo > 16.0:
			return "20G30: mean %.2f kt (want 20), max %.1f, min %.1f" % [sum / n, hi, lo]
		_weather(20.0, 30.0, 0.0, 2000.0)
		var a := _new_weather(3)
		lo = 99.0
		hi = 0.0
		for i in int(600.0 / dt):
			a._physics_process(dt)
			var v: Vector3 = Props.get_v("environment/wind_ned")
			lo = minf(lo, v.length() / KT)
			hi = maxf(hi, v.length() / KT)
		a.free()
		return "" if hi - lo < 0.2 else "gusts still %.1f kt wide at 2000 m AGL" % (hi - lo))


## The vertical wind goes to zero smoothly over the last 10 m above the lowest wheel (C172 and A320 alike).
func test_vertical_wind_tapers_smoothly_into_the_flare() -> String:
	return _guard(func():
		for depth in [1.2, 4.0]:  # wheel below the CG: about a C172 and an A320 on the gear
			_weather(10.0, 0.0, 1.0, 20.0)
			Props.set_v("fdm/wheel_depth_m", depth)
			var w := _new_weather(8)
			var prev := -1.0
			for i in 400:
				var agl: float = depth + 16.0 - i * 0.04
				Props.set_v("fdm/agl_m", agl)
				w._physics_process(1.0 / 120.0)
				var wz: Vector3 = Props.get_v("environment/wind_ned")
				var k: float = wz.z / w._turb.z if absf(w._turb.z) > 1e-4 else prev
				if prev >= 0.0 and absf(k - prev) > 0.03:
					w.free()
					return "wheel depth %.1f m: vertical wind factor jumps %.2f -> %.2f at %.2f m AGL" % [depth, prev, k, agl]
				prev = k
				if agl - depth > 10.5 and absf(k - 1.0) > 1e-4:
					w.free()
					return "full vertical wind expected 10 m above the wheels (factor %.2f)" % k
			w.free()
			if prev > 1e-4:
				return "wheels on the ground (depth %.1f m): vertical wind factor %.3f" % [depth, prev]
		return "")


func test_storm_cell_edge_has_no_wind_step() -> String:
	var worst := 0.0
	for i in range(-3, 4):
		for j in range(-3, 4):
			var cl: Dictionary = CloudStorm.cell(i, j, 0.7, 7)
			if not cl.on:
				continue
			var c: Vector2 = cl.center
			var rad: float = cl.radius
			var prev := Vector3.ZERO
			for k in 3200:
				var d := k * (3.2 * rad / 3200.0)  # ~1-3 m steps out past 2.6 R
				var s := CloudStorm.sample(Vector3(c.x + d, c.y, 50.0), 50.0, 0.0, Vector2.ZERO, 0.7, 400.0)
				if k > 0:
					worst = maxf(worst, ((s.wind as Vector3) - prev).length())
				prev = s.wind
	print("    biggest wind change between neighbouring samples across storm cells: %.3f m/s" % worst)
	return "" if worst < 0.1 else "storm wind steps %.2f m/s between samples ~2 m apart" % worst


func test_thermals_carry_as_much_air_down_as_up() -> String:
	for preset in ["Fair", "Scattered", "Broken"]:
		var c: Dictionary = Part1.cond(preset)
		for frac in [0.3, 0.6, 0.9]:
			var alt: float = c.base_m * frac
			var s := 0.0
			var n := 0
			for x in range(0, 9000, 150):  # one whole noise tile
				for y in range(0, 9000, 150):
					s += CloudConvection.thermal(Vector3(x, y, alt), alt, c, 0.0)
					n += 1
			if absf(s / n) > 0.08:
				return "%s at %.0f m: area-mean vertical wind %+.2f m/s" % [preset, alt, s / n]
	return ""


## environment/ac_precip is the rain where the aircraft is; environment/precip (the camera's, for the visuals) is not
## what the airframe feels.
func test_rain_effects_use_the_aircraft_not_the_camera() -> String:
	return _guard(func():
		_weather(5.0, 0.0, 0.0, 3000.0)
		Props.set_v("weather/precip", 1.0)
		Props.set_v("weather/cloud_cover", 1.0)
		Props.set_v("weather/cloud_base_ft", 1000.0)  # tops near 1200 m: the aircraft at 3000 m is above the rain
		Props.set_v("environment/precip", 1.0)  # the camera is down in it
		var w := _new_weather()
		w._physics_process(1.0 / 120.0)
		var above := Props.get_f("environment/ac_precip")
		Props.set_v("fdm/position_enu", Vector3(0.0, 0.0, 100.0))
		Props.set_v("fdm/agl_m", 100.0)
		Props.set_v("environment/precip", 0.0)  # camera above the cloud, the aircraft under it
		w._physics_process(1.0 / 120.0)
		var below := Props.get_f("environment/ac_precip")
		w.free()
		if above != 0.0 or below < 0.8:
			return "ac_precip above the cloud %.2f (want 0), under it %.2f (want heavy)" % [above, below]
		var h := FdmHarness.new()
		var fx := EnvironmentEffects.new(Icing.params(h.f.def))
		Props.set_v("environment/precip", 1.0)
		Props.set_v("environment/ac_precip", 0.0)
		fx.update(h.f)
		var dry := fx.rain
		Props.set_v("environment/precip", 0.0)
		Props.set_v("environment/ac_precip", 1.0)
		fx.update(h.f)
		var wet := fx.rain
		fx.apply(h.f, 0.0, 0.0)
		return "" if dry == 0.0 and wet == 1.0 else "airframe rain: camera in rain %.2f (want 0), aircraft in rain %.2f (want 1)" % [dry, wet])
