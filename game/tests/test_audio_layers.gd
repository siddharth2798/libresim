extends Node
## The data-driven layer sound engine (aircraft/common/audio_curves.gd pure functions, audio_layers.gd node),
## driven by the A320 section. The aircraft sections: tests/test_audio_aircraft.gd; schema additions (mods, smooth,
## attenuate, clicks, rate): tests/test_audio_space.gd.
## The audio server is a dummy in tests: volumes and pitches are asserted, not output.

static func layers_of(id: String) -> Array:
	var j = JSON.parse_string(FileAccess.get_file_as_string("res://aircraft/%s/aircraft.json" % id))
	return j.audio.layers if j is Dictionary and j.get("audio", {}).has("layers") else []


func _draft() -> Array:
	return layers_of("a320")


func _near(a: float, b: float, eps := 0.01) -> bool:
	return absf(a - b) <= eps


func _ctx(vals: Dictionary, view := "outside", rates := {}) -> Dictionary:
	return {"view": view, "values": vals, "rates": rates}


## Stop every player first, so no playback object outlives the node (headless: the dummy mixer never frees them).
func _dispose(n: Node) -> void:
	for c in n.find_children("*", "AudioStreamPlayer", true, false):
		c.stop()
	remove_child(n)
	n.free()
	OS.delay_msec(150)  # lets the audio thread drop the stopped playbacks


func _layer(id: String) -> Dictionary:
	for l in AudioCurves.expand(_draft(), 2):
		if l.id == id:
			return l
	return {}


# --- pure functions -----------------------------------------------------------

func test_audio_interp() -> String:
	var t := [[0, 0.0], [10, 1.0], [20, 0.5]]
	if not (_near(AudioCurves.interp(t, -5.0), 0.0) and _near(AudioCurves.interp(t, 5.0), 0.5)
			and _near(AudioCurves.interp(t, 15.0), 0.75) and _near(AudioCurves.interp(t, 99.0), 0.5)):
		return "interp: %s" % [[AudioCurves.interp(t, -5.0), AudioCurves.interp(t, 5.0), AudioCurves.interp(t, 15.0), AudioCurves.interp(t, 99.0)]]
	if AudioCurves.interp([], 3.0) != 1.0 or AudioCurves.interp([], 3.0, 0.25) != 0.25:
		return "an empty table gives the default"
	if not _near(AudioCurves.interp([[5, 2.0]], 0.0), 2.0) or not _near(AudioCurves.interp([[5, 2.0]], 9.0), 2.0):
		return "a one-point table is constant"
	return ""


func test_audio_per_engine_expansion() -> String:
	var defs := [
		{"id": "a", "file": "a.wav", "per_engine": true, "drive": "engines/{n}/n1", "pan_spread": 0.5,
			"gate": {"not_props": ["engines/{n}/running"]}, "trigger": {"prop": "engines/{n}/n2"}},
		{"file": "dir/b.wav", "drive": "fdm/tas_mps"},
		{"note": "no file: skipped"},
	]
	var out := AudioCurves.expand(defs, 2)
	if out.size() != 3:
		return "2 engines: 2 + 1 layers, got %d" % out.size()
	var a1: Dictionary = out[0]
	var a2: Dictionary = out[1]
	if a1.id != "a_1" or a2.id != "a_2" or a1.drive != "engines/1/n1" or a2.drive != "engines/2/n1":
		return "ids / drives: %s %s %s %s" % [a1.id, a2.id, a1.drive, a2.drive]
	if not (_near(a1.pan, -0.5) and _near(a2.pan, 0.5)) or a1.n != 1 or a2.n != 2:
		return "pan left / right: %s %s" % [a1.pan, a2.pan]
	if a2.gate.not_props != ["engines/2/running"] or a2.trigger.prop != "engines/2/n2":
		return "{n} must be replaced in gate and trigger: %s %s" % [a2.gate, a2.trigger]
	if out[2].id != "b" or out[2].pan != 0.0 or out[2].n != 0 or out[2].drive != "fdm/tas_mps":
		return "a plain layer is kept once: %s" % [out[2]]
	if AudioCurves.pan_for(1, 1, 0.5) != 0.0 or not _near(AudioCurves.pan_for(2, 4, 0.9), -0.3) or not _near(AudioCurves.pan_for(4, 4, 0.9), 0.9):
		return "pan_for"
	if defs[0].drive != "engines/{n}/n1":
		return "expand must not modify the input"
	return ""


