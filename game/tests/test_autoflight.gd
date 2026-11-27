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
	i.f.alt = 1524.0  # turned below a managed climb: a reversion to V/S, not a new descent (docs/A320-FCU-REFERENCE.md)
	logic.update(i)
	if logic.vert.mode != "V/S" or not logic.writes.has("vs_mgd"):
		return "a target on the wrong side of a managed climb reverts to V/S: %s %s" % [logic.vert.mode, logic.writes]
	i.f.vs_mgd = true
	i.f.select = "MANAGED"  # pushed: the managed descent
	logic.update(i)
	i.f.select = ""
	if logic.vert.mode != "DES":
		return "ALT pushed below the aircraft: managed descent %s" % logic.vert.mode
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


func test_vs_alt_arm_follows_the_selected_rate() -> String:
	var v := AfVertical.new()
	v.set_mode("V/S")
	var i := AfInputs.new()
	i.dt = 0.1
	i.tas = 85.0
	i.alt_m = 670.0
	i.f.alt = 3048.0
	i.f.vs = 0.0
	i.vs_mps = 1.2  # the aircraft is drifting up; the selection is level
	v.update(i, 85.0, false)
	if "ALT" in v.armed:
		return "level V/S armed ALT from the aircraft's drift"
	i.f.vs = 2.5
	i.vs_mps = 0.1  # selected climb, the path is momentarily flat
	v.update(i, 85.0, false)
	return "" if "ALT" in v.armed else "a selected climb toward the altitude should keep ALT armed"


func test_af_smoke() -> String:
	var r := AfRig.new(250.0, 10000.0, 0.0)
	var t0 := Time.get_ticks_msec()
	print("    start: %.1f kt, %.0f ft, lever %.3f" % [r.kias(), r.alt_ft(), Props.get_f("controls/throttle_1")])
	r.run(20.0)
	print("    hands off 20 s (law, no AP): %.1f kt, %.0f ft, %.0f fpm, pitch %.2f; %d ms" % [r.kias(), r.alt_ft(), r.fpm(), rad_to_deg(r.f.euler().y), Time.get_ticks_msec() - t0])
	return ""


## Managed speed in the approach phase (FMS APPR, or APPR / LOC pressed), clean: green dot, below VFE CONF 1, so the flaps can
## come out on managed speed. Before, 250 kt stayed below 10,000 ft until the first flap (VFE CONF 1 is 230 kt).
func test_managed_speed_slows_to_green_dot_in_the_approach() -> String:
	var sp := AfSpeeds.new(AircraftDef.load_def("a320").section("limits"))
	var i := _air(1500.0)
	i.mass_kg = 64000.0
	i.flap_lever = 0
	i.ext_deg = 0.0
	var cruise := Units.mps_to_kt(float(sp.managed(i, "DES").cas))
	if absf(cruise - 250.0) > 0.5:
		return "clean below 10,000 ft outside the approach: 250 kt, got %.1f" % cruise
	var gd := sp.green_dot_kt(i)
	for how in ["APPR", "appr", "loc"]:
		var j := _air(1500.0)
		j.mass_kg = 64000.0
		j.ra_m = 1000.0  # below 7,200 ft
		if how == "APPR":
			j.fms_phase = "APPR"
		else:
			j.f[how] = true
		var kt := Units.mps_to_kt(float(sp.managed(j, "DES").cas))
		if absf(kt - gd) > 0.5 or kt >= 222.0:
			return "%s: clean approach speed %.1f, want green dot %.1f (below VFE CONF 1 - 8)" % [how, kt, gd]
		if how != "APPR":  # armed high (FL140 over the Ghats): not yet the approach phase
			j.ra_m = 3500.0
			j.alt_m = 4267.0
			var high := Units.mps_to_kt(float(sp.managed(j, "DES").cas))
			if high < 270.0:
				return "%s armed at FL140 slowed the managed speed to %.1f: the approach phase starts below 7,200 ft or at DECEL" % [how, high]
	var k := _air(1500.0)
	k.fms_phase = "APPR"
	k.flap_lever = 1
	k.ext_deg = 18.0
	var conf1 := Units.mps_to_kt(float(sp.managed(k, "DES").cas))
	if conf1 >= 222.0:
		return "CONF 1 in the approach: %.1f kt, want below VFE CONF 1 - 8" % conf1
	var s_kt := sp.vls_at_lever(k, 0) + 5.0  # S speed: clean Vls + 5
	if conf1 < s_kt - 0.5:
		return "CONF 1 managed %.1f kt is below S (%.1f): a crew retracting at S would wait forever" % [conf1, s_kt]
	return ""


