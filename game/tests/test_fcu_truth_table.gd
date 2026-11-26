extends Node
## The A320 FCU truth table (docs/A320-FCU-REFERENCE.md, kept as data in tests/fcu_truth_table.json so the document and the
## test agree): the autoflight modes each push / pull / turn / button gives (AfLogic), the FMA colours (AfFma.color), the FCU
## windows (FcuWindows), and the preview timers (AfPreview). Nothing here touches the sim; Props are restored.

const FPM := 0.00508  # m/s per ft/min
const TABLE := "res://tests/fcu_truth_table.json"

var _saved := {}


func teardown() -> void:
	for p in _saved:
		if _saved[p] == null:
			Props._p.erase(p)
		else:
			Props.set_v(p, _saved[p])
	_saved.clear()


func _table() -> Dictionary:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(TABLE))
	return d if d is Dictionary else {}


func _inputs(base: Dictionary) -> AfInputs:
	var i := AfInputs.new()
	i.dt = 0.1
	i.powered = true
	i.wow = bool(base.get("wow", false))
	i.ra_m = 0.0 if i.wow else 3000.0
	i.flex_c = float(base.get("flex_c", 0.0))
	i.pressure_pa = float(base.get("pressure_pa", 101325.0))
	i.cas = 130.0
	i.tas = 200.0
	i.gs_mps = 200.0
	i.alt_m = Units.ft_to_m(float(base.get("alt_ft", 10000)))
	i.lever = float(base.get("lever", 0.3))
	i.engine_lever = i.lever
	i.f.fd = bool(base.get("fd", true))
	i.f.ap1 = true
	i.f.alt = Units.ft_to_m(float(base.get("fcu_alt_ft", 10000)))
	i.f.spd = 130.0
	i.f.vs = float(base.get("vs_fpm", 0)) * FPM
	i.f.vs_mgd = bool(base.get("vs_mgd", false))
	i.f.spd_mgd = bool(base.get("spd_mgd", false))
	if base.get("gps", false):
		i.gps = {"brg": 0.0, "dist": 50000.0, "xtk": 0.0}
	i.flap_lever = int(base.get("flap_lever", 0))
	i.f.ap2 = bool(base.get("ap2", false))
	i.f.appr = bool(base.get("appr", false))
	if base.get("ils", false):  # an ILS to the north, the 3 degree path with its antenna 300 m up the runway, the aircraft on it
		i.ils = {"course": 0.0, "loc": Vector2(0.0, 4000.0), "gs_pos": Vector2(0.0, 300.0), "gs_h": 0.0, "gs_rad": deg_to_rad(3.0), "gs_valid": true}
		_on_path(i, float(base.get("ra_ft", 600)))
	return i


## On the path at `ra_ft` over a flat runway at height 0, on the axis, 70 m/s down the path.
func _on_path(i: AfInputs, ra_ft: float) -> void:
	var h := Units.ft_to_m(ra_ft)
	i.ra_m = h
	i.pos = Vector3(0.0, 300.0 - h / tan(deg_to_rad(3.0)), h)
	i.alt_m = h
	i.gs_mps = 70.0
	i.tas = 72.0
	i.vs_mps = -3.7
	i.heading = 0.0
	i.track = 0.0


func _apply(i: AfInputs, f: Dictionary) -> void:
	for k in f:
		match k:
			"fcu_alt_ft": i.f.alt = Units.ft_to_m(float(f[k]))
			"vs_fpm": i.f.vs = float(f[k]) * FPM
			"lever":
				i.lever = float(f[k])
				i.engine_lever = i.lever
			"wow": i.wow = bool(f[k])
			"ra_ft":
				if i.ils.is_empty():
					i.ra_m = Units.ft_to_m(float(f[k]))
				else:
					_on_path(i, float(f[k]))
			"flap_lever": i.flap_lever = int(f[k])
			"gs_mps": i.gs_mps = float(f[k])
			"gs_valid": i.ils.gs_valid = bool(f[k])
			"ils_off": i.ils = {}
			"alt_ft": i.alt_m = Units.ft_to_m(float(f[k]))
			_: i.f[k] = f[k]


## The state the node writes back to the FCU, as the next tick reads it.
func _write_back(i: AfInputs, logic: AfLogic, mirror_ap := false) -> void:
	for k in ["hdg_mgd", "vs_mgd"]:
		if logic.writes.has(k):
			i.f[k] = logic.writes[k]
	if logic.writes.has("vs"):
		i.f.vs = float(logic.writes.vs)
	i.f.athr = logic.thr.armed  # the button follows the state
	if mirror_ap:  # as the node does (_sync_fcu): a disconnected AP is not asked for again
		i.f.ap1 = logic.ap1
		i.f.ap2 = logic.ap2


