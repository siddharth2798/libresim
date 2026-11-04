extends Node
## Readiness logic of the start screen (core/setup_checks.gd; the dialog is tests/test_fly_confirm.gd). The runway is passed explicitly
## (heading 90, 2000 m) so the checks do not depend on the local data/ folder; one test reads the real data.
## Wind: from 180 degrees off the heading = tail wind, 90 off = cross wind (the maths is exact there).

const RWY := {"ident": "09", "length_m": 2000.0, "heading_deg": 90.0}
const TAIL := 270.0  # wind from behind runway 09
const CROSS := 180.0  # wind from the south, 90 degrees off runway 09 (from the right of a heading-090 take-off)


func _setup(aircraft := "c172", extra := {}) -> Dictionary:
	var s := Session.DEFAULT.duplicate(true)
	s.aircraft = aircraft
	s.wind_kt = 0.0
	s.gust_kt = 0.0
	s.visibility_m = 20000.0
	if aircraft == "a320":
		s.fuel_gal = 12000.0  # total kg
		s.cabin_kg = 6000.0
		s.cargo_kg = 1000.0
	for k in extra:
		s[k] = extra[k]
	return s


func _ids(setup: Dictionary, rwy := RWY) -> Array:
	return SetupChecks.checks(setup, rwy).map(func(c): return c.id)


func _level(setup: Dictionary, id: String, rwy := RWY) -> String:
	for c in SetupChecks.checks(setup, rwy):
		if c.id == id:
			return c.level
	return ""


func test_checks_quiet_setup_is_ready_for_both_aircraft() -> String:
	for ac in ["c172", "a320"]:
		var list := SetupChecks.checks(_setup(ac), RWY if ac == "c172" else {"ident": "09", "length_m": 3400.0, "heading_deg": 90.0})
		if not list.is_empty() or SetupChecks.worst(list) != "ok" or not SetupChecks.reasons(list).is_empty():
			return "%s: a plain setup should have no checks, got %s" % [ac, list]
	return ""


func test_checks_item_shape_and_steps() -> String:
	var s := _setup("c172", {"wind_kt": 30.0, "wind_dir_deg": CROSS, "visibility_m": 800.0, "copilot_kg": 120.0, "rear_kg": 200.0, "baggage_kg": 54.0, "fuel_gal": 20.0})
	var list := SetupChecks.checks(s, RWY)
	for c in list:
		if not (c.has("step") and c.has("level") and c.has("text") and c.has("id")) or c.text == "":
			return "malformed check %s" % [c]
		if not c.step in ["aircraft", "airport", "weather"] or not c.level in ["bad", "warn"]:
			return "unknown step or level in %s" % [c]
	if SetupChecks.step_level(list, "aircraft") != "bad" or SetupChecks.step_level(list, "weather") != "bad":
		return "step_level: %s" % [list]
	if SetupChecks.step_level(list, "airport") != "ok":
		return "no airport problem was set up"
	return ""


func test_checks_over_weight_both_aircraft() -> String:
	var s := _setup("c172", {"fuel_gal": 20.0, "copilot_kg": 120.0, "rear_kg": 200.0, "baggage_kg": 54.0})
	if not "over_weight" in _ids(s):
		return "c172 at %.0f kg (MTOW 1157) should be over weight" % WeightBalance.takeoff_kg(AircraftDef.load_def("c172").data, s)
	if _level(s, "over_weight") != "bad":
		return "over weight must be bad"
	var texts := SetupChecks.reasons(SetupChecks.checks(s, RWY))
	if texts.is_empty() or not texts[0].begins_with("Over maximum takeoff weight by "):
		return "wording: %s" % [texts]
	if "over_weight" in _ids(_setup("c172", {"fuel_gal": 10.0}), RWY):
		return "a light c172 is not over weight"
	var a := _setup("a320", {"fuel_gal": 19000.0, "cabin_kg": 15000.0, "cargo_kg": 3000.0})
	if not "over_weight" in _ids(a, {}):
		return "a320 at %.0f kg (MTOW 73500) should be over weight" % WeightBalance.takeoff_kg(AircraftDef.load_def("a320").data, a)
	return ""


