class_name AircraftAudio
extends Node
## The aircraft's sound: builds the layer engine (audio_layers.gd; schema in audio_curves.gd) from aircraft.json
## "audio.layers", with the sounds from the aircraft's sounds/ folder (see its SOURCES.md). A missing sound is silent;
## an aircraft with no layers is silent. Every aircraft (C172, A320) is data: engine, propeller or fans, avionics,
## warnings, pumps, motors, tyres, wind, rain and switch clicks are layers. The touchdown squeal is per wheel and placed
## at the wheel (world/tyre_squeal.gd). "audio.gpws": true adds the stall horn and lite GPWS tones (gpws_player.gd).
## Plan and audit: docs/AUDIO-PLAN.md.

var layers: AudioLayers


func _ready() -> void:
	AudioSettings.apply()
	var def := AircraftDef.current()
	var dir := def.path("sounds")
	if not dir.ends_with("/"):
		dir += "/"
	var audio := def.section("audio")
	if bool(audio.get("gpws", false)):
		var gpws := GpwsPlayer.new()
		add_child(gpws)
		gpws.setup(dir)
	set_process(false)
	if not audio.has("layers"):
		push_warning("aircraft %s has no audio.layers: silent" % def.id)
		return
	layers = AudioLayers.new()
	layers.source = get_parent().get_node_or_null("Aircraft") as Node3D if get_parent() else null
	add_child(layers)
	layers.setup(dir, audio.layers, def.engine_count())
