extends RefCounted
## Saved flight situations (core/situation.gd, core/situation_fdm.gd): the FDM state
## survives a capture -> JSON file text -> apply round trip, and a restored FDM keeps
## flying exactly like the original.

const KT := 0.514444


## A C172 that has been flying for a few seconds (cruise, partly burnt fuel, some flap).
func _flying() -> FdmHarness:
	var h := FdmHarness.new(2300.0)
	var f := h.f
	f.set_airborne(1200.0, -800.0, 900.0, 0.6, 100 * KT)
	f.prop.rpm = 2300.0
	f.trim_level(100 * KT)
	f.wind_ned = Vector3(3.0, -2.0, 0.0)
	f.mb.tanks[0].contents_kg = 50.0
	f.mb.tanks[1].contents_kg = 41.0
	f.mb.update()
	f.fcs.flap_cmd = 1
	h.mode = "alt"
	h.target_alt = 950.0
	h.run(4.0)
	return h


## Through JSON text, as on disk (full-precision floats, ints come back as floats).
func _via_json(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d, "", false, true))


func _diff(a: FDM, b: FDM) -> String:
	var dp := Vector3(a.pos_n - b.pos_n, a.pos_e - b.pos_e, a.pos_d - b.pos_d).length()
	var dv := (a.v_b - b.v_b).length()
	var dq := a.q.angle_to(b.q)
	var drpm := absf(a.prop.rpm - b.prop.rpm)
	var dfuel := absf(a.mb.tanks[0].contents_kg - b.mb.tanks[0].contents_kg) + absf(a.mb.tanks[1].contents_kg - b.mb.tanks[1].contents_kg)
	var dflap := absf(a.fcs.flap_deg - b.fcs.flap_deg)
	return "pos %.2e m, vel %.2e m/s, att %.2e rad, rpm %.2e, fuel %.2e kg, flap %.2e deg" % [dp, dv, dq, drpm, dfuel, dflap] \
		if dp > 1e-6 or dv > 1e-5 or dq > 1e-5 or drpm > 1e-6 or dfuel > 1e-9 or dflap > 1e-6 else ""


func test_situation_fdm_round_trip() -> String:
	var a := _flying()
	var d := _via_json(Situation.capture_fdm(a.f))
	var b := FdmHarness.new(2550.0)  # perturbed: different place, attitude, weight, engine state
	b.f.set_on_ground(-5000.0, 3000.0, 2.0)
	b.f.prop.rpm = 0.0
	b.f.fcs.flap_deg = 30.0
	Situation.apply_fdm(b.f, d)
	var err := _diff(a.f, b.f)
	print("    after %.1f s: alt %.1f m, %.0f KCAS, %.0f rpm, fuel %.2f kg, flap %.1f deg -> restored %s" % [
		a.f.time, a.f.altitude(), a.f.cas / KT, a.f.prop.rpm, a.f.mb.fuel_kg(), a.f.fcs.flap_deg, "exactly" if err == "" else err])
	if absf(b.f.mb.mass - a.f.mb.mass) > 1e-6:
		return "mass differs: %.3f vs %.3f kg" % [b.f.mb.mass, a.f.mb.mass]
	if b.f.engine.magnetos != 3 or typeof(b.f.engine.magnetos) != TYPE_INT:
		return "magnetos not restored as int"
	return "" if err == "" else "restored state differs: " + err


func test_situation_fdm_determinism() -> String:
	var a := _flying()
	var d := _via_json(Situation.capture_fdm(a.f))
	var b := FdmHarness.new()
	Situation.apply_fdm(b.f, d)
	# both continue hands-off with the same fixed inputs for 10 s
	for h in [a, b]:
		h.mode = "none"
		h.f.fcs.pitch = 0.05
		h.f.fcs.roll = -0.1
		h.f.fcs.yaw = 0.0
		h.run(10.0)
	var err := _diff(a.f, b.f)
	print("    10 s after restore: original vs restored %s (alt %.1f m)" % ["identical" if err == "" else err, a.f.altitude()])
	return "" if err == "" else "diverged: " + err


func test_situation_fdm_damage() -> String:
	var a := FdmHarness.new()
	a.f.set_on_ground(0.0, 0.0, 0.0)
	var nose: Dictionary = a.f.gear.contacts.filter(func(c): return c.name == "NOSE")[0]
	a.f.damage._fail_gear(nose, "nose gear collapsed (test)")
	a.f.damage.flaps_jammed = true
	a.f.damage.hard_landings = 2
	var b := FdmHarness.new()
	Situation.apply_fdm(b.f, _via_json(Situation.capture_fdm(a.f)))
	var nb: Dictionary = b.f.gear.contacts.filter(func(c): return c.name == "NOSE")[0]
	var dm := b.f.damage
	print("    collapsed nose gear, jammed flaps, 2 hard landings -> restored: %s, events %s" % [dm.gear_failed.keys(), dm.events])
	if not dm.gear_failed.has("NOSE") or nb.wheel or not nb.pos.is_equal_approx(nose.pos):
		return "collapsed gear not restored"
	if not dm.flaps_jammed or not dm.structure_damaged or dm.hard_landings != 2:
		return "damage flags not restored"
	return "" if Array(dm.events) == Array(a.f.damage.events) else "events differ"