func test_checks_over_weight_boundary_is_strict() -> String:
	var j := AircraftDef.load_def("c172").data
	var s := _setup("c172", {"fuel_gal": 17.0})
	var base := WeightBalance.takeoff_kg(j, s)
	s.baggage_kg = float(j.mtow_kg) - base - 0.01  # a hair under MTOW
	if "over_weight" in _ids(s):
		return "just under MTOW is not over weight"
	s.baggage_kg += 0.5
	if not "over_weight" in _ids(s):
		return "MTOW + 0.5 kg is over weight"
	return ""


func test_checks_cg_out_of_the_envelope() -> String:
	var j := AircraftDef.load_def("c172").data
	var s := _setup("c172", {"fuel_gal": 6.0, "rear_kg": 120.0, "baggage_kg": 54.0})
	var wb := WeightBalance.compute(j, s)
	if wb.ok:
		return "the probe setup should be out of the CG envelope (cg %.1f)" % wb.takeoff.cg_in
	if _level(s, "cg_out") != "bad":
		return "CG out should be bad: %s" % [_ids(s)]
	if "over_weight" in _ids(s):
		return "this setup is aft, not heavy"
	if "cg_out" in _ids(_setup("c172"), RWY):
		return "the default loading is inside the envelope"
	return ""


func test_checks_runway_length_runway_start_only() -> String:
	var short := {"ident": "09", "length_m": 900.0, "heading_deg": 90.0}
	var a := _setup("a320", {"fuel_gal": 8000.0})
	if _level(a, "runway_short", short) != "bad":
		return "a320 on 900 m should be bad (min 1800)"
	if "runway_short" in _ids(_setup("a320", {"fuel_gal": 8000.0}), {"ident": "09", "length_m": 1800.0, "heading_deg": 90.0}):
		return "exactly the minimum is long enough"
	var c := _setup("c172")
	var min_c := float(GroundParams.ground(AircraftDef.load_def("c172")).min_runway_m)
	if absf(min_c - 175.3) > 0.01:
		return "c172 ground.min_runway_m is %s, the owner confirmed 175.3 (575 ft)" % min_c
	if _level(c, "runway_short", {"ident": "09", "length_m": 170.0, "heading_deg": 90.0}) != "bad":
		return "c172 on 170 m should be bad"
	if "runway_short" in _ids(c, {"ident": "09", "length_m": 175.3, "heading_deg": 90.0}):
		return "the c172 minimum itself is long enough"
	if "runway_short" in _ids(c, {"ident": "09", "length_m": 900.0, "heading_deg": 90.0}):
		return "a c172 is fine on 900 m"
	for start in ["air", "stand"]:
		if "runway_short" in _ids(_setup("a320", {"fuel_gal": 8000.0, "start": start}), short):
			return "%s start: runway length does not apply" % start
	return ""


func test_checks_tailwind_boundary_and_start_kinds() -> String:
	for start in ["runway", "air"]:
		var s := _setup("c172", {"start": start, "wind_dir_deg": TAIL, "wind_kt": 5.0})
		if "tailwind" in _ids(s):
			return "%s: a 5 kt tailwind is not bad" % start
		s.wind_kt = 5.1
		if _level(s, "tailwind") != "bad":
			return "%s: a 5.1 kt tailwind is bad (%s)" % [start, _ids(s)]
		s.wind_dir_deg = 90.0  # headwind
		s.wind_kt = 30.0
		if "tailwind" in _ids(s):
			return "%s: a headwind is not a tailwind" % start
	var st := _setup("c172", {"start": "stand", "wind_dir_deg": TAIL, "wind_kt": 20.0})
	if not _ids(st).is_empty():
		return "a stand start has no runway wind checks: %s" % [_ids(st)]
	var t := SetupChecks.reasons(SetupChecks.checks(_setup("c172", {"wind_dir_deg": TAIL, "wind_kt": 8.0}), RWY))
	if t != ["Tailwind 8 kt on runway 09"]:
		return "wording: %s" % [t]
	return ""


