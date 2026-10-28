extends RefCounted
## The A320's fly-by-wire law (fdm/fbw_*.gd) on the A320's own data (AircraftDef.make with "fcs": {"law":
## "airbus_fbw"}, because aircraft.json arrives with the aircraft): law factory, hands-off flight, load factor
## and roll rate responses, protections, reversion, ground mode, the autopilot interface, the real control
## pipeline and a takeoff with the law on. The C172 keeps direct control (asserted here too).

const A := preload("res://tests/test_fdm_a320.gd")
const KT := 0.514444
const FT := 0.3048
const DT := 1.0 / 60.0


func _def(fcs := true) -> AircraftDef:
	var d: Dictionary = A.DATA.duplicate(true)
	if fcs:
		d["fcs"] = {"law": "airbus_fbw"}
	return AircraftDef.make("a320", d, "res://aircraft/a320")


func _run(f: FDM, seconds: float, dt := DT) -> void:
	for i in int(seconds / dt):
		f.step(dt)


## Clean, gear up, engines running, trimmed in level flight at a CAS (kt) and altitude (ft); the law takes over.
func _cruise(kcas: float, alt_ft: float, flap := 0, gear := false) -> FDM:
	var f := FDM.new(_def())
	f.atmo.update(alt_ft * FT)
	f.fcs.flap_cmd = flap
	f.set_airborne(0.0, 0.0, alt_ft * FT, 0.0, kcas * KT)
	for u in f.units:
		u.warm_start(true)
	f.fcs.gear_cmd = 1 if gear else 0
	f.gear.gear_pos = 1.0 if gear else 0.0
	f.fcs.settle()
	f.trim_level(kcas * KT * sqrt(1.225 / f.atmo.density))
	return f


func _law(f: FDM) -> FbwLaw:
	return f.fcs.law


func _reset_props() -> void:
	for k in ["failures/adr", "failures/adirs", "failures/elac", "failures/hyd_g", "failures/hyd_b", "failures/hyd_y", "failures/fac", "ap/cmd/active"]:
		Props.set_v(k, false)
	Props.set_v("fcs/law_force", -1)
	Props.set_v("ap/cmd/nz_g", 0.0)
	Props.set_v("ap/cmd/roll_rate_dps", 0.0)


# --- law factory ------------------------------------------------------------

func test_fbw_law_factory_and_direct_default() -> String:
	var c172 := FDM.new()
	if c172.fcs.law != null:
		return "the C172 must keep direct control"
	var bare := FDM.new(_def(false))
	if bare.fcs.law != null:
		return "an A320 without aircraft.json fcs.law is direct"
	var f := FDM.new(_def())
	if not f.fcs.law is FbwLaw or _law(f).par.f("nz_max") != 2.5:
		return "airbus_fbw law not installed: %s" % [f.fcs.law]
	var own := _def()
	own.data["fcs"]["nz_max"] = 2.2
	own.data["fcs"]["pitch"] = {"kq": 70.0}
	var g := FDM.new(own)
	var pp: Dictionary = _law(g).par.d.pitch
	return "" if _law(g).par.f("nz_max") == 2.2 and pp.kq == 70.0 and pp.kiq == 120.0 else "aircraft.json fcs must merge over the defaults: %s" % [pp]


# --- hands-off flight -----------------------------------------------------------

func _hands_off(f: FDM, label: String) -> String:
	var a0 := f.altitude()
	var v0 := f.vt
	_run(f, 60.0, 1.0 / 30.0)
	print("    %s hands off 60 s: alt %+.1f m, TAS %.1f -> %.1f, bank %.2f deg, THS %.2f" % [label, f.altitude() - a0, v0, f.vt, rad_to_deg(f.euler().x), f.fcs.stabilizer_deg])
	if f.damage.crashed or absf(f.altitude() - a0) > 40.0 or absf(f.vt - v0) > 0.03 * v0 or absf(rad_to_deg(f.euler().x)) > 2.0:
		return "%s: not holding: alt %+.1f m, TAS %.1f -> %.1f, bank %.1f" % [label, f.altitude() - a0, v0, f.vt, rad_to_deg(f.euler().x)]
	return ""


