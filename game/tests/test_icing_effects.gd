extends RefCounted
## What ice and rain do: airframe drag / CLmax / stall speed, a flight at the same power, engine power and
## thrust (inlet ice, bleed air), heavy rain. The conditions and protection: tests/test_icing.gd.

const I := preload("res://tests/test_icing.gd")
const KT := 0.514444


func test_icing_airframe_effect_drag_clmax_and_stall() -> String:
	return I._guard(func():
		var h := FdmHarness.new()
		var f := h.f
		var base_amax := f.aero.alpha_max
		var fx := EnvironmentEffects.new(Icing.params(f.def))
		var q := 0.5 * 1.225 * 51.0 * 51.0
		var inp := {"vt": 51.0, "alpha": 0.05, "alphadot": 0.0, "beta": 0.0, "qbar": q, "agl": 500.0, "rho": 1.225, "u": 51.0,
			"p": 0.0, "q": 0.0, "r": 0.0, "v_induced": 0.0, "elevator": 0.0, "aileron": 0.0, "rudder": 0.0, "flap_deg": 0.0,
			"mach": 0.15, "temperature": 288.15, "ctx": {}}
		var d0: float = f.aero.evaluate(inp)[0].x
		var peak := func() -> float:
			var best := 0.0
			for i in range(0, 40):
				inp.alpha = i * 0.01
				best = maxf(best, f.aero.evaluate(inp)[0].z)
			return best
		var lift0: float = peak.call()
		fx.apply(f, 1.0, 0.0)
		inp.alpha = 0.05
		var d1: float = f.aero.evaluate(inp)[0].x
		var lift1: float = peak.call()
		var amax1 := f.aero.alpha_max
		var drag_up := d1 / d0
		var vs_up := sqrt(lift0 / lift1)
		var cd0_pct: float = (d1 - d0) / (q * float(f.cfg.metrics.wing_area_m2) / 4.4482216) / 0.031  # added CD vs the C172's CD0 (about 0.031)
		print("    full ice: drag x%.2f at 100 KIAS, CLmax x%.2f, stall speed x%.2f, alpha_max %.3f -> %.3f (CD0 + %.0f %%)" % [
			drag_up, lift1 / lift0, vs_up, base_amax, amax1, cd0_pct * 100.0])
		fx.apply(f, 0.0, 0.0)
		var amax0 := f.aero.alpha_max
		inp.alpha = 0.05
		var d2: float = f.aero.evaluate(inp)[0].x
		if drag_up < 1.15 or drag_up > 1.6:
			return "drag at full ice x%.2f (want 1.15..1.6)" % drag_up
		if lift1 / lift0 > 0.84 or lift1 / lift0 < 0.6:
			return "CLmax at full ice x%.2f (want 0.60..0.84)" % (lift1 / lift0)
		if vs_up < 1.10 or amax1 >= base_amax * 0.95 or amax0 != base_amax or d2 != d0:
			return "stall speed x%.2f, alpha_max %.3f / restored %.3f, restored drag %s" % [vs_up, amax1, amax0, d2 == d0]
		return "")


func _cruise(ice: float) -> Array:
	var h := FdmHarness.new()
	var f := h.f
	f.set_airborne(0, 0, 1000.0, 0, 100 * KT)
	f.prop.rpm = 2300.0
	f.engine.throttle = 0.6
	f.engine.mixture = 0.9
	h.mode = "alt"
	h.target_alt = 1000.0
	var fx := EnvironmentEffects.new()
	fx.apply(f, ice, 0.0)
	h.run(60.0)
	return [h.kcas(), f.altitude(), f.pos_n, f.pos_e, f.v_b.x, f.alpha]


func test_icing_iced_c172_slower_at_same_power_and_clean_is_identical() -> String:
	return I._guard(func():
		var clean := _cruise(0.0)
		var again := _cruise(0.0)
		var iced := _cruise(1.0)
		print("    same power, 60 s: clean %.1f KCAS, iced %.1f KCAS, alpha %.3f -> %.3f" % [clean[0], iced[0], clean[5], iced[5]])
		if clean != again:
			return "inactive effects must leave the flight identical: %s vs %s" % [clean, again]
		if iced[0] > clean[0] - 5.0 or iced[5] <= clean[5]:
			return "iced aircraft should fly slower (%.1f vs %.1f KCAS) at a higher alpha" % [iced[0], clean[0]]
		return "")


