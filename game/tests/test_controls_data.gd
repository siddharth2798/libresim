extends Node
## Aircraft controls as data (aircraft.json "controls", input/aircraft_controls.gd): the C172 keeps
## exactly its old action set, a synthetic twin jet (tests/generic_fixtures.gd) offers the airliner
## actions, per-engine levers stay consistent, detents snap, the controls page filters.

const FX := preload("res://tests/generic_fixtures.gd")
const JET_GROUPS := ["throttle", "trim", "flaps", "brakes", "parking_brake", "thrust_levers", "reverse",
	"speedbrake", "gear", "autobrake", "engine_master", "engine_mode", "apu", "rudder_trim", "tiller", "fcu"]
const A320_DETENTS := [{"name": "REV MAX", "pos": -1.0}, {"name": "REV IDLE", "pos": -0.1}, {"name": "IDLE", "pos": 0.0, "zone": 0.03},
	{"name": "CL", "pos": 0.556}, {"name": "FLX/MCT", "pos": 0.778}, {"name": "TOGA", "pos": 1.0}]
const PREFIXES := ["controls/throttle_", "controls/reverse_", "controls/engine_master", "controls/fcu/", "controls/gear",
	"controls/speedbrake", "controls/autobrake", "controls/apu", "controls/rudder_trim", "controls/tiller",
	"controls/engine_mode", "controls/tlev", "controls/mixture_", "input/held/", "input/axis_owner/throttle"]


func _near(a: float, b: float, tol := 1e-4) -> bool:
	return absf(a - b) <= tol


## Props are global: remove what a test created so the FDM fallbacks of other tests stay untouched.
func _clean() -> void:
	for k in Props.dump("").keys():
		for p in PREFIXES:
			if k.begins_with(p):
				Props._p.erase(k)
	Props.set_v("controls/throttle", 0.0)


func _jet(separate := true, reverse := true) -> AircraftControls:
	var sec := {"actions": JET_GROUPS, "levers": {"throttle": {"separate": separate, "reverse": reverse, "detents": A320_DETENTS}}}
	return AircraftControls.for_def(AircraftDef.make("jet", {"controls": sec}, "res://aircraft/c172", FX.turbine_config()))


func test_controls_c172_action_set_unchanged() -> String:
	var held := ["pitch_down", "pitch_up", "roll_left", "roll_right", "yaw_left", "yaw_right", "throttle_up", "throttle_down",
		"mixture_rich", "mixture_lean", "trim_down", "trim_up", "brakes", "brake_left", "brake_right", "starter"]
	var press := ["flaps_down", "flaps_up", "parking_brake", "magnetos_next", "mouse_yoke", "master", "avionics", "fuel_selector",
		"fuel_shutoff", "beacon", "nav_lights", "strobes", "landing_light", "taxi_light", "pitot_heat"]
	var axes := ["pitch", "roll", "yaw", "throttle", "mixture", "brake_left", "brake_right", "pitch_trim_axis"]
	var buttons := ["flaps_up", "flaps_down", "brakes", "parking_brake", "trim_up", "trim_down", "view_next", "view_cockpit",
		"starter", "magnetos_next", "toggle_map", "pause"]
	for c in [AircraftControls.for_def(AircraftDef.load_def("c172")), AircraftControls.default_set()]:
		if c.held_keys() != held or c.press_keys() != press:
			return "c172 key actions changed: %s / %s" % [c.held_keys(), c.press_keys()]
		if c.axes() != axes or c.buttons() != buttons:
			return "c172 joystick actions changed: %s / %s" % [c.axes(), c.buttons()]
		if c.levers.count != 1 or c.levers.reverse or c.levers.separate or not c.levers.detents.is_empty():
			return "c172 lever model must be one plain lever"
	return ""


func test_controls_c172_seeds_nothing() -> String:
	_clean()
	AircraftControls.for_def(AircraftDef.load_def("c172")).seed_props()
	var left := []
	for k in Props.dump("").keys():
		for p in PREFIXES:
			if k.begins_with(p):
				left.append(k)
	return "" if left.is_empty() else "the C172 must not publish airliner props: %s" % [left]


