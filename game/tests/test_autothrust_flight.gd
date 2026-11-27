extends Node
## A320 autothrust over a whole flight (systems/autoflight_thrust.gd, autoflight_logic.gd): the links the VABB - VAPO flight on the
## autopilot found broken (tests/probe_a320_flight.tscn, docs/USAGE.md "A whole flight on the autopilot"). Pure logic with AfInputs.


func _ground(lever: float) -> AfInputs:
	var i := AfInputs.new()
	i.dt = 0.1
	i.powered = true
	i.wow = true
	i.ra_m = 0.0
	i.alt_m = 0.0
	i.cas = 0.0
	i.lever = lever
	i.engine_lever = lever
	i.f.fd = true
	return i


func _air(lever: float, alt_m: float) -> AfInputs:
	var i := AfInputs.new()
	i.dt = 0.1
	i.powered = true
	i.wow = false
	i.ra_m = alt_m
	i.alt_m = alt_m
	i.cas = 130.0
	i.tas = 200.0
	i.gs_mps = 200.0
	i.lever = lever
	i.engine_lever = lever
	i.f.fd = true
	i.f.alt = alt_m
	i.f.spd = 130.0
	return i


## The node writes the armed state back to the FCU button, the next tick reads it.
func _step(logic: AfLogic, i: AfInputs, n := 1) -> void:
	for k in n:
		logic.update(i)
		i.f.athr = logic.thr.armed


## A gradual lever advance (keyboard, a quadrant): the takeoff modes start at 0.7, the A/THR arms only at TOGA a moment later.
## LVR CLB must still ask for the CL detent above the reduction altitude (before, it never showed: A/THR stayed MAN TOGA all flight).
func test_lvr_clb_after_a_gradual_lever_advance() -> String:
	var logic := AfLogic.new({})
	var g := _ground(0.0)
	for k in 30:  # 0 -> TOGA over 3 s
		g.lever = minf(k / 29.0, 1.0)
		_step(logic, g)
	if not logic.thr.armed or not logic.takeoff:
		return "TOGA on the roll: armed %s takeoff %s" % [logic.thr.armed, logic.takeoff]
	var i := _air(AfThrust.TOGA, 700.0)  # above the thrust reduction altitude, levers still in TOGA
	i.f.athr = true
	_step(logic, i, 3)
	return "" if logic.fma.thrust == "LVR CLB" else "LVR CLB after a gradual advance to TOGA, FMA [%s]" % logic.fma.thrust


## After an autoland the AP lets go below 20 kt; the levers may still be in CL. A/THR goes on holding idle on the ground (before, the
## engines went to climb thrust on the runway the moment the roll out ended). Levers to idle then disconnect it.
func test_autoland_roll_out_end_keeps_idle_until_the_levers_come_back() -> String:
	var t := AfThrust.new()
	t.armed = true
	var i := _ground(AfThrust.CL)
	i.cas = 40.0
	t.update(i, "", 60.0, false, 2, true)  # the roll out: RETARD
	if not t.active or t.lever_cmd != 0.0:
		return "roll out with levers in CL: idle, active %s cmd %.2f" % [t.active, t.lever_cmd]
	t.update(i, "", 60.0, false, 0, false)  # the AP let go at 20 kt
	if not t.active or t.lever_cmd != 0.0 or t.mode != "RETARD":
		return "after the AP let go: still idle (RETARD), active %s cmd %.2f mode %s" % [t.active, t.lever_cmd, t.mode]
	i.lever = 0.0
	t.update(i, "", 60.0, false, 0, false)
	if t.armed or t.active:
		return "levers to idle after the autoland disconnect A/THR: armed %s" % t.armed
	var u := AfThrust.new()  # an ordinary ground roll (no autoland): A/THR never commands on the ground
	u.armed = true
	u.update(_ground(AfThrust.CL), "", 60.0, false, 0, false)
	return "" if not u.active else "on the ground without an autoland A/THR must not command"
