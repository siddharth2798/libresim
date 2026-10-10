extends RefCounted
## M3 flight-model test cards vs the C172S POH (2550 lb, sea level, ISA, no wind).
## Each card prints its measurement; tolerance is +/-10 % unless noted.

const KT := 0.514444
const FT := 0.3048


static func _check(name: String, got: float, want: float, tol := 0.10) -> String:
	print("    %s: got %.1f, POH %.1f" % [name, got, want])
	if absf(got - want) > absf(want) * tol:
		return "%s %.1f outside %.0f%% of %.1f" % [name, got, tol * 100.0, want]
	return ""


func test_fdm_static_rpm() -> String:
	var h := FdmHarness.new()
	h.f.set_on_ground(0, 0, 0)
	h.mode = "none"
	h.f.prop.rpm = 1000.0
	h.f.engine.throttle = 1.0
	h.f.gear.brake_left = 1.0
	h.f.gear.brake_right = 1.0
	h.run(15.0)
	if absf(h.f.pos_n) > 2.0:
		return "brakes did not hold: moved %.1f m" % h.f.pos_n
	return _check("static RPM", h.f.prop.rpm, 2360.0, 0.03)


func test_fdm_mag_drop() -> String:
	var h := FdmHarness.new()
	h.f.set_on_ground(0, 0, 0)
	h.mode = "none"
	h.f.gear.brake_left = 1.0
	h.f.gear.brake_right = 1.0
	h.f.prop.rpm = 1700.0
	h.f.engine.throttle = 0.42
	h.run(10.0)
	var both := h.f.prop.rpm
	h.f.engine.magnetos = 1
	h.run(5.0)
	var drop := both - h.f.prop.rpm
	print("    run-up %.0f RPM, left-mag drop %.0f RPM" % [both, drop])
	if drop < 50.0 or drop > 150.0:
		return "mag drop %.0f RPM not in 50..150" % drop
	return ""


func test_fdm_takeoff_roll() -> String:
	var h := FdmHarness.new()
	var f := h.f
	f.set_on_ground(0, 0, 0)
	h.mode = "none"
	f.fcs.flap_cmd = 1  # 10 deg, POH short-field config
	f.prop.rpm = 2300.0
	f.engine.throttle = 1.0
	h.run(1.0)  # settle on the gear
	var n0 := f.pos_n
	var roll := [0.0]
	h.run(60.0, func():
		f.fcs.yaw = clampf(-3.0 * f.euler().z if f.euler().z < PI else 3.0 * (TAU - f.euler().z), -1, 1)
		f.fcs.pitch = 0.6 if h.kcas() > 51.0 else 0.0
		if not f.gear.wow:
			roll[0] = f.pos_n - n0
			return true
		return false)
	if roll[0] <= 0.0:
		return "never lifted off"
	return _check("ground roll ft", roll[0] / FT, 960.0, 0.15)


func test_fdm_climb_vy() -> String:
	var h := FdmHarness.new()
	h.f.set_airborne(0, 0, 300, 0, 74 * KT, 0.12)
	h.f.prop.rpm = 2400.0
	h.f.engine.throttle = 1.0
	h.mode = "speed"
	h.target_cas = 74 * KT
	h.run(40.0)
	var alt0 := h.f.altitude()
	h.run(60.0)
	var roc := (h.f.altitude() - alt0) / FT
	print("    at %.0f KCAS, %.0f RPM" % [h.kcas(), h.f.prop.rpm])
	return _check("climb fpm", roc, 730.0, 0.12)


func test_fdm_cruise_75() -> String:
	var h := FdmHarness.new(2550.0)
	var f := h.f
	f.set_airborne(0, 0, 6000 * FT, 0, 110 * KT)
	f.prop.rpm = 2500.0
	h.mode = "alt"
	h.target_alt = 6000 * FT
	f.engine.mixture = 0.82  # leaned for cruise (best power)
	var target := 0.75 * f.engine.max_power
	f.engine.throttle = 0.8
	h.run(120.0, func():
		f.engine.throttle = clampf(f.engine.throttle + (target - f.engine.power_w) * 2e-8, 0.2, 1.0)
		return false)
	print("    %.0f hp, %.0f RPM, alt %.0f ft" % [f.engine.power_w / 745.7, f.prop.rpm, f.altitude() / FT])
	return _check("cruise KTAS", h.ktas(), 122.0)


func _stall(flap: int) -> float:
	var h := FdmHarness.new()
	var f := h.f
	f.set_airborne(0, 0, 1000, 0, 75 * KT)
	f.fcs.flap_cmd = flap
	f.engine.throttle = 0.0
	f.prop.rpm = 900.0
	h.mode = "alt"
	h.target_alt = 1000
	var min_cas := [999.0]
	h.run(90.0, func():
		min_cas[0] = minf(min_cas[0], h.kcas())
		return f.altitude() < 1000.0 - 50.0 * FT)  # stalled when height can't be held
	return min_cas[0]


func test_fdm_stall_clean() -> String:
	return _check("clean stall KCAS", _stall(0), 53.0)


func test_fdm_stall_full_flaps() -> String:
	return _check("flaps 30 stall KCAS", _stall(3), 48.0)


func test_fdm_glide() -> String:
	var h := FdmHarness.new()
	var f := h.f
	f.set_airborne(0, 0, 2000, 0, 68 * KT)
	f.engine.magnetos = 0
	f.engine.throttle = 0.0
	f.prop.rpm = 1200.0
	h.mode = "speed"
	h.target_cas = 68 * KT
	h.run(30.0)
	var a0 := f.altitude()
	var d0 := Vector2(f.pos_n, f.pos_e)
	h.run(90.0)
	var ratio := Vector2(f.pos_n, f.pos_e).distance_to(d0) / (a0 - f.altitude())
	print("    windmilling %.0f RPM" % f.prop.rpm)
	return _check("glide ratio", ratio, 9.0, 0.15)


func test_fdm_hands_off_stability() -> String:
	# Trim in level flight with the autopilot, transfer elevator to trim, release.
	var h := FdmHarness.new()
	var f := h.f
	f.set_airborne(0, 0, 1000, 0, 100 * KT)
	f.prop.rpm = 2400.0
	f.engine.throttle = 0.65
	h.mode = "alt"
	h.target_alt = 1000
	h.run(60.0)
	f.fcs.pitch_trim = f.fcs.pitch
	f.fcs.pitch = 0.0
	h.mode = "none"
	var a0 := f.altitude()
	var worst := [0.0]
	h.run(60.0, func():
		worst[0] = maxf(worst[0], absf(f.altitude() - a0))
		f.fcs.roll = clampf(-2.0 * f.euler().x - 0.5 * f.w_b.x, -1, 1)  # wings leveller only
		return false)
	print("    max altitude deviation %.0f ft over 60 s hands-off" % (worst[0] / FT))
	if worst[0] / FT > 150.0:
		return "phugoid too large or divergent: %.0f ft" % (worst[0] / FT)
	return ""