func test_controls_twin_jet_offers_airliner_actions() -> String:
	var c := _jet()
	for a in ["speedbrake_out", "gear_toggle", "autobrake_next", "engine_master_2", "engine_mode_next", "apu_start",
			"rudder_trim_left", "reverse", "fcu_hdg_left", "throttle_detent_up", "throttle_2_up", "pitch_up", "view_next"]:
		if not c.offers(a):
			return "%s should be offered" % a
	for a in ["mixture_rich", "starter", "magnetos_next", "fuel_selector", "fuel_shutoff"]:
		if c.offers(a):
			return "%s is a piston action" % a
	for a in ["speedbrake", "tiller", "throttle_2", "rudder_trim_axis"]:
		if not a in c.axes():
			return "axis %s missing: %s" % [a, c.axes()]
	if "mixture" in c.axes() or c.levers.count != 2 or not c.levers.separate or not c.levers.reverse:
		return "twin jet lever model: count %d separate %s reverse %s" % [c.levers.count, c.levers.separate, c.levers.reverse]
	# a C172 without the groups: the airliner actions are hidden but stay in the saved profile
	var t := KeyBindings.defaults()
	if not t.has("gear_toggle") or not t.has("fcu_spd_up"):
		return "airliner actions must have default keys"
	if not KeyBindings.conflicts(t).is_empty():
		return "default conflicts: %s" % [KeyBindings.conflicts(t)]
	return ""


func test_controls_unknown_group_is_ignored() -> String:
	var c := AircraftControls.for_def(AircraftDef.make("x", {"controls": {"actions": ["flaps", "no_such_group"]}}, "res://aircraft/c172"))
	return "" if c.groups == ["flaps"] and c.offers("flaps_up") and not c.offers("throttle_up") else "groups %s" % [c.groups]


func test_controls_levers_write_consistently() -> String:
	_clean()
	var one := EngineLevers.make(1, {})
	one.write("tlev", 0, 0.4)
	if not _near(Props.get_f("controls/tlev"), 0.4) or Props.has("controls/tlev_1") or Props.has("controls/tlev_2"):
		return "one engine writes only the shared lever"
	var shared := EngineLevers.make(2, {})
	shared.write("tlev", 1, 0.6)  # a shared lever: any write moves both
	if not (_near(Props.get_f("controls/tlev"), 0.6) and _near(Props.get_f("controls/tlev_1"), 0.6) and _near(Props.get_f("controls/tlev_2"), 0.6)):
		return "shared levers out of step: %s" % [Props.dump("controls/tlev")]
	var sep := EngineLevers.make(2, {"separate": true})
	sep.write("throttle", 0, 0.3)
	sep.write("throttle", 1, 0.7)
	if not (_near(Props.get_f("controls/throttle"), 0.3) and _near(Props.get_f("controls/throttle_1"), 0.3) and _near(Props.get_f("controls/throttle_2"), 0.7)):
		return "separate levers: %s" % [Props.dump("controls/throttle")]
	if not _near(sep.read("throttle", 1), 0.7) or not _near(sep.read("tlev", 1), 0.6):
		return "read follows FdmNode's rule"
	sep.write_all("throttle", 0.5)
	var ok := _near(Props.get_f("controls/throttle"), 0.5) and _near(Props.get_f("controls/throttle_2"), 0.5)
	var tri := EngineLevers.make(3, {"separate": true})
	tri.write("mixture", 2, 0.9)  # only the throttle can be separate
	ok = ok and _near(Props.get_f("controls/mixture"), 0.9) and _near(Props.get_f("controls/mixture_2"), 0.9) and _near(Props.get_f("controls/mixture_3"), 0.9)
	_clean()
	return "" if ok else "write_all / mixture must move every engine"


func test_controls_lever_position_and_reverse() -> String:
	_clean()
	var l := _jet().levers
	l.write_pos(0, -0.4)
	if not _near(l.pos(0), -0.4) or Props.get_f("controls/throttle") != 0.0 or not _near(Props.get_f("controls/reverse_1"), 0.4):
		return "reverse position -0.4: throttle %f reverse_1 %f" % [Props.get_f("controls/throttle"), Props.get_f("controls/reverse_1")]
	if Props.get_f("controls/reverse_2") != 0.0:
		return "separate levers: lever 2 must stay out of reverse"
	l.write_pos(0, 0.6)
	if Props.get_f("controls/reverse_1") != 0.0 or not _near(Props.get_f("controls/throttle"), 0.6):
		return "forward position must clear reverse"
	l.write_pos(1, -3.0)
	var clamped := _near(l.pos(1), -1.0)
	l.write_pos_all(0.25)
	var both := _near(l.pos(0), 0.25) and _near(l.pos(1), 0.25) and Props.get_f("controls/reverse_2") == 0.0
	_clean()
	var plain := EngineLevers.make(1, {})
	plain.write_pos(0, -0.5)  # no reverse range: clamped at idle
	var idle := Props.get_f("controls/throttle") == 0.0 and not Props.has("controls/reverse_1")
	_clean()
	return "" if clamped and both and idle else "clamp %s / all %s / plain %s" % [clamped, both, idle]


