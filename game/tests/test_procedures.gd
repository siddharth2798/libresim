extends RefCounted
## Published SIDs and STARs: the data (avionics/procedures.gd), the route they make (procedure_route.gd, RouteSetup.gps_plan,
## FlightPlan.with_procedures, the MCDU INIT SID / STAR keys), the FMS limits (fms_constraints.gd, VerticalProfile caps) and the
## managed modes (AfVertical ALT CST, AfSpeeds). A small document stands in for procedures.json (Procedures.use), so no data file
## is read; every test puts the real one back.

const PROBE := preload("res://tests/probe_a320_flight.gd")
const DOC := {
	"airports": {
		"VAPO": {"sids": [{"name": "OPAKA2A", "rwy": "28", "legs": [{"fix": "D273E", "lo_ft": 2900}, {"fix": "OPAKA"}]}], "stars": []},
		"VABB": {"sids": [{"name": "PPN3A", "rwy": "27", "legs": [{"fix": "BB150", "lo_ft": 6000}, {"fix": "BB155", "lo_ft": 11000, "hi_ft": 12000}]}],
			"stars": [{"name": "OPAKA3K", "rwy": "27", "vectors_true": 180.0, "legs": [{"fix": "OPAKA"},
				{"fix": "VELKO", "lo_ft": 12000, "spd_kt": 230}, {"fix": "BB257", "lo_ft": 10000, "hi_ft": 10000}]}]}},
	"fixes": {"D273E": {"x": -60000.0, "y": 0.0}, "OPAKA": {"x": 100000.0, "y": 60000.0}, "VELKO": {"x": 60000.0, "y": 30000.0},
		"BB257": {"x": 20000.0, "y": 15000.0}, "BB150": {"x": -20000.0, "y": -20000.0}, "BB155": {"x": -20000.0, "y": -40000.0}},
}
## VABB runway 27 threshold at the origin, landing west: its final fix F is 8 nm east of it.
const AIRPORTS := [
	{"ident": "VABB", "icao": "VABB", "x": 0.0, "y": 0.0, "elev_m": 0.0, "runways": [{"le": {"ident": "09", "x": -3000.0, "y": 0.0,
		"heading_true": 90.0}, "he": {"ident": "27", "x": 0.0, "y": 0.0, "heading_true": 270.0}}]},
	{"ident": "VAPO", "icao": "VAPO", "x": -50000.0, "y": 0.0, "elev_m": 592.0, "runways": [{"le": {"ident": "10", "x": -52000.0,
		"y": 0.0, "heading_true": 94.0}, "he": {"ident": "28", "x": -50000.0, "y": 0.0, "heading_true": 274.0}}]},
]


func _with_doc(f: Callable) -> String:
	Procedures.use(DOC)
	var r: String = f.call()
	Procedures.use(null)
	return r


func test_procedures_lists_by_runway() -> String:
	return _with_doc(func() -> String:
		if Procedures.names("VABB", "STAR", "27") != ["OPAKA3K"] or not Procedures.names("VABB", "STAR", "09").is_empty():
			return "STARs by runway %s" % [Procedures.names("VABB", "STAR", "27")]
		if Procedures.find("vapo", "SID", "opaka 2a", "28").is_empty() or not Procedures.find("VAPO", "SID", "OPAKA2A", "10").is_empty():
			return "find is by name and runway"
		if Procedures.text({"lo": 12000.0, "spd": 230.0}) != "230/+FL120" or Procedures.text({"lo": 6000.0}) != "+6000":
			return "text %s %s" % [Procedures.text({"lo": 12000.0, "spd": 230.0}), Procedures.text({"lo": 6000.0})]
		if Procedures.text({"lo": 11000.0, "hi": 11000.0}) != "FL110" or Procedures.text({"lo": 11000.0, "hi": 12000.0}) != "FL110-FL120":
			return "at / window text"
		return "")


