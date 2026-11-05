extends RefCounted
## The checklist logic of tests/check_a320_controls.gd (captain_check.gd), headless.


func _state(over := {}) -> Dictionary:
	var s := {"pitch": 0.0, "roll": 0.0, "yaw": 0.0, "thr1": 0.0, "thr2": 0.0, "name1": "IDLE", "name2": "IDLE",
		"rev1": 0.0, "rev2": 0.0, "flaps": 0, "sb": 0.0, "mode": 0, "gear": 1, "ab": 0, "m1": true, "m2": true,
		"park": false, "btn": {}}
	s.merge(over, true)
	return s


func _run(c: CaptainCheck, states: Array) -> void:
	c.feed(_state(), CaptainCheck.WARMUP + 0.1)  # past the start-up window (a no-op when it is already over)
	for s in states:
		c.feed(s, 0.5)


func test_nothing_ticks_at_rest() -> String:
	var c := CaptainCheck.new()
	_run(c, [_state(), _state(), _state()])
	return "" if c.checked() == 0 else "ticked at rest: %s" % [c.done.keys()]


func test_warmup_ignores_the_start_sync() -> String:
	var c := CaptainCheck.new()
	c.feed(_state({"m1": false, "gear": 0}), 0.1)  # the start-up sync: not a movement
	c.feed(_state(), 0.1)
	c.feed(_state(), 0.1)
	_run(c, [_state()])
	return "" if not c.is_done("m1_off") and not c.is_done("gear_up") else "start sync ticked"


func test_sidestick_directions() -> String:
	var c := CaptainCheck.new()
	_run(c, [_state(), _state({"pitch": -1.0}), _state({"pitch": 1.0}), _state({"roll": 1.0}), _state({"yaw": -1.0})])
	for id in ["pitch_fwd", "pitch_back", "roll_r", "yaw_l"]:
		if not c.is_done(id):
			return "%s not ticked" % id
	return "" if not c.is_done("roll_l") and not c.is_done("yaw_r") else "ticked the wrong direction"


func test_lever_sequence_and_idle_needs_a_move_first() -> String:
	var c := CaptainCheck.new()
	_run(c, [_state()])
	if c.is_done("l1_idle"):
		return "idle ticked before the lever moved"
	_run(c, [_state({"thr1": 0.556, "name1": "CL"}), _state({"thr1": 0.778, "name1": "FLX/MCT"}),
		_state({"thr1": 1.0, "name1": "TOGA"}), _state({"thr1": 0.0, "name1": "IDLE"}), _state({"rev1": 1.0})])
	for id in ["l1_cl", "l1_flx", "l1_toga", "l1_idle", "l1_rev"]:
		if not c.is_done(id):
			return "%s not ticked" % id
	return "" if not c.is_done("l2_cl") else "lever 2 ticked by lever 1"


func test_lever_not_seated_does_not_tick_idle() -> String:
	var c := CaptainCheck.new()
	_run(c, [_state({"thr2": 1.0, "name2": "TOGA"}), _state({"thr2": 0.031, "name2": ""})])
	return "" if not c.is_done("l2_idle") else "an unseated lever counted as idle"


func test_flaps_speed_brake_and_back_to_zero() -> String:
	var c := CaptainCheck.new()
	_run(c, [_state({"flaps": 2}), _state({"flaps": 3}), _state({"flaps": 4}), _state({"flaps": 5}), _state({"flaps": 0}),
		_state({"sb": 0.25}), _state({"sb": 0.5}), _state({"sb": 0.75}), _state({"sb": 1.0}), _state({"sb": 0.0})])
	for id in ["fl_1", "fl_2", "fl_3", "fl_full", "fl_0", "sb_25", "sb_50", "sb_75", "sb_100", "sb_0"]:
		if not c.is_done(id):
			return "%s not ticked" % id
	return ""


func test_switches() -> String:
	var c := CaptainCheck.new()
	_run(c, [_state({"mode": 1}), _state({"mode": 2}), _state({"mode": 0}), _state({"gear": 0}), _state({"gear": 1}),
		_state({"m1": false}), _state({"m1": true}), _state({"m2": false}), _state({"m2": true}),
		_state({"park": true}), _state({"park": false})])
	for id in ["mode_crank", "mode_ign", "mode_norm", "gear_up", "gear_dn", "m1_off", "m1_on", "m2_off", "m2_on", "park_on", "park_off"]:
		if not c.is_done(id):
			return "%s not ticked" % id
	return ""


func test_auto_brake_needs_button_and_level() -> String:
	var c := CaptainCheck.new()
	_run(c, [_state({"btn": {21: true}, "ab": 0})])  # button without the game's response: not ticked
	if c.is_done("ab_btv"):
		return "ticked without the level"
	_run(c, [_state({"btn": {21: true}, "ab": 1}), _state({"btn": {22: true}, "ab": 1}), _state({"btn": {23: true}, "ab": 2}),
		_state({"btn": {24: true}, "ab": 2}), _state({"btn": {25: true}, "ab": 3}), _state({"btn": {}, "ab": 0})])
	for id in ["ab_btv", "ab_low", "ab_2", "ab_3", "ab_hi", "ab_off"]:
		if not c.is_done(id):
			return "%s not ticked" % id
	return ""


func test_reset_and_report() -> String:
	var c := CaptainCheck.new()
	_run(c, [_state({"pitch": -1.0})])
	if c.checked() != 1 or c.unchecked().size() != c.total() - 1:
		return "counts wrong"
	c.reset()
	return "" if c.checked() == 0 else "reset did not clear"
