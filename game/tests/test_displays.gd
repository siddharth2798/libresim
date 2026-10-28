extends RefCounted
## P4 tests: panel.json loader (C172 rects unchanged, spans / rects / size), the glass displays (dry
## paint with default and plausible Props, FCU / MCDU / ND / SD clicks), tape / clip / projection maths,
## speed markers and the airliner instrument publishers.

const DISPLAYS := ["pfd", "nd", "ewd", "sd", "fcu", "mcdu"]
var _saved := {}


func _begin() -> void:
	_saved = Props.dump("")


func _end() -> void:
	Props._p.clear()
	Props.restore(_saved)


func _display(name: String) -> Display:
	return load("res://ui/displays/%s.gd" % name).new()


func _c172_layout() -> Dictionary:
	return InstrumentPanel.normalize(JSON.parse_string(FileAccess.get_file_as_string("res://aircraft/c172/panel.json")))


func test_disp_c172_panel_unchanged() -> String:
	var l := _c172_layout()
	var r := InstrumentPanel.rects_of(l)
	var want := {"asi": Rect2(12, 12, 190, 190), "ai": Rect2(202, 12, 190, 190), "vor2": Rect2(582, 214, 190, 190),
		"tach": Rect2(12, 416, 190, 190), "adf": Rect2(582, 416, 190, 190), "strip": Rect2(202, 416, 380, 190),
		"radios": Rect2(784, 12, 380, 594), "switches": Rect2(12, 618, 1152, 64)}
	for k in want:
		if r.get(k) != want[k]:
			return "%s: %s, was %s" % [k, r.get(k), want[k]]
	if InstrumentPanel.natural_size_of(l) != Vector2(1176, 688):
		return "natural size %s" % InstrumentPanel.natural_size_of(l)
	return "" if r.size() == 13 else "item count %d" % r.size()


func test_disp_panel_schema() -> String:
	var l := InstrumentPanel.normalize({"cell": 100, "pad": 10, "cols": 2, "rows": 1, "gauges": {
		"wide": {"script": "x", "cell": [0, 0], "span": [2, 1]}, "free": {"script": "y", "kind": "display", "rect": [500, 20, 300, 200]}}})
	var r := InstrumentPanel.rects_of(l)
	if r.wide != Rect2(10, 10, 200, 100):
		return "span: %s" % r.wide
	if r.free != Rect2(500, 20, 300, 200):
		return "rect: %s" % r.free
	if InstrumentPanel.natural_size_of(l) != Vector2(810, 230):  # free rect sticks out of the grid: room + pad
		return "grown size %s" % InstrumentPanel.natural_size_of(l)
	l["size"] = [1000, 700]
	if InstrumentPanel.natural_size_of(l) != Vector2(1000, 700):
		return "explicit size"
	return ""


func test_disp_a320_panel() -> String:
	var l := InstrumentPanel.normalize(JSON.parse_string(FileAccess.get_file_as_string("res://aircraft/a320/panel.json")))
	var r := InstrumentPanel.rects_of(l)
	var ns := InstrumentPanel.natural_size_of(l)
	for k in DISPLAYS:
		if not r.has(k) or l.gauges[k].get("kind") != "display":
			return "%s missing or not a display" % k
		if not Rect2(Vector2.ZERO, ns).encloses(r[k]):
			return "%s outside the panel" % k
		var d := _display(k)
		var ok: bool = absf(d.design.x / d.design.y - r[k].size.x / r[k].size.y) < 0.02
		d.free()
		if not ok:
			return "%s rect aspect differs from its design" % k
		for o in DISPLAYS:
			if o < k and r[o].intersects(r[k]):
				return "%s overlaps %s" % [k, o]
	return ""


func test_disp_render_all() -> String:
	_begin()
	for state in ["empty", "cruise", "approach"]:
		DisplayFixtures.set_state(state)
		for k in DISPLAYS:
			var d := _display(k)
			var n := d.dry_paint()
			d.free()
			if n < 20:
				_end()
				return "%s drew only %d commands with %s props" % [k, n, state]
	for page in SD.PAGES:
		var sd := SD.new()
		Props.set_v("sd/page", page)
		var n := sd.dry_paint()
		sd.free()
		if n < 20:
			_end()
			return "SD page %s empty" % page
	for page in MCDU.PAGE_IDS:
		var m := MCDU.new()
		Props.set_v("mcdu/page", page)
		var n := m.dry_paint()
		m.free()
		if n < 20:
			_end()
			return "MCDU page %s empty" % page
	_end()
	return ""