func test_fbw_hands_off_level_250kt_fl100() -> String:
	return _hands_off(_cruise(250.0, 10000.0), "250 kt FL100")


func test_fbw_hands_off_level_mach_05() -> String:
	var f := FDM.new(_def())
	f.atmo.update(3048.0)
	var tas := 0.5 * f.atmo.sound_speed
	f.set_airborne(0.0, 0.0, 3048.0, 0.0, tas)
	for u in f.units:
		u.warm_start(true)
	f.fcs.gear_cmd = 0
	f.gear.gear_pos = 0.0
	f.trim_level(tas)
	return _hands_off(f, "M0.5 FL100")


# --- pitch -----------------------------------------------------------------------

func test_fbw_load_factor_step_1_5g() -> String:
	var f := _cruise(250.0, 10000.0)
	var l := _law(f)
	f.fcs.pitch = 0.0 + 0.02 + 0.5 / 1.5 * 0.98  # sidestick for a 0.5 g increment (dead zone 2 %)
	var peak := 0.0
	var t63 := -1.0
	var late: Array[float] = []
	for i in 300:
		f.step(DT)
		peak = maxf(peak, l.s.nz)
		if t63 < 0.0 and l.s.nz >= 1.0 + 0.63 * 0.5:
			t63 = i * DT
		if i > 120:
			late.append(l.s.nz)
	var lo: float = late.min()
	print("    0.5 g step at 250 kt: peak %.3f g, 63 %% after %.2f s, nz over 2-5 s: %.3f..%.3f, alpha %.1f deg" % [peak, t63, lo, late.max(), rad_to_deg(f.alpha)])
	if t63 < 0.0 or t63 > 2.0 or peak > 1.58 or lo < 1.42:
		return "load factor response: 63 %% at %.2f s, peak %.3f, settled low %.3f (want ~1.5 g, t63 under 2 s, no overshoot)" % [t63, peak, lo]
	return ""


func test_fbw_release_holds_flight_path() -> String:
	var f := _cruise(250.0, 10000.0)
	f.fcs.pitch = 0.4
	_run(f, 3.0)
	f.fcs.pitch = 0.0
	var g0 := rad_to_deg(_law(f).s.gamma)
	_run(f, 8.0)
	var g1 := rad_to_deg(_law(f).s.gamma)
	var nz := _law(f).s.nz
	print("    stick released at gamma %.1f deg: gamma %.1f after 8 s, nz %.3f, THS %.2f" % [g0, g1, nz, f.fcs.stabilizer_deg])
	return "" if absf(g1 - g0) < 2.0 and absf(nz - 1.0) < 0.06 else "flight path not held: gamma %.1f -> %.1f, nz %.3f" % [g0, g1, nz]


func test_fbw_alpha_protection_full_aft_stick() -> String:
	var f := _cruise(200.0, 10000.0)
	var l := _law(f)
	f.fcs.pitch = 1.0
	var amax := 0.0
	var seen := false
	for i in 720:  # 12 s
		f.step(DT)
		amax = maxf(amax, f.alpha)
		seen = seen or Props.get_b("fcs/prot/alpha")
	print("    full aft stick clean from 200 kt: max alpha %.2f deg (prot %.1f, max %.2f, stall %.2f), CAS %.0f kt, nz %.2f, floor %s" % [
		rad_to_deg(amax), rad_to_deg(l.prot.a_prot), rad_to_deg(l.prot.a_max), rad_to_deg(l.prot.a_stall), f.cas / KT, l.s.nz, Props.get_b("fcs/alpha_floor")])
	if f.damage.crashed or not seen:
		return "alpha protection not active (or crashed)"
	if amax > l.prot.a_max + deg_to_rad(0.8) or amax >= l.prot.a_stall:
		return "alpha %.2f exceeded alpha max %.2f / stall %.2f" % [rad_to_deg(amax), rad_to_deg(l.prot.a_max), rad_to_deg(l.prot.a_stall)]
	return "" if Props.get_b("fcs/alpha_floor") else "alpha floor flag not set at alpha max"


