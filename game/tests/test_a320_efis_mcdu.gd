extends RefCounted
## A320 cockpit additions: every ND mode (NdModes; the EFIS knob order and its 3D pivots), the FCU knobs springing in
## and out on push / pull (CockpitLevers), the MCDU on long routes (text fitted to the screen, F-PLN scrolling) and the
## PEDALS DISC button (pedals stop steering the nose wheel; the key binding).

var _saved := {}


func _begin() -> void:
	_saved = Props.dump("")


func _end() -> void:
	Props._p.clear()
	Props.restore(_saved)


func _levers() -> Dictionary:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://aircraft/a320/aircraft.json"))
	return d.cockpit.levers


func test_nd_modes_all_five() -> String:
	_begin()
	var err := ""
	var nd := ND.new()
	Props.set_v("fdm/position_enu", Vector3.ZERO)
	Props.set_v("instruments/nd/route", [{"id": "AAA", "x": 30000.0, "y": 40000.0}])
	Props.set_v("avionics/nav1/valid", true)
	Props.set_v("avionics/nav1/cdi_raw", 0.5)
	Props.set_v("avionics/nav2/valid", true)
	Props.set_v("avionics/nav2/kind", "ILS")
	Props.set_v("avionics/nav2/gs_valid", true)
	var calls := {}
	for m in 5:
		Props.set_v("controls/nd/mode", m)
		calls[m] = nd.dry_paint()
	if calls[NdModes.VOR] <= calls[NdModes.NAV] - 3 and calls[NdModes.LS] <= calls[NdModes.VOR]:
		err = "radio modes draw nothing extra %s" % calls
	if err == "" and (NdModes.receiver(NdModes.VOR) != 1 or NdModes.receiver(NdModes.LS) != 2 or NdModes.receiver(NdModes.ARC) != 0):
		err = "receivers"
	if err == "" and ND.plan_centre(Vector2(1, 2), [{"x": 30.0, "y": 40.0}]) != Vector2(30, 40):
		err = "PLAN centres on the active waypoint"
	if err == "" and ND.plan_centre(Vector2(1, 2), []) != Vector2(1, 2):
		err = "PLAN without a route centres on the aircraft"
	var order := []
	var m := NdModes.LS
	for i in 5:
		order.append(NdModes.NAMES[m])
		m = NdModes.step(m, 1)
	if err == "" and order != ["ROSE LS", "ROSE VOR", "ROSE NAV", "ARC", "PLAN"]:
		err = "knob order %s" % [order]
	var b := NdModes.bar_offset(1.0, 0.0, 200.0)  # course straight up, fly right: bar two dots right
	if err == "" and not b.is_equal_approx(Vector2(80, 0)):
		err = "deviation bar %s" % b
	if err == "" and not NdModes.bar_offset(-5.0, 0.0, 200.0).is_equal_approx(Vector2(-80, 0)):
		err = "deviation bar clamps"
	Props.set_v("controls/nav1/freq_mhz", 116.6)
	Props.set_v("controls/nav1/obs_deg", 270.0)
	Props.set_v("avionics/nav1/ident", "BBB")
	if err == "" and NdModes.receiver_lines(NdModes.VOR, 1).slice(0, 4) != ["VOR1", "116.60", "CRS 270", "BBB"]:
		err = "receiver lines %s" % [NdModes.receiver_lines(NdModes.VOR, 1)]
	nd.free()
	_end()
	return err


func test_efis_knobs_turn_through_every_mode() -> String:
	var lv := _levers()
	for side in ["cpt", "fo"]:
		var m: Dictionary = lv["nd_mode_" + side]
		if m.get("values") != [3.0, 2.0, 1.0, 0.0, 4.0]:
			return "%s mode detents %s" % [side, m.get("values")]
		var angles := {}
		for row in m.get("map", []):
			angles[int(row[0])] = float(row[1])
		if angles.size() != 5:
			return "%s mode has no animation for every mode %s" % [side, angles]
		# one detent of the knob is 45 deg, in dial order LS VOR NAV ARC PLAN (the pivot turns + anticlockwise)
		for pair in [[3, 2], [2, 1], [1, 0], [0, 4]]:
			if not is_equal_approx(angles[pair[0]] - angles[pair[1]], 45.0):
				return "%s mode %s -> %s is not one 45 deg detent" % [side, pair[0], pair[1]]
		var r: Dictionary = lv["nd_range_" + side]
		if (r.get("map", []) as Array).size() != 6:
			return "%s range has no animation" % side
	var glb := (load("res://aircraft/a320/models/interior.glb") as PackedScene).instantiate()
	var miss := []
	for n in ["nd_mode_cpt", "nd_mode_fo", "nd_range_cpt", "nd_range_fo"]:
		var p := glb.find_child("pivot_" + n, true, false)
		if p == null or p.get_child_count() == 0:
			miss.append(n)
	glb.free()
	return "" if miss.is_empty() else "interior.glb has no knob mesh under %s" % [miss]


