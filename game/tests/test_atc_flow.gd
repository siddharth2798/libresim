extends "res://tests/atc_fixture.gd"
## ATC flows (game/atc): a whole departure and a whole arrival through the state machine with
## a fake world (see atc_fixture.gd). Rules, advisories and the session: test_atc_rules.gd.


func test_atc_full_departure() -> String:
	var c := _ctl()
	var mon := AtcMonitor.new(c)
	var w := _world(126.4, {"at_stand": true, "where": "stand 12"})
	var t := _pump(c, mon, w, 0.0, 1.0)
	if c.s.state != "parked" or _count(c, "atc") + _count(c, "system") != 0:
		return "starts parked and silent: %s, %s" % [c.s.state, _text(c)]
	if _ids(c.menu(w)) != ["atis", "clearance", "pushback", "taxi", "tune"]:
		return "parked menu on the ATIS frequency: %s" % [_ids(c.menu(w))]
	c.request("atis", w, t)
	t = _pump(c, mon, w, t, 2.0)
	var err := _need(_text(c), ["Test ATIS: Test information Alpha. Runway 27 in use. Wind 270 degrees 8 knots.", "QNH 1012", "Acknowledge information Alpha"])
	if err != "":
		return err
	w.com1_mhz = 121.85  # tune Delivery
	c.request("clearance", w, t)
	t = _pump(c, mon, w, t, 3.0)
	err = _need(_text(c), ["You: Test Delivery, VT-FSM, Cessna 172 at stand 12, information Alpha, request VFR departure",
		"Test Delivery: VT-FSM, cleared VFR, departure runway 27, climb not above 2000 feet, squawk " + c.s.squawk, "Cleared VFR, runway 27",
		"VT-FSM, readback correct"])
	if err != "" or c.s.state != "clearance" or not c.s.cleared:
		return err if err != "" else "after the clearance: state %s cleared %s" % [c.s.state, c.s.cleared]
	if _ids(c.menu(w)) != ["atis", "pushback", "taxi", "tune", "say_again"]:
		return "menu after the clearance: %s" % [_ids(c.menu(w))]
	w.com1_mhz = 121.9  # Ground
	c.request("pushback", w, t)
	t = _pump(c, mon, w, t, 2.0)
	if _calls != ["pushback"] or not _text(c).contains("start-up and pushback approved"):
		return "pushback hook %s\n%s" % [_calls, _text(c)]
	c.request("taxi", w, t)
	t = _pump(c, mon, w, t, 2.0)
	err = _need(_text(c), ["Test Ground: VT-FSM, taxi to holding point runway 27 via A, B, QNH 1012.", "Taxi to holding point runway 27 via A, B"])
	if err != "" or c.s.state != "taxi" or _calls != ["pushback", "taxi"]:
		return err if err != "" else "after taxi: %s %s" % [c.s.state, _calls]
	w.merge({"pos": Vector2(60, 0), "gs": 4.0, "at_stand": false}, true)
	t = _pump(c, mon, w, t, 1.0)
	w.merge({"pos": Vector2(200, 0), "gs": 0.5, "rwy_dist": 60.0, "hold_dist": 15.0}, true)  # at the holding point
	t = _pump(c, mon, w, t, 1.5)
	if c.s.state != "hold_short" or not _text(c).contains("Test Ground: VT-FSM, contact Test Tower 118.1.") or c.s.handoff != "TWR":
		return "holding point: %s handoff '%s'\n%s" % [c.s.state, c.s.handoff, _text(c)]
	if _ids(c.menu(w)) != ["ready", "atis", "tune", "say_again"]:
		return "hold short menu on Ground: %s" % [_ids(c.menu(w))]
	w.com1_mhz = 118.1
	t = _pump(c, mon, w, t, 1.0)
	if c.s.handoff != "":
		return "handover is done once COM1 is on the tower"
	c.request("ready", w, t)
	t = _pump(c, mon, w, t, 2.0)
	if _need(_text(c), ["holding point runway 27, ready for departure", "line up runway 27 and wait"]) != "" or not c.s.lineup_ok:
		return "line up and wait:\n" + _text(c)
	w.merge({"pos": Vector2(250, 10), "on_runway": true, "aligned": true, "rwy_dist": 0.0, "gs": 0.0}, true)
	t = _pump(c, mon, w, t, 1.0)
	if c.s.state != "lined_up" or c.s.cleared_takeoff:
		return "lined up, not yet cleared: %s %s" % [c.s.state, c.s.cleared_takeoff]
	t = _pump(c, mon, w, t, 4.0)
	if _need(_text(c), ["Test Tower: VT-FSM, wind 270 degrees 8 knots, runway 27, cleared for takeoff."]) != "" or not c.s.cleared_takeoff:
		return "cleared for takeoff after lining up:\n" + _text(c)
	w.merge({"pos": Vector2(330, 10), "gs": 22.0}, true)
	t = _pump(c, mon, w, t, 1.0)
	if c.s.state != "takeoff":
		return "rolling: " + c.s.state
	w.merge({"pos": Vector2(600, 10), "wow": false, "agl": 5.0, "gs": 36.0, "on_runway": false, "vs": 3.0}, true)
	t = _pump(c, mon, w, t, 2.0)
	if c.s.state != "departed" or c.s.cleared_takeoff:
		return "airborne: %s" % c.s.state
	w.merge({"pos": Vector2(900, 10), "agl": 200.0, "alt": 200.0}, true)
	t = _pump(c, mon, w, t, 2.0)
	if _need(_text(c), ["Test Tower: VT-FSM, contact Test Approach 127.9."]) != "" or c.s.handoff != "APP":
		return "departure handoff:\n" + _text(c)
	if _count(c, "advisory") != 0:
		return "a correct departure gets no advisory:\n" + _text(c)
	return _clean(c)