func test_audio_drive_expressions() -> String:
	var v := {"a": 3.0, "b": 4.0, "on": true, "off": false}
	var checks := {
		"a": 3.0, 5.0: 5.0, "on": 1.0, "off": 0.0, "missing": 0.0,
	}
	for k in checks:
		if not _near(AudioCurves.drive_value(k, v), checks[k]):
			return "drive %s = %s, expected %s" % [k, AudioCurves.drive_value(k, v), checks[k]]
	var ex := [[["sum", "a", "b"], 7.0], [["mul", "a", "b"], 12.0], [["sub", 0, "a"], -3.0], [["sub", "b", "a", 0.5], 0.5],
		[["div", "b", "a"], 4.0 / 3.0], [["div", "a", 0], 0.0], [["max", "off", "on"], 1.0], [["min", "a", "b"], 3.0],
		[["abs", ["sub", 0, "b"]], 4.0], [["mul", "on", "b"], 4.0]]
	for e in ex:
		if not _near(AudioCurves.drive_value(e[0], v), e[1]):
			return "expr %s = %s, expected %s" % [e[0], AudioCurves.drive_value(e[0], v), e[1]]
	return ""


func test_audio_gates() -> String:
	var vals := {"fdm/wow": true, "x": 5.0, "flag": true, "gear": 0.5, "p": 0.0}
	var rates := {"fdm/flap_deg": 0.0, "fdm/slat_deg": -0.4}
	var ok := func(g: Dictionary, view := "cockpit") -> bool: return AudioCurves.gate_ok(g, _ctx(vals, view, rates))
	if not ok.call({}):
		return "an empty gate passes"
	if not ok.call({"view": "cockpit"}) or ok.call({"view": "outside"}) or not ok.call({"view": "outside"}, "outside"):
		return "view gate"
	if not ok.call({"ground": true}) or ok.call({"ground": false}):
		return "ground gate (fdm/wow = true)"
	if not ok.call({"props": ["flag"]}) or ok.call({"props": ["flag", "p"]}) or not ok.call({"not_props": ["p"]}) or ok.call({"not_props": ["flag"]}):
		return "props / not_props gate"
	if not ok.call({"min": {"x": 5.0}}) or ok.call({"min": {"x": 5.1}}) or not ok.call({"max": {"x": 5.0}}) or ok.call({"max": {"x": 4.9}}):
		return "min / max gate"
	if not ok.call({"between": {"gear": [0.02, 0.98]}}) or ok.call({"between": {"x": [5.0, 9.0]}}) or ok.call({"between": {"x": [0.0, 5.0]}}):
		return "between gate is exclusive (in transit)"
	if not ok.call({"moving": {"keys": ["fdm/flap_deg", "fdm/slat_deg"], "rate_min": 0.1}}) or ok.call({"moving": {"keys": ["fdm/flap_deg"], "rate_min": 0.1}}):
		return "moving gate (any key's rate, either sign)"
	if ok.call({"view": "cockpit", "ground": true, "min": {"x": 9.0}}):
		return "all conditions must hold"
	return ""


func test_audio_edge_triggers() -> String:
	var rise := {"edge": "rising"}
	var fall := {"edge": "falling"}
	if not AudioCurves.edge(rise, false, true) or AudioCurves.edge(rise, true, true) or AudioCurves.edge(rise, true, false):
		return "rising on a bool"
	if not AudioCurves.edge(fall, true, false) or AudioCurves.edge(fall, false, false) or AudioCurves.edge(fall, false, true):
		return "falling on a bool"
	if not AudioCurves.edge({"edge": "rising", "threshold": 4.0}, 3.9, 4.1) or AudioCurves.edge({"edge": "rising", "threshold": 4.0}, 4.1, 5.0):
		return "numeric rising crosses the threshold once"
	var chg := {"edge": "change", "to": [0, 1]}
	if not AudioCurves.edge(chg, 2, 0) or not AudioCurves.edge(chg, 2, 1) or AudioCurves.edge(chg, 0, 2) or AudioCurves.edge(chg, 1, 1):
		return "change with a 'to' list (gear locks up / down, not in transit)"
	if not AudioCurves.edge({"edge": "change"}, 0.0, 1.0) or AudioCurves.edge({"edge": "change"}, 2.0, 2.0):
		return "plain change"
	if AudioCurves.edge(rise, null, true):
		return "no previous sample, no edge"
	return ""


func test_audio_layer_states_a320_curves() -> String:
	var idle := _layer("eng_idle_1")
	var power := _layer("eng_power_1")
	var whine := _layer("eng_whine_2")
	if idle.is_empty() or power.is_empty() or whine.is_empty():
		return "draft layers eng_idle / eng_power / eng_whine missing"
	var at_idle := AudioCurves.layer_state(idle, _ctx({"engines/1/n1": 20.0}))
	if not _near(at_idle.pitch, 1.0, 0.02) or at_idle.vol < 0.8:
		return "idle loop at N1 20%%: pitch 1.0, loud (%s)" % [at_idle]
	if AudioCurves.layer_state(idle, _ctx({"engines/1/n1": 0.0})).vol != 0.0 or AudioCurves.layer_state(idle, _ctx({"engines/1/n1": 90.0})).vol != 0.0:
		return "idle loop silent when stopped and at takeoff power"
	var takeoff := AudioCurves.layer_state(power, _ctx({"engines/1/n1": 95.0}))
	if not _near(takeoff.pitch, 1.3, 0.03) or takeoff.vol < 0.8:
		return "roar loop at N1 95%%: pitch +30%%, loud (%s)" % [takeoff]
	if AudioCurves.layer_state(power, _ctx({"engines/1/n1": 20.0})).vol != 0.0:
		return "roar loop silent at idle"
	var w := AudioCurves.layer_state(whine, _ctx({"engines/2/n2": 100.0}))
	if w.pitch <= 1.2 or w.vol <= AudioCurves.layer_state(whine, _ctx({"engines/2/n2": 60.0})).vol:
		return "whine follows N2 (rises in pitch and volume): %s" % [w]
	var cock := AudioCurves.layer_state(power, _ctx({"engines/1/n1": 95.0}, "cockpit"))
	if cock.vol >= takeoff.vol:
		return "outside views hear the engines louder: %s vs %s" % [cock.vol, takeoff.vol]
	if AudioCurves.muffle_for(power, "cockpit") <= 0.0 or AudioCurves.muffle_for(power, "outside") != 0.0:
		return "interior low-pass only in the cockpit view"
	return ""