func test_checks_crosswind_limit_per_aircraft() -> String:
	var lim := {"c172": 15.0, "a320": 33.0}
	for ac in lim:
		if SetupChecks.max_crosswind_kt(AircraftDef.load_def(ac)) != lim[ac]:
			return "%s limits.max_crosswind_kt should be %s" % [ac, lim[ac]]
		var rwy := {"ident": "09", "length_m": 3400.0, "heading_deg": 90.0}
		for start in ["runway", "air"]:
			var s := _setup(ac, {"start": start, "wind_dir_deg": CROSS, "wind_kt": lim[ac]})
			if "crosswind" in _ids(s, rwy):
				return "%s %s: exactly %s kt is not bad" % [ac, start, lim[ac]]
			s.wind_kt = lim[ac] + 0.1
			if _level(s, "crosswind", rwy) != "bad":
				return "%s %s: %s kt should be bad" % [ac, start, s.wind_kt]
	var s2 := _setup("c172", {"wind_dir_deg": CROSS, "wind_kt": 25.0})
	if SetupChecks.reasons(SetupChecks.checks(s2, RWY)) != ["Crosswind 25 kt, above 15 kt"]:
		return "wording: %s" % [SetupChecks.reasons(SetupChecks.checks(s2, RWY))]
	s2.wind_dir_deg = 0.0  # from the left: the same size
	if _level(s2, "crosswind") != "bad":
		return "a crosswind from the left counts too"
	s2.aircraft = "a320"
	if "crosswind" in _ids(s2, {"ident": "09", "length_m": 3400.0, "heading_deg": 90.0}):
		return "25 kt is within the a320 limit"
	return ""


func test_checks_the_runway_follows_the_setup_not_a_fixed_heading() -> String:
	var s := _setup("c172", {"wind_dir_deg": 90.0, "wind_kt": 20.0})
	if not SetupChecks.checks(s, {"ident": "27", "length_m": 2000.0, "heading_deg": 270.0}).any(func(c): return c.id == "tailwind"):
		return "wind from 090 on runway 27 is a tailwind"
	if SetupChecks.checks(s, RWY).any(func(c): return c.id == "tailwind"):
		return "wind from 090 on runway 09 is a headwind"
	return ""


func test_checks_low_visibility_warns_and_never_asks() -> String:
	var s := _setup("c172", {"visibility_m": 1599.0})
	var list := SetupChecks.checks(s, RWY)
	if _level(s, "low_visibility") != "warn" or SetupChecks.worst(list) != "warn" or not SetupChecks.reasons(list).is_empty():
		return "low visibility should be a warn that does not ask: %s" % [list]
	if "low_visibility" in _ids(_setup("c172", {"visibility_m": 1600.0})):
		return "1600 m is not low visibility"
	var air := SetupChecks.checks(_setup("c172", {"start": "air", "visibility_m": 800.0}), RWY)
	return "" if air.size() == 1 and air[0].level == "warn" else "air start: %s" % [air]


func test_checks_worst_and_reasons() -> String:
	var ok := []
	var warn := [{"step": "weather", "level": "warn", "id": "x", "text": "w"}]
	var mix := warn + [{"step": "aircraft", "level": "bad", "id": "y", "text": "b1"}, {"step": "airport", "level": "bad", "id": "z", "text": "b2"}]
	if SetupChecks.worst(ok) != "ok" or SetupChecks.worst(warn) != "warn" or SetupChecks.worst(mix) != "bad":
		return "worst: %s %s %s" % [SetupChecks.worst(ok), SetupChecks.worst(warn), SetupChecks.worst(mix)]
	if SetupChecks.reasons(mix) != ["b1", "b2"] or not SetupChecks.reasons(warn).is_empty():
		return "reasons: %s" % [SetupChecks.reasons(mix)]
	return ""


func test_checks_runway_lookup_from_the_real_data() -> String:
	if not FileAccess.file_exists(Paths.data("runways.json")):
		print("    (no data/processed/runways.json here: skipped)")
		return ""
	var r := SetupChecks.runway_of({"airport": "VABB", "runway": "09"})
	if r.is_empty() or r.ident != "09" or r.length_m < 1000.0:
		return "VABB 09: %s" % [r]
	var longest := SetupChecks.runway_of({"airport": "VABB", "runway": ""})
	var unknown := SetupChecks.runway_of({"airport": "VABB", "runway": "99"})
	if longest.is_empty() or longest != unknown or longest.length_m < r.length_m:
		return "no / unknown ident should give the longest runway: %s %s" % [longest, unknown]
	if not SetupChecks.runway_of({"airport": "ZZZZ"}).is_empty():
		return "an unknown airport has no runway"
	return ""