## The SID replaces the departure fix, the STAR (its first fix not repeated) and its vectors point come before the final fix.
func test_gps_plan_flies_sid_and_star() -> String:
	return _with_doc(func() -> String:
		var s := {"airport": "VAPO", "start": "runway", "runway": "28", "route": {"dest": "VABB", "arr_rwy": "27", "wps": [],
			"cruise_ft": 14000.0, "sid": "OPAKA2A", "star": "OPAKA3K"}}
		var plan := RouteSetup.gps_plan(s, func(_id): return true, AIRPORTS)
		var want := ["OPAKA", "VELKO", "BB257", "VABB27V", "VABB27F", "VABB"]
		if plan.target != "D273E" or plan.next != want:
			return "route %s %s" % [plan.target, plan.next]
		if plan.sid != "OPAKA2A" or plan.star != "OPAKA3K" or plan.dep_rwy != "28":
			return "names %s %s %s" % [plan.sid, plan.star, plan.dep_rwy]
		var c: Dictionary = plan.cstr
		if c.size() != 3 or c.D273E.lo != 2900.0 or c.D273E.proc != "SID" or c.BB257.hi != 10000.0 or c.VELKO.spd != 230.0 \
				or c.VELKO.proc != "STAR":
			return "constraints %s" % c
		var none := RouteSetup.gps_plan({"airport": "VAPO", "start": "runway", "runway": "10", "route": s.route}, func(_id): return true, AIRPORTS)
		if none.target != "VAPO10D" or none.sid != "":
			return "a SID of another runway is not flown: %s %s" % [none.target, none.sid]
		return "")


## The vectors point: on the STAR's published heading from its last fix, as far as the descent from FL100 to the final fix needs.
func test_star_vectors_point_gives_the_descent_room() -> String:
	return _with_doc(func() -> String:
		var p := Procedures.find("VABB", "STAR", "OPAKA3K", "27")
		if ProcedureRoute.vectors(p, "VABB", "27", AIRPORTS) != "VABB27V":
			return "no vectors point"
		var v: Vector2 = Procedures.points["VABB27V"]
		var l := Vector2(20000.0, 15000.0)
		var f := Vector2(8.0 * 1852.0, 0.0)
		var need := (10000.0 - VerticalProfile.APPROACH_AGL_FT) / VerticalProfile.FT_PER_NM + VerticalProfile.DECEL_NM
		var s := l.distance_to(v) / 1852.0
		if absf(v.x - l.x) > 1.0 or v.y >= l.y:
			return "not south of BB257: %s" % v
		if s + v.distance_to(f) / 1852.0 < need or (s - 0.5) + (l + Vector2(0, -(s - 0.5) * 1852.0)).distance_to(f) / 1852.0 >= need:
			return "not the shortest vectors that fit: %.1f nm out" % s
		var near := {"name": "X", "vectors_true": 180.0, "legs": [{"fix": "OPAKA", "lo_ft": 3000.0, "hi_ft": 3000.0}]}
		return "" if ProcedureRoute.vectors(near, "VABB", "27", AIRPORTS) == "" else "a STAR ending low and far out needs no vectors")


func test_mcdu_files_sid_and_star() -> String:
	return _with_doc(func() -> String:
		var f := FlightPlan.file(["VAPO", "VABB"], func(_id): return true)
		var w := FlightPlan.with_procedures(f, "28", "27", "OPAKA2A", "OPAKA3K", AIRPORTS)
		if w.target != "D273E" or w.next != ["OPAKA", "VELKO", "BB257", "VABB27V", "VABB27F", "VABB"] or w.cstr.size() != 3:
			return "filed %s %s %s" % [w.target, w.next, w.cstr]
		var plain := FlightPlan.with_procedures(f, "28", "27")
		if plain.target != "VAPO28D" or plain.sid != "":
			return "no procedure: the runway fixes %s" % plain
		if McduProcs.next_name(["A", "B"], "") != "A" or McduProcs.next_name(["A", "B"], "A") != "B" or McduProcs.next_name(["A", "B"], "B") != "":
			return "the SID key cycles the published names, then none"
		return "")


func test_mcdu_sid_key_offers_the_runway_procedure() -> String:
	var keys := {"mcdu/init/from_to": "", "mcdu/init/dep_rwy": "", "mcdu/init/arr_rwy": "", "mcdu/init/sid": "", "mcdu/init/star": "",
		"mcdu/scratch": "", "controls/gps/target": "", "controls/gps/route_next": [], RouteSetup.CSTR_PROP: {}, "controls/fms/origin": "",
		"controls/fcu/hdg_managed": false, "controls/fcu/spd_managed": false}  # prop -> the value when it was unset
	var old := {}
	for k in keys:
		old[k] = Props.get_v(k, keys[k])
	var r := _with_doc(func() -> String:
		var d := MCDU.new()
		Props.set_v("mcdu/init/from_to", "VAPO/VABB")
		Props.set_v("mcdu/init/dep_rwy", "28")
		Props.set_v("mcdu/init/arr_rwy", "27")
		Props.set_v("mcdu/init/sid", "")
		Props.set_v("mcdu/init/star", "")
		McduProcs.line_key(d, "l", "")
		var got := [Props.get_v("mcdu/init/sid"), Props.get_v("controls/gps/target")]
		McduProcs.line_key(d, "r", "XXXX1A")
		var bad := str(Props.get_v("mcdu/scratch", ""))
		d.free()
		if got != ["OPAKA2A", "D273E"]:
			return "L6 with an empty scratchpad picks the runway's SID and refiles: %s" % [got]
		if bad != FlightPlan.NOT_IN_DB or (Props.get_v(RouteSetup.CSTR_PROP, {}) as Dictionary).get("D273E", {}).get("lo", 0.0) != 2900.0:
			return "an unpublished STAR is refused (%s), the SID's limits are filed" % bad
		return "")
	for k in keys:
		Props.set_v(k, old[k])
	return r


