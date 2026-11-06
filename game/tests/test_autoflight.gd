extends RefCounted

func _air(alt_m: float) -> AfInputs:
	var i := AfInputs.new()
	i.dt = 0.1
	i.powered = true
	i.wow = false
	i.ra_m = 3000.0
	i.alt_m = alt_m
	i.cas = 130.0
	i.tas = 200.0
	i.vs_mps = 0.0
	i.gs_mps = 200.0
	i.f.fd = true
	i.f.ap1 = true
	i.f.alt = alt_m
	i.f.spd = 130.0
	return i


func test_af_managed_vertical() -> String:
	var logic := AfLogic.new({})
	var i := _air(3048.0)
	logic.update(i)
	if not logic.ap1 or logic.vert.mode != "ALT":
		return "engage %s %s" % [logic.ap1, logic.vert.mode]
	i.f.alt = 10668.0
	i.f.vs_mgd = true
	i.f.select = "MANAGED"
	logic.update(i)
	if logic.vert.mode != "CLB":
		return "climb %s" % logic.vert.mode
	i.f.select = ""
	i.f.alt = 1524.0
	logic.vert.set_mode("V/S")
	logic.update(i)
	if logic.vert.mode != "DES":
		return "descent from a managed altitude change %s" % logic.vert.mode
	var level := AfLogic.new({})
	var j := _air(3048.0)
	level.update(j)
	level.vert.set_mode("V/S")
	j.f.vs_mgd = true
	j.f.select = "MANAGED"
	level.update(j)
	if level.vert.mode != "ALT":
		return "managed at the selected altitude went to %s" % level.vert.mode
	return ""


func test_af_smoke() -> String:
	var r := AfRig.new(250.0, 10000.0, 0.0)
	var t0 := Time.get_ticks_msec()
	print("    start: %.1f kt, %.0f ft, lever %.3f" % [r.kias(), r.alt_ft(), Props.get_f("controls/throttle_1")])
	r.run(20.0)
	print("    hands off 20 s (law, no AP): %.1f kt, %.0f ft, %.0f fpm, pitch %.2f; %d ms" % [r.kias(), r.alt_ft(), r.fpm(), rad_to_deg(r.f.euler().y), Time.get_ticks_msec() - t0])
	return ""