func test_disp_math() -> String:
	if not is_equal_approx(DispMath.tape_y(35100.0, 35000.0, 0.27, 221.0), 194.0):
		return "tape_y"
	var m := DispMath.tape_marks(280.0, 3.0, 137.0, 10.0)
	if m.size() != 9 or m[0] != 240.0 or m[-1] != 320.0:
		return "tape_marks %s" % [m]
	var cl := DispMath.clip_line(Vector2(-10, 5), Vector2(10, 5), Rect2(0, 0, 5, 10))
	if cl.size() != 2 or cl[0] != Vector2(0, 5) or cl[1] != Vector2(5, 5):
		return "clip_line %s" % [cl]
	if not DispMath.clip_line(Vector2(-10, 20), Vector2(10, 20), Rect2(0, 0, 5, 10)).is_empty():
		return "clip_line outside"
	var poly := DispMath.clip_poly(PackedVector2Array([Vector2(-5, -5), Vector2(5, -5), Vector2(5, 5), Vector2(-5, 5)]), Rect2(0, 0, 10, 10))
	if poly.size() != 4 or not is_equal_approx(absf(_area(poly)), 25.0):
		return "clip_poly area %s" % _area(poly)
	if not is_equal_approx(DispMath.hdg_x(350.0, 10.0, 2.0, 100.0), 60.0):
		return "hdg_x wraps"
	if not (is_equal_approx(DispMath.vs_frac(1000.0), 0.4) and is_equal_approx(DispMath.vs_frac(-2000.0), -0.7) and is_equal_approx(DispMath.vs_frac(9000.0), 1.0)):
		return "vs_frac"
	var p := DispMath.nd_project(Vector2(1000, 0), PI * 0.5, 10000.0, Vector2(300, 500), 100.0)  # heading east: east is ahead
	if p.distance_to(Vector2(300, 490)) > 0.01:
		return "nd_project %s" % p
	var s := DispMath.sphere_point(Vector2(0, -10), Vector2.ZERO, PI * 0.5)  # banked right: the sky moves left
	if s.distance_to(Vector2(-10, 0)) > 0.01:
		return "sphere_point %s" % s
	if DispMath.conf_text(1, 10.0) != "1+F" or DispMath.conf_text(1, 0.0) != "1" or DispMath.conf_text(4, 35.0) != "FULL":
		return "conf_text"
	return "" if DispMath.round_alt(35010.0) == 35020 else "round_alt"


func _area(p: PackedVector2Array) -> float:
	var a := 0.0
	for i in p.size():
		a += p[i].cross(p[(i + 1) % p.size()])
	return a * 0.5


func test_disp_airspeeds() -> String:
	var spec := AirSpeeds.spec_of({})
	var clean := AirSpeeds.markers(spec, 64000.0, 0.0, false, 101325.0)
	if absf(clean.vls - 134.0 * 1.23) > 0.01 or clean.vsw >= clean.vls or clean.vmax != 350.0:
		return "clean markers %s" % [clean]
	if absf(AirSpeeds.markers(spec, 256000.0, 0.0, false, 101325.0).vls - clean.vls * 2.0) > 0.01:
		return "Vls does not scale with sqrt(mass)"
	var full := AirSpeeds.markers(spec, 64000.0, 62.0, true, 101325.0)
	if full.vls >= clean.vls or full.vmax != 177.0:
		return "full config markers %s" % [full]
	if AirSpeeds.markers(spec, 64000.0, 0.0, true, 101325.0).vmax != 280.0:
		return "gear down Vle"
	var mmo := AirSpeeds.cas_kt_at_mach(0.82, 23842.0)
	if mmo < 270.0 or mmo > 300.0 or AirSpeeds.markers(spec, 64000.0, 0.0, false, 23842.0).vmax != mmo:
		return "Mmo speed at FL350 %.1f" % mmo
	return "" if is_equal_approx(AirSpeeds.table([[0.0, 10.0], [10.0, 20.0]], 5.0), 15.0) else "table"


