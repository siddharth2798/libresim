extends "res://tests/ils_test_base.gd"
## Which ILS to tune (avionics/ils_pick.gd, pure functions) on the stations of the NavDatabase, whatever the data holds.


func test_route_arrival_runway_gives_its_ils() -> String:
	var checked := 0
	for s in stations():
		var w := IlsPick.wanted(ctx(str(s.airport), str(s.runway), far(s, 80.0), float(s.course_true)))
		if w.s.is_empty() or w.s.ident != s.ident or absf(float(w.s.mhz) - float(s.mhz)) > 0.001 or w.why != "route":
			return "ARR RWY %s of %s: got %s (%s), want %s" % [s.runway, s.airport, w.s.get("ident"), w.why, s.ident]
		checked += 1
	var s0: Dictionary = stations()[0]
	var bare := str(s0.runway).trim_prefix("0")  # "9" for "09"
	if bare != str(s0.runway) and IlsPick.wanted(ctx(str(s0.airport), bare, far(s0, 80.0), float(s0.course_true))).s.get("ident") != s0.ident:
		return "ARR RWY %s (no leading zero) should find %s" % [bare, s0.ident]
	return "" if checked >= 5 else "only %d ILS runways in the data" % checked


func test_route_waits_for_100_nm_or_the_descent() -> String:
	var s: Dictionary = stations()[0]
	var rwy := str(s.runway)
	var ap := str(s.airport)
	var apos := airport_of(s)
	var pos := func(nm: float) -> Vector3:
		return Vector3(float(apos.x) - nm * NM, float(apos.y), 3000.0 + float(s.threshold.h))
	if not IlsPick.wanted(ctx(ap, rwy, pos.call(130.0), 90.0)).s.is_empty():
		return "130 nm out in the cruise: nothing is tuned yet"
	if IlsPick.wanted(ctx(ap, rwy, pos.call(130.0), 90.0, "DES")).s.is_empty():
		return "in the descent the arrival ILS is tuned whatever the distance"
	if IlsPick.wanted(ctx(ap, rwy, pos.call(99.0), 90.0)).s.is_empty():
		return "99 nm out: tuned"
	return ""


func test_destination_without_a_runway_takes_the_straight_in_one() -> String:
	for s in stations():
		var w := IlsPick.wanted(ctx(str(s.airport), "", far(s, 50.0), float(s.course_true)))  # flying down its final course
		if w.s.is_empty() or w.s.airport != s.airport or absf(wrapf(float(w.s.course_true) - float(s.course_true), -180.0, 180.0)) > 20.0:
			return "from the %s side of %s: got %s" % [s.runway, s.airport, w.s.get("ident")]
	return ""


func test_lineup_without_a_route_picks_the_runway_ahead() -> String:
	var checked := 0
	for s in stations():
		var w := IlsPick.wanted(ctx("", "", final(s, 12.0, 300.0), float(s.course_true) + 10.0))
		if w.s.is_empty() or w.s.airport != s.airport or absf(wrapf(float(w.s.course_true) - float(s.course_true), -180.0, 180.0)) > 20.0 \
				or w.why != "lineup":
			return "12 nm on the %s final of %s: got %s (%s)" % [s.runway, s.airport, w.s.get("ident"), w.why]
		checked += 1
	return "" if checked >= 5 else "only %d ILS runways" % checked


func test_lineup_limits() -> String:
	var s: Dictionary = stations()[0]
	var crs := float(s.course_true)
	if IlsPick.wanted(ctx("", "", final(s, 12.0), crs)).s.is_empty():
		return "the reference case should tune"
	var cases := {"30 nm out": final(s, 30.0), "9,000 ft above the threshold": final(s, 12.0, 9000.0)}
	for k in cases:
		if not IlsPick.wanted(ctx("", "", cases[k], crs)).s.is_empty():
			return "%s: nothing should be tuned" % k
	if not IlsPick.wanted(ctx("", "", final(s, 12.0), crs + 70.0)).s.is_empty():
		return "track 70 deg off the course: no tune"
	if not IlsPick.wanted(ctx("", "", final(s, 12.0), crs + 180.0)).s.is_empty():
		return "flying away: no tune"
	var c := deg_to_rad(crs)
	var past := Vector2(s.threshold.x, s.threshold.y) + Vector2(sin(c), cos(c)) * 2.0 * NM  # beyond the threshold
	if not IlsPick.wanted(ctx("", "", Vector3(past.x, past.y, float(s.threshold.h) + 300.0), crs)).s.is_empty():
		return "past the threshold: no tune"
	if IlsPick.wanted(ctx("", "", final(s, 12.0, 9000.0), crs, "", true)).s.is_empty():
		return "LOC / APPR armed lifts the height limit"
	if not IlsPick.wanted(ctx("", "", Vector3(0, 4.0e6, 3000.0), 0.0)).s.is_empty():
		return "nowhere near an ILS: none"
	return ""


func test_records_without_geometry_are_skipped() -> String:
	var s: Dictionary = stations()[0]
	var odd := [{"ident": "XXXX", "airport": s.airport, "runway": "", "mhz": 110.0}, s]  # a record that lacks its course and threshold
	var w := IlsPick.wanted({"stations": odd, "names": [], "dest": null, "arr_rwy": "", "pos": final(s, 12.0), "track": deg_to_rad(float(s.course_true)),
		"phase": "", "armed": false})
	return "" if w.s.get("ident") == s.ident else "a record with no geometry must not stop the pick: %s" % [w.s.get("ident")]
