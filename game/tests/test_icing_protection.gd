extends RefCounted
## Protection against ice and what blocked probes do: pitot heat (C172), the alt-air lever, the A320's wing and
## engine anti-ice with bleed air, the pitot-static system. Conditions and rates: tests/test_icing.gd.

const I := preload("res://tests/test_icing.gd")
const T_ICE := 263.15  # -10 C static


func test_icing_pitot_heat_protects_c172() -> String:
	return I._guard(func():
		var ic := I._icing()
		I._run(ic, 400.0)
		var open := Props.get_b("icing/pitot_blocked")
		ic.reset()
		Props.set_v("controls/electrical/pitot_heat", true)
		Props.set_v("systems/electrical/powered", true)
		I._run(ic, 600.0)
		var heated := ic.pitot
		var blocked_hot := Props.get_b("icing/pitot_blocked")
		Props.set_v("systems/electrical/powered", false)  # no bus power: the heater does nothing
		I._run(ic, 400.0)
		var dead := Props.get_b("icing/pitot_blocked")
		Props.set_v("systems/electrical/powered", true)
		I._run(ic, 40.0)
		var cleared := not Props.get_b("icing/pitot_blocked") and ic.pitot < 0.1
		ic.free()
		if not open:
			return "unheated pitot should block in cloud within 400 s"
		if heated > 0.02 or blocked_hot:
			return "heated pitot iced: %.2f" % heated
		if not dead:
			return "pitot heat without bus power should not protect"
		if not cleared:
			return "restoring heat should clear the probe in 40 s"
		return "")


func test_icing_pitot_static_blocked_by_ice() -> String:
	return I._guard(func():
		for k in ["atmosphere/pressure_pa", "fdm/alpha_rad"]:
			Props._p.erase(k)
		var ps := PitotStatic.new()
		ps._ready()
		Props.set_v("atmosphere/pressure_pa", 80000.0)
		Props.set_v("fdm/cas_mps", 40.0)
		Props.set_v("fdm/tas_mps", 45.0)
		ps._physics_process(0.01)
		var p0 := Props.get_f("systems/pitot_static/pitot_pa")
		Props.set_v("icing/pitot_blocked", true)
		ps._physics_process(0.01)
		Props.set_v("fdm/cas_mps", 70.0)  # a climb in cloud: the airspeed rises but the frozen pitot cannot see it
		ps._physics_process(0.01)
		var frozen := Props.get_f("systems/pitot_static/pitot_pa")
		Props.set_v("atmosphere/pressure_pa", 75000.0)  # ...and the pressure falls: pitot + drain blocked reads like an altimeter
		ps._physics_process(0.01)
		Props.set_v("icing/pitot_blocked", false)
		ps._physics_process(0.01)
		var free := Props.get_f("systems/pitot_static/pitot_pa")
		# static port: frozen at 0.9, but the alternate static source bypasses it
		Props.set_v("atmosphere/pressure_pa", 80000.0)
		Props.set_v("icing/static_blocked", true)
		ps._physics_process(0.01)
		Props.set_v("atmosphere/pressure_pa", 70000.0)
		ps._physics_process(0.01)
		var stat_frozen := Props.get_f("systems/pitot_static/static_pa")
		Props.set_v("systems/alternate_static", true)
		ps._physics_process(0.01)
		var stat_alt := Props.get_f("systems/pitot_static/static_pa")
		ps.free()
		if absf(frozen - p0) > 1.0:
			return "pitot pressure should freeze when blocked by ice: %.0f -> %.0f Pa" % [p0, frozen]
		if free <= 75000.0 + 100.0 or free == frozen:
			return "pitot should recover when the ice clears: %.0f Pa" % free
		if absf(stat_frozen - 80000.0) > 1.0 or absf(stat_alt - (70000.0 + PitotStatic.ALT_STATIC_DP)) > 1.0:
			return "static: frozen %.0f (want 80000), alternate source %.0f" % [stat_frozen, stat_alt]
		return "")


func test_icing_alt_air_lever_and_a320_anti_ice() -> String:
	return I._guard(func():
		var c := I._icing("c172")
		I._run(c, 400.0)
		var loose: float = c.engines[0]
		Props.set_v("controls/alt_air", true)
		I._run(c, 120.0)
		var fixed: float = c.engines[0]
		c.free()
		Props.set_v("controls/alt_air", false)
		# A320 at about FL200 on a hot day (-10 C) in dense cumulus at 200 m/s
		I._cond(T_ICE, 1.0, "cumulus", 0.7, 200.0)
		for i in 2:
			Props.set_v("engines/%d/running" % (i + 1), true)
		var a := I._icing("a320")
		I._run(a, 300.0)
		var bare := [a.airframe, a.engines[0], a.pitot]
		var detected := Props.get_b("icing/ice_detected")
		Props.set_v("controls/anti_ice/wing", true)
		Props.set_v("controls/anti_ice/eng_1", true)
		I._run(a, 120.0)
		var pen := Props.get_f("icing/bleed_penalty")
		var protected := [a.airframe, a.engines[0], a.engines[1]]
		var eng2_ice: float = a.engines[1]
		for i in 2:
			Props.set_v("engines/%d/running" % (i + 1), false)  # no bleed air from stopped engines
		I._run(a, 300.0)
		var no_bleed: float = a.airframe
		a.free()
		print("    A320 5 min in cloud: airframe %.2f, inlet %.2f; anti-ice 2 min later: %.2f / %.2f, bleed penalty %.3f" % [bare[0], bare[1], protected[0], protected[1], pen])
		if loose < 0.3 or fixed > 0.05:
			return "alt air: inlet ice %.2f unprotected, %.2f with the lever" % [loose, fixed]
		if bare[0] < 0.3 or bare[1] < 0.3 or not detected or bare[2] > 0.05:
			return "A320 without anti-ice: airframe %.2f, inlet %.2f, detected %s, probe %.2f (heated: probe stays clean)" % [bare[0], bare[1], detected, bare[2]]
		if protected[0] > 0.05 or protected[1] > 0.05 or eng2_ice < 0.3 or pen < 0.03 or pen > 0.05:
			return "anti-ice: airframe %.2f, inlet 1 %.2f, inlet 2 (off) %.2f, bleed penalty %.3f" % [protected[0], protected[1], eng2_ice, pen]
		if no_bleed < 0.3:
			return "wing anti-ice needs a running engine: airframe %.2f" % no_bleed
		return "")