func _check(logic: AfLogic, i: AfInputs, seen: Array, e: Dictionary) -> String:
	var got := {"vert": logic.vert.mode, "lat": logic.lat.mode, "armed_vert": logic.vert.armed, "armed_lat": logic.lat.armed,
		"vs_mgd": i.f.vs_mgd, "hdg_mgd": i.f.hdg_mgd, "athr_armed": logic.thr.armed, "athr_active": logic.thr.active,
		"fma_lat": logic.fma.lateral, "fma_thrust": logic.fma.thrust, "fma_misc": logic.fma.misc,
		"fma_vert": logic.fma.vertical, "fma_appr": logic.fma.approach, "land": logic.land.phase, "ap1": logic.ap1, "ap2": logic.ap2,
		"disc": logic.disconnect_count, "warning": logic.warning, "spd_preview": logic.spd_preset > 0.0, "vs": i.f.vs / FPM, "level": absf(logic.vert.gamma_cmd) < 0.002}
	for k in e:
		if k == "writes":
			for w in e[k]:
				if not w in seen:
					return "writes %s expected %s" % [seen, e[k]]
		elif k == "vs":
			if absf(float(got.vs) - float(e[k])) > 1.0:
				return "V/S target %.0f expected %s" % [got.vs, e[k]]
		elif k == "disc":
			if int(got.disc) != int(e[k]):
				return "%d disconnects, expected %d" % [got.disc, e[k]]
		elif str(got[k]) != str(e[k]):
			return "%s is %s, expected %s" % [k, got[k], e[k]]
	return ""


func test_modes_follow_the_truth_table() -> String:
	var bad := []
	for row in _table().get("modes", []):
		var i := _inputs(row.base)
		var logic := AfLogic.new({})
		var n := 0
		for st in row.steps:
			n += 1
			_apply(i, st.get("f", {}))
			var seen := []
			for t in int(st.get("n", 1)):
				i.f.select = str(st.get("select", "")) if t == 0 else ""
				logic.update(i)
				seen.append_array(logic.writes.keys())
				_write_back(i, logic, bool(row.base.get("ils", false)))
			var err := _check(logic, i, seen, st.get("expect", {}))
			if err != "":
				bad.append("%s (step %d): %s" % [row.id, n, err])
				break
	return "" if bad.is_empty() else "\n".join(bad)


func test_fma_colours_follow_the_truth_table() -> String:
	var bad := []
	for r in _table().get("colors", []):
		var got := AfFma.color(str(r.col), int(r.line), str(r.text), bool(r.get("athr_active", false)))
		if got != str(r.expect):
			bad.append("%s line %d of '%s' (A/THR active %s): %s, expected %s" % [r.col, r.line, r.text, r.get("athr_active", "-"), got, r.expect])
	return "" if bad.is_empty() else "\n".join(bad)


func test_fma_boxes_follow_the_truth_table() -> String:
	var bad := []
	for r in _table().get("boxes", []):
		var got := AfFma.box(str(r.col), str(r.text))
		if got != str(r.expect):
			bad.append("%s '%s': box '%s', expected '%s'" % [r.col, r.text, got, r.expect])
		if AfFma.flashes(str(r.col), str(r.text)) != bool(r.get("flashes", false)):
			bad.append("%s '%s': flashing is %s" % [r.col, r.text, not bool(r.get("flashes", false))])
	return "" if bad.is_empty() else "\n".join(bad)


func test_fcu_windows_follow_the_truth_table() -> String:
	var bad := []
	for r in _table().get("windows", []):
		Props.set_v("controls/fcu/spd_mach", false)
		for p in r.props:
			if not _saved.has(p):
				_saved[p] = Props.get_v(p, null)
			Props.set_v(p, r.props[p])
		Props.set_v("controls/fcu/trk_fpa", false)
		Props.set_v("systems/electrical/avionics_powered", true)
		var w: Dictionary = {}
		match str(r.win):
			"spd": w = FcuWindows.spd()
			"hdg": w = FcuWindows.hdg()
			"alt": w = FcuWindows.alt()
			_: w = FcuWindows.vs()
		if str(r.get("label", w.label)) != str(w.label):
			bad.append("%s: label '%s', expected '%s'" % [r.id, w.label, r.label])
		if w.text != r.text or bool(w.dot) != bool(r.dot):
			bad.append("%s: shows '%s' dot %s, expected '%s' dot %s" % [r.id, w.text, w.dot, r.text, r.dot])
	return "" if bad.is_empty() else "\n".join(bad)