## The FMS phase: a descent flown down to the approach altitude stays DES (it fell back to CRZ before), and the last APPR_NM
## of the route are APPR.
func test_profile_phase_stays_down_and_becomes_appr() -> String:
	var at := 1950.0 + VerticalProfile.APPROACH_AGL_FT  # levelled at the approach altitude
	var bottom := VerticalProfile.decide(14000.0, at, 40.0, 1950.0, "DES")
	if bottom.phase != "DES":
		return "at the approach altitude after the descent: DES, got %s" % bottom.phase
	var fresh := VerticalProfile.decide(14000.0, 14000.0, 80.0, 1950.0, "")
	if fresh.phase != "CRZ":
		return "cruise far out, no descent yet: CRZ, got %s" % fresh.phase
	var below := VerticalProfile.decide(14000.0, 11500.0, 34.0, 1950.0, "DES")  # under the 300 ft/nm line (tod 33 nm here)
	if below.phase != "DES":
		return "below the descent profile mid-descent: DES, got %s (it flipped to CLB in the VABB - VAPO flight)" % below.phase
	var back_up := VerticalProfile.decide(14000.0, 13900.0, 80.0, 1950.0, "DES")
	if back_up.phase != "CRZ":
		return "back at the cruise level: CRZ, got %s" % back_up.phase
	var near := VerticalProfile.decide(14000.0, at, VerticalProfile.APPR_NM - 1.0, 1950.0, "DES")
	if near.phase != "APPR":
		return "within %.0f nm in the descent: APPR, got %s" % [VerticalProfile.APPR_NM, near.phase]
	var high := VerticalProfile.decide(14000.0, 9000.0, 20.0, 1950.0, "")
	if high.phase != "APPR" or not high.descend:
		return "descending within APPR_NM: APPR, got %s" % high
	var path_ft := VerticalProfile.FINAL_NM * 1852.0 * tan(deg_to_rad(3.0)) / 0.3048  # the glide path over the 8 nm arrival fix
	if float(high.approach_ft) - 1950.0 > path_ft - 200.0:
		return "approach altitude %.0f ft above the field: must be under the 3 deg path at the arrival fix (%.0f ft) to capture G/S from below" % [
			float(high.approach_ft) - 1950.0, path_ft]
	return ""


## A climb mode far below its target speed (the acceleration to 250 kt after the flaps come in) accelerates level at worst: it never
## commands a descent (before, the speed law went down to -3 deg: the A320 sank 900 ft/min at 1,700 ft in CLB).
func test_climb_never_descends_and_descent_never_climbs() -> String:
	for m in ["CLB", "OP CLB"]:
		var v := AfVertical.new()
		var i := _air(500.0)
		i.f.alt = 4000.0
		i.cas = 95.0  # target 128.6: 65 kt slow
		v.set_mode(m)
		for k in 50:
			v.update(i, 128.6, false)
		if v.gamma_cmd < 0.0:
			return "%s 65 kt slow: flight path %.2f deg, want >= 0" % [m, rad_to_deg(v.gamma_cmd)]
	for m in ["DES", "OP DES"]:  # the mirror case: 70 kt fast in a descent (green dot asked at 280 kt) slows level, never climbs
		var v := AfVertical.new()
		var i := _air(4000.0)
		i.f.alt = 1200.0
		i.cas = 144.0  # target 108: 70 kt fast
		v.set_mode(m)
		for k in 50:
			v.update(i, 108.0, false)
		if v.gamma_cmd > 0.0:
			return "%s 70 kt fast: flight path %.2f deg, want <= 0 (it climbed 1,500 ft at idle before)" % [m, rad_to_deg(v.gamma_cmd)]
	return ""


## A managed climb levels off as ALT CRZ (ALT* in between). Before, the flag was set and then cleared by set_mode("ALT*") on the
## same line, so the FMA only ever said ALT.
func test_managed_climb_levels_as_alt_crz() -> String:
	var v := AfVertical.new()
	var i := _air(4200.0)
	i.f.alt = 4267.0  # FL140, 67 m above
	i.vs_mps = 10.0
	v.set_mode("CLB")
	v.update(i, 128.6, false)
	if v.mode != "ALT*" or not v.crz:
		return "capture from CLB: %s crz %s" % [v.mode, v.crz]
	i.alt_m = 4266.0
	i.vs_mps = 0.2
	v.update(i, 128.6, false)
	var fma := AfFma.vertical(v, false, AfLand.new())
	if v.mode != "ALT" or fma != "ALT CRZ":
		return "levelled after a managed climb: mode %s FMA [%s], want ALT CRZ" % [v.mode, fma]
	var o := AfVertical.new()
	o.set_mode("OP CLB")
	var j := _air(4200.0)
	j.f.alt = 4267.0
	j.vs_mps = 10.0
	o.update(j, 128.6, false)
	j.alt_m = 4266.0
	j.vs_mps = 0.2
	o.update(j, 128.6, false)
	if AfFma.vertical(o, false, AfLand.new()) != "ALT":
		return "after an open climb: ALT, got [%s]" % AfFma.vertical(o, false, AfLand.new())
	var d := AfVertical.new()
	d.set_mode("DES")
	var k := _air(1330.0)
	k.f.alt = 1262.0  # the approach altitude, 68 m below
	k.vs_mps = -10.0
	d.update(k, 128.6, false)
	k.alt_m = 1263.0
	k.vs_mps = -0.2
	d.update(k, 128.6, false)
	return "" if AfFma.vertical(d, false, AfLand.new()) == "ALT" else "after a managed descent: ALT, got [%s]" % AfFma.vertical(d, false, AfLand.new())