func test_icing_iced_stall_speed_rises_in_flight() -> String:
	return I._guard(func():
		var vs := []
		for ice in [0.0, 1.0]:
			var h := FdmHarness.new()
			var f := h.f
			var fx := EnvironmentEffects.new()
			fx.apply(f, ice, 0.0)
			f.set_airborne(0, 0, 1000, 0, 75 * KT)
			f.engine.throttle = 0.0
			f.prop.rpm = 900.0
			h.mode = "alt"
			h.target_alt = 1000
			var min_cas := [999.0]
			h.run(90.0, func():
				min_cas[0] = minf(min_cas[0], h.kcas())
				return f.altitude() < 1000.0 - 50.0 * 0.3048)
			vs.append(min_cas[0])
		print("    stall KCAS clean %.1f, iced %.1f" % [vs[0], vs[1]])
		if vs[1] < vs[0] * 1.08:
			return "iced stall %.1f KCAS vs clean %.1f: should be at least 8 %% higher" % [vs[1], vs[0]]
		return "")


func test_icing_engine_power_scale_piston_and_turbine() -> String:
	return I._guard(func():
		var power := func(ice: float) -> float:
			var h := FdmHarness.new()
			var fx := EnvironmentEffects.new(Icing.params(h.f.def))
			fx.apply(h.f, 0.0, 0.0, [ice])
			h.f.set_airborne(0, 0, 1000.0, 0, 90 * KT)
			h.f.prop.rpm = 2400.0
			h.f.engine.throttle = 1.0
			h.mode = "none"
			h.run(4.0)
			return h.f.engine.power_w
		var p0: float = power.call(0.0)
		var p1: float = power.call(1.0)
		var jet := FDM.new(AircraftDef.load_def("a320"))
		jet.set_airborne(0, 0, 6000.0, 0, 200.0)
		for u in jet.units:
			u.warm_start(true)
			u.engine.throttle = 0.8
		var thrust := func(ice: float, bleed: float) -> Array:
			var fx := EnvironmentEffects.new(Icing.params(jet.def))
			fx.apply(jet, 0.0, 0.0, [ice, 0.0], [bleed, 0.0])
			for i in 120 * 12:  # the EGT takes about 4 s to follow
				jet.step(1.0 / 120.0)
			return [jet.units[0].engine.thrust_n, jet.units[0].engine.egt_k]
		var c: Array = thrust.call(0.0, 0.0)
		for i in 120 * 20:
			jet.step(1.0 / 120.0)
		c = thrust.call(0.0, 0.0)
		var ic: Array = thrust.call(1.0, 0.0)
		var bl: Array = thrust.call(0.0, 0.05)
		print("    piston %.0f -> %.0f W at full inlet ice; turbine thrust %.0f N clean, %.0f N iced (EGT +%.0f K), %.0f N with bleed" % [p0, p1, c[0], ic[0], ic[1] - c[1], bl[0]])
		if p1 > p0 * 0.85 or p1 < p0 * 0.6:
			return "piston power %.0f -> %.0f W (want a 15..40 %% loss)" % [p0, p1]
		if ic[0] > c[0] * 0.9 or ic[1] <= c[1] + 5.0 or bl[0] > c[0] * 0.97 or bl[0] < c[0] * 0.92:
			return "turbine thrust %.0f / iced %.0f (EGT %.0f -> %.0f) / bleed %.0f" % [c[0], ic[0], c[1], ic[1], bl[0]]
		return "")


func test_icing_heavy_rain_small_lift_loss_and_drag() -> String:
	return I._guard(func():
		var h := FdmHarness.new()
		var fx := EnvironmentEffects.new(Icing.params(h.f.def))
		fx.apply(h.f, 0.0, 0.5)
		var light := fx.active
		fx.apply(h.f, 0.0, 0.95)
		var heavy := fx.active
		var cl := fx.cl_loss
		var cd := fx.cd_add
		var jet := FDM.new(AircraftDef.load_def("a320"))
		var fj := EnvironmentEffects.new(Icing.params(jet.def))
		fj.apply(jet, 0.0, 0.95)
		var n1 := jet.units[0].engine.n1_scale
		fx.apply(h.f, 0.0, 0.0)
		if light or not heavy or cl < 0.01 or cl > 0.06 or cd <= 0.0 or cd > 0.003:
			return "rain 0.5 active %s, 0.95 active %s, lift loss %.3f, CD %.4f" % [light, heavy, cl, cd]
		if n1 >= 1.0 or n1 < 0.98 or fx.active:
			return "turbine N1 scale %.3f in heavy rain, clean again: %s" % [n1, not fx.active]
		return "")
