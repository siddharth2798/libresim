extends RefCounted
## Tick rates, gauges, radios and GPS at 30 Hz: each runs at the old 120 Hz and at 30 Hz through the same scripted flight
## (tests/tick_twin.gd) and the published values are compared. A 30 Hz reading is the position / attitude up to 33 ms
## ago, so the tolerances below are what that hold costs at the speed of the scenario, not slack. Radios and GPS skip
## quietly where the nav data is not built (data/processed). See also tests/test_tick_rate.gd and test_tick_systems.gd.

const DT := 1.0 / 120.0
const NM := 1852.0
const FT := 0.3048


## A coordinated 30 degree right turn at 50 m/s, a little nose up: the state of the FDM at time t (shared by both passes).
func _turn(f: FDM, t: float) -> void:
	var rate := 9.80665 * tan(deg_to_rad(30.0)) / 50.0
	f.q = FDM.euler_to_quat(deg_to_rad(30.0), deg_to_rad(3.0), 0.3 + rate * t)
	f.accel_b = Vector3(0.0, 0.0, -9.80665 / cos(deg_to_rad(30.0)))
	f.w_b = Vector3(0.0, rate * sin(deg_to_rad(30.0)), rate * cos(deg_to_rad(30.0)))


func test_tick_gyros_compass_and_turn_coordinator_match() -> String:
	var snap: Dictionary = Props._p.duplicate(true)
	Props.set_v("systems/vacuum/suction_inhg", 5.0)
	Props.set_v("failures/ai", false)
	Props.set_v("failures/hi", false)
	Props.set_v("failures/tc", false)
	Props.set_v("systems/electrical/tc_powered", true)
	var f := FDM.new()
	var inputs := func(t: float): _turn(f, t)
	var gy := func(n: GyroInstruments):
		_turn(f, 0.0)
		n.fdm = f
		n._ai_spin = 1.0
		n._hi_spin = 1.0
		n._hi_drift_dir = 1.0
	var comp := func(n: MagneticCompass):
		_turn(f, 0.0)
		n.fdm = f
		n.settle()
	var keys_g := ["instruments/ai/pitch_rad", "instruments/ai/roll_rad", "instruments/hi_deg", "instruments/tc_rate", "instruments/tc_ball"]
	var pg := TickTwin.twin(GyroInstruments, 60.0, inputs, gy, keys_g)
	var pc := TickTwin.twin(MagneticCompass, 60.0, inputs, comp, ["instruments/compass_deg"])
	Props._p = snap
	var err := TickTwin.check("gyros and turn coordinator, 1 min in a 30 degree turn", pg,
		{"instruments/ai/pitch_rad": 0.003, "instruments/ai/roll_rad": 0.003, "instruments/hi_deg": 0.1,
		"instruments/tc_rate": 0.03, "instruments/tc_ball": 0.03})
	if err != "":
		return err
	return TickTwin.check("magnetic compass in the same turn", pc, {"instruments/compass_deg": 1.5})


## The random drift of a failed gyro: one random step per run adds up as the square root of the runs, so the step is scaled
## (GyroInstruments._noise_k) and the spread after 30 s must be the same at 120 Hz and 30 Hz, not twice as big.
func test_tick_failed_gyro_wanders_the_same_at_any_rate() -> String:
	var snap: Dictionary = Props._p.duplicate(true)
	Props.set_v("systems/vacuum/suction_inhg", 0.0)
	Props.set_v("failures/ai", true)
	Props.set_v("failures/hi", true)
	Props.set_v("systems/electrical/tc_powered", true)
	var f := FDM.new()
	_turn(f, 0.0)
	f.q = Quaternion.IDENTITY
	f.accel_b = Vector3(0.0, 0.0, -9.80665)
	f.w_b = Vector3.ZERO
	var spread := [[], []]  # per rate: heading offsets (deg) and attitude wander (deg) of 24 gyros
	for k in 2:
		for seed_i in 24:
			var g := GyroInstruments.new()
			g.fdm = f
			g._rng.seed = 1000 + seed_i
			g._hi_drift_dir = 0.0
			g._hi_offset = 0.0
			g._ai_spin = 0.0  # seized rotors: spin 0, so the noise is at its largest
			g._hi_spin = 0.0
			if k == 0:
				g._tick = TickRate.new(120.0)
			for i in int(30.0 / DT):
				g._physics_process(DT)
			spread[k].append([rad_to_deg(g._hi_offset), rad_to_deg(g._down.angle_to(Vector3(0, 0, 1)))])
			g.free()
	Props._p = snap
	var rms := func(a: Array, j: int) -> float:
		var s := 0.0
		for r in a:
			s += r[j] * r[j]
		return sqrt(s / a.size())
	var h_ref: float = rms.call(spread[0], 0)
	var h_new: float = rms.call(spread[1], 0)
	var a_ref: float = rms.call(spread[0], 1)
	var a_new: float = rms.call(spread[1], 1)
	print("    failed gyro after 30 s, rms over 24 runs (120 Hz / 30 Hz): heading drift %.2f / %.2f deg, attitude wander %.2f / %.2f deg" % [h_ref, h_new, a_ref, a_new])
	if h_ref < 0.2 or a_ref < 0.5:
		return "the failed gyro must wander (heading %.2f, attitude %.2f deg)" % [h_ref, a_ref]
	if h_new / h_ref > 1.45 or h_new / h_ref < 0.69 or a_new / a_ref > 1.45 or a_new / a_ref < 0.69:
		return "wander differs between rates: heading %.2f vs %.2f deg, attitude %.2f vs %.2f deg (a plain 30 Hz step would double it)" % [h_ref, h_new, a_ref, a_new]
	return ""


