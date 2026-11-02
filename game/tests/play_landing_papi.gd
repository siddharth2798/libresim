extends RefCounted
## Test-only PAPI check of tests/play_landing.gd. Takes the real units the flight scene built for the
## landing runway end (RunwayLights._built[icao].papis) and checks, along the approach, that what the
## pilot's eye would see ("WWRR", outer unit first) matches a reading worked out here from the eye's
## elevation angle to each unit. Headless there are no pixels (the colour is a shader), so this is
## the data and the rule.

const ANGLES := [3.5, 3.1667, 2.8333, 2.5]  # inner -> outer, own copy of the standard
const SAMPLE_NM := [4.5, 3.0, 2.0, 1.0, 0.5]
const NM := 1852.0
const MAX_WAIT := 20.0  # s of flight to wait for the lights to be built

var units: Array = []
var problems: Array = []
var samples: Array = []  # printed "nm:reading@elev"
var seen: Dictionary = {}  # readings seen
var seq: Array = []  # distinct readings in order
var _done := {}
var _inited := false
var _t_check := 0.0
var _static_ok := false
var _gp_n := 0
var _gp_ww := 0
var _mismatch := 0
var _thr_elev := 0.0
var _unit_along := 0.0
var _unit_lat := 0.0


## Find the PAPI of the lesson's runway end; true when found. Records problems of its layout.
func find(flight: Node, ts: Node) -> bool:
	var rl: Node = flight.get_node("RunwayLights")
	var icao := str(Session.setup.airport)
	if not rl._built.has(icao):
		return false
	for p in rl._built[icao].papis:
		if str(p[0]) == str(Session.setup.runway):
			units = p[1]
			_check_layout(rl, ts)
			return true
	return false


func _fail(msg: String) -> void:
	if msg not in problems:
		problems.append(msg)


func _check_layout(rl: Node, ts: Node) -> void:
	var rw: Dictionary = ts._rw
	var thr: Vector2 = rw.thr
	var h := deg_to_rad(float(rw.hdg))
	var u := Vector2(sin(h), cos(h))
	var left := Vector2(-u.y, u.x)
	var width := 30.0
	for r in ts.airports.data.runways:
		if r.airport == Session.setup.airport and str(Session.setup.runway) in [str(r.ends[0].ident), str(r.ends[1].ident)]:
			width = float(r.width)
	var want_along := minf(300.0, float(rw.length) * 0.25)  # no glide-slope antenna: 300 m past the threshold
	for e in rl._ils:
		if e.airport == Session.setup.airport and str(e.runway) == str(Session.setup.runway):
			want_along = (Vector2(e.gs.x, e.gs.y) - thr).dot(u)  # abeam the glide-slope antenna
	if units.size() != 4:
		_fail("units=%d" % units.size())
		return
	var last_lat := 0.0
	_thr_elev = float(rw.elev)
	_unit_along = (Vector2(units[1].pos.x, units[1].pos.y) - thr).dot(u)
	_unit_lat = (Vector2(units[1].pos.x, units[1].pos.y) - thr).dot(left)
	for k in 4:
		var rel: Vector2 = Vector2(units[k].pos.x, units[k].pos.y) - thr
		var lat := rel.dot(left)
		if absf(float(units[k].angle) - float(ANGLES[k])) > 0.001:
			_fail("angle%d=%.3f" % [k, units[k].angle])
		if absf(rel.dot(u) - want_along) > 3.0:
			_fail("along%d=%.0f_want_%.0f" % [k, rel.dot(u), want_along])
		if lat < width * 0.5 + 5.0 or lat > width * 0.5 + 60.0 or lat <= last_lat:
			_fail("lateral%d=%.1f_not_left_of_runway" % [k, lat])
		last_lat = lat
	_static_ok = problems.is_empty()
	print("PLAY PAPI layout: %d units, along %.0f m (want %.0f), left offsets %.0f..%.0f m, angles %s -> %s" % [
		units.size(), (Vector2(units[0].pos.x, units[0].pos.y) - thr).dot(u), want_along,
		(Vector2(units[0].pos.x, units[0].pos.y) - thr).dot(left), last_lat, ANGLES, "OK" if _static_ok else str(problems)])