func test_disp_air_data_publisher() -> String:
	_begin()
	Props.set_v("fdm/cas_mps", Units.kt_to_mps(250.0))
	Props.set_v("fdm/tas_mps", Units.kt_to_mps(445.0))
	Props.set_v("fdm/vs_mps", Units.FPM * -1500.0)
	Props.set_v("fdm/agl_m", 300.0)
	Props.set_v("fdm/mass_kg", 64000.0)
	Props.set_v("atmosphere/pressure_pa", 23842.0)
	Props.set_v("atmosphere/temperature_k", 218.8)
	Props.set_v("controls/baro/std", true)
	Props.set_v("failures/adr", false)
	var a := AirlinerAirData.new()
	a.publish(1.0 / 120.0)
	var err := ""
	if absf(Props.get_f("instruments/pfd/ias_kt") - 250.0) > 0.5:
		err = "ias %s" % Props.get_f("instruments/pfd/ias_kt")
	elif absf(Props.get_f("instruments/pfd/alt_ft") - 35000.0) > 60.0:
		err = "alt %s" % Props.get_f("instruments/pfd/alt_ft")
	elif absf(Props.get_f("instruments/pfd/vs_fpm") + 1500.0) > 1.0:
		err = "vs"
	elif absf(Props.get_f("instruments/pfd/mach") - 0.78) > 0.03:
		err = "mach %s" % Props.get_f("instruments/pfd/mach")
	elif absf(Props.get_f("instruments/pfd/ra_ft") - 984.3) > 1.0:
		err = "ra"
	elif not Props.get_b("instruments/pfd/baro_std") or Props.get_f("instruments/pfd/baro_hpa") != 1013.25:
		err = "baro std"
	Props.set_v("fdm/agl_m", 5000.0)
	Props.set_v("failures/adr", true)
	a.publish(1.0 / 120.0)
	if err == "" and (Props.get_b("instruments/pfd/valid") or Props.get_f("instruments/pfd/ias_kt") != 0.0 or Props.get_f("instruments/pfd/ra_ft") != -1.0):
		err = "failures/adr flag"
	a.free()
	_end()
	return err


func test_disp_adirs_and_engines() -> String:
	_begin()
	Props.set_v("fdm/pitch_rad", 0.05)
	Props.set_v("fdm/roll_rad", -0.1)
	Props.set_v("fdm/heading_rad", PI * 0.5)
	Props.set_v("fdm/track_rad", PI * 0.5 + 0.1)
	Props.set_v("fdm/accel_body", Vector3(0, 0, -9.81))
	Props.set_v("failures/adr", false)
	var ad := Adirs.new()
	ad.publish()
	var err := ""
	if absf(Props.get_f("instruments/adirs/heading_deg") - 90.3) > 0.01 or absf(Props.get_f("instruments/adirs/pitch_rad") - 0.05) > 1e-6:
		err = "adirs attitude / heading"
	elif Props.get_f("instruments/adirs/slip") != 0.0 or Adirs.slip_of(Vector3(0, 1.0, -9.81)) >= 0.0:
		err = "slip"
	Props.set_v("failures/adr", true)
	ad.publish()
	if err == "" and (Props.get_b("instruments/adirs/valid") or Props.get_f("instruments/adirs/roll_rad") != 0.0):
		err = "adirs failure flag"
	ad.free()
	var c := AirlinerEngines.to_display(0.865, 0.91, 913.15, 0.32, 358000.0)
	if err == "" and (absf(c.n1_pct - 86.5) > 1e-6 or absf(c.n2_pct - 91.0) > 1e-6 or absf(c.egt_c - 640.0) > 0.01 or absf(c.ff_kgh - 1152.0) > 0.01 or absf(c.oil_psi - 51.9) > 0.1):
		err = "engine units %s" % [c]
	Props.set_v("engine/count", 2)
	Props.set_v("engines/2/n1", 50.0)  # percent, like fdm_airliner_props
	Props.set_v("engines/2/ff", 0.25)
	Props.set_v("engines/2/running", true)
	var e := AirlinerEngines.new()
	e.publish(0.01)
	if err == "" and (Props.get_f("instruments/engines/2/n1_pct") != 50.0 or Props.get_f("instruments/engines/2/ff_kgh") != 900.0 or not Props.get_b("instruments/engines/2/running")):
		err = "engine publish"
	e.free()
	var w := NdFeed.wind_from(Vector3(0, 10, 0))  # air moving east = a west wind
	if err == "" and (absf(w.x - 270.0) > 0.01 or absf(w.y - 19.44) > 0.05):
		err = "wind_from %s" % w
	_end()
	return err


