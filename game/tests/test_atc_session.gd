extends "res://tests/atc_fixture.gd"
## ATC state in saved flights, the menu over every state, and the session publishing /atc/*
## (fake world: atc_fixture.gd).


func test_atc_state_survives_save_and_load() -> String:
	var c := _ctl()
	var mon := AtcMonitor.new(c)
	var w := _world(121.85, {"at_stand": true})
	var t := _pump(c, mon, w, 0.0, 1.0)
	c.request("clearance", w, t)
	t = _pump(c, mon, w, t, 3.0)
	var saved := {}
	var d := c.export()
	for k in d:
		saved[k] = str_to_var(var_to_str(d[k]))  # what a save file does to a property
	var c2 := _ctl()
	c2.adopt(saved)
	if c2.s.state != "clearance" or not c2.s.cleared or c2.s.squawk != c.s.squawk or c2.log.size() != c.log.size() \
			or c2.log[-1].text != c.log[-1].text or c2.s.runway != c.s.runway:
		return "adopted state differs: %s vs %s" % [c2.s, c.s]
	var keys: Array = d.keys()
	for k in ["atc/state", "atc/airport", "atc/runway", "atc/squawk", "atc/callsign", "atc/cleared_takeoff", "atc/cleared_land", "atc/last_tx"]:
		if not keys.has(k):
			return "property %s is not published" % k
	return "" if Situation.PROP_PREFIXES.has("atc/") else "saved flights must include atc/"

func test_atc_session_publishes_properties_and_adopts_saved_state() -> String:
	var keep_atc := Props.dump("atc/")
	var keep := {}
	for k in ["fdm/position_enu", "fdm/wow", "fdm/groundspeed_mps", "fdm/heading_rad", "fdm/agl_m", "fdm/alt_m", "fdm/vs_mps", "controls/com1/freq_mhz"]:
		keep[k] = Props.get_v(k)
	Props.set_v("atc/stamp", "")
	Props.set_v("fdm/position_enu", Vector3(-500.0, 3.0, 5.0))
	Props.set_v("fdm/wow", true)
	Props.set_v("fdm/groundspeed_mps", 0.0)
	Props.set_v("fdm/heading_rad", PI / 2.0)
	Props.set_v("controls/com1/freq_mhz", 118.1)
	var airports := [{"icao": "TEST", "ident": "TEST", "name": "Test Aerodrome", "type": "medium_airport", "x": 0.0, "y": 0.0}]
	var rw := [{"airport": "TEST", "width": 45.0, "length": 2000.0, "ends": [{"ident": "09", "x": -1000.0, "y": 0.0, "heading_true": 90.0},
		{"ident": "27", "x": 1000.0, "y": 0.0, "heading_true": 270.0}]}]
	var s := AtcSession.new()
	s.setup(AtcWorld.make_env(airports, {}, rw, {}), {})
	s.tick(0.3)
	var err := ""
	if Props.get_v("atc/state") != "lined_up" or Props.get_v("atc/airport") != "TEST" or str(Props.get_v("atc/callsign")) != AtcSession.callsign() \
			or str(Props.get_v("atc/squawk")).length() != 4 or str(Props.get_v("atc/stamp")) == "" or Props.get_v("atc/facility") != "Test Tower":
		err = "published: %s" % [Props.dump("atc/")]
	if err == "":  # a loaded flight brings its own /atc/*: the session takes it over
		Props.set_v("atc/state", "final")
		Props.set_v("atc/cleared_land", true)
		Props.set_v("atc/stamp", "elsewhere:1")
		s.tick(0.3)
		if s.c.s.state != "final" or not s.c.s.cleared_land or Props.get_v("atc/state") != "final":
			err = "adopt: state %s cleared_land %s" % [s.c.s.state, s.c.s.cleared_land]
	s.close()
	Props.restore(keep_atc)
	Props.set_v("atc/stamp", "")
	for k in keep:
		if keep[k] != null:
			Props.set_v(k, keep[k])
	return err

func test_atc_session_follows_the_lesson_flag() -> String:
	var keep: String = Session.training
	Session.training = ""
	var free := AtcSession.in_lesson()
	Session.training = "landing"
	var lesson := AtcSession.in_lesson()
	Session.training = keep
	return "" if not free and lesson else "in_lesson must follow Session.training (free %s, lesson %s)" % [free, lesson]

func test_atc_menu_never_exceeds_six_and_every_call_works() -> String:
	for state in AtcState.STATES:
		for ground in [true, false]:
			var c := _ctl()
			var mon := AtcMonitor.new(c)
			var w := _world(118.0, {"wow": ground, "at_stand": ground, "rwy_dist": 50.0})
			mon.step(w, 0.0)
			c.s.state = state
			var m := c.menu(w)
			if m.size() > 6:
				return "%s: %d menu entries" % [state, m.size()]
			for e in m:  # picking anything must not crash or leave a dirty line
				w.com1_mhz = 118.0 if e.kind == "tune" else 118.1
				c.request(e.id, w, 0.0, float(e.get("mhz", 0.0)), str(e.get("name", "")))
			c.update(100.0)
			if _clean(c) != "":
				return "%s/%s: %s" % [state, ground, _clean(c)]
	return ""


## Build and drop an ATC session (locals die when this returns); weak references to what should be gone.
func _drop_session(with_queue: bool) -> Array:
	var airports := [{"icao": "TEST", "ident": "TEST", "name": "Test Aerodrome", "type": "medium_airport", "x": 0.0, "y": 0.0}]
	var rw := [{"airport": "TEST", "width": 45.0, "length": 2000.0, "ends": [{"ident": "09", "x": -1000.0, "y": 0.0, "heading_true": 90.0},
		{"ident": "27", "x": 1000.0, "y": 0.0, "heading_true": 270.0}]}]
	var s := AtcSession.new()
	s.setup(AtcWorld.make_env(airports, {}, rw, {}), {"tune": func(_mhz: float): pass})
	if with_queue:
		var c := s.c
		c.say_raw("atc", "Tower", "x", "x", 1.0e9, func(): c.rev += 1)  # never due: stays queued
		s.close()
	return [weakref(s), weakref(s.c)]


func test_atc_session_is_freed_when_released() -> String:
	# The voice hook used to capture the session itself (session -> controller -> on_tx -> session): a
	# reference cycle that leaked six ATC scripts at exit after every flight (the e2e sweep's "resources still
	# in use at exit"). Queued replies capture the controller the same way; close() must drop them.
	for with_queue in [false, true]:
		var refs := _drop_session(with_queue)
		if refs[0].get_ref() != null or refs[1].get_ref() != null:
			return "%s: the ATC session or controller is still alive after the last reference was dropped (reference cycle)" % ("with a queued reply" if with_queue else "plain")
	return ""