func test_atc_full_arrival() -> String:
	var c := _ctl()
	var mon := AtcMonitor.new(c)
	var w := _air_world(127.9)
	var t := _pump(c, mon, w, 0.0, 1.0)
	if c.s.state != "enroute" or _ids(c.menu(w)) != ["atis", "inbound"]:
		return "airborne start: %s %s" % [c.s.state, _ids(c.menu(w))]
	c.request("inbound", w, t)
	t = _pump(c, mon, w, t, 2.0)
	var err := _need(_text(c), ["You: Test Approach, VT-FSM, Cessna 172, 6 miles west of the field, 2300 feet", "Test Approach: VT-FSM, runway 27 in use, QNH 1012, join left-hand downwind runway 27, contact Test Tower 118.1."])
	if err != "" or c.s.state != "inbound" or c.s.handoff != "TWR":
		return err if err != "" else "inbound: %s handoff %s" % [c.s.state, c.s.handoff]
	t = _glide(c, mon, w, t, Vector2(-9000, 400))  # 4.9 nm, still on approach frequency
	t = _pump(c, mon, w, t, 2.0)
	if _text(c).count("contact Test Tower 118.1") < 3:  # reply, readback, reminder
		return "approach reminds the pilot to call the tower:\n" + _text(c)
	w.com1_mhz = 118.1
	t = _pump(c, mon, w, t, 1.0)
	if c.s.handoff != "" or _ids(c.menu(w)) != ["final", "atis", "say_again"]:
		return "on the tower: handoff '%s' menu %s" % [c.s.handoff, _ids(c.menu(w))]
	c.request("final", w, t)
	t = _pump(c, mon, w, t, 2.0)
	err = _need(_text(c), ["You: Test Tower, VT-FSM, final runway 27", "Test Tower: VT-FSM, wind 270 degrees 8 knots, runway 27, cleared to land."])
	if err != "" or c.s.state != "final" or not c.s.cleared_land:
		return err if err != "" else "final: %s %s" % [c.s.state, c.s.cleared_land]
	t = _glide(c, mon, w, t, Vector2(-700, 3))
	w.merge({"agl": 40.0, "vs": -2.0, "gs": 33.0, "appr": {"ident": "27", "along": -400.0, "cross": 3.0, "tail_kt": -8.0}}, true)
	t = _pump(c, mon, w, t, 1.0)
	w.merge({"agl": 0.0, "wow": true, "on_runway": true, "aligned": true, "gs": 30.0, "vs": 0.0, "appr": {}}, true)
	t = _pump(c, mon, w, t, 0.5)  # (the 1.5 s debounce above counted as airborne)
	if c.s.state != "landed" or not c.s.arrived or c.s.cleared_land:
		return "touchdown: %s arrived %s" % [c.s.state, c.s.arrived]
	w.gs = 12.0
	t = _glide(c, mon, w, t, Vector2(-200, 3))
	t = _pump(c, mon, w, t, 1.5)
	if _need(_text(c), ["Test Tower: VT-FSM, vacate runway when able, contact Test Ground 121.9."]) != "" or c.s.handoff != "GND":
		return "vacate call:\n" + _text(c)
	w.merge({"on_runway": false, "gs": 8.0, "pos": Vector2(-100, 60)}, true)
	t = _pump(c, mon, w, t, 1.0)
	if c.s.state != "vacated" or _ids(c.menu(w)) != ["taxi_stand", "tune", "say_again"]:
		return "vacated: %s %s" % [c.s.state, _ids(c.menu(w))]
	w.com1_mhz = 121.9
	c.request("taxi_stand", w, t)
	t = _pump(c, mon, w, t, 2.0)
	err = _need(_text(c), ["runway 27 vacated, request taxi to the apron", "Test Ground: VT-FSM, taxi to the apron via B."])
	if err != "" or c.s.state != "taxi" or not _calls.has("stand"):
		return err if err != "" else "taxi to the apron: %s %s" % [c.s.state, _calls]
	w.merge({"pos": Vector2(0, 100), "gs": 0.0, "at_stand": true}, true)
	t = _pump(c, mon, w, t, 1.0)
	if c.s.state != "parked" or c.s.arrived or c.s.cleared or c.s.runway != "":
		return "parked at the stand: %s" % c.s.state
	if _count(c, "advisory") != 0:
		return "a correct arrival gets no advisory:\n" + _text(c)
	return _clean(c)

