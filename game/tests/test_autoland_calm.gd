extends RefCounted
## The A320 autoland in calm air at two runways with different ILS frequencies (VABB 27, VAPO 28), closed loop with the real
## autoflight and the real fly-by-wire law (tests/af_ils_rig.gd, helpers in tests/autoland_test_base.gd). Tolerances: touchdown
## 300 to 900 m past the threshold, within 5 m of the axis, sink under 300 ft/min, pitch under 10 deg, within 7 m of the axis on the
## roll out, the FMA words in order (G/S, LAND, FLARE, ROLL OUT, THR IDLE, RETARD, CAT3 DUAL), the AP drops by itself at a walking speed.

const B := preload("res://tests/autoland_test_base.gd")

var _b := B.new()
var _rigs: Array = []


func teardown() -> void:
	for r in _rigs:
		r.free_all()
	_rigs.clear()


func _one(part: int) -> String:
	var rw: Array = _b.runways()[part]
	var r := _b.land(_b.station(rw[0], rw[1]), {"nm": 3.2, "kias": 140.0})
	_rigs.append(r)
	var label := "%s %s calm" % [rw[0], rw[1]]
	var e := _b.check_landing(r, label)
	if e == "":
		e = _b.check_words(r, label)
	if e == "" and Props.get_b("ap/ap1"):
		e = "%s: the AP is still on at %.0f kt on the roll out" % [label, r.gs_kt()]
	return e


func test_autoland_vabb_27_calm() -> String:
	return _one(0)


func test_autoland_vapo_28_calm() -> String:
	return _one(1)
