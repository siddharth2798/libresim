extends Node
## Pure A320 GPWS cues (aircraft/common/gpws.gd) and the audio.gpws gate.
## Feet and ft/min, matching CalloutLogic. The player is not required for the cue tests.


func _i(agl: float, vs: float, wow := false, stall := false, ap := false) -> Dictionary:
	return {"agl_ft": agl, "vs_fpm": vs, "wow": wow, "stall": stall, "ap_disconnect_edge": ap}


## Stop players before freeing so the headless mixer does not keep a playback.
func _dispose(n: Node) -> void:
	for c in n.find_children("*", "AudioStreamPlayer", true, false):
		c.stop()
	remove_child(n)
	n.free()


func test_gpws_stall_holds() -> String:
	var s := Gpws.new_state()
	var cues := []
	for _n in 4:
		cues.append(Gpws.step(s, _i(800.0, 0.0, false, true), 0.05))
	cues.append(Gpws.step(s, _i(800.0, 0.0, false, false), 0.05))
	if cues != ["stall", "stall", "stall", "stall", ""]:
		return "stall should hold for the whole warning: %s" % [cues]
	var t := Gpws.new_state()
	Gpws.step(t, _i(600.0, -200.0, false, true), 0.05)
	if Gpws.step(t, _i(490.0, -200.0, false, true), 0.05) != "stall":
		return "stall holds while an altitude gate is crossed"
	if Gpws.step(t, _i(480.0, -200.0), 0.05) != "alt":
		return "the altitude call deferred by the stall should play once the stall ends"
	return ""


func test_gpws_alt_fires_once() -> String:
	var s := Gpws.new_state()
	var n := 0
	var agl := 640.0
	Gpws.step(s, _i(agl, -400.0), 0.02)  # arm above the gates
	while agl > 5.0:
		agl -= 10.0
		if Gpws.step(s, _i(agl, -400.0), 0.02) == "alt":
			n += 1
	var extra := 0
	agl = 0.0
	while agl < 640.0:  # back up, still under the 700 ft re-arm
		agl += 10.0
		Gpws.step(s, _i(agl, 400.0), 0.02)
	while agl > 5.0:
		agl -= 10.0
		if Gpws.step(s, _i(agl, -400.0), 0.02) == "alt":
			extra += 1
	if n != 6 or extra != 0:
		return "expected the six heights once each, got %d then %d more" % [n, extra]
	return ""


func test_gpws_alt_rearms() -> String:
	var s := Gpws.new_state()
	Gpws.step(s, _i(620.0, -300.0), 0.05)
	if Gpws.step(s, _i(490.0, -300.0), 0.05) != "alt":
		return "first descent missed 500 ft"
	Gpws.step(s, _i(700.0, 200.0), 0.05)  # "above 700", so 700 itself does not re-arm
	if Gpws.step(s, _i(490.0, -300.0), 0.05) != "":
		return "700 ft must not re-arm the altitude calls"
	Gpws.step(s, _i(720.0, 200.0), 0.05)
	if Gpws.step(s, _i(490.0, -300.0), 0.05) != "alt":
		return "climbing above 700 ft should re-arm"
	Gpws.step(s, _i(0.0, 0.0, true), 0.05)
	Gpws.step(s, _i(620.0, 400.0), 0.05)
	if Gpws.step(s, _i(490.0, -300.0), 0.05) != "alt":
		return "weight on wheels should re-arm"
	var level := Gpws.new_state()
	Gpws.step(level, _i(620.0, 0.0), 0.05)
	if Gpws.step(level, _i(400.0, 0.0), 0.05) != "":
		return "no altitude call unless descending"
	return ""


func test_gpws_sink_cooldown() -> String:
	var s := Gpws.new_state()
	var a := Gpws.step(s, _i(400.0, -1200.0), 0.0)
	var b := Gpws.step(s, _i(400.0, -1200.0), 1.5)
	var c := Gpws.step(s, _i(400.0, -1200.0), 2.5)  # t = 4.0 s
	if a != "sink" or b != "" or c != "sink":
		return "sink should repeat only after 4 s: %s / %s / %s" % [a, b, c]
	if Gpws.step(Gpws.new_state(), _i(400.0, -1200.0, true), 0.0) != "":
		return "no sink on the ground"
	if Gpws.step(Gpws.new_state(), _i(500.0, -1200.0), 0.0) != "":
		return "no sink at 500 ft"
	if Gpws.step(Gpws.new_state(), _i(400.0, -1000.0), 0.0) != "":
		return "no sink at -1000 fpm"
	return ""


func test_gpws_ap_edge() -> String:
	var s := Gpws.new_state()
	if Gpws.step(s, _i(2000.0, 0.0), 0.0) != "":
		return "no autopilot tone without the disconnect edge"
	if Gpws.step(s, _i(2000.0, 0.0, false, false, true), 0.0) != "ap":
		return "disconnect edge missed"
	if Gpws.step(s, _i(2000.0, 0.0), 0.0) != "":
		return "the disconnect tone should not latch"
	if Gpws.step(s, _i(400.0, -2000.0, false, true, true), 0.0) != "stall":
		return "stall takes the frame over the disconnect edge"
	return ""


func test_gpws_player_only_on_a320() -> String:
	if AircraftDef.load_def("c172").section("audio").get("gpws", false):
		return "c172 must not set audio.gpws"
	if not AircraftDef.load_def("a320").section("audio").get("gpws", false):
		return "a320 audio.gpws must be true"
	# Missing wavs stay silent, so this does not start playback (the headless mixer leaks those).
	var off := _spawn({"audio": {}})
	var on := _spawn({"audio": {"gpws": true}})
	var off_has: bool = off.get_children().any(func(c): return c is GpwsPlayer)
	var on_has: bool = on.get_children().any(func(c): return c is GpwsPlayer)
	var on_proc := on.is_processing()
	_dispose(off)
	_dispose(on)
	if off_has:
		return "a player was added without audio.gpws"
	if not on_has:
		return "audio.gpws did not add a player"
	if not on_proc:
		return "gpws without audio.layers should keep the aircraft audio process"
	return ""


func _spawn(data: Dictionary) -> AircraftAudio:
	var prev = Session.setup.get("aircraft")
	AircraftDef._cache["gpws_probe"] = AircraftDef.make("gpws_probe", data, "res://aircraft/none")
	Session.setup["aircraft"] = "gpws_probe"
	var a := AircraftAudio.new()
	add_child(a)
	AircraftDef._cache.erase("gpws_probe")
	if prev == null:
		Session.setup.erase("aircraft")
	else:
		Session.setup["aircraft"] = prev
	return a
