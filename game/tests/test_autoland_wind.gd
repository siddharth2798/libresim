extends RefCounted
## The A320 autoland in a 14 kt crosswind with light turbulence (Dryden filters as in the game), from the right at VABB 27 and from the
## left at VAPO 28, and a 20 kt head wind with moderate turbulence, the same tolerances as tests/test_autoland_calm.gd (helpers in
## tests/autoland_test_base.gd). The crab is taken out in the flare, the roll out holds the axis with rudder and nose wheel.

const B := preload("res://tests/autoland_test_base.gd")

var _b := B.new()
var _rigs: Array = []


func teardown() -> void:
	for r in _rigs:
		r.free_all()
	_rigs.clear()


func _one(apt: String, rwy: String, rel: float, kt: float, turb: float, seed_n: int) -> String:
	var r := _b.land(_b.station(apt, rwy), {"nm": 4.0, "kias": 140.0, "wind_rel_deg": rel, "wind_kt": kt, "turb": turb, "seed": seed_n})
	_rigs.append(r)
	var label := "%s %s wind %d/%d turb %.2f" % [apt, rwy, int(rel), int(kt), turb]
	var e := _b.check_landing(r, label)
	if e == "":
		e = _b.check_words(r, label)
	if e == "" and absf(r.td.heading_err) > 5.0:
		e = "%s: %.1f deg of crab left at touchdown" % [label, r.td.heading_err]
	return e


func test_autoland_vabb_27_crosswind_from_the_right() -> String:
	return _one("VABB", "27", 90.0, 14.0, 0.33, 2)


func test_autoland_vapo_28_crosswind_from_the_left() -> String:
	return _one("VAPO", "28", -90.0, 14.0, 0.33, 3)


func test_autoland_vabb_27_head_wind_and_moderate_turbulence() -> String:
	return _one("VABB", "27", 0.0, 20.0, 0.5, 4)