func test_audio_shot_volume_and_gates() -> String:
	if not _layer("touchdown").is_empty():
		return "the touchdown squeal is per wheel and placed at the wheel (world/tyre_squeal.gd), not a fdm/wow layer"
	var gear := _layer("gear_motion")
	if not AudioCurves.layer_state(gear, _ctx({"fdm/gear_pos": 0.5})).on or AudioCurves.layer_state(gear, _ctx({"fdm/gear_pos": 1.0})).on:
		return "gear motion only while in transit"
	return ""


# --- the node ------------------------------------------------------------------

func test_audio_layers_node_two_engines() -> String:
	var node := AudioLayers.new()
	add_child(node)
	node.setup("res://aircraft/a320/sounds/", _draft(), 2)
	var err := ""
	var idle1: AudioStreamPlayer = node._players.get("eng_idle_1")
	var idle2: AudioStreamPlayer = node._players.get("eng_idle_2")
	if idle1 == null or idle2 == null or idle1.stream == null:
		err = "per-engine players with a loaded stream expected"
	elif idle1.bus == idle2.bus or not idle1.bus.begins_with("AL_Engine_") or AudioServer.get_bus_index(idle1.bus) < 0:
		err = "engines 1 / 2 need different panned child buses: %s %s" % [idle1.bus, idle2.bus]
	elif AudioServer.get_bus_send(AudioServer.get_bus_index(idle1.bus)) != "Engine":
		err = "child bus must send to Engine"
	else:
		var v := {"engines/1/n1": 20.0, "engines/2/n1": 0.0, "engines/1/running": true, "engines/2/running": false,
			"engines/1/n2": 62.0, "engines/2/n2": 0.0, "fdm/wow": true}
		node.apply(_ctx(v.duplicate(), "outside"))
		if node.states.eng_idle_1.vol < 0.8 or node.states.eng_idle_2.vol != 0.0:
			err = "engine 1 at idle is heard, engine 2 off is not: %s / %s" % [node.states.eng_idle_1, node.states.eng_idle_2]
		elif idle1.volume_db < -10.0 or idle2.volume_db > -70.0:
			err = "player volumes follow: %.1f / %.1f dB" % [idle1.volume_db, idle2.volume_db]
		else:
			node.apply(_ctx(v.duplicate(), "cockpit"))
			var lp: AudioEffectLowPassFilter = node._lowpass.get("eng_idle_1")
			if lp == null or lp.cutoff_hz > 5000.0:
				err = "cockpit view must engage the low-pass"
			else:
				node.apply(_ctx(v.duplicate(), "outside"))
				if lp.cutoff_hz < 20000.0:
					err = "outside view must release the low-pass"
		if err.is_empty():  # engine 2 starts: n2 rises through 4 % while not running -> start one-shot
			var a := v.duplicate()
			a["engines/2/n2"] = 3.0
			node.apply(_ctx(a))
			var b := a.duplicate()
			b["engines/2/n2"] = 6.0
			node.apply(_ctx(b))
			if not node.states.eng_start_2.on or node.states.eng_start_1.on:
				err = "start whine fires for engine 2 only: %s / %s" % [node.states.eng_start_2, node.states.eng_start_1]
			else:
				node.apply(_ctx(b))
				if node.states.eng_start_2.on:
					err = "an edge fires once"
	_dispose(node)
	return err


func test_audio_layers_first_frame_fires_nothing() -> String:
	var node := AudioLayers.new()
	add_child(node)
	node.setup("res://aircraft/a320/sounds/", _draft(), 2)
	node.apply(_ctx({"engines/1/running": false, "engines/1/n2": 50.0, "fdm/wow": true, "fdm/gear_state": 1}))
	var fired := false
	for id in node.states:
		fired = fired or (node.layers.any(func(l): return l.id == id and not l.get("loop", true)) and node.states[id].on)
	_dispose(node)
	return "a one-shot fired on the very first frame" if fired else ""