## The eye's elevation angle (deg) to each unit, inner first.
func _elevs(eye: Vector3) -> Array:
	var out := []
	for k in 4:
		var d: Vector3 = eye - units[k].pos
		out.append(rad_to_deg(atan2(d.z, Vector2(d.x, d.y).length())))
	return out


## What the eye sees, worked out here (outer unit first).
static func expected(elevs: Array) -> String:
	var out := ""
	for k in range(3, -1, -1):
		out += "W" if elevs[k] > ANGLES[k] else "R"
	return out


## Called every bot tick with the snapshot s and the eye (ENU). Samples at 4.5 / 3 / 2 / 1 / 0.5 nm
## out and once a second down to 300 m.
func tick(s: Dictionary, eye: Vector3, t: float) -> void:
	if units.is_empty():
		return
	var dist: float = s.dist
	if not _inited:
		_inited = true
		for nm in SAMPLE_NM:
			if nm * NM > dist + 100.0:
				_done[nm] = true  # started nearer than this
	var due := false
	for nm in SAMPLE_NM:
		if not _done.has(nm) and dist <= nm * NM:
			_done[nm] = true
			due = true
			_check(s, eye, "%.1fnm" % nm)
	if not due and dist > 300.0 and s.wow < 0.5 and t >= _t_check:
		_t_check = t + 1.0
		_check(s, eye, "")


func _check(s: Dictionary, eye: Vector3, label: String) -> void:
	var el := _elevs(eye)
	var mid := (float(el[0]) + float(el[3])) * 0.5
	var got := Papi.reading(units, eye)  # the game's rule
	var want := expected(el)  # worked out here
	var shape := not got.contains("RW")  # whites outside, reds inside
	if got != want:
		_mismatch += 1
		_fail("reading_%s_want_%s_at_%.0fm" % [got, want, s.dist])
	if not shape:
		_fail("reading_%s_not_monotone" % got)
	# the three clear cases from the elevation angle itself
	if mid > 3.6 and got != "WWWW" or mid < 2.4 and got != "RRRR" or mid > 2.95 and mid < 3.05 and got != "WWRR":
		_fail("reading_%s_at_%.2fdeg" % [got, mid])
	# cross-check with the bot's own path angle (gp_dev: from the threshold, crossing 15 m above it): the
	# angle that path gives to the unit (its distance and height above the threshold) must be the eye's
	if s.dist > 400.0:
		var hgt: float = 15.0 + s.dist * tan(deg_to_rad(3.0 + float(s.gp_dev))) - (float(units[1].pos.z) - _thr_elev)
		var pred: float = rad_to_deg(atan2(hgt, sqrt(pow(s.dist + _unit_along, 2.0) + _unit_lat * _unit_lat)))
		if absf(mid - pred) > 0.4:
			_fail("elev_%.2f_vs_bot_path_%.2f_at_%.0fm" % [mid, pred, s.dist])
	if absf(float(s.gp_dev)) <= 0.2 and s.dist > 400.0:
		_gp_n += 1
		_gp_ww += 1 if got == "WWRR" else 0
	seen[got] = true
	if seq.is_empty() or seq[-1] != got:
		seq.append(got)
	if label != "":
		samples.append("%s:%s@%.2f" % [label, got, mid])
		print("PLAY PAPI sample %s: sees %s (expected %s), eye %.2f deg, bot path %.2f deg, gp_dev %+.2f" % [label, got, want, mid, 3.0 + float(s.gp_dev), s.gp_dev])


## Verdict text after the run: "OK ..." or "FAIL ...". `need` = a reading that must have been seen ("" = none).
func verdict(need: String) -> Array:
	if units.is_empty():
		return [false, "no_papi_for_runway_%s" % Session.setup.runway]
	var bad := problems.duplicate()
	if samples.is_empty():
		bad.append("no_samples")
	if need != "" and not seen.has(need):
		bad.append("never_saw_%s" % need)
	if _gp_n >= 3 and _gp_ww * 2 < _gp_n:
		bad.append("WWRR_only_%d_of_%d_on_path" % [_gp_ww, _gp_n])
	var info := "seq=%s on_path_WWRR=%d/%d" % [">".join(PackedStringArray(seq)), _gp_ww, _gp_n]
	return [bad.is_empty(), (info if bad.is_empty() else info + " " + ",".join(PackedStringArray(bad)))]
