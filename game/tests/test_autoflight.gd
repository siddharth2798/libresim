extends RefCounted

func test_af_smoke() -> String:
	var r := AfRig.new(250.0, 10000.0, 0.0)
	var t0 := Time.get_ticks_msec()
	print("    start: %.1f kt, %.0f ft, lever %.3f" % [r.kias(), r.alt_ft(), Props.get_f("controls/throttle_1")])
	r.run(20.0)
	print("    hands off 20 s (law, no AP): %.1f kt, %.0f ft, %.0f fpm, pitch %.2f; %d ms" % [r.kias(), r.alt_ft(), r.fpm(), rad_to_deg(r.f.euler().y), Time.get_ticks_msec() - t0])
	return ""
