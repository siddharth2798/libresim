extends RefCounted
## Weight & balance (aircraft/weight_balance.gd) against the C172S POH envelope.


func _ac() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://aircraft/c172/aircraft.json"))


func _setup(fuel: float, copilot: float, rear: float, bag: float) -> Dictionary:
	return {"fuel_gal": fuel, "copilot_kg": copilot, "rear_kg": rear, "baggage_kg": bag}


func test_wb_pilot_full_fuel() -> String:
	var r := WeightBalance.compute(_ac(), _setup(28.0, 0.0, 0.0, 0.0))
	if r.is_empty():
		return "no result (envelope or config missing)"
	var t: Dictionary = r.takeoff
	print("    pilot + full fuel: %.0f lb, CG %.1f in (landing %.1f in) ok=%s" % [t.lb, t.cg_in, r.landing.cg_in, r.ok])
	if t.cg_in < 37.0 or t.cg_in > 45.0:
		return "CG %.1f in outside plausible 37-45 in" % t.cg_in
	if not r.ok or t.over_max:
		return "light single-pilot loading flagged out of limits"
	return ""


func test_wb_aft_loaded() -> String:
	var r := WeightBalance.compute(_ac(), _setup(5.0, 0.0, 200.0, 54.0))
	var t: Dictionary = r.takeoff
	print("    rear 200 kg + baggage 54 kg, 5 gal/tank: %.0f lb, CG %.1f in, normal=%s" % [t.lb, t.cg_in, t.normal])
	if t.normal and t.cg_in < 46.5:
		return "aft loading neither flagged nor near the 47.3 in aft limit (CG %.1f)" % t.cg_in
	if t.utility:
		return "aft loading accepted in the utility category (aft limit 40.5 in)"
	return ""


func test_wb_overweight() -> String:
	var r := WeightBalance.compute(_ac(), _setup(28.0, 110.0, 200.0, 54.0))
	var t: Dictionary = r.takeoff
	print("    full load: %.0f lb, CG %.1f in, over_max=%s ok=%s" % [t.lb, t.cg_in, t.over_max, r.ok])
	if not t.over_max or r.ok:
		return "%.0f lb not flagged over 2550 lb" % t.lb
	return ""


func test_wb_matches_fdm_cg() -> String:
	var ac := _ac()
	var cfg := WeightBalance.load_config(ac)
	var mb := MassBalance.new(cfg)
	var s := _setup(20.0, 80.0, 120.0, 30.0)
	for t in mb.tanks:
		t.contents_kg = 20.0 * 2.72
	mb.set_payload("Co-Pilot", 80.0)
	mb.set_payload("Left Passenger", 60.0)
	mb.set_payload("Right Passenger", 60.0)
	mb.set_payload("Baggage", 30.0)
	var p := WeightBalance.point(ac, cfg, s, 20.0)
	var fdm_in := mb.cg.x / 0.0254 + float(ac.cg_envelope.datum_offset_in)
	if absf(p.cg_in - fdm_in) > 0.05 or absf(p.kg - mb.mass) > 0.1:
		return "W&B %.2f in / %.1f kg vs FDM %.2f in / %.1f kg" % [p.cg_in, p.kg, fdm_in, mb.mass]
	return ""
