extends RefCounted
## The A320 glide slope capture, closed loop with the real autoflight, fly-by-wire law and FDM (tests/af_ils_rig.gd), at two runways
## with different ILS frequencies (VABB 27, VAPO 28): APPR armed (LOC and G/S blue), LOC* then LOC, then G/S* and G/S, down the 3 degree
## path. From below, level at the platform altitude (the way a real approach flows); from a little above the path (the old fixed 15 m
## window never captured an aircraft 50 ft or more above the path that stayed level: G/S* never appeared); and no capture from far above.

const B := preload("res://tests/autoland_test_base.gd")

var _b := B.new()
var _rigs: Array = []


func teardown() -> void:
	for r in _rigs:
		r.free_all()
	_rigs.clear()


## `dev_m`: metres above (+) or below (-) the path at the start, `nm` out, level, LOC and APPR pressed, both APs on.
func _start(rw: Array, nm: float, dev_m: float) -> AfIlsRig:
	var st := _b.station(rw[0], rw[1])
	var path_ft := (tan(deg_to_rad(float(st.gs_deg))) * nm * 1852.0 + 15.0 + dev_m) / AfIlsRig.FT
	var r := AfIlsRig.new(_b.db(), st, {"nm": nm, "alt_ft": path_ft, "kias": 140.0})
	_rigs.append(r)
	return r


## Capture, then 40 s on the path: the vertical column has G/S* then G/S and the aircraft is within 10 m of the path.
func _check(r: AfIlsRig, rw: Array, label: String, secs: float) -> String:
	r.run(secs)
	var v: Array = r.words.vertical
	var gs := v.find("G/S")
	if v.find("G/S*") < 0 or gs < 0 or gs < v.find("G/S*"):
		return "%s %s %s: vertical column %s, want G/S* then G/S (FMA %s)" % [rw[0], rw[1], label, v, r.fma_all()]
	var lat: Array = r.words.lateral
	if lat.find("LOC") < 0:
		return "%s %s %s: lateral column %s, want LOC" % [rw[0], rw[1], label, lat]
	var st := _b.station(rw[0], rw[1])
	var gd := Vector2(r.f.pos_e, r.f.pos_n).distance_to(Vector2(st.gs.x, st.gs.y))
	var h := -r.f.pos_d - (float(st.gs.h) + tan(deg_to_rad(float(st.gs_deg))) * gd)
	if absf(h) > 10.0 or r.crashed:
		return "%s %s %s: %.1f m off the path 40 s after the capture" % [rw[0], rw[1], label, h]
	print("    %s %s %s: %s, %.1f m from the path at the end" % [rw[0], rw[1], label, v, h])
	return ""


func test_capture_from_below_level_at_the_platform_two_runways() -> String:
	for rw in _b.runways():
		var r := _start(rw, 6.5, -150.0)  # 150 m below the path, level: the path comes down to it in about 40 s
		var e := _check(r, rw, "from below", 85.0)
		if e != "":
			return e
	return ""


func test_capture_from_a_little_above_the_path() -> String:
	for rw in _b.runways():
		var r := _start(rw, 6.0, 40.0)  # 40 m = 130 ft above the path, level: never captured before
		var e := _check(r, rw, "from above", 70.0)
		if e != "":
			return e
	return ""


func test_no_capture_from_far_above_and_the_glide_slope_stays_armed() -> String:
	var rw: Array = _b.runways()[1]
	var r := _start(rw, 6.0, 300.0)
	r.run(40.0)
	if "G/S*" in r.words.vertical or "G/S" in r.words.vertical:
		return "captured the beam from 300 m above: %s" % [r.words.vertical]
	return "" if str(Props.get_v("ap/fma/vertical", "")).contains("G/S") else "G/S is not armed (cyan) while above the path: %s" % r.fma_all()
