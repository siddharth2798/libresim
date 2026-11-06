class_name GpwsPlayer
extends Node
## Plays the A320 stall horn and lite GPWS tones (cues from gpws.gd). AircraftAudio adds
## this only when aircraft.json "audio.gpws" is true, so the C172 path is unchanged.
## Cockpit bus (core/audio_settings.gd). A missing wav is silent.
## Props are SI. agl and vertical speed are converted here to feet and ft/min, the units
## Gpws shares with CalloutLogic. These tones play in normal flight; the instructor
## callouts in ui/callouts.gd stay off unless the pilot turns them on.

const CUES := {
	"stall": "stall_horn_loop.wav",
	"alt": "gpws_alt.wav",
	"sink": "gpws_sink.wav",
	"ap": "gpws_ap.wav",
}
const GAIN := {"stall": 0.72, "alt": 0.5, "sink": 0.7, "ap": 0.62}

var _state := Gpws.new_state()
var _players := {}
var _ap := false
var _ap_seen := false


func setup(sounds_dir: String) -> void:
	var dir := sounds_dir if sounds_dir.ends_with("/") else sounds_dir + "/"
	for cue in CUES:
		_players[cue] = _player(dir + str(CUES[cue]), cue == "stall")


func _player(path: String, loop: bool) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var s: AudioStreamWAV = load(path) if ResourceLoader.exists(path) else null
	if loop and s:
		s = s.duplicate()
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
	p.stream = s
	p.volume_db = -80.0
	p.bus = "Cockpit"
	add_child(p)
	if loop and s:
		p.play()
	return p


func _process(dt: float) -> void:
	if _players.is_empty():
		return
	var ap := Props.get_b("ap/cmd/takeover")
	var edge := _ap_seen and ap and not _ap
	_ap = ap
	_ap_seen = true
	var cue := Gpws.step(_state, {
		"agl_ft": Units.m_to_ft(Props.get_f("fdm/agl_m")),
		"vs_fpm": Units.mps_to_fpm(Props.get_f("fdm/vs_mps")),
		"wow": Props.get_b("fdm/wow"),
		"stall": Props.get_b("fcs/stall_warning") or Props.get_b("fdm/stall_warning"),
		"ap_disconnect_edge": edge,
	}, dt)
	_apply(cue)


func _apply(cue: String) -> void:
	var stall: AudioStreamPlayer = _players.stall
	stall.volume_db = linear_to_db(GAIN.stall if cue == "stall" else 0.0001)
	if cue == "" or cue == "stall":
		return
	var p: AudioStreamPlayer = _players[cue]
	if p.stream:
		p.volume_db = linear_to_db(float(GAIN[cue]))
		p.play()
