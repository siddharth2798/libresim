class_name EngineSound
extends AudioStreamPlayer
## Procedural cockpit audio (placeholder until recorded CC0 loops are added):
## 4-cylinder firing pulses at RPM/30 Hz, prop/exhaust noise scaled by power,
## wind noise with airspeed, tyre rumble on the ground, and the stall horn.
## Reads Props only.

const RATE := 22050.0

var _gen: AudioStreamGeneratorPlayback
var _phase := 0.0
var _horn_phase := 0.0
var _lp := 0.0
var _lp2 := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var g := AudioStreamGenerator.new()
	g.mix_rate = RATE
	g.buffer_length = 0.15
	stream = g
	volume_db = -6.0
	play()
	_gen = get_stream_playback()


func _process(_dt: float) -> void:
	if _gen == null:
		return
	var rpm := Props.get_f("engine/rpm")
	var power := clampf(Props.get_f("engine/power_w") / 134000.0, 0.0, 1.0)
	var running := Props.get_b("engine/running")
	var tas := Props.get_f("fdm/tas_mps")
	var wow := Props.get_b("fdm/wow")
	var gs := Props.get_f("fdm/groundspeed_mps")
	var horn := Props.get_b("fdm/stall_warning")
	var f_fire := rpm / 30.0
	var eng_amp := (0.18 + 0.5 * power) if running else 0.12 * clampf(rpm / 500.0, 0.0, 1.0)
	var wind_amp := clampf(tas / 60.0, 0.0, 1.0) ** 2 * 0.35
	var rumble := clampf(gs / 25.0, 0.0, 1.0) * 0.4 if wow else 0.0
	var n := _gen.get_frames_available()
	for i in n:
		_phase = fmod(_phase + f_fire / RATE, 1.0)
		# sharp firing pulse with a decaying tail + 2nd harmonic for the prop
		var pulse := exp(-_phase * 7.0) - 0.3 + 0.25 * sin(TAU * _phase * 2.0)
		var noise := _rng.randf() * 2.0 - 1.0
		_lp += (noise - _lp) * 0.08  # low-passed noise (wind)
		_lp2 += (noise - _lp2) * 0.01  # very low (rumble)
		var s := pulse * eng_amp * (0.85 + 0.15 * noise) + _lp * wind_amp * 2.0 + _lp2 * rumble * 6.0
		if horn:
			_horn_phase = fmod(_horn_phase + 1600.0 / RATE, 1.0)
			s += (0.12 if _horn_phase < 0.5 else -0.12)
		s = clampf(s, -1.0, 1.0)
		_gen.push_frame(Vector2(s, s))
