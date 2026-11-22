extends RefCounted
## Turbulence levels and rotary gusts (world/turbulence.gd), cloud turbulence floors (world/cloud_field.gd), storm
## updrafts (world/cloud_storm.gd), rain shafts (world/cloud_convection.gd), cloud towers and icing above the freezing
## level. Terrain flow (ridge lift, lee waves, rotor): tests/test_terrain_flow.gd.

const FT := 0.3048
const KT := 0.514444
const Physics := preload("res://tests/test_weather_physics.gd")


func test_turbulence_levels_follow_mil_f_8785c() -> String:
	# above 2000 ft: the exceedance curves, ft/s at 1750 and 3750 ft (light 1e-2, moderate 1e-3, severe 1e-5)
	var rows := [[6.9, 7.4], [9.6, 10.6], [17.6, 23.0]]
	for k in 3:
		var lv := (k + 1) / 3.0
		var s := Turbulence.sigma_w(lv, 2500.0 * FT)
		var want: float = lerpf(rows[k][0], rows[k][1], (2500.0 - 1750.0) / 2000.0) * FT
		if absf(s - want) > 0.01:
			return "level %.2f at 2500 ft: sigma %.2f m/s, want %.2f" % [lv, s, want]
	print("    sigma_w at 3750 ft: light %.2f, moderate %.2f, severe %.2f m/s; at 500 ft: %.2f / %.2f / %.2f" % [
		Turbulence.sigma_w(1.0 / 3.0, 3750.0 * FT), Turbulence.sigma_w(2.0 / 3.0, 3750.0 * FT), Turbulence.sigma_w(1.0, 3750.0 * FT),
		Turbulence.sigma_w(1.0 / 3.0, 500.0 * FT), Turbulence.sigma_w(2.0 / 3.0, 500.0 * FT), Turbulence.sigma_w(1.0, 500.0 * FT)])
	# below 1000 ft: 0.1 W20 with W20 = 15 / 30 / 45 kt
	for k in 3:
		var lv := (k + 1) / 3.0
		if absf(Turbulence.sigma_w(lv, 100.0) - 0.1 * 15.0 * (k + 1) * KT) > 1e-3:
			return "level %.2f near the ground: sigma %.3f, want 0.1 x %d kt" % [lv, Turbulence.sigma_w(lv, 100.0), 15 * (k + 1)]
	if Turbulence.sigma_w(0.0, 3000.0) != 0.0 or Turbulence.level_name(0.0) != "None" or Turbulence.level_name(0.7) != "Moderate":
		return "level 0 must be none; names"
	# no growth with the wind aloft: the same sigma in a 10 kt and a 60 kt wind at 3000 m
	return Physics._guard(func():
		var sig := []
		for aloft in [10.0, 60.0]:
			Physics._weather(aloft, 0.0, 0.5, 3000.0)
			var w := Physics._new_weather()
			w._physics_process(1.0 / 120.0)
			sig.append(Props.get_f("environment/turbulence_sigma"))
			w.free()
		return "" if absf(sig[0] - sig[1]) < 1e-6 and absf(sig[0] - Turbulence.sigma_w(0.5, 3000.0)) < 1e-6 else "sigma in 10 / 60 kt aloft: %s" % [sig])


func test_convective_cloud_is_never_smooth() -> String:
	if CloudField.turbulence_floor("cumulus", 0.6, 0.0) < 1.2 or CloudField.turbulence_floor("cumulonimbus", 0.6, 0.0) < 3.0:
		return "cloud floors: cumulus %.2f, cumulonimbus %.2f" % [CloudField.turbulence_floor("cumulus", 0.6, 0.0), CloudField.turbulence_floor("cumulonimbus", 0.6, 0.0)]
	if CloudField.turbulence_floor("cumulus", 0.0, 0.0) != 0.0 or CloudField.turbulence_floor("stratiform", 0.6, 0.0) > 0.5:
		return "clear air has no floor; stratus is gentle"
	var c := Physics.Part1.cond("Scattered")
	for x in range(-8000, 8000, 100):
		var p := Vector3(x, 2000.0, c.base_m + 300.0)
		if CloudField.density(p, c.base_m, c.cover, c.drift) > 0.4:
			var r := CloudPhysics.evaluate(c, p, p.z, 0.0)
			return "" if float(r.turb_floor) >= 1.2 else "inside cumulus the turbulence floor is %.2f m/s" % float(r.turb_floor)
	return "no dense cumulus found on the line"


