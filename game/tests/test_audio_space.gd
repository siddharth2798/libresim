extends Node
## Layer schema additions (aircraft/common/audio_curves.gd, audio_space.gd, audio_layers.gd; docs/AUDIO-PLAN.md): distance
## fall-off and Doppler of exterior layers, volume easing, "mods", the "rate" drive, "clicks" groups, and the A320 / C172
## layers built on them (PTU, pumps, master warning and caution, chimes, turbulence). Dummy audio server: values only.

const TL := preload("res://tests/test_audio_layers.gd")


func _near(a: float, b: float, eps := 0.01) -> bool:
	return absf(a - b) <= eps


func _ctx(vals: Dictionary, view := "outside", extra := {}) -> Dictionary:
	var c := {"view": view, "values": vals, "rates": {}}
	c.merge(extra, true)
	return c


func _layer(aircraft: String, id: String, engines := 2) -> Dictionary:
	for l in AudioCurves.expand(TL.layers_of(aircraft), engines):
		if l.id == id:
			return l
	return {}


func _dispose(n: Node) -> void:
	for c in n.find_children("*", "AudioStreamPlayer", true, false):
		c.stop()
	remove_child(n)
	n.free()
	OS.delay_msec(150)


func test_audio_space_distance_and_doppler() -> String:
	if AudioSpace.distance_gain(5.0) != 1.0 or AudioSpace.distance_gain(15.0) != 1.0:
		return "full volume up to the reference distance"
	if not _near(AudioSpace.distance_gain(30.0), 0.5) or not _near(AudioSpace.distance_gain(1515.0), 0.01, 0.001):
		return "inverse distance past ref: %.3f %.4f" % [AudioSpace.distance_gain(30.0), AudioSpace.distance_gain(1515.0)]
	if AudioSpace.distance_gain(1515.0, 15.0, 0.5) <= AudioSpace.distance_gain(1515.0):
		return "a smaller rolloff carries further"
	if not _near(AudioSpace.doppler(0.0), 1.0) or not _near(AudioSpace.doppler(34.0), 340.0 / 306.0, 0.001):
		return "doppler: %.3f %.3f" % [AudioSpace.doppler(0.0), AudioSpace.doppler(34.0)]
	if AudioSpace.doppler(-60.0) >= 1.0 or AudioSpace.doppler(5000.0) > 2.0:
		return "receding lowers the pitch; clamped"
	if AudioSpace.ease(0.0, 1.0, 0.1, 0.0) != 1.0 or AudioSpace.ease(0.0, 1.0, 0.0, 0.5) != 1.0:
		return "tau or dt 0 snaps"
	if not _near(AudioSpace.ease(0.0, 1.0, 0.5, 0.5), 1.0 - exp(-1.0), 0.001):
		return "first-order easing"
	if not _near(AudioSpace.closing_speed(100.0, 90.0, 1.0, 0.0), 10.0 * (1.0 - exp(-4.0)), 0.001):
		return "closing speed is low-passed: %.3f" % AudioSpace.closing_speed(100.0, 90.0, 1.0, 0.0)
	return ""


func test_audio_mods_rate_and_clicks() -> String:
	var l := {"file": "x.wav", "drive": "a", "volume": [[0, 0.0], [10, 1.0]],
		"mods": [{"drive": "b", "volume": [[0, 1.0], [100, 0.0]]}, {"drive": ["rate", "c"], "volume": [[0, 0.0], [2, 1.0]]}]}
	var st := AudioCurves.layer_state(l, _ctx({"a": 10.0, "b": 50.0, "rate:c": 1.0}))
	if not _near(st.vol, 0.25):
		return "mods multiply: %s" % st
	if not AudioCurves.watched(l).has("b") or not AudioCurves.watched(l).has("c"):
		return "mod and rate keys are sampled: %s" % [AudioCurves.watched(l)]
	if AudioCurves.drive_value(["abs", ["rate", "c"]], {"rate:c": -3.0}) != 3.0:
		return "rate drive"
	var cl := AudioCurves.expand([{"clicks": {"file_on": "on.wav", "file_off": "off.wav", "props": ["controls/x", "controls/y"]}}], 1)
	if cl.size() != 4 or cl[0].id != "click_controls_x_on" or cl[1].trigger.edge != "falling" or cl[0].loop != false:
		return "clicks expand to on / off one-shots: %s" % [cl.map(func(e): return e.id)]
	if AudioCurves.shot_volume(cl[0], _ctx({}, "outside")) != 0.0 or AudioCurves.shot_volume(cl[0], _ctx({}, "cockpit")) <= 0.0:
		return "clicks are heard in the cockpit only"
	return ""


