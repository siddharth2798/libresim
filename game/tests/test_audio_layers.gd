extends Node
## The data-driven layer sound engine (aircraft/common/audio_curves.gd pure functions, audio_layers.gd node),
## the C172 sound path staying as it was, and the draft A320 audio section (files exist and are credited).
## The audio server is a dummy in tests: volumes and pitches are asserted, not output.

const DRAFT := "res://aircraft/a320/audio_section.json"
const C172_LOOPS := ["engine-idle", "engine", "engine-crank", "gyro", "wind1", "tires-rolling-asphalt", "rumble",
	"stall2", "flaps-motor", "trim", "avionics-400Hz", "rain", "rain-windshield"]
const C172_SHOTS := ["engine-start", "engine-cut", "squeal", "click", "click2", "double-click", "lever", "keys", "flaps-click"]


func _draft() -> Array:
	var j = JSON.parse_string(FileAccess.get_file_as_string(DRAFT))
	return j.layers if j is Dictionary and j.has("layers") else []


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
	var td := _layer("touchdown")
	var fast := {"fdm/groundspeed_mps": 70.0, "fdm/vs_mps": -3.0, "fdm/wow": true}
	var slow := {"fdm/groundspeed_mps": 5.0, "fdm/vs_mps": -3.0, "fdm/wow": true}
	var hard := AudioCurves.shot_volume(td, _ctx(fast))
	var soft := AudioCurves.shot_volume(td, _ctx({"fdm/groundspeed_mps": 70.0, "fdm/vs_mps": -0.2, "fdm/wow": true}))
	if hard <= soft or soft <= 0.0:
		return "touchdown squeal grows with sink rate (%.2f vs %.2f)" % [hard, soft]
	if AudioCurves.shot_volume(td, _ctx(slow)) != 0.0:
		return "no squeal at taxi speed (gate min groundspeed)"
	if td.trigger.prop != "fdm/wow" or td.trigger.edge != "rising":
		return "touchdown trigger is fdm/wow rising"
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


# --- the C172 path is unchanged -------------------------------------------------

func test_audio_c172_path_unchanged() -> String:
	var prev = Session.setup.get("aircraft")
	Session.setup["aircraft"] = "c172"
	var def := AircraftDef.current()
	var err := ""
	if def.id != "c172" or def.section("audio").has("layers"):
		err = "the c172 audio section must not have layers"
	else:
		var a := AircraftAudio.new()
		add_child(a)
		var loops: Array = a._loops.keys()
		var shots: Array = a._shots.keys()
		loops.sort()
		shots.sort()
		var el := C172_LOOPS.duplicate()
		var es := C172_SHOTS.duplicate()
		el.sort()
		es.sort()
		if loops != el or shots != es:
			err = "c172 loops / shots changed: %s / %s" % [loops, shots]
		elif not a.is_processing() or a.get_children().any(func(c): return c is AudioLayers):
			err = "c172 keeps its own _process and has no layer node"
		_dispose(a)
	if prev == null:
		Session.setup.erase("aircraft")
	else:
		Session.setup["aircraft"] = prev
	return err


func test_audio_a320_aircraft_uses_layers() -> String:
	var def := AircraftDef.make("a320x", {"audio": {"layers": _draft()}}, "res://aircraft/a320")
	var prev = Session.setup.get("aircraft")
	AircraftDef._cache["a320x"] = def
	Session.setup["aircraft"] = "a320x"
	var a := AircraftAudio.new()
	add_child(a)
	var err := ""
	if a.is_processing() or not a.get_children().any(func(c): return c is AudioLayers) or not a._loops.is_empty():
		err = "an aircraft with audio.layers uses AudioLayers and not the c172 loops"
	_dispose(a)
	AircraftDef._cache.erase("a320x")
	if prev == null:
		Session.setup.erase("aircraft")
	else:
		Session.setup["aircraft"] = prev
	return err


# --- the draft A320 section and its credits --------------------------------------

func test_audio_a320_draft_files_exist_and_are_credited() -> String:
	var layers := _draft()
	if layers.size() < 20:
		return "draft audio section missing or too short (%d layers)" % layers.size()
	var a320_md := FileAccess.get_file_as_string("res://aircraft/a320/sounds/SOURCES.md")
	var c172_md := FileAccess.get_file_as_string("res://aircraft/c172/sounds/SOURCES.md")
	if a320_md.is_empty():
		return "a320/sounds/SOURCES.md missing"
	var ids := {}
	for l in layers:
		var f: String = l.get("file", "")
		if f.is_empty():
			return "layer without a file: %s" % [l]
		if ids.has(l.get("id", f)):
			return "duplicate layer id %s" % l.get("id", f)
		ids[l.get("id", f)] = true
		if not l.get("bus", "Cockpit") in AudioCurves.BUSES:
			return "layer %s: unknown bus %s" % [l.get("id"), l.get("bus")]
		var path := f if f.begins_with("res://") else "res://aircraft/a320/sounds/" + f
		if not FileAccess.file_exists(path):
			return "layer %s: %s does not exist" % [l.get("id"), path]
		var md := c172_md if f.begins_with("res://aircraft/c172/") else a320_md
		var key := f.get_file() if not f.begins_with("res://") else f.get_file().get_basename()
		if not md.contains(key):
			return "%s is not listed in its SOURCES.md" % key
		if l.get("loop", true) == false and not l.has("trigger"):
			return "one-shot layer %s needs a trigger" % l.get("id")
		for k in AudioCurves.watched(l):
			if k.contains("{n}") and not l.get("per_engine", false):
				return "layer %s uses {n} without per_engine" % l.get("id")
	var dir := DirAccess.open("res://aircraft/a320/sounds")
	for f in dir.get_files():
		if (f.ends_with(".wav") or f.ends_with(".ogg")) and not a320_md.contains(f):
			return "a320/sounds/%s is not in SOURCES.md" % f
	return ""
