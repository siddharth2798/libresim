class_name Thunder
extends Node
## Thunder after each lightning strike (environment/lightning, WeatherFx): the strike is put at a random distance, the
## sound arrives distance / speed of sound later, quieter and duller the further away (Thunder.plan, pure,
## tests/test_world_sound.gd). Up to MAX_PENDING peals wait at once. world/sounds/thunder.wav; bus Environment; the
## cockpit hears it through the airframe. Child of WeatherFx.

const SOUND_MPS := 340.0
const NEAR_KM := 0.8
const FAR_KM := 6.0
const MAX_PENDING := 4
const COCKPIT := 0.7

var pending: Array = []  # [{t: seconds left, vol, pitch}]
var _players: Array = []
var _prev := 0.0
var _quiet := 10.0  # seconds since the last flash: a new strike after a pause of 1 s
var _rng := RandomNumberGenerator.new()


## {delay (s), vol (linear), pitch} of thunder from a strike dist_km away.
static func plan(dist_km: float) -> Dictionary:
	var d := clampf(dist_km, 0.1, 30.0)
	return {"delay": d * 1000.0 / SOUND_MPS, "vol": clampf(1.6 / (1.0 + d), 0.05, 1.0), "pitch": clampf(1.05 - 0.05 * d, 0.7, 1.05)}


func _ready() -> void:
	_rng.randomize()
	var f := WorldSound.path("thunder.wav")
	var s: AudioStream = load(f) if ResourceLoader.exists(f) else null
	AudioSettings.ensure_buses()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.stream = s
		p.bus = "Environment"
		add_child(p)
		_players.append(p)


## A strike now: queue its peal (public for tests).
func strike(dist_km: float) -> void:
	if pending.size() < MAX_PENDING:
		var pl := plan(dist_km)
		pending.append({"t": pl.delay, "vol": pl.vol, "pitch": pl.pitch})


func _process(dt: float) -> void:
	var flash := Props.get_f("environment/lightning")
	if flash > 0.4 and _prev <= 0.4 and _quiet > 1.0:
		strike(_rng.randf_range(NEAR_KM, FAR_KM))
	_quiet = 0.0 if flash > 0.05 else _quiet + dt
	_prev = flash
	step(dt)


## Count the waiting peals down and play those that are due (public for tests).
func step(dt: float) -> Array:
	var due := []
	for e in pending:
		e.t -= dt
		if e.t <= 0.0:
			due.append(e)
	for e in due:
		pending.erase(e)
		var p: AudioStreamPlayer = _players[0] if not _players[0].playing else _players[1]
		var vol: float = e.vol * (COCKPIT if WorldSound.cockpit_view() else 1.0)
		p.volume_db = linear_to_db(maxf(vol, 0.0001))
		p.pitch_scale = e.pitch
		if p.stream:
			p.play()
	return due