func test_fbw_nz_limit_clean_and_flaps() -> String:
	var f := _cruise(300.0, 10000.0)
	f.fcs.pitch = 1.0
	var peak := 0.0
	for i in 150:
		f.step(DT)
		peak = maxf(peak, _law(f).s.nz)
	var lim := _law(f).prot.nz_limits(_law(f).s, _law(f).par)
	print("    full aft at 300 kt: peak nz %.2f (limit %.1f clean)" % [peak, lim.y])
	return "" if peak < 2.7 and peak > 2.0 and lim.y == 2.5 else "nz peak %.2f, limit %.1f" % [peak, lim.y]


func test_fbw_landing_configuration_is_stable() -> String:
	var f := _cruise(140.0, 3000.0, 5, true)  # FULL, gear down
	f.fcs.flap_deg = 35.0
	f.fcs.slat_deg = 27.0
	f.trim_level(140.0 * KT * sqrt(1.225 / f.atmo.density))
	var l := _law(f)
	var a0 := f.altitude()
	_run(f, 10.0, 1.0 / 30.0)
	var drift := f.altitude() - a0
	var al := rad_to_deg(f.alpha)
	f.fcs.pitch = 0.02 + 0.25 / 1.5 * 0.98  # 0.25 g
	var peak := 0.0
	for i in 240:
		f.step(DT)
		peak = maxf(peak, l.s.nz)
	f.fcs.pitch = 0.0
	_run(f, 4.0)
	print("    FULL 140 kt gear down: 10 s hands off %+.1f m (alpha %.1f deg), 0.25 g step peak %.3f (ref 1.089 with its slower loop), prot %.1f / max %.1f deg, nz limit %.1f" % [drift, al, peak, rad_to_deg(l.prot.a_prot), rad_to_deg(l.prot.a_max), l.prot.nz_limits(l.s, l.par).y])
	return "" if absf(drift) < 15.0 and peak > 1.15 and peak < 1.32 and l.prot.nz_limits(l.s, l.par).y == 2.0 and not f.damage.crashed else "landing config: drift %.1f, peak %.3f" % [drift, peak]


func test_fbw_flare_mode_bias() -> String:
	var l := FbwLaw.new()
	l.par = FbwParams.from_def(_def())
	var s := l.s
	s.gear_pos = 1.0
	s.lever = 0.0
	s.ra_ft = 100.0
	var hi := l.pitch.demand(s, l.par, l.prot, 0.0)
	s.ra_ft = 20.0
	var mid := l.pitch.demand(s, l.par, l.prot, 0.0)
	s.ra_ft = 5.0
	var low := l.pitch.demand(s, l.par, l.prot, 0.0)
	var on: bool = l.pitch.flare
	s.lever = 0.8  # thrust up (go-around): no flare law
	l.pitch.demand(s, l.par, l.prot, 0.0)
	print("    flare mode: nz demand %.3f at 100 ft, %.3f at 20 ft, %.3f at 5 ft; go-around lever: flare %s" % [hi, mid, low, l.pitch.flare])
	return "" if absf(hi - 1.0) < 1e-6 and mid < 0.97 and low < mid and absf(low - 0.9) < 0.01 and on and not l.pitch.flare else "flare bias"


# --- roll and yaw ----------------------------------------------------------------

func _roll_step(stick: float) -> Array:
	var f := _cruise(250.0, 10000.0)
	f.fcs.roll = stick
	var pk := 0.0
	var t63 := -1.0
	var rate_ss := 0.0
	for i in 150:  # 2.5 s
		f.step(DT)
		var p := rad_to_deg(f.w_b.x)
		pk = maxf(pk, p)
		if t63 < 0.0 and p >= 0.63 * 15.0 * stick:
			t63 = i * DT
	rate_ss = rad_to_deg(f.w_b.x)
	return [rate_ss, t63, pk, f]