func test_controls_detents_snap_and_step() -> String:
	var d := A320_DETENTS
	if LeverDetents.snap(0.02, d) != 0.0 or LeverDetents.snap(0.99, d) != 1.0 or LeverDetents.snap(0.55, d) != 0.556:
		return "values inside a zone must snap onto the detent"
	if LeverDetents.snap(0.3, d) != 0.3 or LeverDetents.snap(0.67, d) != 0.67:
		return "values between detents stay"
	if LeverDetents.snap(0.04, d) != 0.04:
		return "IDLE zone is 0.03"
	if LeverDetents.name_at(0.778, d) != "FLX/MCT" or LeverDetents.name_at(0.7, d) != "" or LeverDetents.name_at(-1.0, d) != "REV MAX":
		return "name_at"
	if LeverDetents.step(0.0, d, 1) != 0.556 or LeverDetents.step(0.6, d, 1) != 0.778 or LeverDetents.step(1.0, d, 1) != 1.0:
		return "step up"
	if LeverDetents.step(1.0, d, -1) != 0.778 or LeverDetents.step(0.3, d, -1) != 0.0 or LeverDetents.step(0.0, d, -1) != -0.1:
		return "step down"
	if LeverDetents.step(0.0, d, -1, false) != 0.0:
		return "no reverse detents when the aircraft has no reverse"
	if LeverDetents.step(0.5, [], 1) != 0.5:
		return "no detents: the lever stays"
	return ""


func test_controls_axis_to_lever_position() -> String:
	if LeverDetents.axis_to_pos(0.0, 0.2) != -1.0 or not _near(LeverDetents.axis_to_pos(0.2, 0.2), 0.0) or LeverDetents.axis_to_pos(1.0, 0.2) != 1.0:
		return "reverse zone: back = REV MAX, 20 % = idle, forward = full"
	if not _near(LeverDetents.axis_to_pos(0.1, 0.2), -0.5) or not _near(LeverDetents.axis_to_pos(0.6, 0.2), 0.5):
		return "linear on both sides of idle"
	for p in [-1.0, -0.5, 0.0, 0.3, 1.0]:
		if not _near(LeverDetents.axis_to_pos(LeverDetents.pos_to_axis(p, 0.25), 0.25), p):
			return "pos_to_axis is the inverse (%f)" % p
	return "" if LeverDetents.axis_to_pos(0.7, 0.0) == 0.7 else "no reverse range: the axis is the lever"


func _stub() -> Node:
	var s := GDScript.new()
	s.source_code = "extends Node\nvar down := {}\nfunc _k(a): return down.get(a, false)\nfunc _axis(n, p): return float(_k(p)) - float(_k(n))\n"
	s.reload()
	var n := Node.new()
	n.set_script(s)
	return n