func test_atc_tower_asks_for_report_final_once() -> String:
	var c := _ctl()
	var mon := AtcMonitor.new(c)
	var w := _air_world(123.5, {"pos": Vector2(-14000, 300), "apt_dist": 14000.0, "apt_dist_nm": 7.5}, "twr")
	var t := _pump(c, mon, w, 0.0, 1.0)
	c.request("inbound", w, t)
	t = _pump(c, mon, w, t, 2.0)
	if not _text(c).contains("Test Tower: VT-FSM, runway 27 in use, QNH 1012, join left-hand downwind runway 27, report final."):
		return "direct inbound call to the tower:\n" + _text(c)
	t = _glide(c, mon, w, t, Vector2(-9000, 300))
	t = _pump(c, mon, w, t, 4.0)
	if _text(c).count("report final runway 27") != 1:
		return "report final is asked once:\n" + _text(c)
	return ""

func test_atc_straight_in_and_runway_busy() -> String:
	var c := _ctl()
	var mon := AtcMonitor.new(c)
	var appr := {"ident": "09", "along": -9000.0, "cross": 20.0, "tail_kt": 8.0}  # lined up for 09 with a tailwind: not accepted
	var w := _air_world(123.5, {"appr": appr}, "twr")
	var t := _pump(c, mon, w, 0.0, 1.0)
	c.request("inbound", w, t)
	t = _pump(c, mon, w, t, 2.0)
	if not _text(c).contains("join left-hand downwind runway 27"):
		return "tailwind approach gets the into-wind runway:\n" + _text(c)
	w.appr = {"ident": "09", "along": -9000.0, "cross": 20.0, "tail_kt": 2.0}
	c = _ctl()
	mon = AtcMonitor.new(c)
	t = _pump(c, mon, w, 0.0, 1.0)
	c.request("inbound", w, t)
	t = _pump(c, mon, w, t, 2.0)
	if not _text(c).contains("make straight-in approach runway 09"):
		return "lined up with a light tailwind: straight-in runway 09:\n" + _text(c)
	# runway occupied: continue approach, then cleared to land by itself when it frees up
	w.merge({"rwy_free": false, "apt_dist_nm": 3.0, "apt_dist": 5500.0}, true)
	c.request("final", w, t)
	t = _pump(c, mon, w, t, 2.0)
	if not _text(c).contains("continue approach, runway 09 is occupied") or c.s.cleared_land or c.s.state != "final":
		return "busy runway:\n" + _text(c)
	w.rwy_free = true
	t = _pump(c, mon, w, t, 2.0)
	if not c.s.cleared_land or not _text(c).contains("runway 09, cleared to land."):
		return "cleared to land once the runway is free:\n" + _text(c)
	return _clean(c)
