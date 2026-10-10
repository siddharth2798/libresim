extends RefCounted
## M5 instrument tests: pressure instruments, gyro and compass errors.

const DT := 1.0 / 120.0


func _setup() -> Array:
	var h := FdmHarness.new(2300.0)
	var fn := FdmNode.new()
	fn.fdm = h.f
	var nodes := {"ps": PitotStatic.new(), "vac": Vacuum.new(), "air": AirDataInstruments.new(),
		"gyro": GyroInstruments.new(), "comp": MagneticCompass.new()}
	nodes.gyro.fdm = h.f
	nodes.comp.fdm = h.f
	nodes.air._ready()
	Props.set_v("instruments/altimeter/kollsman_inhg", 29.92)
	Props.set_v("failures/vacuum_pump", false)
	return [h, fn, nodes]


func _tick(h: FdmHarness, fn: FdmNode, nodes: Dictionary, seconds: float, fly := true) -> void:
	for i in int(seconds / DT):
		if fly:
			h._autopilot()
			h.f.step(DT)
		fn._publish()
		for k in ["ps", "vac", "air", "gyro", "comp"]:
			nodes[k]._physics_process(DT)


func test_inst_altimeter_and_asi() -> String:
	var s := _setup()
	var h: FdmHarness = s[0]
	h.f.set_airborne(0, 0, 1000.0, 0.0, 50.0)
	h.f.prop.rpm = 2400.0
	h.f.engine.throttle = 0.7
	h.mode = "alt"
	h.target_alt = 1000.0
	_tick(h, s[1], s[2], 20.0)
	var alt := Props.get_f("instruments/altimeter_ft")
	var true_ft := h.f.altitude() / 0.3048
	print("    altimeter %.0f ft (true %.0f), ASI %.1f kt vs CAS %.1f kt" % [alt, true_ft, Props.get_f("instruments/asi_kt"), h.kcas()])
	if absf(alt - true_ft) > 30.0:
		return "altimeter error %.0f ft at standard QNH" % (alt - true_ft)
	Props.set_v("instruments/altimeter/kollsman_inhg", 30.92)  # +1 inHg -> reads ~+1000 ft
	_tick(h, s[1], s[2], 2.0)
	var d := Props.get_f("instruments/altimeter_ft") - alt
	if absf(d - 940.0) > 80.0:
		return "Kollsman +1 inHg changed reading by %.0f ft (expect ~ +940)" % d
	return ""


func test_inst_vsi_lag() -> String:
	var s := _setup()
	var h: FdmHarness = s[0]
	h.f.set_airborne(0, 0, 1000.0, 0.0, 50.0)
	h.f.prop.rpm = 2400.0
	h.f.engine.throttle = 0.7
	h.target_alt = 1000.0
	_tick(h, s[1], s[2], 20.0)
	h.f.engine.throttle = 1.0
	h.target_alt = 1600.0  # step climb
	var true_vs := []
	var vsi := []
	for i in 12:
		_tick(h, s[1], s[2], 0.5)
		true_vs.append(h.fpm())
		vsi.append(Props.get_f("instruments/vsi_fpm"))
	print("    after 1 s: true %.0f / VSI %.0f fpm;  after 6 s: true %.0f / VSI %.0f fpm" % [true_vs[1], vsi[1], true_vs[11], vsi[11]])
	if vsi[1] > true_vs[1] * 0.8:
		return "VSI has no lag"
	if absf(vsi[11] - true_vs[11]) > absf(true_vs[11]) * 0.25 + 50.0:
		return "VSI did not catch up within ~6 s"
	return ""


func test_inst_vacuum_failure_tumbles_ai() -> String:
	var s := _setup()
	var h: FdmHarness = s[0]
	var nodes: Dictionary = s[2]
	h.f.set_airborne(0, 0, 1000.0, 0.0, 50.0)
	h.f.prop.rpm = 2400.0
	h.f.engine.throttle = 0.7
	h.target_alt = 1000.0
	nodes.gyro.start_running()
	_tick(h, s[1], nodes, 10.0)
	var ok_err := absf(Props.get_f("instruments/ai/roll_rad") - h.f.euler().x)
	Props.set_v("failures/vacuum_pump", true)
	_tick(h, s[1], nodes, 300.0)
	var bad_err := absf(Props.get_f("instruments/ai/roll_rad") - h.f.euler().x) + absf(Props.get_f("instruments/ai/pitch_rad") - h.f.euler().y)
	Props.set_v("failures/vacuum_pump", false)
	print("    AI error healthy %.1f deg, 5 min after vacuum failure %.1f deg, flag %s" % [rad_to_deg(ok_err), rad_to_deg(bad_err), Props.get_b("instruments/ai/flag")])
	if rad_to_deg(ok_err) > 1.0:
		return "healthy AI error too big"
	if rad_to_deg(bad_err) < 3.0:
		return "AI did not drift after vacuum failure"
	return ""


func test_inst_compass_northerly_turn_error() -> String:
	var s := _setup()
	var h: FdmHarness = s[0]
	var nodes: Dictionary = s[2]
	h.f.set_airborne(0, 0, 1000.0, 0.0, 50.0)  # heading north
	h.f.prop.rpm = 2400.0
	h.f.engine.throttle = 0.7
	h.target_alt = 1000.0
	_tick(h, s[1], nodes, 10.0)
	nodes.comp.settle()
	# roll into a 20 deg right bank turn and hold it for 3 s
	h.mode = "alt"
	var hdg0 := rad_to_deg(h.f.euler().z)
	for i in int(3.0 / DT):
		h._autopilot()
		h.f.fcs.roll = clampf(2.0 * (deg_to_rad(20.0) - h.f.euler().x) - 0.5 * h.f.w_b.x, -1, 1)
		h.f.step(DT)
		s[1]._publish()
		nodes.comp._physics_process(DT)
	var true_turn := wrapf(rad_to_deg(h.f.euler().z) - hdg0, -180.0, 180.0)
	var compass_turn := wrapf(Props.get_f("instruments/compass_deg") - hdg0, -180.0, 180.0)
	print("    turning from north: true heading change %+.1f deg, compass shows %+.1f deg" % [true_turn, compass_turn])
	if compass_turn > true_turn - 2.0:
		return "no northerly turning error (compass should lag when turning from north)"
	return ""