func test_disp_fcu_writes_props() -> String:
	_begin()
	var f := FCU.new()
	f.dry_paint()
	Props.set_v("controls/fcu/ap1", false)
	var ap1: Rect2 = _zone(f, "btn_ap1")
	if f._zone_at(ap1.get_center()) != "btn_ap1":
		f.free()
		_end()
		return "click zone of AP1"
	f._press("btn_ap1", MOUSE_BUTTON_LEFT, ap1.get_center())
	var err := "" if Props.get_b("controls/fcu/ap1") else "AP1 not set"
	f._press("btn_ap1", MOUSE_BUTTON_LEFT, ap1.get_center())
	if err == "" and Props.get_b("controls/fcu/ap1"):
		err = "AP1 not toggled back"
	for b in ["athr", "loc", "appr", "ap2"]:
		f._press("btn_" + b, MOUSE_BUTTON_LEFT, Vector2.ZERO)
		if err == "" and not Props.get_b("controls/fcu/" + b):
			err = "button " + b
	Props.set_v("controls/fcu/spd_kt", 250.0)
	var w: Rect2 = FCU.WIN[0]
	f._press("knob_spd", MOUSE_BUTTON_LEFT, w.get_center() + Vector2(20, 0))
	f._press("knob_spd", MOUSE_BUTTON_LEFT, w.get_center() + Vector2(20, 0))
	f._press("knob_spd", MOUSE_BUTTON_LEFT, w.get_center() - Vector2(20, 0))
	if err == "" and Props.get_f("controls/fcu/spd_kt") != 251.0:
		err = "SPD knob %s" % Props.get_f("controls/fcu/spd_kt")
	f._press("knob_spd", MOUSE_BUTTON_RIGHT, w.get_center() + Vector2(20, 0))
	if err == "" and Props.get_f("controls/fcu/spd_kt") != 261.0:
		err = "SPD right click x10"
	Props.set_v("controls/fcu/hdg_deg", 359.0)
	f._wheel("knob_hdg", 1.0)
	if err == "" and Props.get_f("controls/fcu/hdg_deg") != 0.0:
		err = "HDG wrap"
	Props.set_v("controls/fcu/alt_ft", 10000.0)
	f._wheel("knob_alt", 1.0)
	Props.set_v("controls/fcu/vs_fpm", 0.0)
	f._wheel("knob_vs", -1.0)
	if err == "" and (Props.get_f("controls/fcu/alt_ft") != 10100.0 or Props.get_f("controls/fcu/vs_fpm") != -100.0):
		err = "ALT / V/S steps"
	if err == "" and (FCU.stepped("alt", 39000.0, 5.0) != 39000.0 or FCU.stepped("vs", 5950.0, 5.0) != 6000.0):
		err = "knob limits"
	Props.set_v("controls/fcu/hdg_managed", false)
	f._press("knob_hdg", MOUSE_BUTTON_MIDDLE, Vector2.ZERO)
	if err == "" and not Props.get_b("controls/fcu/hdg_managed"):
		err = "HDG managed toggle"
	f.free()
	_end()
	return err


func _zone(d: Display, id: String) -> Rect2:
	for h in d._hot:
		if h[1] == id:
			return h[0]
	return Rect2()