func _legs(ids: Array, nm: Array) -> Array:
	var out := []
	for k in ids.size():
		out.append({"ident": ids[k], "cum_m": float(nm[k]) * 1852.0})
	return out


func test_fms_ceiling_floor_and_speed() -> String:
	var c := {"A": {"lo": 6000.0, "hi": 0.0, "spd": 0.0, "proc": "SID"}, "B": {"lo": 11000.0, "hi": 12000.0, "spd": 0.0, "proc": "SID"},
		"C": {"lo": 28000.0, "hi": 28000.0, "spd": 0.0, "proc": "SID"}, "S1": {"lo": 12000.0, "hi": 0.0, "spd": 230.0, "proc": "STAR"},
		"S2": {"lo": 11000.0, "hi": 11000.0, "spd": 190.0, "proc": "STAR"}}
	var climb := _legs(["A", "B", "C"], [5, 15, 40])
	if FmsConstraints.ceiling(climb, c, 14000.0).ft != 12000.0:
		return "ceiling %s" % FmsConstraints.ceiling(climb, c, 14000.0)
	if FmsConstraints.applies(c.C, 14000.0) or not FmsConstraints.applies(c.C, 30000.0):
		return "a SID limit wholly above the cruise level is not flown"
	var star := _legs(["S1", "S2"], [20, 30])
	if FmsConstraints.floor_of(star, c).ft != 12000.0 or FmsConstraints.caps(star, c) != [{"s_nm": 30.0, "hi_ft": 11000.0}]:
		return "floor / caps %s %s" % [FmsConstraints.floor_of(star, c), FmsConstraints.caps(star, c)]
	if FmsConstraints.speed_limit(star, c, true, 0.0, 280.0) != 0.0:
		return "230 kt 20 nm ahead from 280 kt: not yet (decel distance 12 nm)"
	if FmsConstraints.speed_limit(_legs(["S1"], [10]), c, false, 0.0, 280.0) != 230.0:
		return "still in cruise, 10 nm before a 230 kt STAR fix: slow down now (VELKO was passed at 274 kt)"
	if FmsConstraints.speed_limit(_legs(["S1"], [10]), c, false, 0.0, 280.0, true) != 0.0:
		return "climbing: STAR limits do not apply"
	if FmsConstraints.speed_limit(_legs(["S1", "S2"], [5, 15]), c, true, 0.0, 280.0) != 230.0:
		return "230 kt within its deceleration distance"
	if FmsConstraints.speed_limit(_legs(["S2"], [30]), c, true, 230.0, 230.0) != 230.0:
		return "a passed STAR limit holds in the descent"
	if not FmsConstraints.met(c.S2, 11050.0, 195.0) or FmsConstraints.met(c.S2, 11300.0, 190.0) or FmsConstraints.met(c.S1, 12000.0, 250.0):
		return "met with 100 ft / 10 kt"
	if FmsConstraints.predicted(c.B, 3000.0, 20.0, false) != "met" or FmsConstraints.predicted(c.B, 3000.0, 10.0, false) != "missed" \
			or FmsConstraints.predicted(c.A, 1000.0, 5.0, false) != "missed" or FmsConstraints.predicted(c.S2, 3000.0, 5.0, false) != "met":
		return "climb prediction"
	var v := FmsConstraints.new()
	v.passed("S1", c, 12050.0, 228.0, 14000.0)
	v.passed("C", c, 14000.0, 280.0, 14000.0)
	if v.log.size() != 2 or not v.log[0].met or not v.log[1].skip or v.held_kt != 230.0:
		return "log %s held %.0f" % [v.log, v.held_kt]
	Props.set_v("avionics/fms/cstr_log", [])
	return ""


