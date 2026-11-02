class_name AircraftAudio
extends Node
## Recorded aircraft sounds (the aircraft's sounds/ folder, e.g. aircraft/c172/sounds, see SOURCES.md)
## driven by Props. A sound the folder lacks is simply silent, so a partial set works. The engine
## and wind mappings are the aircraft.json "audio" section (defaults below = c172p); the engine
## loops follow engine 1 (props engine/rpm, engine/running).
## Loops: engine idle/run (volume & pitch from RPM, mappings after the c172p
## sound config), starter crank, gyro spin, wind (airspeed), tyre roll + rumble
## (ground speed), stall horn, flap motor, trim wheel, avionics fan, rain (environment/precip;
## on the windshield it drums harder with airspeed).
## One-shots: engine catch / cut, touchdown squeal, switch clicks, levers.
## Cockpit view hears everything; outside views hear the engine louder and no clicks.
## An aircraft whose aircraft.json "audio" has a "layers" list (the A320) uses audio_layers.gd instead and
## none of the code below (audio_curves.gd has the schema).

## aircraft.json "audio": "engine" and "wind" override these keys one by one.
const DEFAULTS := {
	"engine": {
		"idle_fade_from_rpm": 900.0, "idle_fade_span_rpm": 500.0,  # idle loop fades out over this rpm range
		"idle_volume": 0.9, "idle_pitch_rpm": 700.0,               # pitch = rpm / idle_pitch_rpm (0.6..1.6)
		"run_slope": 0.000294118, "run_offset": 0.205882353,       # run loop volume = rpm * slope + offset
		"run_min": 0.5, "run_max": 0.95,
		"run_start_rpm": 600.0, "run_ramp_rpm": 400.0,             # run loop fades in over this rpm range
		"pitch_slope": 0.000434783, "pitch_offset": 0.01,          # run loop pitch = rpm * slope + offset
		"windmill_min_rpm": 200.0, "windmill_rpm": 2500.0,         # engine off but turning: quiet noise
	},
	"wind": {
		"slope": 0.0015, "min": 0.03, "max": 0.25,                 # volume from true airspeed (kt)
		"alt_slope": 0.000015,                                     # fades with altitude (ft)
		"pitch_slope": 0.0035, "pitch_offset": 1.25,
	},
}

var _dir := ""  # sounds folder with trailing slash
var _eng := {}
var _wind := {}
var _loops := {}  # name -> AudioStreamPlayer
var _shots := {}
var _prev := {}
var _trim_prev := 0.0
var _trim_t := 0.0
const WATCH := ["controls/electrical/master_bat", "controls/electrical/master_alt", "controls/electrical/avionics",
	"controls/lights/beacon", "controls/lights/landing", "controls/lights/taxi", "controls/lights/nav",
	"controls/lights/strobe", "controls/electrical/pitot_heat", "systems/alternate_static", "controls/fuel/shutoff"]


const BUS := {"engine-idle": "Engine", "engine": "Engine", "engine-crank": "Engine", "engine-start": "Engine",
	"engine-cut": "Engine", "wind1": "Environment", "tires-rolling-asphalt": "Environment", "rumble": "Environment",
	"rain": "Environment", "rain-windshield": "Environment", "squeal": "Environment"}  # everything else: Cockpit (see core/audio_settings.gd)


func _ready() -> void:
	AudioSettings.apply()
	var def := AircraftDef.current()
	_dir = def.path("sounds")
	if not _dir.ends_with("/"):
		_dir += "/"
	if def.section("audio").has("layers"):  # data-driven layer engine (audio_layers.gd); the c172 code below is not used
		var layers := AudioLayers.new()
		add_child(layers)
		layers.setup(_dir, def.section("audio").layers, def.engine_count())
		set_process(false)
		return
	_eng = _mapping(def, "engine")
	_wind = _mapping(def, "wind")
	for n in ["engine-idle", "engine", "engine-crank", "gyro", "wind1", "tires-rolling-asphalt", "rumble",
			"stall2", "flaps-motor", "trim", "avionics-400Hz", "rain", "rain-windshield"]:
		_loops[n] = _player(n, true)
	for n in ["engine-start", "engine-cut", "squeal", "click", "click2", "double-click", "lever", "keys", "flaps-click"]:
		_shots[n] = _player(n, false)


func _mapping(def: AircraftDef, key: String) -> Dictionary:
	var d: Dictionary = DEFAULTS[key].duplicate()
	d.merge(def.section("audio").get(key, {}), true)
	return d


func _player(n: String, loop: bool) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var path := _dir + n + ".wav"
	var s: AudioStreamWAV = load(path) if ResourceLoader.exists(path) else null
	if loop and s:
		s = s.duplicate()
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
	p.stream = s
	p.volume_db = -80.0
	p.bus = BUS.get(n, "Cockpit")
	add_child(p)
	if loop and s:
		p.play()
	return p


func _loop(n: String, vol: float, pitch := 1.0) -> void:
	var p: AudioStreamPlayer = _loops[n]
	p.volume_db = linear_to_db(maxf(vol, 0.0001))
	p.pitch_scale = clampf(pitch, 0.05, 4.0)


