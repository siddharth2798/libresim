class_name TyreSqueal
extends Node3D
## Touchdown tyre squeal: the chirp of a tyre being spun up by the runway, played once per wheel per touchdown
## (TouchdownDetect events) from that wheel. Each gear leg has its own AudioStreamPlayer3D that follows its contact
## point while it plays, so the left main is heard on the left in the cockpit, a chase camera hears it from
## the gear, and the tower hears it faint and far. Louder for a firmer, faster touchdown; muffled by the cabin
## in the cockpit view. Bus "Environment" (Options: Wind & environment).
## aircraft.json "touchdown.squeal" (all optional): file (in the aircraft's sounds/, or a res:// path; default
## squeal.wav), gain (1), pitch (1), unit_m (12: the distance at which it plays at full volume; bigger = carries
## further). A missing file is silent.

const DEFAULTS := {"file": "squeal.wav", "gain": 1.0, "pitch": 1.0, "unit_m": 12.0}
const COCKPIT := 0.6  # the cabin and the engine noise cover part of it
const COCKPIT_HZ := 2500.0  # through the cabin wall the high end is gone

var fdm_node: FdmNode
var _par := {}
var _stream: AudioStream
var _players := {}  # wheel -> AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()


## Linear volume 0..1 of a wheel's squeal from its sink rate (m/s), slip (m/s, ground speed minus rim speed) and
## sideways tyre speed (m/s): a soft touchdown still chirps, a firm fast one shrieks.
static func volume(sink: float, slip: float, vlat := 0.0) -> float:
	var speed_f := clampf((Vector2(slip, vlat).length() - TouchdownDetect.MIN_SLIP) / 30.0, 0.0, 1.0)
	var press := clampf(maxf(sink, absf(vlat)) / 2.5, 0.0, 1.0)
	return clampf((0.3 + 0.7 * speed_f) * (0.45 + 0.55 * press), 0.0, 1.0)


static func params(def: AircraftDef) -> Dictionary:
	var p := DEFAULTS.duplicate()
	p.merge(def.section("touchdown").get("squeal", {}), true)
	var f := str(p.file)
	if not f.begins_with("res://"):
		var dir := def.path("sounds")
		p.file = dir + ("" if dir.ends_with("/") else "/") + f
	return p


func setup(f: FdmNode, def: AircraftDef) -> void:
	fdm_node = f
	_rng.randomize()
	AudioSettings.ensure_buses()  # "Environment" must exist, or the player falls back to Master
	_par = params(def)
	_stream = load(_par.file) if ResourceLoader.exists(_par.file) else null


func play(ev: Dictionary) -> void:
	if _stream == null:
		return
	var p: AudioStreamPlayer3D = _players.get(ev.wheel)
	if p == null:
		p = AudioStreamPlayer3D.new()
		p.stream = _stream
		p.bus = "Environment"
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = float(_par.unit_m)
		p.max_db = 0.0
		p.max_distance = 4000.0
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(p)
		_players[ev.wheel] = p
	var cockpit: bool = Props.get_v("view/mode", "Chase") == "Cockpit"
	var vol := volume(ev.sink, ev.get("slip", ev.gs), ev.get("vlat", 0.0)) * float(_par.gain) * (COCKPIT if cockpit else 1.0)
	p.volume_db = linear_to_db(maxf(vol, 0.0001))
	p.attenuation_filter_cutoff_hz = COCKPIT_HZ if cockpit else 5000.0
	p.pitch_scale = float(_par.pitch) * _rng.randf_range(0.94, 1.06)
	p.global_position = FloatingOrigin.to_render_d(ev.e, ev.n, fdm_node.fdm.ground_height.call(ev.n, ev.e))
	p.play()


func _process(_dt: float) -> void:
	for w in _players:
		var p: AudioStreamPlayer3D = _players[w]
		if p.playing:
			p.global_position = wheel_render(w)


## Render position of a wheel's contact point now (FDM state, so it follows the aircraft and the origin shifts).
func wheel_render(wheel: String) -> Vector3:
	var w := TouchdownDetect.wheel_enu(fdm_node.fdm, wheel)
	return FloatingOrigin.to_render_d(w.x, w.y, w.z)


func stop_all() -> void:
	for w in _players:
		(_players[w] as AudioStreamPlayer3D).stop()