func test_tick_engine_gauges_match() -> String:
	var snap: Dictionary = Props._p.duplicate(true)
	Props.set_v("systems/electrical/gauges_powered", true)
	var inputs := func(t: float):
		Props.set_v("engine/rpm", minf(t * 240.0, 2400.0))  # 240 rpm/s for 10 s
		Props.set_v("engine/oil_press_pa", 3.0e5 * minf(t / 10.0, 1.0))
		Props.set_v("engine/fuel_flow_kgs", 0.004 * minf(t / 10.0, 1.0))
		Props.set_v("fuel/left_kg", 80.0 - 0.002 * t)
		Props.set_v("fuel/right_kg", 80.0 - 0.002 * t)
		Props.set_v("systems/vacuum/suction_inhg", minf(t / 4.0, 5.0))
	var pair := TickTwin.twin(EngineInstruments, 30.0, inputs, func(_n): pass,
		["instruments/tach_rpm", "instruments/oil_press_psi", "instruments/fuel_flow_gph", "instruments/fuel_left_gal", "instruments/suction_inhg"])
	Props._p = snap
	return TickTwin.check("engine gauges, start and climb", pair, {"instruments/tach_rpm": 12.0,
		"instruments/oil_press_psi": 0.7, "instruments/fuel_flow_gph": 0.1, "instruments/fuel_left_gal": 0.01, "instruments/suction_inhg": 0.15})


## Pitot-static (30 Hz) feeding the ASI, altimeter and VSI (30 Hz): both at 120 Hz, then both at 30 Hz, in a climb at 5 m/s with the speed rising 1 kt/s.
func test_tick_pitot_static_and_air_data_chain_matches() -> String:
	var snap: Dictionary = Props._p.duplicate(true)
	var keys := ["instruments/asi_kt", "instruments/altimeter_ft", "instruments/vsi_fpm", "systems/pitot_static/pitot_pa"]
	var pair := []
	for ref in [true, false]:
		Props.set_v("instruments/altimeter/kollsman_inhg", 29.92)
		for k in ["failures/pitot_blocked", "failures/static_blocked", "systems/alternate_static", "icing/pitot_blocked", "icing/static_blocked"]:
			Props.set_v(k, false)
		var ps := PitotStatic.new()
		var ad := AirDataInstruments.new()
		ad._ready()
		if ref:
			ps._tick = TickRate.new(120.0)
			ad._tick = TickRate.new(120.0)
		var rows := []
		var t := 0.0
		for i in int(60.0 / DT):
			t += DT
			var alt := 300.0 + 5.0 * t
			Props.set_v("atmosphere/pressure_pa", 101325.0 * pow(1.0 - 2.25577e-5 * alt, 5.25588))
			Props.set_v("fdm/cas_mps", (40.0 + t) * Units.KT)
			Props.set_v("fdm/tas_mps", (42.0 + t) * Units.KT)
			Props.set_v("fdm/alpha_rad", 0.05)
			ps._physics_process(DT)
			ad._physics_process(DT)
			if (i + 1) % 120 == 0:
				var row := {"t": t}
				for k in keys:
					row[k] = Props.get_v(k)
				rows.append(row)
		pair.append(rows)
		ps.free()
		ad.free()
	Props._p = snap
	return TickTwin.check("pitot-static into ASI / altimeter / VSI, 1 min climb", pair, {"instruments/asi_kt": 0.3,
		"instruments/altimeter_ft": 1.5, "instruments/vsi_fpm": 15.0, "systems/pitot_static/pitot_pa": 20.0})


func _nav_setup(n: NavRadios) -> void:
	n._ready()
	Props.set_v("systems/electrical/avionics_powered", true)
	Props.set_v("failures/nav1", false)
	Props.set_v("failures/nav2", false)
	Props.set_v("failures/dme", false)
	Props.set_v("failures/adf", false)