func test_disp_mcdu_entry() -> String:
	_begin()
	var m := MCDU.new()
	m.dry_paint()
	Props.set_v("mcdu/page", "PERF")
	Props.set_v("mcdu/scratch", "")
	for k in ["k_1", "k_3", "k_8"]:
		m._press(k, MOUSE_BUTTON_LEFT, Vector2.ZERO)
	m._press("l1", MOUSE_BUTTON_LEFT, Vector2.ZERO)
	var err := ""
	if Props.get_f("mcdu/perf/v1") != 138.0 or str(Props.get_v("mcdu/scratch")) != "":
		err = "V1 not stored"
	m._press("l1", MOUSE_BUTTON_LEFT, Vector2.ZERO)  # empty scratchpad: copies the field
	if err == "" and str(Props.get_v("mcdu/scratch")) != "138":
		err = "line key copy"
	m._press("k_CLR", MOUSE_BUTTON_LEFT, Vector2.ZERO)
	if err == "" and str(Props.get_v("mcdu/scratch")) != "13":
		err = "CLR"
	m._press("k_CLR", MOUSE_BUTTON_RIGHT, Vector2.ZERO)
	m._press("k_A", MOUSE_BUTTON_LEFT, Vector2.ZERO)
	m._press("r1", MOUSE_BUTTON_LEFT, Vector2.ZERO)
	if err == "" and (str(Props.get_v("mcdu/scratch")) != "FORMAT ERROR" or Props.get_f("mcdu/perf/flex_c", -1.0) != -1.0):
		err = "numeric field accepted text"
	m._press("p_FPLN", MOUSE_BUTTON_LEFT, Vector2.ZERO)
	Props.set_v("controls/gps/target", "VABB")
	Props.set_v("controls/gps/route_next", ["VAPO"])
	Props.set_v("mcdu/scratch", "")
	for k in ["k_A", "k_B", "k_C", "k_D"]:
		m._press(k, MOUSE_BUTTON_LEFT, Vector2.ZERO)
	m._press("l2", MOUSE_BUTTON_LEFT, Vector2.ZERO)
	if err == "" and Props.get_v("controls/gps/route_next") != ["ABCD"]:
		err = "F-PLN replace %s" % [Props.get_v("controls/gps/route_next")]
	if err == "" and MCDU.with_waypoint(["A", "B"], 5, "C") != ["A", "B", "C"]:
		err = "with_waypoint append"
	m.free()
	_end()
	return err


func test_disp_nd_sd_clicks() -> String:
	_begin()
	var nd := ND.new()
	Props.set_v("controls/nd/mode", 0)
	Props.set_v("controls/nd/range_nm", 40.0)
	nd._press("mode", MOUSE_BUTTON_LEFT, Vector2.ZERO)
	nd._press("range", MOUSE_BUTTON_LEFT, Vector2.ZERO)
	var err := ""
	if Props.get_f("controls/nd/mode") != 1.0 or Props.get_f("controls/nd/range_nm") != 80.0:
		err = "ND mode / range"
	nd._wheel("range", -1.0)
	if err == "" and Props.get_f("controls/nd/range_nm") != 40.0:
		err = "ND range wheel"
	nd.free()
	var sd := SD.new()
	sd.dry_paint()
	sd._press("WHEEL", MOUSE_BUTTON_LEFT, Vector2.ZERO)
	if err == "" and (sd.page() != "WHEEL" or _zone(sd, "FUEL") == Rect2()):
		err = "SD page key"
	Props.set_v("sd/page", "nonsense")
	if err == "" and sd.page() != "ENG":
		err = "SD unknown page"
	sd.free()
	_end()
	return err


func test_disp_panel_builds_children_at_rects() -> String:
	var err := ""
	var a320 := InstrumentPanel.normalize(JSON.parse_string(FileAccess.get_file_as_string("res://aircraft/a320/panel.json")))
	for l in [_c172_layout(), a320]:
		var p := InstrumentPanel.new()
		p.layout_override = l
		p.size = InstrumentPanel.natural_size_of(l)
		p._ready()  # not in the tree (the root is busy during a test run): builds the children all the same
		var r := InstrumentPanel.rects_of(l)
		for k in l.gauges:
			var c: Control = p.get_node(k)
			if c.position != r[k].position or c.size != r[k].size:
				err = "%s at %s %s, want %s" % [k, c.position, c.size, r[k]]
		for k in ["strip", "radios", "switches"]:
			if l.has(k) and (p._items[k] as Control).size != r[k].size:
				err = "%s size" % k
		if l.gauges.has("pfd") and not (p.get_node("pfd") is Display):
			err = "pfd is not a Display"
		p.free()
		if err != "":
			return err
	return ""