## The top of descent comes early enough for an at-or-below STAR limit (before, it was only from the approach level).
func test_top_of_descent_meets_star_limits() -> String:
	var plain := VerticalProfile.decide(14000.0, 14000.0, 120.0, 33.0, "CRZ")
	var capped := VerticalProfile.decide(14000.0, 14000.0, 120.0, 33.0, "CRZ", [{"s_nm": 60.0, "hi_ft": 11000.0}])
	if plain.descend or absf(plain.tod_nm - ((14000.0 - 2233.0) / 300.0 + 8.0 + 6.0 + 4.0)) > 0.01:
		return "no caps: as before %s" % plain
	if absf(capped.tod_nm - 70.0) > 0.01 or capped.descend:  # 120 - 60 + 3000 / 300
		return "capped tod %s" % capped
	var at := VerticalProfile.decide(14000.0, 14000.0, 69.0, 33.0, "CRZ", [{"s_nm": 9.0, "hi_ft": 11000.0}])
	return "" if at.descend and at.phase == "DES" else "10 nm before an FL110 limit from FL140: descend %s" % at


func _in(alt_m: float, fcu_m: float, vs: float) -> AfInputs:
	var i := AfInputs.new()
	i.dt = 0.1
	i.tas = 150.0
	i.cas = 130.0
	i.alt_m = alt_m
	i.vs_mps = vs
	i.f.alt = fcu_m
	i.f.vs_mgd = true
	return i


## Managed CLB levels at a SID at-or-below limit (ALT CST*, ALT CST) and climbs on by itself once the FMS drops it.
func test_managed_climb_levels_at_a_constraint() -> String:
	var v := AfVertical.new()
	v.set_mode("CLB")
	var i := _in(3640.0, 4267.0, 3.0)
	i.cstr_ceil_m = 3657.6
	v.update(i, 130.0, false)
	if v.mode != "ALT*" or not v.cst or AfFma.vertical(v, false) != "ALT CST*":
		return "capture %s %s %s" % [v.mode, v.cst, AfFma.vertical(v, false)]
	i.alt_m = 3657.0
	i.vs_mps = 0.0
	v.update(i, 130.0, false)
	if v.mode != "ALT" or absf(v.hold_m - 3657.6) > 0.1 or AfFma.vertical(v, false) != "ALT CST":
		return "hold %s %.1f %s" % [v.mode, v.hold_m, AfFma.vertical(v, false)]
	v.update(i, 130.0, false)
	if v.mode != "ALT":
		return "stays while the limit is ahead: %s" % v.mode
	i.cstr_ceil_m = 0.0
	v.update(i, 130.0, false)
	if v.mode != "CLB" or v.cst:
		return "the fix passed: the climb goes on, %s" % v.mode
	var above := AfVertical.new()
	above.set_mode("CLB")
	var j := _in(3800.0, 4267.0, 5.0)
	j.cstr_ceil_m = 3657.6
	above.update(j, 130.0, false)
	return "" if above.mode == "CLB" else "a limit already below the aircraft does not make a descent: %s" % above.mode


func test_managed_descent_levels_at_a_constraint() -> String:
	var v := AfVertical.new()
	v.set_mode("DES")
	var i := _in(3365.0, 680.0, -3.0)
	i.cstr_floor_m = 3352.8
	v.update(i, 130.0, false)
	if v.mode != "ALT*" or not v.cst:
		return "capture %s" % v.mode
	i.alt_m = 3353.0
	i.vs_mps = 0.0
	v.update(i, 130.0, false)
	i.cstr_floor_m = 3048.0
	v.update(i, 130.0, false)
	if v.mode != "DES":
		return "a lower limit next: the descent goes on, %s" % v.mode
	var s := AfSpeeds.new({})
	var k := _in(3000.0, 3000.0, 0.0)
	var free := Units.mps_to_kt(s.managed(k, "DES").cas)
	k.cstr_spd_kt = 230.0
	var lim := Units.mps_to_kt(s.managed(k, "DES").cas)
	return "" if absf(free - 250.0) < 1.0 and absf(lim - 230.0) < 1.0 else "managed speed %.0f -> %.0f with a 230 kt limit" % [free, lim]


func test_probe_checks_every_constraint() -> String:
	var c := {"A": {"lo": 2900.0}, "B": {"hi": 11000.0}}
	var ok := [{"ident": "A", "text": "+2900", "alt_ft": 3500.0, "kt": 250.0, "met": true, "skip": false},
		{"ident": "B", "text": "-FL110", "alt_ft": 11000.0, "kt": 250.0, "met": true, "skip": false}]
	if PROBE.constraint_check(c, ok) != "":
		return "all met"
	if PROBE.constraint_check(c, ok.slice(0, 1)) == "":
		return "a constraint fix never passed must fail"
	var miss := ok.duplicate(true)
	miss[1].met = false
	return "" if PROBE.constraint_check(c, miss) != "" else "a missed constraint must fail"