func test_refused_presses_spring_back_on_the_fcu() -> String:
	var snap := Props._p.duplicate()
	var af := Autoflight.new()
	af.setup({})
	for k in ["ap1", "ap2", "athr", "loc", "appr", "hdg_managed", "vs_managed", "ap_disc", "athr_disc"]:
		Props.set_v("controls/fcu/" + k, false)  # earlier suites may leave an AP engaged
	Props.set_v("failures/ap", false)
	Props.set_v("fdm/wow", false)
	Props.set_v("fdm/alt_m", 3000.0)
	Props.set_v("fdm/agl_m", 3000.0)
	Props.set_v("fdm/cas_mps", 70.0)
	Props.set_v("fdm/tas_mps", 90.0)
	Props.set_v("controls/fcu/fd", false)  # no AP, no FD: nothing can arm
	Props.set_v("controls/fcu/loc", true)
	Props.set_v("controls/fcu/appr", true)
	af.tick(0.1)
	var no_guidance := [Props.get_b("controls/fcu/loc"), Props.get_b("controls/fcu/appr"), Props.get_b("ap/loc")]
	Props.set_v("controls/fcu/fd", true)  # the FD on, no route: a managed heading push is refused
	Props.set_v("controls/fcu/hdg_managed", true)
	Props.set_v("controls/fcu/loc", true)
	af.tick(0.1)
	af.tick(0.1)
	var with_fd := [Props.get_b("controls/fcu/hdg_managed"), Props.get_b("controls/fcu/loc"), Props.get_b("ap/loc"), str(Props.get_v("ap/fma/lateral"))]
	af.free()
	for k in Props._p.keys():
		if not snap.has(k):
			Props._p.erase(k)
	for k in snap:
		Props._p[k] = snap[k]
	if no_guidance != [false, false, false]:
		return "LOC / APPR pressed with no AP and no FD arm nothing and spring back: %s" % [no_guidance]
	return "" if with_fd == [false, true, true, "HDG\nLOC"] else "FD on, no route: %s (HDG push refused, LOC armed and lit)" % [with_fd]


func test_every_knob_has_push_and_pull_keys_equal_to_the_cockpit_knob() -> String:
	var lev: Dictionary = AircraftDef.load_def("a320").section("cockpit").levers
	var t := KeyBindings.defaults()
	var sh := KeyBindings.shifted_keys(t)
	for k in ["spd", "hdg", "alt", "vs"]:
		for way in ["push", "pull"]:
			var a := "fcu_%s_%s" % [k, way]
			var want: Dictionary = lev[k + "_sel"][way]
			if ControlActions.SETS.get(a, {}) != want:
				return "%s writes %s but the cockpit knob %s writes %s" % [a, ControlActions.SETS.get(a), way, want]
			if ControlActions.group_of(a) != "fcu" or not a in InputBindings.BUTTONS or InputBindings.LABELS.get(a, "") == "":
				return "%s is an FCU action with a joystick button and a label" % a
			if KeyLabels.LABELS.get(a, "") == "" or t.get(a, []).is_empty():
				return "%s has a key label and a default key" % a
	var e := InputEventKey.new()
	e.physical_keycode = KEY_UP
	e.alt_pressed = true
	e.shift_pressed = true
	e.pressed = true
	if not KeyBindings.matches(t, "fcu_alt_pull", e, sh) or KeyBindings.matches(t, "fcu_alt_up", e, sh):
		return "Shift+Alt+Up pulls the ALT knob and does not also turn it"
	return ""


func test_previews_time_out_as_documented() -> String:
	var i := AfInputs.new()
	i.dt = 0.1
	var p := AfPreview.new()
	i.f.hdg_mgd = true
	i.f.spd_mgd = true
	p.update(i, false)
	i.f.hdg = 1.0
	i.f.spd = 140.0
	i.f.vs = 5.0 * FPM * 100.0
	p.update(i, false)
	if p.hdg != AfPreview.HDG_S or p.spd != AfPreview.SPD_S or p.vs != AfPreview.VS_S:
		return "a turn starts every preview: hdg %s spd %s vs %s" % [p.hdg, p.spd, p.vs]
	if AfPreview.VS_S != 45.0 or AfPreview.HDG_S != 45.0 or AfPreview.SPD_S != 10.0:
		return "documented times: V/S 45 s, HDG 45 s, SPD 10 s"
	for k in int(AfPreview.SPD_S / i.dt) + 2:
		p.update(i, false)
	if p.spd > 0.0 or p.hdg <= 0.0 or p.vs <= 0.0:
		return "after 10 s only the speed preview is over: hdg %.1f spd %.1f vs %.1f" % [p.hdg, p.spd, p.vs]
	for k in int(AfPreview.VS_S / i.dt):
		p.update(i, false)
	if p.hdg > 0.0 or p.vs > 0.0:
		return "after 45 s all previews are over: hdg %.1f vs %.1f" % [p.hdg, p.vs]
	i.f.hdg = 2.0
	p.update(i, false)
	i.f.hdg_mgd = false  # pulled: selected, no preview
	p.update(i, false)
	return "" if p.hdg == 0.0 else "a pull ends the heading preview"
