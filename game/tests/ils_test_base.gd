extends RefCounted
## Shared helpers of tests/test_ils_pick.gd and tests/test_ils_autotune.gd. The ILS stations come from the NavDatabase
## (simulated and real records alike): the tests pick them from it and never name an ident or a frequency, so they hold
## when the ILS data changes. Props the tests touch are saved by begin() and put back by teardown().

const NM := 1852.0
const START_MHZ := 116.6  # NAV2 at the start of a test: a VOR channel, no ILS
const KEYS := ["controls/nav2/freq_mhz", "controls/nav2/obs_deg", "controls/nav1/freq_mhz", "controls/ils_auto/resume", "controls/fcu/loc",
	"controls/fcu/appr", "fdm/position_enu", "fdm/track_rad", "fdm/wow", "route/dest", "mcdu/init/from_to", "mcdu/init/arr_rwy",
	"mcdu/scratch", "ap/fma/lateral", "avionics/fms/phase", "avionics/nav2/kind", "avionics/nav2/valid", "avionics/nav2/ident",
	"avionics/nav2/gs_valid", "avionics/ils_auto/ident", "avionics/ils_auto/mhz", "avionics/ils_auto/active", "avionics/ils_auto/manual",
	"avionics/ils_auto/why", "systems/electrical/avionics_powered", "controls/efis/ls", "failures/nav1", "failures/nav2"]

var _saved := {}
var _opt: Variant = null
var _made: Array = []
var _db: NavDatabase


func teardown() -> void:
	for n in _made:
		if is_instance_valid(n):
			n.free()
	_made.clear()
	for k in _saved:
		if _saved[k] == null:
			Props._p.erase(k)
		else:
			Props.set_v(k, _saved[k])
	_saved.clear()
	if _opt != null:
		UserOptions.set_v("ils_autotune", _opt)
		_opt = null


func begin() -> void:
	for k in KEYS:
		if not _saved.has(k):
			_saved[k] = Props.get_v(k) if Props.has(k) else null
	for k in ["failures/nav1", "failures/nav2", "fdm/wow", "controls/fcu/loc", "controls/fcu/appr", "controls/ils_auto/resume",
			"avionics/nav2/valid"]:
		Props.set_v(k, false)
	Props.set_v("systems/electrical/avionics_powered", true)
	Props.set_v("controls/efis/ls", true)
	Props.set_v("controls/nav2/freq_mhz", START_MHZ)
	Props.set_v("ap/fma/lateral", "NAV")
	for k in ["avionics/fms/phase", "avionics/nav2/kind", "avionics/nav2/ident", "mcdu/init/from_to", "mcdu/init/arr_rwy", "route/dest"]:
		Props.set_v(k, "")


func stations() -> Array:
	if _db == null:
		_db = NavDatabase.new()
	return _db.ils


## Two stations at one airport with different frequencies (so a change of arrival runway is a change of frequency): [a, b] or [].
func pair() -> Array:
	for a in stations():
		for b in _db.ils:
			if a.airport == b.airport and absf(float(a.mhz) - float(b.mhz)) > 0.01 and a.runway != b.runway:
				return [a, b]
	return []


## The airport (NavDatabase.airport) of station `s`.
func airport_of(s: Dictionary) -> Dictionary:
	stations()
	return _db.airport(str(s.airport))


## `nm` out on the final approach course of `s`, on its 3 degree path (ENU).
func final(s: Dictionary, nm: float, extra_ft := 0.0) -> Vector3:
	var c := deg_to_rad(float(s.course_true))
	var th := Vector2(s.threshold.x, s.threshold.y) - Vector2(sin(c), cos(c)) * nm * NM
	return Vector3(th.x, th.y, float(s.threshold.h) + tan(deg_to_rad(3.0)) * nm * NM + extra_ft * 0.3048)


## A cruise point `nm` back along the final approach course of `s`, high above it (route tests: far from the threshold).
func far(s: Dictionary, nm: float, alt_m := 3000.0) -> Vector3:
	var p := final(s, nm)
	return Vector3(p.x, p.y, alt_m + float(s.threshold.h))


func fly(p: Vector3, track_deg: float) -> void:
	Props.set_v("fdm/position_enu", p)
	Props.set_v("fdm/track_rad", deg_to_rad(track_deg))


func node(airliner := true) -> IlsAutotune:
	var n := IlsAutotune.new()
	stations()
	n.db = _db
	n.airliner = airliner
	_made.append(n)
	return n


## The plan the way the MCDU files it: FROM/TO, ARR RWY and the route's destination.
func plan(dest: String, rwy: String) -> void:
	Props.set_v("mcdu/init/from_to", "VABB/" + dest if dest != "" else "")
	Props.set_v("mcdu/init/arr_rwy", rwy)
	Props.set_v("route/dest", dest)


func plan_of(s: Dictionary) -> void:
	plan(str(s.airport), str(s.runway))


func mhz() -> float:
	return Props.get_f("controls/nav2/freq_mhz")


func ctx(dest: String, rwy: String, pos: Vector3, track_deg: float, phase := "", armed := false) -> Dictionary:
	stations()
	var ap := _db.airport(dest) if dest != "" else {}
	return {"stations": _db.ils, "names": [str(ap.get("icao", "")), str(ap.get("ident", ""))] if not ap.is_empty() else [],
		"dest": Vector2(ap.x, ap.y) if not ap.is_empty() else null, "arr_rwy": rwy, "pos": pos, "track": deg_to_rad(track_deg),
		"phase": phase, "armed": armed}