func test_controls_keyboard_levers_on_a_twin_jet() -> String:
	_clean()
	var c := _jet()
	var kb := _stub()
	var lk := LeverKeys.new(kb)
	kb.down = {"throttle_up": true}
	for i in 60:
		lk.update(c, 0.05)  # 3 s of both levers up
	var up := Props.get_f("controls/throttle") == 1.0 and Props.get_f("controls/throttle_2") == 1.0
	kb.down = {"throttle_1_down": true}
	for i in 20:
		lk.update(c, 0.05)  # 1 s: lever 1 only
	var one := _near(Props.get_f("controls/throttle"), 0.5) and Props.get_f("controls/throttle_2") == 1.0 \
		and _near(Props.get_f("controls/throttle_1"), Props.get_f("controls/throttle"))
	Props.set_v("controls/throttle", 0.0)  # idle both, then the detent keys
	c.levers.write_all("throttle", 0.0)
	lk.detent_key(c, "throttle_detent_up")
	var cl := c.levers.pos(0) == 0.556 and c.levers.pos(1) == 0.556
	lk.detent_key(c, "throttle_detent_down")
	lk.detent_key(c, "throttle_detent_down")
	var rev_idle := c.levers.pos(0) == -0.1
	c.levers.write_all("throttle", 0.0)
	c.levers.write_pos_all(0.0)
	kb.down = {"reverse": true}
	for i in 30:
		lk.update(c, 0.05)
	var in_rev := _near(c.levers.pos(0), -1.0) and _near(Props.get_f("controls/reverse_2"), 1.0)
	kb.down = {}
	for i in 30:
		lk.update(c, 0.05)
	var back := c.levers.pos(0) == 0.0 and Props.get_f("controls/reverse_1") == 0.0
	c.levers.write_pos_all(0.5)
	kb.down = {"reverse": true}
	lk.update(c, 0.05)  # reverse cannot be selected above idle
	var interlock := _near(c.levers.pos(0), 0.5)
	# a joystick axis owns lever 2: the keyboard leaves it
	kb.down = {"throttle_down": true}
	Props.set_v("input/axis_owner/throttle_2", "joy")
	lk.update(c, 0.05)
	var owned := _near(c.levers.pos(1), 0.5) and c.levers.pos(0) < 0.5
	kb.free()
	_clean()
	if not (up and one and cl and rev_idle and in_rev and back and interlock and owned):
		return "up %s one %s CL %s revidle %s rev %s back %s interlock %s owned %s" % [up, one, cl, rev_idle, in_rev, back, interlock, owned]
	return ""


func test_controls_c172_keyboard_throttle_path() -> String:
	_clean()
	var c := AircraftControls.default_set()
	var kb := _stub()
	var lk := LeverKeys.new(kb)
	Props.set_v("controls/throttle", 0.2)
	kb.down = {"throttle_up": true}
	lk.update(c, 0.5)
	var v := Props.get_f("controls/throttle")
	kb.down = {"mixture_lean": true}
	Props.set_v("controls/mixture", 1.0)
	lk.update(c, 1.0)
	var m := Props.get_f("controls/mixture")
	Props.set_v("controls/throttle", 0.0)
	Props.set_v("controls/mixture", 1.0)
	kb.free()
	if not _near(v, 0.45) or not _near(m, 0.5) or Props.has("controls/throttle_2") or Props.has("controls/reverse_1"):
		return "throttle %f, mixture %f" % [v, m]
	return ""


func test_controls_press_steps() -> String:
	_clean()
	Props.set_v("controls/gear", 1)
	ControlSteps.press("gear_toggle")
	var up: int = Props.get_v("controls/gear")
	ControlSteps.press("gear_toggle")
	var down: int = Props.get_v("controls/gear")
	for i in 5:
		ControlSteps.press("autobrake_next")
	var ab: int = Props.get_v("controls/autobrake")  # 0 -> 1 2 3 0 1
	for i in 6:
		ControlSteps.press("speedbrake_out")
	var sb := Props.get_f("controls/speedbrake")
	ControlSteps.press("speedbrake_in")
	ControlSteps.press("engine_master_2")
	ControlSteps.press("fcu_ap1")
	var ok := up == 0 and down == 1 and ab == 1 and _near(sb, 1.0) and _near(Props.get_f("controls/speedbrake"), 0.75) \
		and Props.get_b("controls/engine_master_2") and not Props.get_b("controls/engine_master_1") and Props.get_b("controls/fcu/ap1")
	var fl := ControlSteps.handles("flaps_up") and not ControlSteps.handles("throttle_detent_up")
	_clean()
	return "" if ok and fl else "gear %d %d autobrake %d speedbrake %f" % [up, down, ab, sb]


func test_controls_fcu_knob_repeats() -> String:
	_clean()
	Props.set_v("controls/fcu/hdg_deg", 359.0)
	Props.set_v("controls/fcu/alt_ft", 10000.0)
	var st := {}
	ControlSteps.knob("fcu_hdg_right", true, 0.016, st)  # first press: one step, wraps 359 -> 0
	var wrapped := Props.get_f("controls/fcu/hdg_deg")
	ControlSteps.knob("fcu_hdg_right", true, 0.1, st)  # still inside the repeat delay
	var held := Props.get_f("controls/fcu/hdg_deg")
	for i in 5:
		ControlSteps.knob("fcu_alt_up", true, 0.12, st)  # 0.48 s held: first press + one repeat
	var alt := Props.get_f("controls/fcu/alt_ft")
	ControlSteps.knob("fcu_hdg_right", false, 0.1, st)
	var released := not st.has("fcu_hdg_right")
	_clean()
	return "" if wrapped == 0.0 and held == 0.0 and alt == 10200.0 and released else "hdg %f %f alt %f" % [wrapped, held, alt]