func test_tick_vor_and_dme_match_inbound() -> String:
	var db := NavDatabase.new()
	var v := {}
	for s in db.vors:
		if s.ident == "BBB":
			v = s
	if v.is_empty():
		return ""  # no nav data on this machine
	var snap: Dictionary = Props._p.duplicate(true)
	Props.set_v("controls/nav1/freq_mhz", v.mhz)
	Props.set_v("controls/nav1/obs_deg", 90.0)
	var inputs := func(t: float):  # inbound at 70 m/s, 3 nm north of the 090 radial, from 30 nm out
		Props.set_v("fdm/position_enu", Vector3(v.x + 30.0 * NM - 70.0 * t, v.y + 3.0 * NM, 6000.0 * FT))
		Props.set_v("fdm/heading_rad", deg_to_rad(270.0))
	var pair := TickTwin.twin(NavRadios, 200.0, inputs, _nav_setup,
		["avionics/nav1/cdi", "avionics/nav1/radial_deg", "avionics/nav1/dme_nm", "avionics/nav1/valid", "avionics/nav1/to_from", "avionics/adf/valid"], 1.0, 0.5 + 2.0 * DT)  # samples 2 ticks after a 30 Hz run: the held value

	Props._p = snap
	return TickTwin.check("VOR / DME, 200 s inbound at 70 m/s", pair, {"avionics/nav1/cdi": 0.02, "avionics/nav1/radial_deg": 0.05, "avionics/nav1/dme_nm": 0.002})


func test_tick_ils_localizer_and_glideslope_match() -> String:
	var db := NavDatabase.new()
	var s := {}
	for i in db.ils:
		if i.ident == "IBB27":
			s = i
	if s.is_empty():
		return ""
	var snap: Dictionary = Props._p.duplicate(true)
	Props.set_v("controls/nav2/freq_mhz", s.mhz)
	var th := Vector2(s.threshold.x, s.threshold.y)
	var back := -Vector2(sin(deg_to_rad(s.course_true)), cos(deg_to_rad(s.course_true)))
	var gs := Vector2(s.gs.x, s.gs.y)
	var inputs := func(t: float):  # final from 8 nm at 70 m/s, 150 m left of the centreline, a little above the 3 degree path
		var p := th + back * (8.0 * NM - 70.0 * t) + Vector2(-back.y, back.x) * 150.0
		var alt: float = s.gs.h + tan(deg_to_rad(3.0)) * p.distance_to(gs) + 20.0
		Props.set_v("fdm/position_enu", Vector3(p.x, p.y, alt))
		Props.set_v("fdm/heading_rad", deg_to_rad(s.course_true))
	var pair := TickTwin.twin(NavRadios, 120.0, inputs, _nav_setup,
		["avionics/nav2/cdi", "avionics/nav2/gs", "avionics/nav2/gs_valid", "avionics/nav2/valid", "avionics/nav2/dme_nm"], 1.0, 0.5 + 2.0 * DT)

	Props._p = snap
	return TickTwin.check("ILS localizer and glide slope, 2 min of final", pair,
		{"avionics/nav2/cdi": 0.02, "avionics/nav2/gs": 0.03, "avionics/nav2/dme_nm": 0.002})


func test_tick_gps_leg_and_sequencing_match() -> String:
	var db := NavDatabase.new()
	var a = db.position_of("VAPO")
	var b = db.position_of("VABB")
	if a == null or b == null:
		return ""
	var snap: Dictionary = Props._p.duplicate(true)
	Props.set_v("systems/electrical/avionics_powered", true)
	Props.set_v("failures/gps", false)
	Props.set_v("fdm/groundspeed_mps", 70.0)
	var setup := func(n: Gps):
		n.db = db
		Props.set_v("controls/gps/target", "VAPO")
		Props.set_v("controls/gps/route_next", ["VABB"])
	var inputs := func(t: float):  # north to VAPO from 10 nm south, half a nm east of the line; the GPS flips to VABB when 1 nm out
		Props.set_v("fdm/position_enu", Vector3(a.x + 0.5 * NM, a.y - 10.0 * NM + 70.0 * t, 1000.0))
	var pair := TickTwin.twin(Gps, 260.0, inputs, setup, ["avionics/gps/dist_nm", "avionics/gps/brg_mag", "avionics/gps/xtk_nm",
		"avionics/gps/ident", "controls/gps/target"], 0.01, 0.005)
	Props._p = snap
	var flips := []
	for pass_rows in pair:
		var at := -1.0
		for row in pass_rows:
			if at < 0.0 and row["controls/gps/target"] == "VABB":
				at = row["t"]
		flips.append(at)
	print("    GPS sequences to the next waypoint at %.3f s (120 Hz) / %.3f s (30 Hz)" % [flips[0], flips[1]])
	if flips[0] < 0.0 or absf(flips[0] - flips[1]) > 1.0 / 30.0 + 0.011:
		return "waypoint sequencing at %.3f vs %.3f s" % [flips[0], flips[1]]
	# compare the leg numbers away from the flip (the leg changes there by definition), on the first 200 s
	var cut := minf(flips[0], flips[1]) - 0.1
	var early := [pair[0].filter(func(r): return r["t"] < cut and fmod(r["t"], 1.0) < 0.011), pair[1].filter(func(r): return r["t"] < cut and fmod(r["t"], 1.0) < 0.011)]
	return TickTwin.check("GPS leg to VAPO, once a second", early, {"avionics/gps/dist_nm": 0.002, "avionics/gps/brg_mag": 0.05, "avionics/gps/xtk_nm": 0.002})