func test_fbw_roll_rate_per_stick() -> String:
	var h := _roll_step(0.5)
	var u := _roll_step(1.0)
	print("    roll rate: half stick %.2f deg/s (ref 7.35), full %.2f deg/s (ref 15.0), 63 %% after %.2f / %.2f s (ref 0.4-0.5)" % [h[0], u[0], h[1], u[1]])
	if absf(h[0] - 7.35) > 1.2 or absf(u[0] - 15.0) > 1.8 or u[1] > 0.9 or u[2] > 17.5:
		return "roll rate half %.2f full %.2f (peak %.2f), t63 %.2f" % [h[0], u[0], u[2], u[1]]
	return ""


func test_fbw_bank_hold_when_released() -> String:
	var f := _cruise(250.0, 10000.0)
	f.fcs.roll = 1.0
	while rad_to_deg(f.euler().x) < 15.0:
		f.step(DT)
	f.fcs.roll = 0.0
	_run(f, 2.0)
	var b0 := rad_to_deg(f.euler().x)
	var a0 := f.altitude()
	_run(f, 6.0)
	var b1 := rad_to_deg(f.euler().x)
	print("    released near 15 deg: bank %.1f after 2 s, %.1f after 8 s, altitude %+.0f m in the turn, beta %.2f deg" % [b0, b1, f.altitude() - a0, rad_to_deg(f.beta)])
	if absf(b1 - b0) > 2.5 or b0 < 12.0 or absf(f.altitude() - a0) > 30.0 or absf(rad_to_deg(f.beta)) > 1.5:
		return "bank not held / not coordinated: %.1f -> %.1f, alt %+.0f, beta %.2f" % [b0, b1, f.altitude() - a0, rad_to_deg(f.beta)]
	return ""


func test_fbw_30_degree_turn_holds_altitude() -> String:
	var f := _cruise(250.0, 10000.0)
	f.fcs.roll = 0.6
	while rad_to_deg(f.euler().x) < 28.0:
		f.step(DT)
	f.fcs.roll = 0.0
	_run(f, 3.0)
	var a0 := f.altitude()
	var lo := 0.0
	var hi := 0.0
	for i in 720:  # 12 s hands off
		f.step(DT)
		lo = minf(lo, f.altitude() - a0)
		hi = maxf(hi, f.altitude() - a0)
	var b := rad_to_deg(f.euler().x)
	print("    30 deg turn 12 s hands off: bank %.1f deg, altitude %+.1f..%+.1f m (limit 30 m = 100 ft), nz %.3f" % [b, lo, hi, _law(f).s.nz])
	return "" if lo > -30.0 and hi < 30.0 and absf(b - 30.0) < 5.0 else "turn: bank %.1f, altitude %+.1f..%+.1f m" % [b, lo, hi]


func test_fbw_bank_limit() -> String:
	var f := _cruise(300.0, 10000.0)
	f.fcs.roll = 1.0
	var bmax := 0.0
	for i in 480:  # 8 s
		f.step(DT)
		bmax = maxf(bmax, rad_to_deg(f.euler().x))
	print("    full roll stick held 8 s at 300 kt: max bank %.1f deg (limit 67), bank protection %s, alpha %.1f deg" % [bmax, Props.get_b("fcs/prot/bank"), rad_to_deg(f.alpha)])
	return "" if bmax > 62.0 and bmax < 69.0 and Props.get_b("fcs/prot/bank") else "bank %.1f deg" % bmax


func test_fbw_rudder_travel_limit_and_damper() -> String:
	var f := _cruise(150.0, 3000.0)
	f.fcs.yaw = 1.0
	f.step(DT)
	var slow: float = f.fcs.cmd["rudder"]
	var fast := _law(f).yaw.travel_deg(_law(f).par, 300.0, true)
	var none := _law(f).yaw.travel_deg(_law(f).par, 300.0, false)
	f.fcs.yaw = 0.0  # damper: a yaw rate kick is opposed
	f.w_b.z = 0.1
	f.step(DT)
	var damp: float = f.fcs.cmd["rudder"]
	print("    rudder travel: %.1f deg at 150 kt, %.1f deg at 300 kt (%.1f without FAC), damper vs yaw rate 0.1: %.2f deg" % [slow, fast, none, damp])
	return "" if absf(slow - 25.0) < 0.5 and fast < 12.0 and fast > 5.0 and none == 25.0 and damp < -1.0 else "rudder travel / damper"
