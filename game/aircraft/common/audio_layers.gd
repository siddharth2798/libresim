class_name AudioLayers
extends Node
## Data-driven layered aircraft sound (used when aircraft.json "audio" has "layers", see
## audio_curves.gd for the layer schema; the C172 keeps its own code path in aircraft_audio.gd).
## Loop layers always play and only their volume / pitch follow the drive; one-shot layers play on a
## Props edge. Per-engine layers are panned left / right through small child buses
## ("AL_<bus>_<pan>_<muffle>", routed to Engine / Environment / Cockpit so the option sliders still
## apply); layers with muffle_hz get a low-pass on that bus while the camera is in the cockpit.
## A sound file that is missing is simply silent.

var layers: Array = []  # expanded layers (AudioCurves.expand)
var _dir := ""
var _players := {}  # id -> AudioStreamPlayer
var _lowpass := {}  # id -> AudioEffectLowPassFilter (its bus is shared by the layers with the same route)
var _keys: Array = []
var _prev := {}  # key -> last sampled value
var _prev_ok := false
var view := "outside"  # last view, for the filters
var states := {}  # id -> {"on", "vol", "pitch"} of the last frame (tests, debugging)


func setup(sounds_dir: String, defs: Array, engine_count: int) -> void:
	_dir = sounds_dir if sounds_dir.ends_with("/") else sounds_dir + "/"
	layers = AudioCurves.expand(defs, engine_count)
	var keys := {}
	for l in layers:
		for k in AudioCurves.watched(l):
			keys[k] = true
		_players[l.id] = _player(l)
	_keys = keys.keys()


func _player(l: Dictionary) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var f: String = l.file
	var path := f if f.begins_with("res://") else _dir + f
	var s: AudioStreamWAV = load(path) if ResourceLoader.exists(path) else null
	var loop: bool = l.get("loop", true)
	if loop and s:
		s = s.duplicate()
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
	p.stream = s
	p.volume_db = -80.0
	p.bus = _route(l)
	add_child(p)
	if loop and s:
		p.play()
	return p


## The bus a layer plays on: its base bus, or a child bus with the panner (and low-pass) it needs.
func _route(l: Dictionary) -> String:
	var base: String = l.get("bus", "Cockpit")
	if not base in AudioCurves.BUSES:
		base = "Cockpit"
	var pan: float = l.get("pan", 0.0)
	var muffle: float = l.get("muffle_hz", 0.0)
	if is_zero_approx(pan) and muffle <= 0.0:
		return base
	var name := "AL_%s_%d_%d" % [base, roundi(pan * 100.0), roundi(muffle)]
	if AudioServer.get_bus_index(name) < 0:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, name)
		AudioServer.set_bus_send(i, base)
		if not is_zero_approx(pan):
			var pn := AudioEffectPanner.new()
			pn.pan = pan
			AudioServer.add_bus_effect(i, pn)
		if muffle > 0.0:
			var lp := AudioEffectLowPassFilter.new()
			lp.cutoff_hz = 20500.0
			AudioServer.add_bus_effect(i, lp)
	if muffle > 0.0:
		var bi := AudioServer.get_bus_index(name)
		for e in AudioServer.get_bus_effect_count(bi):
			if AudioServer.get_bus_effect(bi, e) is AudioEffectLowPassFilter:
				_lowpass[l.id] = AudioServer.get_bus_effect(bi, e)
	return name


func _sample(dt: float) -> Dictionary:
	var vals := {}
	var rates := {}
	for k in _keys:
		var v: Variant = Props.get_v(k, 0.0)
		vals[k] = v
		if _prev.has(k) and (v is float or v is int) and dt > 0.0:
			rates[k] = (float(v) - float(_prev[k])) / dt
	return {"view": view, "values": vals, "rates": rates}


func _process(dt: float) -> void:
	view = "cockpit" if Props.get_v("view/mode", "Chase") == "Cockpit" else "outside"
	apply(_sample(dt), dt)


## One frame with a sampled context (public so tests can drive it without Props).
func apply(ctx: Dictionary, _dt := 0.0) -> void:
	view = ctx.view
	for l in layers:
		var p: AudioStreamPlayer = _players[l.id]
		if l.get("loop", true):
			var st := AudioCurves.layer_state(l, ctx)
			states[l.id] = st
			p.volume_db = linear_to_db(maxf(st.vol, 0.0001))
			p.pitch_scale = st.pitch
			if _lowpass.has(l.id):
				var hz := AudioCurves.muffle_for(l, view)
				_lowpass[l.id].cutoff_hz = hz if hz > 0.0 else 20500.0
		else:
			var trig: Dictionary = l.get("trigger", {})
			var key: String = trig.get("prop", "")
			var fired := _prev_ok and AudioCurves.edge(trig, _prev.get(key), ctx.values.get(key))
			var vol := AudioCurves.shot_volume(l, ctx) if fired else 0.0
			states[l.id] = {"on": fired and vol > 0.0, "vol": vol, "pitch": 1.0}
			if fired and vol > 0.0 and p.stream:
				p.volume_db = linear_to_db(vol)
				p.pitch_scale = clampf(AudioCurves.interp(l.get("pitch", []), AudioCurves.drive_value(l.get("drive"), ctx.values)), 0.05, 4.0)
				p.play()
	_prev = ctx.values.duplicate()
	_prev_ok = true