func test_fcu_knob_springs_on_push_and_pull() -> String:
	_begin()
	var err := ""
	var node := Node3D.new()
	var lv := CockpitLevers.new()
	var it := {"node": node, "basis": Basis(), "pos": Vector3.ZERO, "map": [[0.0, 0.0], [360.0, 4050.0]], "move": "rotate",
		"push": {"controls/fcu/hdg_managed": true}, "pull": {"controls/fcu/hdg_managed": false}, "off": 0.0, "push_t": 0.0}
	Props.set_v("controls/fcu/hdg_managed", false)
	it["sig"] = CockpitLevers.signature(it)
	if CockpitLevers.watch_push(it):
		err = "moved with nothing changed"
	Props.set_v("controls/fcu/hdg_managed", true)  # a key, the 2D FCU or the knob pushed it
	if err == "" and (not CockpitLevers.watch_push(it) or CockpitLevers.push_target(it) <= 0.0):
		err = "push did not spring the knob in"
	it["push_t"] = 0.0
	if err == "" and CockpitLevers.push_target(it) != 0.0:
		err = "knob stayed in"
	Props.set_v("controls/fcu/hdg_managed", false)
	if err == "" and (not CockpitLevers.watch_push(it) or CockpitLevers.push_target(it) >= 0.0):
		err = "pull did not spring the knob out"
	it["off"] = CockpitLevers.PUSH_M
	CockpitLevers.apply(it, 0.0)
	if err == "" and not node.position.is_equal_approx(Vector3(CockpitLevers.PUSH_M, 0, 0)):
		err = "offset not along the knob axis %s" % node.position
	var vs := {"push": {"controls/fcu/vs_fpm": 0.0, "controls/fcu/vs_managed": false, "controls/fcu/vert_select": "LEVEL"},
		"pull": {"controls/fcu/vs_managed": false, "controls/fcu/vert_select": "VS"}}
	Props.set_v("controls/fcu/vs_managed", true)
	Props.set_v("controls/fcu/vert_select", "MANAGED")
	vs["sig"] = CockpitLevers.signature(vs)
	Props.set_v("controls/fcu/vert_select", "OPEN")  # the ALT knob pulled: the V/S knob must not move
	Props.set_v("controls/fcu/vs_managed", false)
	if err == "" and CockpitLevers.watch_push(vs):
		err = "V/S knob moved for the ALT knob"
	node.free()
	lv.free()
	_end()
	return err


func test_mcdu_long_route_fits_and_scrolls() -> String:
	_begin()
	var err := ""
	var m := MCDU.new()
	var long := "VABB/AAAAA/BBBBB/CCCCC/DDDDD/EEEEE/FFFFF/VOPC"
	if McduFpln.from_to_shown(long) != "VABB/VOPC" or McduFpln.from_to_shown("VABB/VOPC") != "VABB/VOPC":
		err = "FROM/TO shows %s" % McduFpln.from_to_shown(long)
	var f := Display.fit_text(ThemeDB.fallback_font, long + long, 20, 384.0)
	if err == "" and ThemeDB.fallback_font.get_string_size(f[0], HORIZONTAL_ALIGNMENT_LEFT, -1, f[1]).x > 384.0:
		err = "fit_text overflows"
	if err == "" and Display.fit_text(ThemeDB.fallback_font, "VABB", 20, 384.0) != ["VABB", 20]:
		err = "short text changed"
	Props.set_v("controls/gps/target", "W0")
	Props.set_v("controls/gps/route_next", ["W1", "W2", "W3", "W4", "W5", "W6"])
	Props.set_v("mcdu/page", "FPLN")
	Props.set_v("mcdu/fpln_top", 0)
	m._wheel("fpln_body", -1.0)  # wheel down: later waypoints
	m._press("slew_dn", MOUSE_BUTTON_LEFT, Vector2.ZERO)
	if err == "" and int(Props.get_f("mcdu/fpln_top")) != 2:
		err = "scroll to %s" % Props.get_f("mcdu/fpln_top")
	m._press("slew_dn", MOUSE_BUTTON_LEFT, Vector2.ZERO)  # 7 waypoints + the slot = 8 lines, 6 shown: top stops at 2
	if err == "" and int(Props.get_f("mcdu/fpln_top")) != 2:
		err = "scrolled past the end"
	Props.set_v("mcdu/scratch", "")
	m._press("l6", MOUSE_BUTTON_LEFT, Vector2.ZERO)  # the 6th line now is the 8th entry: the insert slot
	m._press("l5", MOUSE_BUTTON_LEFT, Vector2.ZERO)
	if err == "" and str(Props.get_v("mcdu/scratch")) != "W6":
		err = "line key on a scrolled page copied %s" % Props.get_v("mcdu/scratch")
	Props.set_v("mcdu/scratch", "NEW")
	m._press("l6", MOUSE_BUTTON_LEFT, Vector2.ZERO)
	if err == "" and Array(Props.get_v("controls/gps/route_next")).back() != "NEW":
		err = "append on a scrolled page %s" % [Props.get_v("controls/gps/route_next")]
	Props.set_v("controls/gps/route_next", [])
	if err == "" and McduFpln.top(MCDU.route().size()) != 0:
		err = "a shorter route left the page scrolled"
	if err == "" and m.dry_paint() < 20:
		err = "paint"
	m.free()
	_end()
	return err


## The binding side (the steering itself: tests/test_fdm_a320.gd test_a320_pedal_disc_frees_the_pedals).
func test_pedal_disc_is_a_control() -> String:
	if not "pedal_disc" in ControlActions.GROUPS.tiller or not "pedal_disc" in ControlActions.HELD_BUTTONS:
		return "pedal_disc is not a held action of the tiller group"
	if (KeyBindings.defaults().get("pedal_disc", []) as Array).is_empty() or not "pedal_disc" in KeyBindings.HELD:
		return "pedal_disc has no default key"
	if not InputBindings.BUTTONS.has("pedal_disc") or not InputBindings.LABELS.has("pedal_disc"):
		return "pedal_disc cannot be put on a joystick button"
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://aircraft/a320/aircraft.json"))
	var groups: Array = d.get("controls", {}).get("actions", [])
	return "" if "tiller" in groups else "the A320 does not offer the tiller group"