func _shot(n: String, vol := 1.0) -> void:
	var p: AudioStreamPlayer = _shots[n]
	p.volume_db = linear_to_db(vol)
	if p.stream:
		p.play()


func _process(dt: float) -> void:
	var cockpit: bool = Props.get_v("view/mode", "Chase") == "Cockpit"
	var rpm := Props.get_f("engine/rpm")
	var running := Props.get_b("engine/running")
	var kt := Units.mps_to_kt(Props.get_f("fdm/tas_mps"))
	var gs := Units.mps_to_kt(Props.get_f("fdm/groundspeed_mps"))
	var wow := Props.get_b("fdm/wow")
	var outside := 1.0 if cockpit else 1.3
	# engine: idle loop fades out as the run loop takes over (c172p mapping)
	var e := _eng
	var idle_fade := clampf(1.0 - (rpm - e.idle_fade_from_rpm) / e.idle_fade_span_rpm, 0.0, 1.0) if running else 0.0
	var run_vol := clampf(rpm * e.run_slope + e.run_offset, e.run_min, e.run_max) * clampf((rpm - e.run_start_rpm) / e.run_ramp_rpm, 0.0, 1.0) if running else 0.0
	if not running and rpm > e.windmill_min_rpm:  # windmilling / spinning down: quiet engine noise
		run_vol = clampf(rpm / e.windmill_rpm, 0.0, 0.4) * 0.5
	_loop("engine-idle", idle_fade * e.idle_volume * outside, clampf(rpm / e.idle_pitch_rpm, 0.6, 1.6))
	_loop("engine", run_vol * outside, rpm * e.pitch_slope + e.pitch_offset)
	var cranking := Props.get_b("controls/starter") and Props.get_b("systems/electrical/starter_ok", true) and not running
	_loop("engine-crank", 0.6 if cranking else 0.0)
	if running and not _prev.get("running", running):
		_shot("engine-start", 0.8)
	elif not running and _prev.get("running", false) and rpm > 300.0:
		_shot("engine-cut", 0.9)
	_prev["running"] = running
	# gyro whine follows vacuum (cockpit only)
	var spin := clampf(Props.get_f("systems/vacuum/suction_inhg") / 5.0, 0.0, 1.0)
	_loop("gyro", (spin * 0.08) if cockpit else 0.0, maxf(spin, 0.05))
	_loop("avionics-400Hz", 0.03 if cockpit and Props.get_b("systems/electrical/avionics_powered") else 0.0)
	# wind & ground
	var alt_ft := Units.m_to_ft(Props.get_f("fdm/alt_m"))
	var w := _wind
	_loop("wind1", clampf(kt * w.slope, w.min, w.max) * clampf(1.0 - alt_ft * w.alt_slope, 0.1, 1.0) * (1.0 if cockpit else 1.6), kt * w.pitch_slope + w.pitch_offset)
	var roll := clampf(log(1.0 + gs) * 0.25, 0.0, 1.0) if wow else 0.0
	_loop("tires-rolling-asphalt", roll * 0.7)
	_loop("rumble", roll * 0.5)
	if wow and not _prev.get("wow", true) and gs > 25.0:
		_shot("squeal", clampf(-Props.get_f("fdm/vs_mps") * 0.6 + 0.3, 0.2, 1.0))
	_prev["wow"] = wow
	# warnings / actuators
	_loop("stall2", 0.7 if Props.get_b("fdm/stall_warning") else 0.0)
	var flap_motor := Props.get_b("systems/electrical/flap_motor_running")
	_loop("flaps-motor", 0.5 if flap_motor and cockpit else (0.2 if flap_motor else 0.0))
	var trim := Props.get_f("controls/pitch_trim")
	_trim_t = 0.25 if absf(trim - _trim_prev) > 1e-5 else _trim_t - dt
	_trim_prev = trim
	_loop("trim", 0.8 if _trim_t > 0.0 and cockpit else 0.0)
	# rain on the canopy: local rain rate (WeatherFx), drumming harder with airspeed
	var rain := Props.get_f("environment/precip")
	var drum := clampf(0.45 + kt / 160.0, 0.45, 1.1)
	_loop("rain", rain * (0.35 if cockpit else 0.55))
	_loop("rain-windshield", rain * drum * (0.7 if cockpit else 0.15), 0.9 + clampf(kt / 400.0, 0.0, 0.3))
	# switch clicks and levers (cockpit)
	for k in WATCH:
		var v := Props.get_b(k)
		if _prev.has(k) and _prev[k] != v and cockpit:
			_shot("click" if v else "click2", 0.7)
		_prev[k] = v
	for k in ["controls/magnetos", "controls/fuel/selector", "controls/flaps"]:
		var v2 = Props.get_v(k, 0)
		if _prev.has(k) and _prev[k] != v2:
			_shot("keys" if k == "controls/magnetos" else ("flaps-click" if k == "controls/flaps" else "double-click"), 0.6 if cockpit else 0.2)
		_prev[k] = v2
	var pb := Props.get_b("controls/parking_brake")
	if _prev.has("pb") and _prev.pb != pb and cockpit:
		_shot("lever", 0.8)
	_prev["pb"] = pb
