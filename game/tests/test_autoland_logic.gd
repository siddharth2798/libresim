extends RefCounted
## The autoland pieces that need no flight: the radio altitude is the height of the wheels, the landing capability rule (both APs, ILS
## with glide slope, gear down, CONF 3 or FULL, localizer captured), the fly-by-wire flare mode stays off while the autopilot flies
## (the autoland flares through the load factor it demands), and the glide slope capture window in height (above and below the path).
## The mode sequences (LAND, FLARE, ROLL OUT, the disconnects) are rows of tests/fcu_truth_table.json; closed loops in tests/test_autoland_*.gd.

const KEEP := ["fdm/agl_m", "fdm/wheel_depth_m"]

var _saved := {}


func teardown() -> void:
	for k in _saved:
		if _saved[k] == null:
			Props._p.erase(k)
		else:
			Props.set_v(k, _saved[k])
	_saved.clear()


func _ils(i: AfInputs) -> void:
	i.ils = {"course": 0.0, "loc": Vector2(0.0, 4000.0), "gs_pos": Vector2(0.0, 300.0), "gs_h": 0.0, "gs_rad": deg_to_rad(3.0), "gs_valid": true}


func test_radio_altitude_is_the_height_of_the_wheels() -> String:
	for k in KEEP:
		_saved[k] = Props.get_v(k) if Props.has(k) else null
	Props.set_v("fdm/agl_m", 3.6)  # the CG on the runway
	Props.set_v("fdm/wheel_depth_m", 3.6)
	var i := AfInputs.new()
	i.read(0.01, null)
	var on_ground := i.ra_m
	Props.set_v("fdm/agl_m", 15.0)
	i.read(0.01, null)
	return "" if on_ground == 0.0 and absf(i.ra_m - 11.4) < 0.01 else "radio altitude %.2f m on the runway (want 0) and %.2f m at CG height 15 m (want 11.4)" % [on_ground, i.ra_m]


func test_autoland_capability_rule() -> String:
	var i := AfInputs.new()
	_ils(i)
	i.flap_lever = 5
	i.gear_down = true
	var lat := AfLateral.new()
	lat.mode = "LOC"
	if not AfLand.capable(i, true, true, lat):
		return "both APs, ILS, gear down, CONF FULL, LOC captured: capable"
	var bad := []
	if AfLand.capable(i, true, false, lat) or AfLand.capable(i, false, true, lat):
		bad.append("one AP only")
	i.flap_lever = 3
	if AfLand.capable(i, true, true, lat):
		bad.append("CONF 2")
	i.flap_lever = 4
	if not AfLand.capable(i, true, true, lat):
		bad.append("CONF 3 is a landing configuration")
	i.gear_down = false
	if AfLand.capable(i, true, true, lat):
		bad.append("gear up")
	i.gear_down = true
	i.ils.gs_valid = false
	if AfLand.capable(i, true, true, lat):
		bad.append("no glide slope signal")
	i.ils.gs_valid = true
	lat.mode = "HDG"
	if AfLand.capable(i, true, true, lat):
		bad.append("localizer not captured")
	lat.mode = "LOC"
	i.ils = {}
	if AfLand.capable(i, true, true, lat):
		bad.append("no ILS")
	return "" if bad.is_empty() else "capable when it should not be: %s" % [bad]


func test_flare_mode_of_the_fly_by_wire_is_off_while_the_autopilot_flies() -> String:
	var l := FbwLaw.new()
	l.par = FbwParams.from_def(AircraftDef.load_def("a320"))
	var s := l.s
	s.gear_pos = 1.0
	s.lever = 0.0
	s.ra_ft = 20.0
	s.dt = 0.01
	l.pitch.demand(s, l.par, l.prot, 0.0, false)
	var manual: bool = l.pitch.flare
	l.pitch.demand(s, l.par, l.prot, 0.0, true)
	return "" if manual and not l.pitch.flare else "flare mode: manual %s (want true), autopilot %s (want false)" % [manual, l.pitch.flare]


func test_glide_slope_capture_window_is_in_angle() -> String:
	var v := AfVertical.new()
	var i := AfInputs.new()
	_ils(i)
	i.f.appr = true
	i.alt_m = 0.0
	i.gs_mps = 70.0
	i.tas = 72.0
	var bad := []
	for case in [[7.0, 60.0, true], [7.0, 100.0, false], [7.0, -20.0, true], [7.0, -60.0, false], [2.0, 14.0, true], [2.0, 40.0, false]]:
		var nm: float = case[0]
		var dev: float = case[1]  # m above the path
		var gd := nm * 1852.0
		i.pos = Vector3(0.0, 300.0 - gd, tan(deg_to_rad(3.0)) * gd + dev)
		v.reset()
		v.set_mode("V/S")
		v.update(i, 0.0, true)
		var captured := v.mode == "G/S*"
		if captured != case[2]:
			bad.append("%.0f nm out, %.0f m above the path: captured %s, want %s" % [nm, dev, captured, case[2]])
	return "" if bad.is_empty() else "\n".join(bad)