func test_controls_seed_props_for_the_jet() -> String:
	_clean()
	_jet().seed_props()
	var ok: bool = Props.get_v("controls/gear") == 1 and Props.has("controls/speedbrake") and Props.get_f("controls/fcu/spd_kt") == 250.0 \
		and Props.has("controls/reverse_2") and Props.has("controls/engine_master_2") and Props.has("controls/throttle_2")
	Props.set_v("controls/gear", 0)  # a seeded prop never overwrites an existing one
	_jet().seed_props()
	var kept: bool = Props.get_v("controls/gear") == 0
	_clean()
	return "" if ok and kept else "seeds: %s kept %s" % [ok, kept]


func test_controls_page_lists_only_offered_actions() -> String:
	var c172 := AircraftControls.default_set()
	var jet := _jet()
	var keys := VBoxContainer.new()
	keys.set_script(load("res://ui/menu/key_bindings_section.gd"))
	keys.set("path", "user://test_controls_no_such_keys.json")
	keys.set("controls", c172)
	add_child(keys)
	var old: Array = keys.get("_slots").keys()
	keys.queue_free()
	var k2 := VBoxContainer.new()
	k2.set_script(load("res://ui/menu/key_bindings_section.gd"))
	k2.set("path", "user://test_controls_no_such_keys.json")
	k2.set("controls", jet)
	add_child(k2)
	var jets: Array = k2.get("_slots").keys()
	var table: Dictionary = k2.get("table")
	k2.queue_free()
	if old != c172.key_actions() or "gear_toggle" in old or "reverse" in old:
		return "C172 key rows must be the old set, got %d" % old.size()
	if jets != jet.key_actions() or not "gear_toggle" in jets or "mixture_rich" in jets:
		return "jet key rows %s" % [jets]
	if not table.has("mixture_rich"):
		return "hidden actions stay in the profile"
	var page := HBoxContainer.new()
	page.set_script(load("res://ui/menu/controls_page.gd"))
	page.set("bindings_path", "user://test_controls_no_such_bindings.json")
	page.set("controls", jet)
	add_child(page)
	var rows: Array = page.get("_rows").keys()
	page.queue_free()
	var want := jet.axes() + jet.buttons()
	rows.sort()
	want.sort()
	return "" if rows == want and "speedbrake" in rows and not "mixture" in rows else "page rows %s" % [rows]


func test_controls_help_card_rows() -> String:
	var t := KeyBindings.defaults()
	var old := ControlHelp.rows(AircraftControls.default_set(), t).map(func(r): return r[1])
	var jet := ControlHelp.rows(_jet(), t).map(func(r): return r[1])
	if not "throttle" in old or not "mixture" in old or "landing gear" in old or "speedbrake in / out" in old:
		return "C172 help: %s" % [old]
	if not "landing gear" in jet or not "thrust reverse (hold)" in jet or "mixture" in jet or "starter" in jet:
		return "jet help: %s" % [jet]
	var pitch: Array = ControlHelp.rows(AircraftControls.default_set(), t)[0]
	return "" if pitch[0] == "↑ ↓ ← →" else "pitch / roll keys read '%s'" % pitch[0]


func test_controls_hidden_actions_do_nothing() -> String:
	var k := KeyboardControls.new()  # the current aircraft is the C172: no gear lever
	k.keys = KeyBindings.defaults()
	k._shifted = KeyBindings.shifted_keys(k.keys)
	Props.set_v("controls/gear", 1)
	var e := InputEventKey.new()
	e.keycode = KEY_G
	e.physical_keycode = KEY_G
	e.ctrl_pressed = true
	e.pressed = true
	k._unhandled_key_input(e)
	var gear: int = Props.get_v("controls/gear")
	k.free()
	_clean()
	return "" if gear == 1 else "a C172 must ignore the gear key"
