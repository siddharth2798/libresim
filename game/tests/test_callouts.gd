extends RefCounted
## Training callout logic (systems/callout_logic.gd).


func _in(ias: float, agl: float, vs: float, wow: bool, throttle := 1.0, bank := 0.0) -> Dictionary:
	return {"ias": ias, "agl": agl, "vs": vs, "wow": wow, "bank": bank, "throttle": throttle}


func _texts(calls: Array) -> Array:
	return calls.map(func(c): return c[0])


func test_callouts_takeoff_sequence() -> String:
	var s := CalloutLogic.new_state()
	var seen := []
	for step in [[10.0, 0.0, 0.0, true], [41.0, 0.0, 0.0, true], [56.0, 0.0, 0.0, true], [62.0, 3.0, 300.0, false], [64.0, 25.0, 600.0, false]]:
		seen += _texts(CalloutLogic.step(s, _in(step[0], step[1], step[2], step[3]), 0.0))
	if seen != ["Airspeed alive", "Rotate", "Positive rate"]:
		return "takeoff calls were %s" % [seen]
	return ""


func test_callouts_approach_heights_once_each() -> String:
	var s := CalloutLogic.new_state()
	var seen := []
	var agl := 650.0
	while agl > 2.0:
		seen += _texts(CalloutLogic.step(s, _in(65.0, agl, -500.0, false, 0.1), 0.0))
		agl -= 2.0
	if seen != ["Five hundred", "One hundred", "Fifty", "Thirty", "Twenty", "Ten"]:
		return "approach calls were %s" % [seen]
	return ""


func test_callouts_cautions_and_cooldown() -> String:
	var s := CalloutLogic.new_state()
	var a := _texts(CalloutLogic.step(s, _in(70.0, 300.0, -1300.0, false, 0.1), 0.0))
	var b := _texts(CalloutLogic.step(s, _in(70.0, 290.0, -1300.0, false, 0.1), 1.0))
	var c := _texts(CalloutLogic.step(s, _in(70.0, 280.0, -1300.0, false, 0.1), 5.0))
	if not ("Sink rate" in a) or "Sink rate" in b or not ("Sink rate" in c):
		return "sink rate should repeat only after the cooldown: %s / %s / %s" % [a, b, c]
	var d := _texts(CalloutLogic.step(CalloutLogic.new_state(), _in(50.0, 200.0, -300.0, false, 0.3, 40.0), 0.0))
	if not ("Low airspeed" in d) or not ("Bank angle" in d):
		return "low airspeed / bank angle cautions missing: %s" % [d]
	if not _texts(CalloutLogic.step(CalloutLogic.new_state(), _in(70.0, 2000.0, -1500.0, false, 0.1, 50.0), 0.0)).is_empty():
		return "no cautions well above the ground"
	return ""