func test_audio_node_smooth_and_attenuate() -> String:
	var defs := [{"id": "eng", "file": "res://aircraft/c172/sounds/engine.wav", "drive": "a", "volume": [[0, 0.0], [1, 1.0]],
		"attenuate": true, "smooth": 0.5}]
	var node := AudioLayers.new()
	add_child(node)
	node.setup("res://aircraft/c172/sounds/", defs, 1)
	var err := ""
	node.apply(_ctx({"a": 1.0}, "outside", {"distance_m": 10.0}))
	if not _near(node.states.eng.vol, 1.0):
		err = "first frame starts at the target: %s" % node.states.eng
	node.apply(_ctx({"a": 0.0}, "outside", {"distance_m": 10.0}), 0.5)
	if err.is_empty() and not _near(node.states.eng.vol, exp(-1.0), 0.01):
		err = "a gate edge eases out, it does not snap: %s" % node.states.eng
	node.apply(_ctx({"a": 1.0}, "outside", {"distance_m": 60.0, "closing_mps": 34.0}))
	if err.is_empty() and (not _near(node.states.eng.vol, 0.25) or not _near(node.states.eng.pitch, 340.0 / 306.0, 0.001)):
		err = "outside 60 m away and closing: quieter and higher: %s" % node.states.eng
	node.apply(_ctx({"a": 1.0}, "cockpit", {"distance_m": 60.0, "closing_mps": 34.0}))
	if err.is_empty() and (not _near(node.states.eng.vol, 1.0) or node.states.eng.pitch != 1.0):
		err = "the cockpit hears it as it is: %s" % node.states.eng
	_dispose(node)
	return err


func test_audio_a320_systems_layers() -> String:
	var base := {"fdm/wow": true}
	var checks := [
		["ptu_bark", {"hyd/ptu_active": true}, {"hyd/ptu_active": false}],
		["master_warning", {"ewd/master_warning": true}, {"ewd/master_warning": false}],
		["hyd_epump_yellow", {"controls/hyd/yellow_epump": true, "systems/electrical/ac2_on": true}, {"controls/hyd/yellow_epump": true}],
		["packs", {"systems/packs/1_on": true}, {}],
		["avionics_fan", {"systems/electrical/ac_ess_on": true}, {}],
		["apu", {"apu/n_pct": 100.0}, {"apu/n_pct": 0.0}],
	]
	for c in checks:
		var l := _layer("a320", c[0])
		if l.is_empty():
			return "a320 layer %s missing" % c[0]
		var on: Dictionary = base.duplicate()
		on.merge(c[1])
		var off: Dictionary = base.duplicate()
		off.merge(c[2])
		if AudioCurves.layer_state(l, _ctx(on, "cockpit")).vol <= 0.0 or AudioCurves.layer_state(l, _ctx(off, "cockpit")).vol != 0.0:
			return "%s follows its system: on %s / off %s" % [c[0], AudioCurves.layer_state(l, _ctx(on, "cockpit")),
				AudioCurves.layer_state(l, _ctx(off, "cockpit"))]
	var apu := _layer("a320", "apu")
	if AudioCurves.layer_state(apu, _ctx({"apu/n_pct": 30.0})).pitch >= AudioCurves.layer_state(apu, _ctx({"apu/n_pct": 100.0})).pitch:
		return "the APU spools up in pitch"
	var chime := _layer("a320", "seatbelt_chime")
	if chime.get("trigger", {}).get("prop") != "controls/signs/seatbelts":
		return "the seat-belt chime watches the real sign property: %s" % chime.get("trigger")
	var caution := _layer("a320", "master_caution")
	if not AudioCurves.edge(caution.trigger, false, true) or AudioCurves.edge(caution.trigger, true, true):
		return "master caution chimes once on the rising edge"
	if _layer("a320", "click_controls_hyd_ptu").is_empty() or _layer("a320", "click_controls_apu_master").is_empty():
		return "overhead switches click"
	return ""


func test_audio_turbulence_and_load() -> String:
	for ac in ["c172", "a320"]:
		var t := _layer(ac, "turbulence")
		var calm := AudioCurves.layer_state(t, _ctx({"fdm/wow": false, "fdm/tas_mps": 60.0, "rate:fdm/load_factor": 0.1}, "cockpit"))
		var rough := AudioCurves.layer_state(t, _ctx({"fdm/wow": false, "fdm/tas_mps": 60.0, "rate:fdm/load_factor": -4.0}, "cockpit"))
		var ground := AudioCurves.layer_state(t, _ctx({"fdm/wow": true, "fdm/tas_mps": 20.0, "rate:fdm/load_factor": -4.0}, "cockpit"))
		if calm.vol != 0.0 or rough.vol <= 0.3 or ground.vol != 0.0:
			return "%s turbulence: calm %s rough %s ground %s" % [ac, calm, rough, ground]
	var run := _layer("c172", "engine_run")
	var v := {"engine/rpm": 2300.0, "engine/running": true}
	var idle_map: float = AudioCurves.layer_state(run, _ctx(v.merged({"engine/map_pa": 40000.0}))).vol
	var full_map: float = AudioCurves.layer_state(run, _ctx(v.merged({"engine/map_pa": 98000.0}))).vol
	if full_map <= idle_map:
		return "the same rpm under full throttle is louder than in a dive at idle: %.3f / %.3f" % [full_map, idle_map]
	return ""