func test_rotary_gusts_sigma_and_tick_rate() -> String:
	var res := {}
	for span in [10.9, 35.7]:
		for hz in [120.0, 30.0]:
			var t := Turbulence.new()
			t.rng.seed = 17
			var dt: float = 1.0 / hz
			var ps := PackedFloat64Array()
			var qs := PackedFloat64Array()
			var rs := PackedFloat64Array()
			for i in int(1200.0 * hz):
				t.step(dt, 300.0, 60.0, 1.5, Vector3(5.0, 0.0, 0.0), 0.3, span)
				ps.append(t.pqr.x)
				qs.append(t.pqr.y)
				rs.append(t.pqr.z)
			res[[span, hz]] = [Physics._std(ps), Physics._std(qs), Physics._std(rs)]
	var lw: float = Turbulence.scales(300.0).lw
	var tw := lw / 60.0
	for span in [10.9, 35.7]:
		var a: Array = res[[span, 120.0]]
		var b: Array = res[[span, 30.0]]
		var sp: float = 1.9 / sqrt(lw * span) * 1.5
		var tq: float = 4.0 * span / (PI * 60.0)
		var sq := 1.5 / (60.0 * sqrt(tq * (tw + tq)))  # var(q) = sigma_w^2 / (V^2 tau_q (tau_w + tau_q)) for this filter
		print("    span %.1f m: sigma_p %.4f (want %.4f), sigma_q %.4f (want %.4f), sigma_r %.4f rad/s; at 30 Hz %.4f %.4f %.4f" % [span, a[0], sp, a[1], sq, a[2], b[0], b[1], b[2]])
		if absf(a[0] / sp - 1.0) > 0.1 or absf(a[1] / sq - 1.0) > 0.15:
			return "span %.1f: sigma_p %.4f vs %.4f, sigma_q %.4f vs %.4f" % [span, a[0], sp, a[1], sq]
		for j in 3:
			if absf(b[j] / a[j] - 1.0) > 0.1:
				return "span %.1f: 30 Hz %s vs 120 Hz %s" % [span, b, a]
	if res[[35.7, 120.0]][0] >= res[[10.9, 120.0]][0] * 0.7:
		return "the A320's span should damp the roll gusts well below the Cessna's"
	return ""


func test_storm_updraft_core_is_strong_and_smooth() -> String:
	var base := Units.ft_to_m(1200.0)
	var top := CloudField.top_m(base, CloudField.CUMULONIMBUS)
	var z := base + 0.45 * (top - base)
	var best := 0.0
	var below := 0.0
	var worst_step := 0.0
	for i in range(-2, 3):
		for j in range(-2, 3):
			var cl: Dictionary = CloudStorm.cell(i, j, 0.9, 7)
			if not cl.on:
				continue
			var c: Vector2 = cl.center
			var rad: float = cl.radius
			for a in range(0, 360, 15):
				var prev := INF
				for k in 400:
					var d := k * 3.0 * rad / 400.0
					var p := c + Vector2(cos(deg_to_rad(a)), sin(deg_to_rad(a))) * d
					var s := CloudStorm.sample(Vector3(p.x, p.y, z), z, 0.0, Vector2.ZERO, 0.9, base)
					var up: float = -(s.wind as Vector3).z
					best = maxf(best, up)
					if prev != INF:
						worst_step = maxf(worst_step, absf(up - prev))
					prev = up
					var lo := CloudStorm.sample(Vector3(p.x, p.y, base - 100.0), base - 100.0, 0.0, Vector2.ZERO, 0.9, base)
					below = maxf(below, -(lo.wind as Vector3).z)
			break
		if best > 0.0:
			break
	print("    storm updraft mid-cloud %.1f m/s, under the base %.1f m/s, biggest change between samples %.2f m/s" % [best, below, worst_step])
	if best < 10.0 or best > 20.0:
		return "updraft core %.1f m/s, want 10-20" % best
	if below > 5.0 or worst_step > 1.0:
		return "inflow under the base %.1f m/s (want gentle), step %.2f m/s" % [below, worst_step]
	return ""


func test_rain_shafts_only_under_heavy_convective_rain() -> String:
	var hi := 0.0
	for x in range(0, 9000, 60):
		var p := Vector3(x, 1234.0, 200.0)
		if CloudConvection.rain_shaft(p, 200.0, 600.0, 0.2, CloudField.CUMULUS, Vector2.ZERO) != 0.0:
			return "a shaft under light rain"
		if CloudConvection.rain_shaft(p, 200.0, 600.0, 1.0, CloudField.STRATIFORM, Vector2.ZERO) != 0.0:
			return "a shaft under stratiform rain"
		if CloudConvection.rain_shaft(Vector3(x, 1234.0, 1200.0), 1200.0, 600.0, 1.0, CloudField.CUMULUS, Vector2.ZERO) != 0.0:
			return "a shaft above the cloud base"
		hi = maxf(hi, CloudConvection.rain_shaft(p, 200.0, 600.0, 1.0, CloudField.CUMULUS, Vector2.ZERO))
	print("    strongest rain-shaft downdraft under heavy cumulus rain: %.1f m/s" % hi)
	return "" if hi >= 1.0 and hi <= 5.0 else "rain shaft %.1f m/s, want 1-5" % hi


## Monsoon at 30 C: the freezing level is near 4.6 km; the cumulonimbus towers reach it, so the icing setting matters.
func test_monsoon_towers_reach_the_freezing_level_and_ice() -> String:
	var c := Physics.Part1.cond("Monsoon")
	var z := 6000.0  # about -9 C on a 30 C day
	var t_c := 30.0 - AtmosphereISA.L * z
	for x in range(0, 9000, 150):
		var p := Vector3(x, 3000.0, z)
		var r := CloudPhysics.evaluate(c, p, z, 0.0)
		if bool(r.in_cloud):
			var rate := IcingRates.cloud_rate(float(r.density), str(r.kind), float(Session.WEATHER.Monsoon.icing), t_c, 120.0)
			print("    Monsoon tower at 6 km (%.0f C): density %.2f, top %.0f m, icing %.2f %%/s" % [t_c, float(r.density), float(r.top_m), rate * 100.0])
			return "" if rate > 0.0 and float(r.top_m) > 9000.0 else "tower at 6 km: icing rate %.5f, top %.0f m" % [rate, float(r.top_m)]
	return "no cumulonimbus tower at 6 km on an 9 km line"
