extends Node
## CockpitPick.next_value: bool toggle, detent step, continuous drag. No viewport.


func test_pick_bool_toggles() -> String:
	var sw := [[0.0, -30.0], [1.0, 30.0]]
	var on = CockpitPick.next_value("controls/lights/beacon", sw, false, 0.0)
	var off = CockpitPick.next_value("controls/parking_brake", sw, true, 40.0)
	var first = CockpitPick.next_value("controls/lights/beacon", sw, 0.0, 0.0)
	if on != true or off != false or first != true:
		return "on %s off %s first %s" % [on, off, first]
	return ""


func test_pick_detent_steps_and_wraps() -> String:
	var mode := [[0.0, 0.0], [1.0, 53.0], [2.0, -53.0]]
	var a = CockpitPick.next_value("controls/engine_mode", mode, 0, -80.0)
	var b = CockpitPick.next_value("controls/engine_mode", mode, a, 0.0)
	var c = CockpitPick.next_value("controls/engine_mode", mode, b, 0.0)
	if a != 1 or b != 2 or c != 0:
		return "mode %s %s %s" % [a, b, c]
	var gear := [[0.0, 0.0], [1.0, 50.0]]
	var up = CockpitPick.next_value("controls/gear", gear, 1, 30.0)
	var down = CockpitPick.next_value("controls/gear", gear, up, 0.0)
	if up != 0 or down != 1:
		return "gear %s %s" % [up, down]
	var tla := [[-1.0, -23.0], [0.0, 0.0], [0.556, 25.0], [1.0, 45.0]]
	var n = CockpitPick.next_value("controls/throttle_1 - controls/reverse_1", tla, 0.0, 0.0)
	if absf(float(n) - 0.556) > 1.0e-4:
		return "tla %s" % n
	return ""


func test_pick_continuous_drag() -> String:
	var stick := [[-1.0, -20.0], [1.0, 20.0]]
	var half := -CockpitPick.DRAG_PX * 0.5
	var up := float(CockpitPick.next_value("controls/roll", stick, 0.0, half))
	var down := float(CockpitPick.next_value("controls/roll", stick, 0.0, -half))
	var held := float(CockpitPick.next_value("controls/speedbrake", [[0.0, 0.0], [1.0, 45.0]], 0.25, 0.0))
	var capped := float(CockpitPick.next_value("controls/roll", stick, 0.5, half))
	if absf(up - 1.0) > 1.0e-4 or absf(down + 1.0) > 1.0e-4 or absf(held - 0.25) > 1.0e-4 or absf(capped - 1.0) > 1.0e-4:
		return "up %s down %s held %s capped %s" % [up, down, held, capped]
	return ""
